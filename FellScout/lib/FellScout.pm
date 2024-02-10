package FellScout;

use Dancer2;
use Dancer2::Plugin::Database;
use Data::Dumper;
use POSIX qw(strftime);
use Cwd;

setting('plugins')->{'Database'}->{'host'}=$ENV{'MYSQL_HOST'};
setting('plugins')->{'Database'}->{'database'}=$ENV{MYSQL_DATABASE};
setting('plugins')->{'Database'}->{'username'}=$ENV{MYSQL_USERNAME};
setting('plugins')->{'Database'}->{'password'}=$ENV{MYSQL_PASSWORD};
setting('plugins')->{'Database'}->{'port'}=$ENV{MYSQL_PORT};

our $VERSION = '0.1';


hook 'before' => sub {
	header 'Content-Type' => 'application/json' if request->path =~ m{^/api/};

	my $sth = database->prepare("select name, value from config");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		var $row->{name} => $row->{value};
	}

	$sth = database->prepare("select
	                          date_format( timediff(now(), time ), \"%kh%im\") as time_since_last_felltrack_update,
	                          timestampdiff(SECOND, time, CURTIME()) as seconds_since_last_felltrack_update
	                          from logs
	                          where
	                          name = 'periodic-jobs'");
	$sth->execute();
	my $page = $sth->fetchrow_hashref();
	$page->{auto_refresh} = param('auto_refresh') if param('auto_refresh') and param('auto_refresh') > 0;

	$page->{google_maps_url} = vars->{'google_maps_url'} if vars->{'google_maps_url'};

	var page => $page;
};

# # # # # SUMMARY
any ['get', 'post'] => '/' => sub{
	my $return = {
		summary => get_summary(),
		page => vars->{page},
	};
	$return->{page}->{title} = 'Event Summary';
	return template 'summary.tt', $return;
};

any ['get', 'post'] => '/api/summary' => sub{
	encode_json(get_summary());
};

#TODO: Better name or display for "furthest-back team" (it's actually the checkpoint the teams are at
sub get_summary {
	my %summary;

	my $sth = database->prepare("select teams.team_number, team_name, unit, district, route, last_checkpoint,
	                             date_format(last_checkpoint_time, \"%H:%i\") as last_checkpoint_time,
	                             date_format( timediff( checkpoints_teams_predictions.expected_time, now() ), \"%kh%im\") as finish_expected_in
	                             from teams
	                             join checkpoints_teams_predictions on
	                               checkpoints_teams_predictions.team_number = teams.team_number
	                               and checkpoints_teams_predictions.checkpoint = 99
	                             order by expected_time desc");
	$sth->execute();
	$summary{general}->{earliest_finish} = $sth->fetchrow_hashref();

	$sth = database->prepare("select teams.team_number, team_name, unit, district, route, last_checkpoint,
	                          date_format(last_checkpoint_time, \"%H:%i\") as last_checkpoint_time,
	                          date_format( timediff( checkpoints_teams_predictions.expected_time, now() ), \"%kh%im\") as finish_expected_in
	                          from teams
	                          join checkpoints_teams_predictions on
	                            checkpoints_teams_predictions.team_number = teams.team_number
	                            and checkpoints_teams_predictions.checkpoint = 99
	                          order by expected_time asc");
	$sth->execute();
	$summary{general}->{latest_finish} = $sth->fetchrow_hashref();

	$sth = database->prepare("select last_checkpoint from teams where completed = 0 order by last_checkpoint asc limit 1");
	$sth->execute();
	$summary{general}->{min_cp} = ($sth->fetchrow_array())[0];

	$sth = database->prepare("select last_checkpoint from teams where completed = 0 order by last_checkpoint desc limit 1");
	$sth->execute();
	$summary{general}->{max_cp} = ($sth->fetchrow_array())[0];

	$sth = database->prepare("select team_number, team_name, unit, district, last_checkpoint from teams where completed = 0 order by team_number asc");
	$sth->execute();
	my $num_out = 0;
	while ( my $row = $sth->fetchrow_hashref()){
		$num_out++;
		push(@{$summary{general}->{teams_out}}, $row->{team_number});
	}
	$summary{general}->{num_not_completed} = $num_out;

	my $routes_sth = database->prepare("select distinct route_name from routes order by route_name");
	my @routes;
	$routes_sth->execute();
	while (my $row = $routes_sth->fetchrow_hashref()){
		my $route = $row->{route_name};

		my $sth = database->prepare("select last_checkpoint from teams where completed = 0 and route = ? order by last_checkpoint asc limit 1");
		$sth->execute($route);
		$summary{routes}->{$route}->{min_cp} = ($sth->fetchrow_array())[0];

		$sth = database->prepare("select last_checkpoint from teams where completed = 0 and route = ? order by last_checkpoint desc limit 1");
		$sth->execute($route);
		$summary{routes}->{$route}->{max_cp} = ($sth->fetchrow_array())[0];

		$sth = database->prepare("select team_number, team_name, unit, district, last_checkpoint from teams where completed = 0 and route = ? order by team_number asc");
		$sth->execute($route);
		my $num_out = 0;
		while ( my $row = $sth->fetchrow_hashref()){
			$num_out++;
			push(@{$summary{routes}->{$route}->{teams_out}}, $row->{team_number});
		}
		$summary{routes}->{$route}->{num_not_completed} = $num_out;

		$sth = database->prepare("select teams.team_number, team_name, unit, district, route, last_checkpoint,
		                          date_format(last_checkpoint_time, \"%H:%i\") as last_checkpoint_time,
		                          date_format( timediff( checkpoints_teams_predictions.expected_time, now() ), \"%kh%im\") as finish_expected_in
		                          from teams
		                          join checkpoints_teams_predictions on
		                            checkpoints_teams_predictions.team_number = teams.team_number
		                            and checkpoints_teams_predictions.checkpoint = 99
		                          where completed = 0
		                            and route = ?
		                          order by expected_time desc");

		$sth->execute($route);
		$summary{routes}->{$route}->{earliest_finish} = $sth->fetchrow_hashref();

		$sth = database->prepare("select teams.team_number, team_name, unit, district, route, last_checkpoint,
		                          date_format(last_checkpoint_time, \"%H:%i\") as last_checkpoint_time,
		                          date_format( timediff( checkpoints_teams_predictions.expected_time, now() ), \"%kh%im\") as finish_expected_in
		                          from teams
		                          join checkpoints_teams_predictions on
		                            checkpoints_teams_predictions.team_number = teams.team_number
		                            and checkpoints_teams_predictions.checkpoint = 99
		                          where completed = 0
		                            and route = ?
		                          order by expected_time asc");
		$sth->execute($route);
		$summary{routes}->{$route}->{latest_finish} = $sth->fetchrow_hashref();

	}

	return \%summary;
}
# # # # # laterunners

any ['get', 'post'] => '/laterunners' => sub {
	if(param('threshold') and param('threshold') =~ m/^\d+(m|pc)$/){
		redirect "/laterunners/".param('threshold');
	}else{
		redirect "/laterunners/0";
	}
};
any ['get', 'post'] => '/laterunners/:threshold?' => sub {
	my $return = {
		laterunners => get_laterunners(param('threshold')),
		threshold => param('threshold'),
		page => vars->{page}
	};
	my $sth = database->prepare("select name,value from config where name like 'lateness_percent_%'");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		$return->{page}->{ $row->{name} } = $row->{value};
	}
	$return->{page}->{table_is_searchable} = 1;
	$return->{page}->{table_sort_column} = 8;
	$return->{page}->{table_sort_order} = 'desc';
	$return->{page}->{title} = 'Late Runners';
	return template 'laterunners.tt', $return;
};
any ['get', 'post'] => '/api/laterunners/' => sub {
	return encode_json(laterunners => get_laterunners( param('threshold') ) )
};

sub get_laterunners(){
	my @laterunners;
	my $legs;
	my $threshold = shift;

	my $sth = database->prepare("select leg_name, seconds from legs");
	$sth->execute;
	$legs = $sth->fetchall_hashref('leg_name');

	$sth = database->prepare('select teams.team_number, team_name, unit, district, route, next_checkpoint, last_checkpoint, current_leg,
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
# # # # # LEGS + CHECKPOINTS
any ['get', 'post'] => '/legs' => sub {
	my $return = {
		legs => get_legs(),
		page => vars->{page},
	};
	$return->{page}->{title} = 'Legs';
	return template 'legs.tt', $return;
};

any ['get', 'post'] => '/api/legs' => sub{
	return encode_json( get_legs() );
};

sub get_legs(){
	my %teams;
	my $sth = database->prepare("select team_number, current_leg from teams where current_leg like '%-%'");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		push(@{$teams{$row->{current_leg}}}, $row->{number});
	}

	my $legs = {};
	$sth = database->prepare("select leg_name, `from`, `to`, date_format(from_unixtime(seconds), \"%kh %im\") as time from legs where leg_name <> '0-0'");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		my $key = sprintf("%02d%02d", $row->{from}, $row->{to});
		$legs->{ $key } = $row;
		my $sth = database->prepare("select team_number from teams where current_leg = ? and completed = 0");
		$sth->execute($row->{leg_name});
		while(my $r = $sth->fetchrow_hashref()){
			push(@{ $legs->{ $key }->{teams} }, $r->{team_number});
		}
	}
	return $legs;
}


any ['get', 'post'] => '/checkpoints' => sub {
	my $return = {
		checkpoints => get_checkpoints(),
		page => vars->{page},
	};
	$return->{page}->{title} = 'Checkpoints';
	return template 'checkpoints.tt', $return;
};

any ['get', 'post'] => '/api/checkpoints' => sub{
	return encode_json( get_checkpoints() );
};

sub get_checkpoints(){
	my %cps;
	my $sth = database->prepare("select distinct `to` from legs order by `to` asc");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		my $cp = $row->{to};
		$cps{$cp}->{cp} = $cp;

		my $sth = database->prepare("select teams.team_number, team_name, route, last_checkpoint,
		                             date_format(last_checkpoint_time, \"%H:%i\") as last_checkpoint_time_hhmm,
		                             date_format(checkpoints_teams_predictions.expected_time, \"%H:%i\") as next_checkpoint_expected_hhmm,
		                             date_format( timediff( checkpoints_teams_predictions.expected_time, now() ), \"%kh%im\") as next_checkpoint_expected_in
		                             from teams
		                             join checkpoints_teams_predictions on
		                               checkpoints_teams_predictions.team_number = teams.team_number
		                               and checkpoints_teams_predictions.checkpoint = teams.next_checkpoint
		                             where completed < 1
		                               and next_checkpoint = ?
		                             order by checkpoints_teams_predictions.expected_time desc");
		$sth->execute($cp);
		while(my $row = $sth->fetchrow_hashref()){
			push(@{$cps{$cp}->{arrivals}}, $row);
		}

		$sth = database->prepare("select teams.team_number , team_name, route, next_checkpoint,
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
	}
	return \%cps;
}

any ['get', 'post'] => '/checkpoint' => sub {
	my $checkpoint = param('checkpoint');
	if($checkpoint =~ m/^\d+$/){
		redirect "/checkpoint/$checkpoint";
	}else{
		redirect "/checkpoints";
	}
	redirect "/checkpoint/$checkpoint";
};

any ['get', 'post'] => '/checkpoint/:checkpoint' => sub {
	my $return = {
		checkpoint => get_checkpoint(param('checkpoint')),
		page => vars->{page},
	};
	$return->{page}->{title} = 'Checkpoint '.param('checkpoint');
	$return->{page}->{table_is_searchable} = 1;
	$return->{page}->{table_sort_column} = 1;
	$return->{page}->{table_sort_order} = 'desc';
	return template 'checkpoint.tt', $return;
};

any ['get', 'post'] => '/api/checkpoint/:checkpoint' => sub{
	return encode_json( get_checkpoint(param('checkpoint')));
};

sub get_checkpoint(){
	my $checkpoint = shift;
	my %cp;
	$cp{cp} = $checkpoint;

	# First, everyone's finish times
	my $sth = database->prepare('select team_number,
	                            date_format(expected_time, "%H:%i") as finish_expected_hhmm,
	                            unix_timestamp(expected_time) as finish_expected_epoch
	                            from checkpoints_teams_predictions
	                            where checkpoint = 99');
	$sth->execute();
	my $finish_times = $sth->fetchall_hashref('team_number');

	# And when we expect everyone to get here
	$sth = database->prepare('select team_number,
	                          date_format(expected_time, "%H:%i") as this_checkpoint_expected_hhmm,
	                          date_format( timediff( expected_time, now() ), "%kh %im") as this_checkpoint_expected_in,
	                          unix_timestamp(expected_time) as this_checkpoint_expected_epoch
	                          from checkpoints_teams_predictions
	                          where checkpoint = ?');
	$sth->execute($checkpoint);
	my $checkpoint_times = $sth->fetchall_hashref('team_number');


	# And now details for every team that has yet to get here
	$sth = database->prepare("select distinct route_name from routes");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		my $route = $row->{'route_name'};
		my $sth = database->prepare('select teams.team_number as team_number, team_name, next_checkpoint, route, unit, district,
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
		                                (select `index` from routes where route_name=? and leg_name like ?))');
		$sth->execute($route, $route, "%-$checkpoint");
		while(my $team = $sth->fetchrow_hashref()){
			$team->{finish_expected_hhmm} = $finish_times->{$team->{team_number}}->{finish_expected_hhmm};
			$team->{finish_expected_in} = $finish_times->{$team->{team_number}}->{finish_expected_in};
			$team->{finish_expected_epoch} = $finish_times->{$team->{team_number}}->{finish_expected_epoch};
			$team->{this_cp_expected_hhmm} = $checkpoint_times->{$team->{team_number}}->{this_checkpoint_expected_hhmm};
			$team->{this_cp_expected_epoch} = $checkpoint_times->{$team->{team_number}}->{this_checkpoint_expected_epoch};
			$team->{this_cp_expected_in_seconds} = $checkpoint_times->{$team->{team_number}}->{this_checkpoint_expected_epoch} - time();
			$team->{this_cp_in} = $checkpoint_times->{$team->{team_number}}->{this_checkpoint_expected_in};
			push(@{$cp{teams}}, $team);
		}
	}
	return \%cp
}

# # # # # ENTRANTS

any ['get', 'post'] => '/api/entrants' => sub {
	return encode_json(get_entrants());
};

any ['get', 'post'] => '/entrants' => sub {
	my $return = {
		page => vars->{page},
		entrants => get_entrants(),
	};
	$return->{page}->{table_is_searchable} = 1;
	$return->{page}->{title} = 'entrants';
	return template 'entrants.tt', $return;
};

sub get_entrants(){
#my $sth = database->prepare("select * from entrants join teams on entrants.team = teams.team_number");
	my $sth = database->prepare("select code, entrant_name, teams.team_number, team_name, entrants.unit, entrants.district, teams.last_checkpoint
	                             from entrants
	                             join teams
	                             on entrants.team = teams.team_number
	                             left join scratch_team_entrants
	                             on entrants.code = scratch_team_entrants.entrant_code");
	$sth->execute();
	return $sth->fetchall_hashref('code');
}

# # # # # TEAMS
any ['get','post'] => '/scratch-teams' => sub {

	my %return;

	if(param('update') or param('add')){
		my %scratch_team_names;
		my %scratch_team_numbers;
		my %existing_scratch_entrants;
		my $sth = database->prepare("select * from scratch_teams
		                             join scratch_team_entrants
		                             on scratch_team_entrants.team_number = scratch_teams.team_number");
		$sth->execute();
		while(my $row = $sth->fetchrow_hashref()){
			$scratch_team_numbers{ lc($row->{team_name}) } = $row->{team_number};
			$scratch_team_names{$row->{team_number}} = $row->{team_name};
			$existing_scratch_entrants{ $row->{entrant_code} } = $row->{team_number};
		}

		if(param('entrants') eq ''){
			info("Deleting scratch team ".param('team_name'));
			my $sth = database->prepare("select entrant_code from scratch_team_entrants where team_number = ?");
			$sth->execute( param('team_number') );
			foreach (my $row = $sth->fetchrow_hashref()){
				my $entrant = $row->{entrant_code};
				$entrant =~ m/^(\d+)/;
				my $team = $1;
				info("Resetting $entrant to $team");
				my $sth = database->prepare("update entrants set team = ? where code = ?");
				$sth->execute($team, $entrant);
			}
			$sth = database->prepare("delete from scratch_teams where team_number = ?");
			$sth->execute(param('team_number'));
			$sth = database->prepare("delete from scratch_team_entrants where team_number = ?");
			$sth->execute(param('team_number'));
			my $number = 0 - param('team_number');
			$sth = database->prepare("delete from teams where team_number = ? and team_number < 0");
			$sth->execute($number);
			push(@{$return{successes}}, "Deleted team -".param('team_number')."");
		}else{
			my $scratch_team_number = param('team_number');
			# Sanitise each entrant's code
			$sth = database->prepare("select code, team from entrants");
			$sth->execute();
			my $all_entrants = $sth->fetchall_hashref('code');

			my @entrants;
			foreach my $entrant (split(m/\s+/, param('entrants'))){
				next if $entrant eq '';
				if($entrant =~ m/(\d+[a-zA-Z])/){
					$entrant = uc($entrant);
					my $errors = 0;
					if($existing_scratch_entrants{ $entrant } and $existing_scratch_entrants{ $entrant } != $scratch_team_number){
						push(@{$return{errors}}, "Entrant '$entrant' is already in scratch team -$existing_scratch_entrants{ $entrant }; perhaps remove them from that first?");
						$errors++;
						error("Entrant $entrant already in $existing_scratch_entrants{$entrant}");
					}
					unless($all_entrants->{$entrant}){
						push(@{$return{errors}}, "There is no entrant with code '$entrant'");
						$errors++;
						error("Tried to add non-existent entrant $entrant");
					}
					push(@entrants, uc($1)) unless $errors > 0;
				}else{
					push(@{$return{errors}}, "'$entrant' is not a valid entrant");
				}
			}
			my $scratch_team_name = param('team_name');

			if(param('add')){
				$scratch_team_name =~ s/[^\w\s\.\,\?\!\"\']//;
				unless($scratch_team_name eq param('team_name')){
					push(@{$return{'warnings'}}, "Sanitised team name '".param('team_name')."' to '$scratch_team_name'");
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
					push(@{$return{errors}}, "There is already a scratch team called '$scratch_team_name'; names need to be unique (this check doesn't consider capital letters)");
					$return{new_team}->{team_name} = $scratch_team_name;
					$return{new_team}->{entrants} = join(' ', sort(@entrants));
					error("Duplicate scratch team: '$scratch_team_name'");
				}
				unless($return{errors}->[0]){
					my $sth_team = database->prepare("insert into scratch_teams (team_name) values (?)");
					$sth_team->execute($scratch_team_name);
					$scratch_team_number = database->{mysql_insertid};
					push(@{$return{successes}}, "Created scratch team $scratch_team_name");
				}
			}

			# Now we have a valid new scratch team name $scratch_team_name and series of entrants @entrants

			# REMEMBER team_number is positive here!

			# First, if any of the entrants in the database are not in the list from the browser, they are to be deleted
			$sth = database->prepare("select entrant_code from scratch_team_entrants where team_number = ?");
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
					my $sth = database->prepare("update entrants set team = ? where code = ?");
					$sth->execute($old_team, $entrant);
					$sth = database->prepare("delete from scratch_team_entrants where entrant_code = ?");
					$sth->execute($entrant);
					push(@{$return{successes}}, "Removed entrant '$entrant' from scratch team $scratch_team_name, back into $old_team");
				}
			}

			# Next, if any of the entrants in the list are not in the database, they are to be added
			unless($return{errors}->[0]){
				foreach my $entrant (@entrants){
					unless(grep/^$entrant$/, @existing_entrants){
						info("Adding $entrant to scratch team $scratch_team_number");
						$entrant =~ m/^(\d+)/;
						my $original_team = $1;
						my $sth = database->prepare("replace into scratch_team_entrants (team_number, entrant_code, previous_team_number) values (?, ?, ?)");
						$sth->execute($scratch_team_number, $entrant, $original_team);
						push(@{$return{successes}}, "Added entrant $entrant to team '$scratch_team_name'");
					}
				}
			}

			# Finally, if there are now no entrants in the database, we need to delete the team
			$sth = database->prepare("select count(*) from scratch_team_entrants where team_number = ?");
			$sth->execute($scratch_team_number);
			if ( ($sth->fetchrow_arrayref())[0] < 1){
				$sth = database->prepare("delete from scratch_teams where team_number = ?");
				$sth->execute->($scratch_team_number);
				push(@{$return{successes}}, "Removed team -$scratch_team_name");
			}

			if($return{errors}->[0]){
				$return{new_team}->{team_name} = $scratch_team_name;
				$return{new_team}->{entrants} = join(' ', sort(@entrants));
			}
			info("Triggering cron");
			run_cronjobs();
		}
	}
	my $sth_t = database->prepare("select team_number, team_name from scratch_teams");
	my $sth_e = database->prepare("select entrant_code from scratch_team_entrants where team_number = ? order by entrant_code asc");
	$sth_t->execute();
	while ( my $team = $sth_t->fetchrow_hashref()){
		$sth_e->execute($team->{team_number});
		my @entrants;
		while (my $entrant = $sth_e->fetchrow_hashref()){
			push(@entrants, $entrant->{entrant_code});
		}
		$return{teams}->{ $team->{team_number} } = $team;
		$return{teams}->{ $team->{team_number} }->{entrants} = join(' ', @entrants);
	}
	$return{page} = vars->{page},
	$return{page}->{title} = 'Scratch Teams';
	return template 'scratch-teams.tt', \%return;
};

any ['get', 'post'] => '/api/teams' => sub {
	return encode_json(get_teams());
};

any ['get', 'post'] => '/teams' => sub {
	my $return = {
		teams => get_teams(),
		page => vars->{page},
	};
	$return->{page}->{table_is_searchable} = 1;
	$return->{page}->{title} = 'Teams';
	return template 'teams.tt', $return;
};

sub get_teams{
	# First, checkpoint times
	my %times;
	my $sth = database->prepare("select team_number, checkpoint,
	                             date_format(expected_time, \"%H:%i\") as expected_hhmm,
	                             date_format( timediff( expected_time, now() ), \"%kh%im\") as expected_in
	                             from checkpoints_teams_predictions");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		$times{ $row->{team_number} }->{ $row->{checkpoint} } = $row;
	}

	# TODO: The date_format on next_checkpoint_expected_in only allows for a team to be up to 23h and 59min late, before it rolls to zero
	$sth = database->prepare('select teams.team_number, team_name, route, district, unit, last_checkpoint, next_checkpoint, current_leg,
	                         timestampdiff(SECOND, last_checkpoint_time, CURTIME()) as seconds_since_checkpoint,
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

any ['get', 'post'] => '/team' => sub {
	my $team = param('team');
	if($team =~ m/^-?\d+$/){
		redirect "/team/$team";
	}else{
		redirect "/teams";
	}
};

any ['get', 'post'] => '/api/team/:team' => sub {
	return encode_json(get_team( param('team')));
};

any ['get', 'post'] => '/team/:team' => sub {
	my $return = {
		page => vars->{page},
		team => get_team( param('team') ),
	};
	$return->{page}->{title} = 'Team ' . $return->{team}->{team_name};
	return template 'team.tt', $return;
};

sub get_team{
	my $team_number = shift;
	$team_number =~ s/[^-\d]+//;
	# TODO: The date_format on next_checkpoint_expected_in only allows for a team to be up to 23h and 59min late, before it rolls to zero
	my $sth = database->prepare('select team_number, team_name, route, district, unit, last_checkpoint, next_checkpoint,
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
		return %team;
	}

	unless($team{last_checkpoint} == 99){
		$sth = database->prepare('select checkpoint,
					 date_format(expected_time, "%H:%i") as expected_hhmm,
					 date_format( timediff( expected_time, now() ), "%kh%im") as expected_in
					 from checkpoints_teams_predictions
					 where team_number = ?');
		$sth->execute($team_number);
		my $cp_expected_times = $sth->fetchall_hashref('checkpoint');

		$sth = database->prepare('select `to` from legs
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

	$sth = database->prepare('select checkpoint, date_format(time, "%H:%i") as hhmm
	                         from checkpoints_teams where team_number = ?
	                         order by checkpoint asc;');
	$sth->execute($team_number);
	$team{previous_checkpoints} = $sth->fetchall_hashref('checkpoint');

	$sth = database->prepare("select code, entrant_name, retired from entrants where team = ?");
	$sth->execute($team_number);

	while(my $row = $sth->fetchrow_hashref()){
		$team{entrants}->{ $row->{code} } = $row;
		$team{active_entrants} = $row->{code} unless $row->{retired} > 0;
	}

	$sth = database->prepare('select team_name as scratch_team_name,
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
		my $sth = database->prepare('select scratch_team_entrants.entrant_code, teams.team_number, teams.team_name
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

	my %legs_seconds;
	$sth = database->prepare("select seconds, legs.leg_name as leg_name, route_name, `index`, `to`
	                          from routes join legs on legs.leg_name = routes.leg_name where route_name = ?");
	$sth->execute( $team{route} );
	while(my $row = $sth->fetchrow_hashref()){
		$legs_seconds{ $row->{index} } = $row;
	}

	return \%team;
};

# # # # # UTILITIES
any ['get','post'] => '/admin' => sub {
	my $sth = database->prepare("select name, value, notes from config");
	my %return;
	if(param('do') and param('do') eq 'crons'){
		my $output = run_cronjobs();
		$return{'done'} = 'Updated from felltrack: '.$output;
		$return{page}->{time_since_last_felltrack_update} = '0h0m';
		$return{page}->{seconds_since_last_felltrack_update} = '1';

	}
	if(param('do') and param('do') eq 'clear-database'){
		clear_cache();
		$return{'done'} = 'Cleared database tables';
	}
	if(param('update')){
		my $sth_update = database->prepare("update config set value = ? where name = ?");

		$sth->execute();
		while (my $row = $sth->fetchrow_hashref()){
			unless(param($row->{name}) eq $row->{value}){
				debug("Updating config setting $row->{name} to '".param($row->{name})."' from '$row->{value}'");
				push(@{$return{changes}}, "Updated $row->{name} to '".param($row->{name})."' from '$row->{value}'");
				$sth_update->execute( param($row->{name}), $row->{name} );
			}
		}
	}
	$sth->execute();
	$return{config} = $sth->fetchall_hashref('name');

	$sth = database->prepare("select name, message,
	                          date_format(time, \"%H:%i\") as time,
	                          date_format( timediff(now(), time ), \"%kh%im\") as time_since
				  from logs order by time desc");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		push(@{ $return{logs} }, $row);
	}

	$return{page} = vars->{page};
	$return{page}->{title} = 'Admin';
	return template 'admin.tt', \%return;
};

any ['get', 'post'] => '/clear-cache' => sub {
	clear_cache();
	return "Cleanup done, you can now click 'back' to get back to where you were";
};

sub clear_cache(){
	info("Clearing cache");
	my @tables = qw/checkpoints_teams checkpoints_teams_predictions entrants legs routes routes_checkpoints teams logs scratch_teams scratch_team_entrants/;
	foreach my $table (@tables){
		# Can't use placeholders here because dbh adds quotes and   delete from 'table_name'  is invalid
		my $sth = database->prepare("delete from $table");
		$sth->execute();
		debug("Cleared $table");
	}
	my $sth = database->prepare("replace into logs (`message`, `name`) values ('Cleared all tables', 'clear_cache')");
	$sth->execute();
	$sth=database->prepare('alter table scratch_teams auto_increment = 1');
	$sth->execute();
}

any ['get', 'post'] => '/cron' => sub {
	run_cronjobs();
	if(request_header('referer')){
		redirect request_header('referer');
	}
	return "Cronjobs done, you can now click 'back' to get back to where you were";
};

sub run_cronjobs(){
	my $cmd = join(" ", cwd()."/bin/get-data", vars->{felltrack_owner}, vars->{felltrack_username}, vars->{felltrack_password});

	my $sth_log = database->prepare("replace into logs (`message`, `name`) values (?, ?)");

	if (vars->{ignore_future_events} and vars->{ignore_future_events} eq 'on'){
		$ENV{IGNORE_FUTURE_EVENTS} = 1;
	}
	if (vars->{skip_fetch_from_felltrack} and vars->{skip_fetch_from_felltrack} eq 'on'){
		$ENV{SKIP_FETCH_FROM_FELLTRACK} = 1;
	}else{
		$ENV{SKIP_FETCH_FROM_FELLTRACK} = undef;
	}

	info("Cron: Getting data: $cmd");
	my $output = '';
	foreach my $line (qx/$cmd/){
		chomp($line);
		info(">  $line");
		$output .= $line;
	}
	$sth_log->execute($output, 'get-data');
	info("Exited: $?");

	$cmd = cwd().'/bin/progress-to-db';
	info("Cron: Updating DB from CSV : $cmd");
	$output = '';
	foreach my $line (qx/$cmd/){
		chomp($line);
		$output .= $line;
		info(">  $line");
	}
	$sth_log->execute($output, 'progress-to-db');
	info("Exited: $?");


	#info("Cron: Updating legs");

	# First, get every possible leg given the routes definition into the legs table
	my $sth = database->prepare("select name, value from config where name like 'route%'");
	my $sth_update = database->prepare("replace into legs (`from`, `to`, `leg_name`) values (?, ?, ?)");
	$sth->execute;
	while(my $row = $sth->fetchrow_hashref()){
		my $route = $row->{name};
		$route =~ s/^route_//;
		my $last_cp = undef;
		foreach my $cp ( split(m/\s+/, $row->{value}) ){
			if(!$last_cp){
				$last_cp = $cp;
			}else{
				my $leg = $last_cp . '-' . $cp;
				$sth_update->execute($last_cp, $cp, $leg);
				$last_cp = $cp;
			}
		}
	}

	# Then use the teams stats to update the checkpoints_teams table (which stores the
	# arrival time at each checkpoint for each team)
	my $legs = {};
	$sth = database->prepare("select checkpoint, previous_checkpoint, seconds_since_previous_checkpoint from checkpoints_teams order by time desc");
	$sth->execute();
	while (my $row = $sth->fetchrow_hashref()){
		my $leg_name = $row->{previous_checkpoint}."-".$row->{checkpoint};
		push(@{$legs->{$leg_name}}, $row->{seconds_since_previous_checkpoint});
	}
	# And then update the legs table to add a 'seconds' value for those legs that teams
	# have completed, by calculating an average time taken
	$sth = database->prepare("replace into legs (`leg_name`, `from`, `to`, `seconds`) values (?, ?, ?, ?)");
	foreach my $leg(keys(%{$legs})){
		my ($from,$to) = split(m/-/, $leg);
		my $expected_seconds = get_percentile($legs->{$leg});
		next if $leg eq '0-0';
		$sth->execute($leg, $from, $to, $expected_seconds);
	}

	#info("Cron: Adding expected times to teams");
	add_expected_times_to_teams();
	$sth_log->execute('completed', 'periodic-jobs');
	return $output;
}


sub add_expected_times_to_teams {
	# First, a couple of look-up hashes which we'll use to estimate time-to-finish. We need to find out where in the ordered list
	# of legs for a given route the current leg comes, and then retrieve each of those that come after it.
	my %index_to_leg;
	my %leg_to_index;
	my %legs;
	my $sth = database->prepare("select * from routes join legs on routes.leg_name = legs.leg_name");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		$index_to_leg{ $row->{route_name} }->{ $row->{index} } = $row->{leg_name};
		$leg_to_index{ $row->{route_name} }->{ $row->{leg_name} } = $row->{index};
		$legs{ $row->{leg_name} } = $row;
	}

	$sth = database->prepare("select team_number, route, last_checkpoint, next_checkpoint, current_leg,
	                         `index` as leg_index,
	                         unix_timestamp(last_checkpoint_time) as last_checkpoint_time_epoch
	                         from teams
	                         join routes on routes.route_name = teams.route
	                           and routes.leg_name = teams.current_leg
	                         where completed < 1");
	my $sth_update = database->prepare("replace into checkpoints_teams_predictions set checkpoint = ?, team_number = ?, expected_time = from_unixtime(?)");
	$sth->execute();
	my $teams = $sth->fetchall_hashref('team_number');
	foreach my $team_number (keys(%{$teams})){
		my %team = %{$teams->{$team_number}};

		unless($team{current_leg}){
			error("Team $team_number has no current_leg");
		}
		unless( $team{last_checkpoint_time_epoch} ){
			error("Team $team_number has no last_checkpoint_time_epoch");
		}

		my $expected_time = $team{last_checkpoint_time_epoch} or error ("Team $team_number has no last_checkpoint_time_epoch");
		my $current_leg = $team{current_leg} or error("Team $team_number has no current_leg");

		my $leg_index = $leg_to_index{ $team{route} }->{ $team{current_leg} };
		while(my $leg_name = $index_to_leg{ $team{route} }->{$leg_index} ){
			my $seconds;
			unless($legs{$leg_name}->{to}){
				error("No next-checkpoint for team $team_number on leg $leg_name on route $team{route}");
				next;
			}
			if($legs{$leg_name}->{seconds}){
				$expected_time += $legs{$leg_name}->{seconds} * vars->{leg_estimate_multiplier};
				$sth_update->execute($legs{$leg_name}->{to}, $team_number, $expected_time);
			}else{
				#info("No prediction data for leg $leg_name for team $team_number; skipping the rest of the legs");
				last;
			}

			$leg_index++;
		}
	}
}

# # # # # DATA MUNGING

# We have two formats for times. A time is always represented as
# HH:MM, and a time _period_ as `HHh MMm`
# All our times are dealt with in seconds generally, so these two
# subs take the seconds and return the appropriate format
#
sub to_hhmm{
	my $epoch_time = shift;
	my $separator = ':';
	$separator = $_ if $_;
	my ($h,$m) = (localtime($epoch_time))[2,1];
	return(sprintf("%02s:%02s", $h, $m));
}
sub to_hh_mm{
	my $epoch_time = shift;
	my ($h,$m) = (localtime($epoch_time))[2,1];
	return(sprintf("%01sh %02sm", $h, $m));
}

sub get_percentile{
	my @in = @{$_[0]};

	my $percentile = 90;
	if(vars->{percentile}){
		$percentile = vars->{percentile};
	}

	my @numbers;
	# If the whole set of numbers we have is already smaller than the percentile_min_sample
	# then we do not want to shrink it further by taking only the most-recent percentile_sample_size
	if (vars->{'percentile_min_sample'} and scalar(@in) >= vars->{percentile_min_sample} and
	    vars->{'percentile_sample_size'} and vars->{'percentile_sample_size'} > 0 ){
		#info("Pcile sample before: ".scalar(@in));
		my $index = int((vars->{'percentile_sample_size'}/100) * $#in - 1 );
		for(0 .. $index){
			push(@numbers, $in[$index]);
		}
		#info("Pcile sample after: ".scalar(@numbers));
		#info("Index: $index");
		@numbers = sort(@numbers);
	}else{
		@numbers = reverse(@in);
	}

	# Having potentially shrunk the sample above, check it's still big enough for a percentile.
	if (vars->{percentile_min_sample} and scalar(@numbers) < vars->{percentile_min_sample} ){
		#info("Not enough samples for pcile (".scalar(@numbers)." < percentile_min_sample of ".vars->{percentile_min_sample}."), using mean");
		my $sum = 0;
		map { $sum += $_ } @in;
		return $sum / scalar(@in);
	}

	my $index = int(($percentile/100) * $#numbers - 1);
	return $numbers[$index];
}
