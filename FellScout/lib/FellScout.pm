package FellScout;

use Dancer2;
use Dancer2::Plugin::Database;
use Data::Dumper;
use POSIX qw(strftime);
use Cwd;

our $VERSION = '0.1';

if($ENV{'MYSQL_HOST'}){
	database({
		driver => 'mysql',
			username => $ENV{'MYSQL_USERNAME'},
			password => $ENV{'MYSQL_PASSWORD'},
			host => $ENV{'MYSQL_HOST'},
			port => $ENV{'MYSQL_PORT'},
			database => $ENV{'MYSQL_DATABASE_NAME'}
	});
}


hook 'before' => sub {
	header 'Content-Type' => 'application/json' if request->path =~ m{^/api/};

	my $sth = database->prepare("select name, value from config");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		var $row->{name} => $row->{value};
	}
};

# # # # # SUMMARY
get '/' => sub{
	return template 'summary.tt', {summary => get_summary()};
};

get '/api/summary' => sub{
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

	$summary{laterunners} = get_laterunners();

	return \%summary;
}
# # # # # laterunners
get '/laterunners' => sub {
	return template 'laterunners.tt', {laterunners => get_laterunners()};
};
get '/api/laterunners/' => sub{
	return encode_json(laterunners => get_laterunners());
};

