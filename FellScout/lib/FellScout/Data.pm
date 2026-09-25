package FellScout::Data;

use strict;
use warnings;
use Exporter 'import';
use Text::CSV qw/csv/;
use FellScout::Log qw(info error debug);

our @EXPORT_OK = qw(
	get_status
	get_summary
	get_laterunners
	get_lateness_thresholds
	get_routes_map
	get_config
	update_config
	get_logs
	get_routes_checkpoints
	import_checkpoints_csv
	get_legs
	get_checkpoints
	get_checkpoint_details
	update_checkpoint_status
	get_checkpoint_arrivals
	get_entrants
	get_teams
	get_team
	get_problems
	clear_cache
	delete_scratch_team
	update_scratch_team
	get_scratch_teams
	get_incidents
	create_incident
	update_incident
	delete_incident
	get_retirements
	create_retirement
	update_retirement
	delete_retirement
	to_hh_mm
	rows_to_csv
);

sub get_status{
	my $dbh = shift;
	my ($last_sync_epoch) = $dbh->selectrow_array(
		"select unix_timestamp(time) from logs where name = 'periodic-jobs'"
	);
	return { last_sync_epoch => $last_sync_epoch };
}

# Turns a get_teams()/get_entrants()-shaped hashref ({id => {field=>value}})
# into a CSV string - column set is just whatever fields the first row has,
# sorted for a stable, predictable order, rather than a separately
# maintained list that could drift from what those functions actually return.
sub rows_to_csv{
	my $rows_by_id = shift;
	my @rows = values %$rows_by_id;
	return '' unless @rows;

	my @fieldnames = sort keys %{ $rows[0] };
	my $csv = Text::CSV->new({ binary => 1, eol => "\r\n" });
	my $out = '';
	$csv->combine(@fieldnames);
	$out .= $csv->string();
	foreach my $row (@rows){
		$csv->combine(map { $row->{$_} // '' } @fieldnames);
		$out .= $csv->string();
	}
	return $out;
}

# Ordered checkpoint-list-per-route plus a colour to draw it with, for the
# Map page's polylines - the colour is simply cycled through a fixed
# palette in route_name order, same as it always has been.
sub get_routes_map{
	my $dbh = shift;
	my @colours = qw/red blue green yellow orange/;
	my %routes;

	my $sth = $dbh->prepare('select distinct route_name from routes order by route_name asc');
	my $sth_cps = $dbh->prepare('select leg_to from routes where route_name = ? order by `index` asc');
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		my $route_name = $row->{route_name};
		$routes{$route_name}->{colour} = $colours[ scalar(keys %routes) % scalar(@colours) ];
		push(@{ $routes{$route_name}->{checkpoints} }, 0);
		$sth_cps->execute($route_name);
		while (my $cp = $sth_cps->fetchrow_hashref()){
			push(@{ $routes{$route_name}->{checkpoints} }, $cp->{leg_to});
		}
	}
	return \%routes;
}

sub get_routes_checkpoints{
	my $dbh = shift;
	my $routes_sth = $dbh->prepare('select distinct route_name from routes');
	$routes_sth->execute();
	my $cps_sth = $dbh->prepare('select leg_name from routes where route_name = ? order by `index` asc');

	my %routes_cps;
	while( my $row = $routes_sth->fetchrow_arrayref() ){
		my $route = $row->[0];
		$cps_sth->execute($route);
		while( my $r = $cps_sth->fetchrow_arrayref() ){
			my $cp = $r->[0];
			$cp =~ s/^\d+-//;
			push(@{$routes_cps{$route}}, $cp);
		}
	}
	return \%routes_cps;
}

# Takes a path to an uploaded CSV (the caller's job to get it there - a
# Dancer2 upload's own ->tempname is the normal case, so each request gets
# its own file rather than every upload racing to write the same shared
# path). Replaces every row in `checkpoints`, then rebuilds `routes` entirely
# from the CSV's "[route name] leg distance" columns.
sub import_checkpoints_csv{
	my $dbh = shift;
	my $csv_path = shift;

	my $checkpoints = csv( in => $csv_path, encoding => 'UTF-8', detect_bom => 1 );
	# `on duplicate key update`, not `replace into` - REPLACE is DELETE+INSERT
	# under the hood, so any column not in this list (status/status_notes/
	# status_updated_at) would silently reset to its default on every
	# re-import. This only ever touches the columns the CSV actually owns.
	my $sth = $dbh->prepare(
		"insert into checkpoints (checkpoint_number, description, manager, mobile, type, os_grid, latitude, longitude, what3words)
		 values (?, ?, ?, ?, ?, ?, ?, ?, ?)
		 on duplicate key update
		   description = values(description), manager = values(manager), mobile = values(mobile),
		   type = values(type), os_grid = values(os_grid), latitude = values(latitude),
		   longitude = values(longitude), what3words = values(what3words)"
	);

	my %routes;
	my $num_checkpoints = 0;
	foreach my $row (@$checkpoints){
		my $cp = $row->{'cp'};
		next unless $cp and $cp =~ m/\w+/;
		$cp =~ s/CP//;
		$cp =~ s/^0//;
		$cp = 0 if $cp =~ m/Start/i;
		$cp = 99 if $cp =~ m/Finish/i;
		$sth->execute($cp, $row->{description}, $row->{'checkpoint manager'}, $row->{mobile}, $row->{'type of checkpoint'}, $row->{'grid reference'}, $row->{latitude}, $row->{longitude}, $row->{what3words});
		$num_checkpoints++;

		foreach my $field (sort(keys(%{$row}))){
			if ($field =~ /^(\S+) leg distance/){
				my $route_name = lc($1);
				if($row->{$field} =~ m/\d+/){
					push(@{$routes{$route_name}}, $cp);
				}
			}
		}
	}

	$dbh->do('delete from routes');
	my $routes_sth = $dbh->prepare(
		'insert into routes(`route_name`, `leg_name`, `leg_from`, `leg_to`, `index`) values (?, ?, ?, ?, ?)'
	);
	my $num_legs = 0;
	foreach my $route (keys(%routes)){
		my @cps = @{$routes{$route}};
		for my $idx (0 .. $#cps){
			my $leg_to = $cps[$idx + 1] // '99';
			my $leg_name = $cps[$idx] . '-' . $leg_to;
			next if $leg_name eq '99-99';
			info("$route $leg_name $idx");
			$routes_sth->execute($route, $leg_name, $cps[$idx], $leg_to, $idx);
			$num_legs++;
		}
	}

	return { checkpoints => $num_checkpoints, routes => scalar(keys(%routes)), legs => $num_legs };
}

sub get_config{
	my $dbh = shift;
	my $sth = $dbh->prepare("select name, value, notes from config");
	$sth->execute();
	return $sth->fetchall_hashref('name');
}

# Applies only the config values that actually changed, matching the old
# /admin route's own "skip unless different" behaviour - returns a list of
# human-readable change messages, same wording it used to build inline.
sub update_config{
	my $dbh = shift;
	my $new_values = shift;
	my $current = get_config($dbh);
	my $sth_update = $dbh->prepare("update config set value = ? where name = ?");
	my @changes;
	foreach my $name (sort keys %$new_values){
		next unless exists $current->{$name};
		my $old_value = $current->{$name}->{value};
		my $new_value = $new_values->{$name};
		next if $new_value eq $old_value;
		$sth_update->execute($new_value, $name);
		push(@changes, "Updated $name to '$new_value' from '$old_value'");
	}
	return \@changes;
}

sub get_logs{
	my $dbh = shift;
	my $sth = $dbh->prepare('select name, message,
	                          date_format(time, "%H:%i") as time,
	                          date_format( timediff(now(), time ), "%kh%im") as time_since
	                          from logs order by time desc');
	$sth->execute();
	my @logs;
	while(my $row = $sth->fetchrow_hashref()){
		push(@logs, $row);
	}
	return \@logs;
}

sub get_lateness_thresholds{
	my $dbh = shift;
	my $sth = $dbh->prepare("select name, value from config where name like 'lateness_percent_%'");
	$sth->execute();
	my %thresholds;
	while(my $row = $sth->fetchrow_hashref()){
		$thresholds{ $row->{name} } = $row->{value};
	}
	return \%thresholds;
}

#TODO: Better name or display for "furthest-back team" (it's actually the checkpoint the teams are at
sub get_summary {
	my $dbh = shift;
	my %summary;

	$summary{general} = _route_summary($dbh, undef);

	my $routes_sth = $dbh->prepare("select distinct route_name from routes order by route_name");
	$routes_sth->execute();
	while (my $row = $routes_sth->fetchrow_hashref()){
		$summary{routes}->{ $row->{route_name} } = _route_summary($dbh, $row->{route_name});
	}

	return \%summary;
}

# The stats block get_summary() computes twice: once for every team, once
# per route with an extra `and route = ?`. $route is undef for the
# all-teams case..
sub _route_summary {
	my ($dbh, $route) = @_;
	my ($route_clause, @route_param) = defined($route) ? (' and route = ?', ($route)) : ('', ());
	my %stats;

	my $sth = $dbh->prepare("select last_checkpoint from teams where completed = 0$route_clause order by last_checkpoint asc limit 1");
	$sth->execute(@route_param);
	$stats{min_cp} = ($sth->fetchrow_array())[0];

	$sth = $dbh->prepare("select last_checkpoint from teams where completed = 0$route_clause order by last_checkpoint desc limit 1");
	$sth->execute(@route_param);
	$stats{max_cp} = ($sth->fetchrow_array())[0];

	$sth = $dbh->prepare("select team_number, team_name, unit, district, last_checkpoint from teams where completed = 0$route_clause order by team_number asc");
	$sth->execute(@route_param);
	my $num_out = 0;
	while ( my $row = $sth->fetchrow_hashref()){
		$num_out++;
		push(@{$stats{teams_out}}, $row->{team_number});
	}
	$stats{num_not_completed} = $num_out;

	$sth = $dbh->prepare("select count(*) from teams where retired > 0$route_clause");
	$sth->execute(@route_param);
	$stats{num_retired} = $sth->fetchrow_array;

	$sth = $dbh->prepare("select count(*) from teams where last_checkpoint = 99$route_clause");
	$sth->execute(@route_param);
	$stats{num_finished} = $sth->fetchrow_array;

	my ($finish_where, @finish_param) = defined($route)
		? ('completed = 0 and route = ?', $route)
		: ('teams.last_checkpoint < 99', ());
	($stats{earliest_finish}, $stats{latest_finish}) = _finish_extremes($dbh, $finish_where, @finish_param);

	return \%stats;
}

# The earliest- and latest-expected-to-finish team, from one query instead
# of the same query run twice (ASC/DESC) - and unlike that old pair, whose
# `desc`/`asc` labelling was backwards (each returned the *other* one), this
# is unambiguous: the fetched rows are sorted soonest-first, so the first
# row is genuinely the earliest finisher and the last is genuinely the
# latest.
sub _finish_extremes {
	my ($dbh, $where, @params) = @_;
	my $sth = $dbh->prepare("select teams.team_number, team_name, unit, district, route, last_checkpoint,
	                             date_format(last_checkpoint_time, \"%H:%i\") as last_checkpoint_time,
	                             date_format( timediff( checkpoints_teams_predictions.expected_time, now() ), \"%kh%im\") as finish_expected_in
	                             from teams
	                             join checkpoints_teams_predictions on
	                               checkpoints_teams_predictions.team_number = teams.team_number
	                               and checkpoints_teams_predictions.checkpoint = 99
	                             where $where
	                             order by expected_time asc");
	$sth->execute(@params);
	my $rows = $sth->fetchall_arrayref({});
	return (undef, undef) unless @$rows;
	return ($rows->[0], $rows->[-1]);
}

sub get_laterunners{
	my $dbh = shift;
	my $threshold = shift;
	my @laterunners;

	my $sth = $dbh->prepare("select leg_name, seconds from legs");
	$sth->execute;
	my $legs = $sth->fetchall_hashref('leg_name');

	$sth = $dbh->prepare('select teams.team_number, team_name, unit, district, route, next_checkpoint, last_checkpoint, current_leg,
	                          date_format(last_checkpoint_time, "%H:%i") as last_checkpoint_time,
	                          unix_timestamp(last_checkpoint_time) as last_checkpoint_time_epoch,
	                          date_format(checkpoints_teams_predictions.expected_time, "%H:%i") as next_checkpoint_expected_hhmm,
	                          date_format( timediff( checkpoints_teams_predictions.expected_time, now() ), "%kh%im") as next_checkpoint_expected_in
	                          from teams
	                          join checkpoints_teams_predictions on
	                            checkpoints_teams_predictions.team_number = teams.team_number
	                            and checkpoints_teams_predictions.checkpoint = teams.next_checkpoint
	                          where checkpoints_teams_predictions.expected_time < NOW()
	                          and teams.completed < 1
	                          order by checkpoints_teams_predictions.expected_time desc');
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		my $expected_duration = $legs->{ $row->{current_leg} }->{seconds};
		my $actual_duration = time() - $row->{last_checkpoint_time_epoch};
		my $diff = $actual_duration - $expected_duration;
		$row->{minutes_late} = sprintf("%0.0f", ($diff / 60));
		$row->{percent_late} = sprintf("%0.0f", ($diff / $actual_duration) * 100);
		$row->{current_leg_duration} = to_hh_mm($legs->{ $row->{current_leg} }->{seconds} );

		my $is_late = 1;
		if($threshold){
			if($threshold =~ m/(\d+)pc$/){
				my $threshold = $1;
				$is_late = 0 unless $row->{percent_late} > $threshold;
			}elsif($threshold =~ m/^(\d+)m$/){
				my $threshold = $1;
				$is_late = 0 unless $row->{minutes_late} > $threshold;
			}
		}
		push(@laterunners, $row) if $is_late > 0;
	}
	return \@laterunners;
}

sub get_legs{
	my $dbh = shift;
	my $legs = {};
	my $sth = $dbh->prepare("select leg_name, `from`, `to`, date_format(from_unixtime(seconds), \"%kh %im\") as time from legs where leg_name <> '0-0'");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		my $key = sprintf("%02d%02d", $row->{from}, $row->{to});
		$legs->{ $key } = $row;
		my $sth = $dbh->prepare("select team_number from teams where current_leg = ? and completed = 0");
		$sth->execute($row->{leg_name});
		while(my $r = $sth->fetchrow_hashref()){
			push(@{ $legs->{ $key }->{teams} }, $r->{team_number});
		}
	}
	return $legs;
}

sub get_checkpoints{
	my $dbh = shift;
	my %cps;
	my $sth = $dbh->prepare("select distinct leg_to from routes order by leg_to asc");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		my $cp = $row->{leg_to};
		$cps{$cp}->{cp} = $cp;

		my $sth = $dbh->prepare("select teams.team_number, team_name, route, last_checkpoint,
		                             date_format(last_checkpoint_time, \"%H:%i\") as last_checkpoint_time_hhmm,
		                             date_format(checkpoints_teams_predictions.expected_time, \"%H:%i\") as next_checkpoint_expected_hhmm,
		                             date_format( timediff( checkpoints_teams_predictions.expected_time, now() ), \"%kh%im\") as next_checkpoint_expected_in
		                             from teams
		                             left outer join checkpoints_teams_predictions on
		                               checkpoints_teams_predictions.team_number = teams.team_number
		                               and checkpoints_teams_predictions.checkpoint = teams.next_checkpoint
		                             where completed < 1
		                               and next_checkpoint = ?
		                             order by checkpoints_teams_predictions.expected_time desc");
		$sth->execute($cp);
		while(my $row = $sth->fetchrow_hashref()){
			push(@{$cps{$cp}->{arrivals}}, $row);
		}

		$sth = $dbh->prepare("select teams.team_number , team_name, route, next_checkpoint,
		                          date_format(last_checkpoint_time, \"%H:%i\") as last_checkpoint_time_hhmm,
		                          date_format(checkpoints_teams_predictions.expected_time, \"%H:%i\") as next_checkpoint_expected_hhmm,
		                          date_format( timediff( checkpoints_teams_predictions.expected_time, now() ), \"%kh%im\") as next_checkpoint_expected_in
		                          from teams
		                          join checkpoints_teams_predictions on
		                            checkpoints_teams_predictions.team_number = teams.team_number
		                            and checkpoints_teams_predictions.checkpoint = teams.next_checkpoint
		                          where completed = 0
		                            and last_checkpoint = ?
		                          order by last_checkpoint_time desc");

		$sth->execute($cp);
		while(my $row = $sth->fetchrow_hashref()){
			push(@{$cps{$cp}->{departures}}, $row);
		}

		$sth = $dbh->prepare("select distinct route_name from routes where leg_from = ?");
		$sth->execute($cp);
		while(my $r = $sth->fetchrow_hashref()){
			my $route = $r->{route_name};

			push(@{$cps{$cp}->{routes}}, $route);

			my $sth_teams = $dbh->prepare("select team_number from teams where route = ? and next_checkpoint <= ? and next_checkpoint > 0 and completed = 0 and retired = 0");
			$sth_teams->execute($route, $cp);
			while(my $t = $sth_teams->fetchrow_arrayref){
				push(@{$cps{$cp}->{future}->{$route}}, $t->[0]);
			}

			$sth_teams = $dbh->prepare("select team_number from teams where route = ? and next_checkpoint > ? and completed = 0 and retired = 0");
			$sth_teams->execute($route, $cp);
			while(my $t = $sth_teams->fetchrow_arrayref){
				push(@{$cps{$cp}->{past}->{$route}}, $t->[0]);
			}
		}
		$cps{$cp}->{details} = get_checkpoint_details($dbh, $cp);
	}
		$cps{0}->{details} = get_checkpoint_details($dbh, 0);
	return \%cps;
}

my @VALID_CHECKPOINT_STATUSES = qw(open issue closed);

sub update_checkpoint_status{
	my ($dbh, $checkpoint_number, $status, $notes) = @_;
	die "invalid checkpoint status '$status'" unless grep { $_ eq $status } @VALID_CHECKPOINT_STATUSES;

	my $sth = $dbh->prepare(
		'update checkpoints set status = ?, status_notes = ?, status_updated_at = now() where checkpoint_number = ?'
	);
	$sth->execute($status, $notes, $checkpoint_number);
	return get_checkpoint_details($dbh, $checkpoint_number);
}

sub get_checkpoint_details{
	my $dbh = shift;
	my $checkpoint = shift;
	my $d;

	my $sth = $dbh->prepare('select * from checkpoints where checkpoint_number = ?');
	$sth->execute($checkpoint);
	$d = $sth->fetchrow_hashref();

	$sth = $dbh->prepare("select distinct route_name from routes where leg_from = ?");
	$sth->execute($checkpoint);
	while(my $r = $sth->fetchrow_hashref()){
		my $route = $r->{route_name};
		push(@{$d->{routes}}, $route);
		  # In general, we don't care about retired teams when we're wondering who has not yet been to a checkpoint
			my $sth_teams = $dbh->prepare("select team_number from teams where route = ? and next_checkpoint <= ? and next_checkpoint > 0 and completed = 0 and retired = 0");
			$sth_teams->execute($route, $checkpoint);
			while(my $t = $sth_teams->fetchrow_arrayref){
				push(@{$d->{teams}->{future}->{$route}}, $t->[0]);
			}

			$sth_teams = $dbh->prepare("select team_number from teams where route = ? and next_checkpoint > ?");
			$sth_teams->execute($route, $checkpoint);
			while(my $t = $sth_teams->fetchrow_arrayref){
				push(@{$d->{teams}->{past}->{$route}}, $t->[0]);
			}

  		$sth_teams = $dbh->prepare("select team_number from teams where route = ? and next_checkpoint = ?");
			$sth_teams->execute($route, $checkpoint);
			while(my $t = $sth_teams->fetchrow_arrayref){
				push(@{$d->{teams}->{next}->{$route}}, $t->[0]);
			}



			my $sth_route = $dbh->prepare("select leg_from from routes where route_name = ? and leg_to = ?");
			$sth_route->execute($route, $checkpoint);
			my $prev = $sth_route->fetchrow_arrayref();
			$d->{previous}->{$route} = $prev->[0];

			$sth_route = $dbh->prepare("select leg_to from routes where route_name = ? and leg_from = ?");
			$sth_route->execute($route, $checkpoint);
			$prev = $sth_route->fetchrow_arrayref();
			$d->{next}->{$route} = $prev->[0];
		}
	return $d;
}

sub get_checkpoint_arrivals{
	my $dbh = shift;
	my $checkpoint = shift;
	my %cp;
	$cp{cp} = $checkpoint;
	# First, everyone's finish times
	my $sth = $dbh->prepare('select team_number,
	                            date_format(expected_time, "%H:%i") as finish_expected_hhmm,
	                            unix_timestamp(expected_time) as finish_expected_epoch
	                            from checkpoints_teams_predictions
	                            where checkpoint = 99');
	$sth->execute();
	my $finish_times = $sth->fetchall_hashref('team_number');

	# And when we expect everyone to get here
	$sth = $dbh->prepare('select team_number,
	                          date_format(expected_time, "%H:%i") as this_checkpoint_expected_hhmm,
	                          date_format( timediff( expected_time, now() ), "%kh %im") as this_checkpoint_expected_in,
	                          unix_timestamp(expected_time) as this_checkpoint_expected_epoch
	                          from checkpoints_teams_predictions
	                          where checkpoint = ?');
	$sth->execute($checkpoint);
	my $checkpoint_times = $sth->fetchall_hashref('team_number');


	# And now details for every team that has yet to get here
	$sth = $dbh->prepare("select distinct route_name from routes");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		my $route = $row->{'route_name'};
		my $sth = $dbh->prepare('select teams.team_number as team_number, team_name, next_checkpoint, route, unit, district,
		                            date_format(checkpoints_teams_predictions.expected_time, "%H:%i") as next_checkpoint_expected_hhmm,
		                            unix_timestamp(last_checkpoint_time) as last_checkpoint_time_epoch,
		                            date_format(last_checkpoint_time, "%H:%i") as last_checkpoint_time_hhmm,
		                            date_format(checkpoints_teams_predictions.expected_time, "%H:%i") as next_checkpoint_expected_hhmm,
		                            unix_timestamp(checkpoints_teams_predictions.expected_time) as next_checkpoint_expected_epoch,
		                            date_format( timediff( checkpoints_teams_predictions.expected_time, now() ), "%kh%im") as next_checkpoint_expected_in,
		                            timestampdiff(SECOND, last_checkpoint_time, CURTIME()) as seconds_since_checkpoint,
		                            `index`
		                            from teams
		                            join routes
		                              on routes.route_name = teams.route
		                              and routes.leg_name = teams.current_leg
		                            join checkpoints_teams_predictions on
		                            checkpoints_teams_predictions.team_number = teams.team_number
		                              and checkpoints_teams_predictions.checkpoint = teams.next_checkpoint
		                            where teams.completed < 1 and current_leg in
		                              (select leg_name from routes where route_name = ? and `index` <=
		                                (select `index` from routes where route_name=? and leg_to = ?
		                                  order by `index` desc limit 1))');
		$sth->execute($route, $route, $checkpoint);
		while(my $team = $sth->fetchrow_hashref()){
			$team->{finish_expected_hhmm} = $finish_times->{$team->{team_number}}->{finish_expected_hhmm};
			$team->{finish_expected_in} = $finish_times->{$team->{team_number}}->{finish_expected_in};
			$team->{finish_expected_epoch} = $finish_times->{$team->{team_number}}->{finish_expected_epoch};
			$team->{this_cp_expected_hhmm} = $checkpoint_times->{$team->{team_number}}->{this_checkpoint_expected_hhmm};
			$team->{this_cp_expected_epoch} = $checkpoint_times->{$team->{team_number}}->{this_checkpoint_expected_epoch};
			$team->{this_cp_expected_in_seconds} = $checkpoint_times->{$team->{team_number}}->{this_checkpoint_expected_epoch} - time();
			$team->{this_cp_in} = $checkpoint_times->{$team->{team_number}}->{this_checkpoint_expected_in};
			$cp{teams}->{$team->{team_number}} = $team;
		}
	}
	return \%cp
}

sub get_entrants{
	my $dbh = shift;
	my $sth = $dbh->prepare('select code, entrant_name, teams.team_number, team_name, entrants.unit, entrants.district,
	                             teams.last_checkpoint as team_last_checkpoint, teams.next_checkpoint as team_next_checkpoint,
	                             teams.route as route, entrants.retired as retired,
	                             entrants.completed as completed,
	                             date_format(checkpoints_teams_predictions.expected_time, "%H:%i") as expected_hhmm,
	                             date_format( timediff( checkpoints_teams_predictions.expected_time, now() ), "%kh%im") as expected_in,
	                             entrants.last_checkpoint as entrant_last_checkpoint
	                             from entrants
	                             join teams
	                               on entrants.team = teams.team_number
	                             left outer join checkpoints_teams_predictions
	                               on checkpoints_teams_predictions.team_number = teams.team_number
	                               and checkpoints_teams_predictions.checkpoint = teams.next_checkpoint
	                             left join scratch_team_entrants
	                               on entrants.code = scratch_team_entrants.entrant_code');
	$sth->execute();
	return $sth->fetchall_hashref('code');
}

sub get_teams{
	my $dbh = shift;
	# First, checkpoint times
	my %times;
	my $sth = $dbh->prepare("select team_number, checkpoint,
	                             date_format(expected_time, \"%H:%i\") as expected_hhmm,
	                             date_format( timediff( expected_time, now() ), \"%kh%im\") as expected_in
	                             from checkpoints_teams_predictions");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		$times{ $row->{team_number} }->{ $row->{checkpoint} } = $row;
	}

	# TODO: The date_format on next_checkpoint_expected_in only allows for a team to be up to 23h and 59min late, before it rolls to zero
	$sth = $dbh->prepare('select teams.team_number, team_name, route, district, unit, last_checkpoint, next_checkpoint, current_leg,
	                         timestampdiff(SECOND, last_checkpoint_time, CURTIME()) as seconds_since_checkpoint, completed, retired,
	                         date_format(last_checkpoint_time, "%H:%i") as last_checkpoint_hhmm,
	                         unix_timestamp(last_checkpoint_time) as last_checkpoint_time_epoch
	                         from teams');
	$sth->execute();
	my $teams;
	while (my $row = $sth->fetchrow_hashref()){
		if($times{ $row->{team_number} }->{99}->{expected_hhmm}){
			$row->{finish_expected_hhmm} = $times{ $row->{team_number} }->{99}->{expected_hhmm};
			$row->{finish_expected_in} = $times{ $row->{team_number} }->{99}->{expected_in};
		}else{
			$row->{finish_expected_hhmm} = $row->{finish_expected_in} = '-';
		}
		if($times{ $row->{team_number} }->{ $row->{next_checkpoint} }->{expected_hhmm}){
			$row->{next_checkpoint_expected_hhmm} = $times{ $row->{team_number} }->{ $row->{next_checkpoint} }->{expected_hhmm};
			$row->{next_checkpoint_expected_in} = $times{ $row->{team_number} }->{ $row->{next_checkpoint} }->{expected_in};
		}else{
			$row->{next_checkpoint_expected_hhmm} = $row->{next_checkpoint_expected_in} = '-';
		}

		$teams->{ $row->{team_number} } = $row;
		if(!$row->{next_checkpoint_expected_hhmm} or $row->{next_checkpoint_expected_hhmm} !~ m/\d+/){
			$row->{next_checkpoint_expected_hhmm} = '--';
			$row->{next_checkpoint_expected_in} = '--';
		}
		if(!$row->{finish_expected_hhmm} or $row->{finish_expected_hhmm} !~ m/\d+/){
			$row->{finish_expected_hhmm} = '--';
			$row->{finish_expected_in} = '--';
		}
	}
	return $teams;
}

sub get_team{
	my $dbh = shift;
	my $team_number = shift;
	$team_number =~ s/[^-\d]+//;
	# TODO: The date_format on next_checkpoint_expected_in only allows for a team to be up to 23h and 59min late, before it rolls to zero
	my $sth = $dbh->prepare('select team_number, team_name, route, district, unit, last_checkpoint, next_checkpoint,
	                            current_leg, current_leg_index,
	                            date_format(last_checkpoint_time, "%H:%i") as last_checkpoint_time_hhmm,
	                            timestampdiff(SECOND, last_checkpoint_time, CURTIME()) as seconds_since_checkpoint,
	                            unix_timestamp(last_checkpoint_time) as last_checkpoint_time_epoch
	                            from teams
	                            where team_number = ?');

	$sth->execute($team_number);
	my %team;
	eval {
		%team = %{ ($sth->fetchrow_hashref())[0] };
	};
	if($@){
		error("Team $team_number does not exist");
		return \%team;
	}

	unless($team{last_checkpoint} == 99){
		$sth = $dbh->prepare('select checkpoint,
					 date_format(expected_time, "%H:%i") as expected_hhmm,
					 date_format( timediff( expected_time, now() ), "%kh%im") as expected_in
					 from checkpoints_teams_predictions
					 where team_number = ?');
		$sth->execute($team_number);
		my $cp_expected_times = $sth->fetchall_hashref('checkpoint');

		$sth = $dbh->prepare('select `to` from legs
					 join routes
					 on routes.leg_name = legs.leg_name
					 where routes.route_name =
					   (select route from teams where team_number = ?)
					 and `to` >=
					   (select next_checkpoint from teams where team_number = ?)');
		$sth->execute($team_number, $team_number);
		my %cp_times;
		while(my $row = $sth->fetchrow_hashref){
			if($cp_expected_times->{ $row->{to} }->{expected_hhmm}){
				$cp_times{ $row->{to} } = $cp_expected_times->{ $row->{to} };
			}else{
				$cp_times{ $row->{to} } = {expected_hhmm => '-', expected_in => '-'};
			}
		}

		$team{next_checkpoint_expected_in}   = $cp_times{ $team{next_checkpoint} }->{expected_in};
		$team{next_checkpoint_expected_hhmm} = $cp_times{ $team{next_checkpoint} }->{expected_hhmm};

		$team{finish_expected_in}   = $cp_times{99}->{expected_in};
		$team{finish_expected_hhmm} = $cp_times{99}->{expected_hhmm};

		$team{remaining_checkpoints} = \%cp_times;
	}

	$sth = $dbh->prepare('select checkpoint, date_format(time, "%H:%i") as hhmm
	                         from checkpoints_teams where team_number = ?
	                         order by checkpoint asc;');
	$sth->execute($team_number);
	$team{previous_checkpoints} = $sth->fetchall_hashref('checkpoint');

	$sth = $dbh->prepare("select code, entrant_name, retired, completed from entrants where team = ?");
	$sth->execute($team_number);

	while(my $row = $sth->fetchrow_hashref()){
		$team{entrants}->{ $row->{code} } = $row;
		$team{active_entrants} = $row->{code} unless $row->{retired} > 0;
	}

	$sth = $dbh->prepare('select team_name as scratch_team_name,
	                         entrants.entrant_name,
	                         scratch_teams.team_number as scratch_team_number,
	                         entrant_code as code,
	                         previous_team_number
	                         from scratch_team_entrants
                                 join scratch_teams on
                                   scratch_teams.team_number = scratch_team_entrants.team_number
	                         join entrants on entrants.code = scratch_team_entrants.entrant_code
	                         where scratch_team_entrants.previous_team_number = ?');

	$sth->execute($team_number);
	while(my $row = $sth->fetchrow_hashref()){
		$team{entrants}->{ $row->{code} } = $row;
	}

	if($team_number < 0){
		my $sth = $dbh->prepare('select scratch_team_entrants.entrant_code, teams.team_number, teams.team_name
		                             from teams
		                             join scratch_team_entrants
		                               on scratch_team_entrants.previous_team_number = teams.team_number
		                               join scratch_teams
		                                 on scratch_teams.team_number = scratch_team_entrants.team_number
		                             where scratch_team_entrants.team_number = ?');
		my $scratch_team_number = 0 - $team_number;
		$sth->execute($scratch_team_number);
		while (my $row = $sth->fetchrow_hashref()){
			$team{entrants}->{ $row->{entrant_code} }->{previous_team_name} = $row->{team_name};
			$team{entrants}->{ $row->{entrant_code} }->{previous_team_number} = $row->{team_number};
		}
	}

	return \%team;
}

sub get_problems{
	my $dbh = shift;
	my $sth = $dbh->prepare('select * from entrants where completed < 1 and retired < 1');
	$sth->execute();
	my %problems;
	my %teams;
	while(my $row = $sth->fetchrow_hashref){
		$teams{ $row->{team} }->{ $row->{code} } = $row;
	}
	foreach my $team_number (sort(keys(%teams))){
		my $team = $teams{$team_number};

		if (scalar(keys(%{$team})) < 3){
			push(@{$problems{'small team'}}, {team => $team_number, message => "only has ".scalar(keys(%{$team}))." entrants (".join(' ', (sort(keys(%{$team})))).")"});
		}
		my(%cps);
		foreach my $entrant_code (sort(keys(%{$teams{$team_number}}))){
			my $entrant = $team->{$entrant_code};
			$cps{$entrant->{last_checkpoint}}++;
		}

		if( scalar(keys(%cps)) > 1){
			push(@{$problems{'split team'}}, {team => $team_number, message => "is split between checkpoints ".join(', ', sort(keys(%cps)))});
		};
	}
	return \%problems;
}

sub clear_cache{
	my $dbh = shift;
	info("Clearing cache");
	my @tables = qw/checkpoints_teams checkpoints_teams_predictions entrants legs routes teams logs scratch_teams scratch_team_entrants/;
	foreach my $table (@tables){
		# Can't use placeholders here because dbh adds quotes and   delete from 'table_name'  is invalid
		my $sth = $dbh->prepare("delete from $table");
		$sth->execute();
		debug("Cleared $table");
	}
	my $sth = $dbh->prepare("replace into logs (`message`, `name`) values ('Cleared all tables', 'clear_cache')");
	$sth->execute();
	$sth = $dbh->prepare('alter table scratch_teams auto_increment = 1');
	$sth->execute();
}

# Deletes a scratch team, resetting every one of its entrants back to
# whichever original team their entrant code implies (e.g. '9A' -> team 9).
# Returns a hashref with a `successes` arrayref, matching the shape the
# /scratch-teams route merges into its template vars.
sub delete_scratch_team{
	my $dbh = shift;
	my $team_number = shift;
	my %result;

	info("Deleting scratch team $team_number");
	my $sth = $dbh->prepare("select entrant_code from scratch_team_entrants where team_number = ?");
	$sth->execute($team_number);
	while(my $row = $sth->fetchrow_hashref()){
		my $entrant = $row->{entrant_code};
		$entrant =~ m/^(\d+)/;
		my $team = $1;
		info("Resetting $entrant to $team");
		my $sth2 = $dbh->prepare("update entrants set team = ? where code = ?");
		$sth2->execute($team, $entrant);
	}
	$sth = $dbh->prepare("delete from scratch_teams where team_number = ?");
	$sth->execute($team_number);
	$sth = $dbh->prepare("delete from scratch_team_entrants where team_number = ?");
	$sth->execute($team_number);
	my $negative_number = 0 - $team_number;
	$sth = $dbh->prepare("delete from teams where team_number = ? and team_number < 0");
	$sth->execute($negative_number);
	push(@{$result{successes}}, "Deleted team -$team_number");

	return \%result;
}

# Creates or updates a scratch team from a space-separated list of entrant
# codes. %args: team_number, team_name, entrants (space-separated codes),
# add (true when this is a brand new team rather than an edit). Returns a
# hashref of successes/errors/warnings/new_team, matching what the
# /scratch-teams route merges into its template vars.
sub update_scratch_team{
	my $dbh = shift;
	my %args = @_;
	my %result;

	my %scratch_team_names;
	my %scratch_team_numbers;
	my %existing_scratch_entrants;
	my $sth = $dbh->prepare("select * from scratch_teams
	                         join scratch_team_entrants
	                         on scratch_team_entrants.team_number = scratch_teams.team_number");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		$scratch_team_numbers{ lc($row->{team_name}) } = $row->{team_number};
		$scratch_team_names{$row->{team_number}} = $row->{team_name};
		$existing_scratch_entrants{ $row->{entrant_code} } = $row->{team_number};
	}

	my $scratch_team_number = $args{team_number};
	# Sanitise each entrant's code
	$sth = $dbh->prepare("select code, team from entrants");
	$sth->execute();
	my $all_entrants = $sth->fetchall_hashref('code');

	my @entrants;
	foreach my $entrant (split(m/\s+/, $args{entrants})){
		next if $entrant eq '';
		if($entrant =~ m/(\d+[a-zA-Z])/){
			$entrant = uc($entrant);
			my $errors = 0;
			if($existing_scratch_entrants{ $entrant } and $existing_scratch_entrants{ $entrant } != $scratch_team_number){
				push(@{$result{errors}}, "Entrant '$entrant' is already in scratch team -$existing_scratch_entrants{ $entrant }; perhaps remove them from that first?");
				$errors++;
				error("Entrant $entrant already in $existing_scratch_entrants{$entrant}");
			}
			unless($all_entrants->{$entrant}){
				push(@{$result{errors}}, "There is no entrant with code '$entrant'");
				$errors++;
				error("Tried to add non-existent entrant $entrant");
			}
			push(@entrants, uc($1)) unless $errors > 0;
		}else{
			push(@{$result{errors}}, "'$entrant' is not a valid entrant");
		}
	}
	my $scratch_team_name = $args{team_name};

	if($args{add}){
		$scratch_team_name =~ s/[^\w\s\.\,\?\!\"\']//;
		unless($scratch_team_name eq $args{team_name}){
			push(@{$result{'warnings'}}, "Sanitised team name '".$args{team_name}."' to '$scratch_team_name'");
		}

		if(!$scratch_team_name or $scratch_team_name =~ m/^\s*$/){
			my %teams;
			foreach my $entrant (@entrants){
				$entrant =~ m/^(\d+)\w$/;
				$teams{$1}++;
			}
			$scratch_team_name = join(', ', (sort(keys(%teams))) );
			$scratch_team_name =~ s/, (\d+)$/ and $1/;
		}
		if($scratch_team_numbers{ lc($scratch_team_name) }){
			push(@{$result{errors}}, "There is already a scratch team called '$scratch_team_name'; names need to be unique (this check doesn't consider capital letters)");
			$result{new_team}->{team_name} = $scratch_team_name;
			$result{new_team}->{entrants} = join(' ', sort(@entrants));
			error("Duplicate scratch team: '$scratch_team_name'");
		}
		unless($result{errors}->[0]){
			my $sth_team = $dbh->prepare("insert into scratch_teams (team_name) values (?)");
			$sth_team->execute($scratch_team_name);
			$scratch_team_number = $dbh->last_insert_id(undef, undef, undef, undef);
			push(@{$result{successes}}, "Created scratch team $scratch_team_name");
		}
	}

	# Now we have a valid new scratch team name $scratch_team_name and series of entrants @entrants

	# REMEMBER team_number is positive here!

	# First, if any of the entrants in the database are not in the list from the browser, they are to be deleted
	$sth = $dbh->prepare("select entrant_code from scratch_team_entrants where team_number = ?");
	$sth->execute( $scratch_team_number );
	my @existing_entrants;
	while(my $row = $sth->fetchrow_hashref()){
		my $entrant = $row->{entrant_code};
		push(@existing_entrants, $entrant);
		unless(grep(/^$entrant$/, @entrants)){
			# Entrant is in team in db, but not in list from user. Delete entrant from team.
			$entrant =~ m/(\d+)/;
			my $old_team = $1;
			info("Removing $entrant from scratch team $scratch_team_number, putting back into team $old_team");
			my $sth2 = $dbh->prepare("update entrants set team = ? where code = ?");
			$sth2->execute($old_team, $entrant);
			$sth2 = $dbh->prepare("delete from scratch_team_entrants where entrant_code = ?");
			$sth2->execute($entrant);
			push(@{$result{successes}}, "Removed entrant '$entrant' from scratch team $scratch_team_name, back into $old_team");
		}
	}

	# Next, if any of the entrants in the list are not in the database, they are to be added
	unless($result{errors}->[0]){
		foreach my $entrant (@entrants){
			unless(grep/^$entrant$/, @existing_entrants){
				info("Adding $entrant to scratch team $scratch_team_number");
				$entrant =~ m/^(\d+)/;
				my $original_team = $1;
				my $sth2 = $dbh->prepare("replace into scratch_team_entrants (team_number, entrant_code, previous_team_number) values (?, ?, ?)");
				$sth2->execute($scratch_team_number, $entrant, $original_team);
				push(@{$result{successes}}, "Added entrant $entrant to team '$scratch_team_name'");
			}
		}
	}

	# Finally, if there are now no entrants in the database, we need to delete the team
	$sth = $dbh->prepare("select count(*) from scratch_team_entrants where team_number = ?");
	$sth->execute($scratch_team_number);
	if ( ($sth->fetchrow_arrayref())[0] < 1){
		$sth = $dbh->prepare("delete from scratch_teams where team_number = ?");
		$sth->execute($scratch_team_number);
		push(@{$result{successes}}, "Removed team -$scratch_team_name");
	}

	if($result{errors}->[0]){
		$result{new_team}->{team_name} = $scratch_team_name;
		$result{new_team}->{entrants} = join(' ', sort(@entrants));
	}

	return \%result;
}

sub get_scratch_teams{
	my $dbh = shift;
	my %teams;
	my $sth_t = $dbh->prepare("select team_number, team_name from scratch_teams");
	my $sth_e = $dbh->prepare("select entrant_code from scratch_team_entrants where team_number = ? order by entrant_code asc");
	$sth_t->execute();
	while ( my $team = $sth_t->fetchrow_hashref()){
		$sth_e->execute($team->{team_number});
		my @entrants;
		while (my $entrant = $sth_e->fetchrow_hashref()){
			push(@entrants, $entrant->{entrant_code});
		}
		$teams{ $team->{team_number} } = $team;
		$teams{ $team->{team_number} }->{entrants} = join(' ', @entrants);
	}
	return \%teams;
}

sub get_incidents{
	my $dbh = shift;
	my $sth = $dbh->prepare('select * from incidents order by created_at desc');
	$sth->execute();
	return $sth->fetchall_hashref('id');
}

sub create_incident{
	my ($dbh, $fields) = @_;
	my $sth = $dbh->prepare(
		'insert into incidents (type, description, checkpoint_number, team_number, owner, status)
		 values (?, ?, ?, ?, ?, ?)'
	);
	$sth->execute(
		$fields->{type}, $fields->{description}, $fields->{checkpoint_number} || undef,
		$fields->{team_number} || undef, $fields->{owner}, $fields->{status} || 'Open',
	);
	my $id = $dbh->last_insert_id(undef, undef, undef, undef);
	return $dbh->selectrow_hashref('select * from incidents where id = ?', undef, $id);
}

sub update_incident{
	my ($dbh, $id, $fields) = @_;
	my $sth = $dbh->prepare(
		'update incidents set type = ?, description = ?, checkpoint_number = ?, team_number = ?,
		   owner = ?, status = ? where id = ?'
	);
	$sth->execute(
		$fields->{type}, $fields->{description}, $fields->{checkpoint_number} || undef,
		$fields->{team_number} || undef, $fields->{owner}, $fields->{status}, $id,
	);
	return $dbh->selectrow_hashref('select * from incidents where id = ?', undef, $id);
}

sub delete_incident{
	my ($dbh, $id) = @_;
	$dbh->prepare('delete from incidents where id = ?')->execute($id);
	return { successes => ["Deleted incident $id"] };
}

sub get_retirements{
	my $dbh = shift;
	my $sth = $dbh->prepare('select * from retirements order by created_at desc');
	$sth->execute();
	return $sth->fetchall_hashref('id');
}

sub create_retirement{
	my ($dbh, $fields) = @_;
	my $sth = $dbh->prepare(
		'insert into retirements (entrant_code, team_number, checkpoint_number, reason, vehicle, status)
		 values (?, ?, ?, ?, ?, ?)'
	);
	$sth->execute(
		uc($fields->{entrant_code} // ''), $fields->{team_number} || undef, $fields->{checkpoint_number} || undef,
		$fields->{reason}, $fields->{vehicle}, $fields->{status} || 'Awaiting pickup',
	);
	my $id = $dbh->last_insert_id(undef, undef, undef, undef);
	return $dbh->selectrow_hashref('select * from retirements where id = ?', undef, $id);
}

sub update_retirement{
	my ($dbh, $id, $fields) = @_;
	my $sth = $dbh->prepare(
		'update retirements set entrant_code = ?, team_number = ?, checkpoint_number = ?,
		   reason = ?, vehicle = ?, status = ? where id = ?'
	);
	$sth->execute(
		uc($fields->{entrant_code} // ''), $fields->{team_number} || undef, $fields->{checkpoint_number} || undef,
		$fields->{reason}, $fields->{vehicle}, $fields->{status}, $id,
	);
	return $dbh->selectrow_hashref('select * from retirements where id = ?', undef, $id);
}

sub delete_retirement{
	my ($dbh, $id) = @_;
	$dbh->prepare('delete from retirements where id = ?')->execute($id);
	return { successes => ["Deleted retirement $id"] };
}

# We have two formats for times. A time is always represented as
# HH:MM, and a time _period_ as `HHh MMm`
# All our times are dealt with in seconds generally, so this sub
# takes the seconds and returns the appropriate format
sub to_hh_mm{
	my $epoch_time = shift;
	my ($h,$m) = (localtime($epoch_time))[2,1];
	return(sprintf("%01sh %02sm", $h, $m));
}

1;