sub get_laterunners(){
	my @laterunners;
	my $sth = database->prepare("select teams.team_number, team_name, unit, district, route, next_checkpoint, last_checkpoint,
	                             date_format(last_checkpoint_time, \"%H:%i\") as last_checkpoint_time,
	                             date_format(checkpoints_teams_predictions.expected_time, \"%H:%i\") as next_checkpoint_expected_time,
	                             date_format( timediff( checkpoints_teams_predictions.expected_time, now() ), \"%kh%im\") as next_checkpoint_expected_in
	                             from teams
	                             join checkpoints_teams_predictions on
	                               checkpoints_teams_predictions.team_number = teams.team_number
	                               and checkpoints_teams_predictions.checkpoint = teams.next_checkpoint
	                             order by checkpoints_teams_predictions.expected_time desc;");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		push(@laterunners, $row);
	}
	return \@laterunners;
}
# # # # # LEGS + CHECKPOINTS
get '/legs' => sub {
	my $legs = get_legs();
	return template 'legs.tt', {legs => $legs};
};

get '/api/legs' => sub{
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
	$sth = database->prepare("select leg_name, `from`, `to`, date_format(from_unixtime(seconds), \"%kh %im\") as time from legs");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		$legs->{ $row->{leg_name} } = $row;
		my $sth = database->prepare("select team_number from teams where current_leg = ?");
		$sth->execute($row->{leg_name});
		while(my $r = $sth->fetchrow_hashref()){
			push(@{ $legs->{ $row->{leg_name} }->{teams} }, $r->{team_number});
		}
	}
	return $legs;
}


get '/checkpoints' => sub {
	my $checkpoints = get_checkpoints();
	return template 'checkpoints.tt', {checkpoints => $checkpoints};
};

get '/api/checkpoints' => sub{
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

get '/checkpoint/:checkpoint' => sub {
	my $checkpoint = get_checkpoint(param('checkpoint'));
	return template 'checkpoint.tt', {checkpoint => $checkpoint};
};

get '/api/checkpoint/:checkpoint' => sub{
	return encode_json( get_checkpoint(param('checkpoint')));
};

sub get_checkpoint(){
	my $checkpoint = shift;
	my %cp;
	$cp{cp} = $checkpoint;

	# First, everyone's finish times
	my $sth = database->prepare("select team_number, date_format(expected_time, \"%H:%i\") as finish_expected_hhmm from checkpoints_teams_predictions where checkpoint = 99");
	$sth->execute();
	my $finish_times = $sth->fetchall_hashref('team_number');

	# And when we expect everyone to get here
	$sth = database->prepare("select team_number,
	                          date_format(expected_time, \"%H:%i\") as this_checkpoint_expected_hhmm,
	                          date_format( timediff( expected_time, now() ), \"%kh %im\")
	                          from checkpoints_teams_predictions
	                          where checkpoint = ?");
	$sth->execute($checkpoint);
	my $checkpoint_times = $sth->fetchall_hashref('team_number');


	# And now details for every team that has yet to get here
	$sth = database->prepare("select distinct route_name from routes");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		my $route = $row->{'route_name'};
		my $sth = database->prepare("select teams.team_number as team_number, team_name, next_checkpoint, route, unit, district,
		                            date_format(checkpoints_teams_predictions.expected_time, \"%H:%i\") as next_checkpoint_expected_hhmm,
		                            unix_timestamp(last_checkpoint_time) as last_checkpoint_time_epoch,
		                            date_format(last_checkpoint_time, \"%H:%i\") as last_checkpoint_time_hhmm,
		                            date_format(checkpoints_teams_predictions.expected_time, \"%H:%i\") as next_checkpoint_expected_hhmm,
		                            date_format( timediff( checkpoints_teams_predictions.expected_time, now() ), \"%kh%im\") as next_checkpoint_expected_in,
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
		                                (select `index` from routes where route_name=? and leg_name like '%-$checkpoint'))");
		$sth->execute($route, $route);
		while(my $team = $sth->fetchrow_hashref()){
			$team->{finish_expected_hhmm} = $finish_times->{$team->{team_number}}->{finish_expected_hhmm};
			$team->{finish_expected_in} = $finish_times->{$team->{team_number}}->{finish_expected_in};
			$team->{this_cp_expected_hhmm} = $checkpoint_times->{$team->{team_number}}->{this_checkpoint_expected_hhmm};
			$team->{this_cp_in} = $checkpoint_times->{$team->{team_number}}->{this_checkpoint_expected_in};
			push(@{$cp{teams}}, $team);
		}
	}
	return \%cp
}

# # # # # ENTRANTS

get '/api/entrants' => sub {
	return encode_json(get_entrants());
};

get '/entrants' => sub {
	return template 'entrants.tt', {entrants => get_entrants()};
};

sub get_entrants(){
	my $sth = database->prepare("select * from entrants join teams on entrants.team = teams.team_number");
	$sth->execute();
	return $sth->fetchall_hashref('code');
}

# # # # # TEAMS
any ['get','post'] => '/scratch-teams' => sub {

	my @errors;

	my $sth_all_entrants = database->prepare("select code from entrants");
	$sth_all_entrants->execute;
	my $all_entrants = $sth_all_entrants->fetchall_hashref('code');

	my $sth_t = database->prepare("select team_number, team_name from scratch_teams");
	my $sth_e = database->prepare("select entrant_code from scratch_team_entrants where team_number = ? order by entrant_code asc");

	my %scratch_teams;
	my %scratch_team_names;
	my %scratch_entrants;
	$sth_t->execute();
	while ( my $team = $sth_t->fetchrow_hashref()){
		$sth_e->execute($team->{team_number});
		my @entrants;
		while (my $entrant = $sth_e->fetchrow_hashref()){
			push(@entrants, $entrant->{entrant_code});

			$scratch_entrants{ $entrant->{entrant_code} } = $team->{team_number};
		}

		$scratch_teams{teams}->{ $team->{team_number} } = $team;
		$scratch_teams{teams}->{ $team->{team_number} }->{entrants} = join(' ', @entrants);

		$scratch_team_names{ lc($team->{team_name}) } = $team->{team_number};
	}

	if(param('update') or param('add')){
		my $team_name = param('team_name');
		$team_name =~ s/[^\w\s\.\,\?\!\"\']//;
		if($scratch_team_names{ lc($team_name) }){
			push(@errors, "There is already a scratch team called '$team_name'; names need to be unique (this check doesn't consider capital letters)");
			error("Duplicate scratch team: '$team_name'");
		}
		
		my @entrants;
		foreach my $entrant (split(m/\s+/, param('entrants'))){
			if($entrant =~ m/(\d+[a-zA-Z])/){
				$entrant = uc($entrant);
				if($scratch_entrants{ $entrant }){
					push(@errors, "Entrant '$entrant' is already in scratch team -$scratch_entrants{ $entrant }; perhaps remove them from that first?");
					error("Entrant $entrant tried to be added to two scratch teams");
				}
				unless($all_entrants->{$entrant}){
					push(@errors, "There is no entrant with code '$entrant'");
					error("Tried to add non-existent entrant $entrant");
				}
				push(@entrants, uc($1));
			}
		}


		if(@errors){
			$scratch_teams{new_team} = { team_name => $team_name, entrants => join(' ', @entrants) };
			$scratch_teams{errors} = \@errors;
		}else{
			if(param('add')){
				my $sth_team = database->prepare("insert into scratch_teams (team_name) values (?)");
				my $sth_entrant = database->prepare("insert into scratch_team_entrants (team_number, entrant_code) values (?,?)");
				
				$sth_team->execute($team_name);
				my $team_number = database->{mysql_insertid};
				foreach my $entrant_code (@entrants){
					$sth_entrant->execute($team_number, $entrant_code);
				}
				info("Created scratch team $team_number as $team_name with entrants ".join(' ', @entrants));

			}elsif(param('update')){
				my $team_number = param('team_number');
				$team_number =~ s/[^\d]//;

				my $sth_team = database->prepare("update scratch_teams set team_name = ? where team_number = ?");
				my $sth_entrant = database->prepare("replace into scratch_team_entrants (team_number, entrant_code) values (?,?)");

				$sth_team->execute($team_name, $team_number);
				foreach my $entrant_code (@entrants){
					$sth_entrant->execute($team_number, $entrant_code);
				}
				info("Updated scratch team $team_number as '$team_name' with entrants ".join(' ', @entrants));
			}
			# Now update the scratch_teams hash to show the new ones
			$sth_t->execute();
			while ( my $team = $sth_t->fetchrow_hashref()){
				$sth_e->execute($team->{team_number});
				my @entrants;
				while (my $entrant = $sth_e->fetchrow_hashref()){
					push(@entrants, $entrant->{entrant_code});
				}
				$scratch_teams{teams}->{ $team->{team_number} } = $team;
				$scratch_teams{teams}->{ $team->{team_number} }->{entrants} = join(' ', @entrants);
			}
			# And update all the other tables:
			info("Triggering cron");
			run_cronjobs();
		}
	}
	return template 'scratch-teams.tt', \%scratch_teams;
	#return encode_json(\%scratch_teams);
};

get '/api/teams' => sub {
	return encode_json(get_teams());
};

get '/teams' => sub {
	return template 'teams.tt', {teams => get_teams()};
};

sub get_teams{
	# First, everyone's finish times
	my $sth = database->prepare("select team_number, date_format(expected_time, \"%H:%i\") as finish_expected_hhmm from checkpoints_teams_predictions where checkpoint = 99");
	$sth->execute();
	my $finish_times = $sth->fetchall_hashref('team_number');

	# TODO: The date_format on next_checkpoint_expected_in only allows for a team to be up to 23h and 59min late, before it rolls to zero
	$sth = database->prepare("select teams.team_number, team_name, route, district, unit, last_checkpoint, next_checkpoint, current_leg,
	                         date_format(checkpoints_teams_predictions.expected_time, \"%H:%i\") as next_checkpoint_expected_hhmm,
	                         date_format( timediff( checkpoints_teams_predictions.expected_time, now() ), \"%kh%im\") as next_checkpoint_expected_in,
	                         date_format(last_checkpoint_time, \"%H:%i\") as last_checkpoint_hhmm,
	                         timestampdiff(SECOND, last_checkpoint_time, CURTIME()) as seconds_since_checkpoint,
	                         unix_timestamp(last_checkpoint_time) as last_checkpoint_time_epoch
	                         from teams
	                         join checkpoints_teams_predictions on
	                           checkpoints_teams_predictions.team_number = teams.team_number
	                           and checkpoints_teams_predictions.checkpoint = teams.next_checkpoint
	                         where completed = 0");
	$sth->execute();
	my $teams;
	while (my $row = $sth->fetchrow_hashref()){
		$row->{finish_expected_hhmm} = $finish_times->{ $row->{team_number} }->{finish_expected_hhmm};
		$teams->{ $row->{team_number} } = $row;
	}

	return $teams;
}

get '/api/team/:team' => sub {
	return encode_json(get_team( param('team')));
};

get '/team/:team' => sub {
	return template 'team.tt', get_team( param('team'));
};

sub get_team{
	my $team_number = shift;
	$team_number =~ s/[^-\d]+//;
	info("Team number: $team_number");

	my %cp_times;
	my $sth = database->prepare("select checkpoint,
	                             date_format(expected_time, \"%H:%i\") as expected_hhmm,
	                             date_format( timediff( expected_time, now() ), \"%kh%im\") as expected_in
	                             from checkpoints_teams_predictions
	                             where team_number = ?");
	$sth->execute($team_number);
	while (my $row = $sth->fetchrow_hashref){
		$cp_times{ $row->{checkpoint} } = $row;
	}

	# TODO: The date_format on next_checkpoint_expected_in only allows for a team to be up to 23h and 59min late, before it rolls to zero
	$sth = database->prepare("select team_number, team_name, route, district, unit, last_checkpoint, next_checkpoint,
	                         current_leg, current_leg_index,
	                         date_format(last_checkpoint_time, \"%H:%i\") as last_checkpoint_time_hhmm,
	                         timestampdiff(SECOND, last_checkpoint_time, CURTIME()) as seconds_since_checkpoint,
	                         unix_timestamp(last_checkpoint_time) as last_checkpoint_time_epoch
	                         from teams
	                         where team_number = ?");

	$sth->execute($team_number);
	my %team;
	eval {
		%team = %{ ($sth->fetchrow_hashref())[0] };
	};
	if($@){
		error("Team $team_number does not exist");
		return %team;
	}

	$team{next_checkpoint_expected_in}   = $cp_times{ $team{next_checkpoint} }->{expected_in};
	$team{next_checkpoint_expected_hhmm} = $cp_times{ $team{next_checkpoint} }->{expected_hhmm};

	$team{finish_expected_in}   = $cp_times{99}->{expected_in};
	$team{finish_expected_hhmm} = $cp_times{99}->{expected_hhmm};

	$team{remaining_checkpoints} = \%cp_times;

	$sth = database->prepare("select code, entrant_name, retired from entrants where team = ?");
	$sth->execute($team_number);
	while(my $row = $sth->fetchrow_hashref()){
		$team{entrants}->{ $row->{code} } = $row;
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
	if(param('update')){
		my $sth_update = database->prepare("replace into config (name, value) values (?, ?)");

		$sth->execute();
		while (my $row = $sth->fetchrow_hashref()){
			if(param( $row->{name}) and !(param($row->{name}) eq $row->{value}) ){
				debug("Updating config setting $row->{name} to '".param($row->{name})."' from $row->{value}");
				$sth_update->execute( $row->{name}, param($row->{name}) );
			}
		}
	}
	$sth->execute();
	return template 'admin.tt', {config => $sth->fetchall_hashref('name')};
};

get '/clear-cache' => sub {
	info("Clearing cache");
	my @tables = qw/checkpoints_teams checkpoints_teams_predictions entrants legs routes routes_checkpoints teams/;
	foreach my $table (@tables){
		# Can't use placeholders here because dbh adds quotes and   delete from 'table_name'  is invalid
		my $sth = database->prepare("delete from $table");
		$sth->execute();
		debug("Cleared $table");
	}
	return "Cleanup done, you can now click 'back' to get back to where you were";
};

get '/cron' => sub {
	run_cronjobs();
	return "Cronjobs done, you can now click 'back' to get back to where you were";
};

sub run_cronjobs(){
	my $cmd = join(" ", cwd()."/bin/get-data", vars->{felltrack_owner}, vars->{felltrack_username}, vars->{felltrack_password});

	if (vars->{ignore_future_events} and vars->{ignore_future_events} eq 'on'){
		$ENV{IGNORE_FUTURE_EVENTS} = 1;
	}
	if (vars->{fetch_from_felltrack} and vars->{fetch_from_felltrack} eq 'off'){
		$ENV{SKIP_FETCH_FROM_FELLTRACK} = 1;
	}

	info("Cron: Getting data: $cmd");
	foreach my $line (qx/$cmd/){
		info(">  $line");
	}
	info("Exited: $?");

	$cmd = cwd().'/bin/progress-to-db';
	info("Cron: Updating DB from CSV : $cmd");
	foreach my $line (qx/$cmd/){
		info(">  $line");
	}
	info("Exited: $?");


	info("Cron: Updating legs");

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
	$sth = database->prepare("select checkpoint, previous_checkpoint, seconds_since_previous_checkpoint from checkpoints_teams");
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
		$sth->execute($leg, $from, $to, $expected_seconds);
	}

	info("Cron: Adding expected times to teams");
	add_expected_times_to_teams();
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
				$expected_time += $legs{$leg_name}->{seconds};
				if(vars->{checkpoint_pause_minutes}){
					$expected_time += vars->{checkpoint_pause_minutes} * 60;
				}
			#debug("Team $team_number expected at cp $legs{$leg_name}->{to} at $expected_time - ".to_hhmm($expected_time)."  (added $legs{$leg_name}->{seconds}s, ".$legs{$leg_name}->{seconds} / 60 ."min)");
			$sth_update->execute($legs{$leg_name}->{to}, $team_number, $expected_time);
			}else{
				info("No prediction data for leg $leg_name for team $team_number; skipping the rest of the legs");
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
	my $n = shift;
	my @numbers = sort(@{$n});
	my $percentile = 90;
	if(vars->{percentile}){
		$percentile = vars->{percentile};
	}
	if(scalar(@numbers) <=4){
		#info("Not enough samples for pcile, getting mean of ".scalar(@numbers)." numbers: ".join(', ', @numbers));
		my $sum = 0;
		map { $sum += $_ } @numbers;
		return $sum / scalar(@numbers);
	}
	my $index = int(($percentile/100) * $#numbers - 1);
	return $numbers[$index];
}
