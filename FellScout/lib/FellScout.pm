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
	my $sth = database->prepare("select distinct route_name from routes order by route_name");
	my @routes;
	$sth->execute();
	while (my $row = $sth->fetchrow_hashref()){
		my $route = $row->{route_name};

		my $t_min_cp_sth = database->prepare("select last_checkpoint from teams where completed = 0 and route = ? order by last_checkpoint asc limit 1");
		$t_min_cp_sth->execute($route);
		$summary{routes}->{$route}->{min_cp} = ($t_min_cp_sth->fetchrow_array())[0];

		my $t_max_cp_sth = database->prepare("select last_checkpoint from teams where completed = 0 and route = ? order by last_checkpoint desc limit 1");
		$t_max_cp_sth->execute($route);
		$summary{routes}->{$route}->{max_cp} = ($t_max_cp_sth->fetchrow_array())[0];

		my $t_still_out_sth = database->prepare("select team_number, team_name, unit, district, last_checkpoint from teams where completed = 0 and route = ? order by team_number asc");
		$t_still_out_sth->execute($route);
		my $num_out = 0;
		while ( my $row = $t_still_out_sth->fetchrow_hashref()){
			$num_out++;
			push(@{$summary{routes}->{$route}->{teams_out}}, $row->{team_number});
		}
		$summary{routes}->{$route}->{num_not_completed} = $num_out;
	}
	return \%summary;
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
	$sth = database->prepare("select `from`, `to`, `seconds` from legs");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		my $leg_name = $row->{from} . '-' . $row->{'to'};
		$legs->{$leg_name} = {
			seconds => $row->{seconds},
			minutes => sprintf("%0.2f", $row->{seconds} / 60 ),
			hours => sprintf("%0.2f", $row->{seconds} / 3600),
			teams => $teams{$leg_name},
		}
	}
	return $legs;
}

# # # # # ENTRANTS

get '/api/entrants' => sub {
	return encode_json(get_entrants());
};

get '/entrants' => sub {
	return template 'entrants2.tt', {entrants => get_entrants()};
};

sub get_entrants(){
	my $sth = database->prepare("select * from entrants join teams on entrants.team = teams.team_number");
	$sth->execute();
	return $sth->fetchall_hashref('code');
}

# # # # # TEAMS

get '/api/teams' => sub {
	return encode_json(get_teams());
};

get '/teams' => sub {
	return template 'teams2.tt', {teams => get_teams()};
};

sub get_teams{
	# TODO: The date_format on next_checkpoint_expected_in only allows for a team to be up to 23h and 59min late, before it rolls to zero
	my $sth = database->prepare("select team_number , team_name, route, district, unit, last_checkpoint, next_checkpoint,
	                            current_leg, next_checkpoint_expected_time, finish_expected_time,
	                            date_format(next_checkpoint_expected_time, \"%H:%i\") as next_checkpoint_expected_hhmm,
	                            date_format(finish_expected_time, \"%H:%i\") as finish_expected_hhmm,
	                            date_format(last_checkpoint_time, \"%H:%i\") as last_checkpoint_time_hhmm,
	                            date_format( timediff( next_checkpoint_expected_time, now() ), \"%kh %im\") as next_checkpoint_expected_in,
	                            timestampdiff(SECOND, last_checkpoint_time, CURTIME()) as seconds_since_checkpoint,
	                            unix_timestamp(last_checkpoint_time) as last_checkpoint_time_epoch
	                            from teams where completed = 0");
	$sth->execute();
	my $teams = $sth->fetchall_hashref('team_number');
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
	$team_number =~ s/[^\d]+//;

	my %team;
	my @entrants;
	# TODO: The date_format on next_checkpoint_expected_in only allows for a team to be up to 23h and 59min late, before it rolls to zero
	my $sth = database->prepare("select team_number , team_name, route, district, unit, last_checkpoint, next_checkpoint,
	                             current_leg, next_checkpoint_expected_time, finish_expected_time,
	                             date_format(next_checkpoint_expected_time, \"%H:%i\") as next_checkpoint_expected_hhmm,
	                             date_format(finish_expected_time, \"%H:%i\") as finish_expected_hhmm,
	                             date_format(last_checkpoint_time, \"%H:%i\") as last_checkpoint_time_hhmm,
	                             date_format( timediff( next_checkpoint_expected_time, now() ), \"%kh %im\") as next_checkpoint_expected_in,
	                             timestampdiff(SECOND, last_checkpoint_time, CURTIME()) as seconds_since_checkpoint,
	                             unix_timestamp(last_checkpoint_time) as last_checkpoint_time_epoch
	                             from teams where team_number = ?");
	$sth->execute($team_number);
	%team = %{$sth->fetchall_hashref('team_number')};
	$sth = database->prepare("select * from entrants where team = ?");
	$sth->execute($team_number);
	while(my $row = $sth->fetchrow_hashref()){
	 $team{$team_number}->{entrants}->{ $row->{code} } = $row->{entrant_name};
	}
	return $team{$team_number};
	#TODO: Sub out remaining legs
};

# # # # # UTILITIES
any ['get','post'] => '/config' => sub {
	my $sth = database->prepare("select name, value from config");
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
	return template 'config.tt', {config => $sth->fetchall_hashref('name')};
};

get '/cron' => sub {

	my $cmd = join(" ", cwd()."/bin/get-data", vars->{felltrack_owner}, vars->{felltrack_username}, vars->{felltrack_password});
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
	my $legs = {};
	my $sth = database->prepare("select checkpoint, previous_checkpoint, seconds_since_previous_checkpoint from checkpoints_teams");
	$sth->execute();
	while (my $row = $sth->fetchrow_hashref()){
		my $leg_name = $row->{previous_checkpoint}."-".$row->{checkpoint};
		push(@{$legs->{$leg_name}}, $row->{seconds_since_previous_checkpoint});
	}
	$sth = database->prepare("replace into legs (`leg_name`, `from`, `to`, `seconds`) values (?, ?, ?, ?)");
	foreach my $leg(keys(%{$legs})){
		my ($from,$to) = split(m/-/, $leg);
		my $expected_seconds = get_percentile($legs->{$leg});
		$sth->execute($leg, $from, $to, $expected_seconds);
	}

	info("Cron: Adding expected times to teams");
	add_expected_times_to_teams()
};


sub add_expected_times_to_teams {
	# First, a couple of look-up hashes which we'll use to estimate time-to-finish. We need to find out where in the ordered list
	# of legs for a given route the current leg comes, and then retrieve each of those that come after it.
	my %index_to_leg;
	my %legs;
	my $sth = database->prepare("select * from routes join legs on routes.leg_name = legs.leg_name");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		$index_to_leg{ $row->{route_name} }->{ $row->{index} } = $row->{leg_name};
		$legs{ $row->{leg_name} } = $row->{seconds};
	}
	$sth = database->prepare("select team_number, route, last_checkpoint, next_checkpoint, current_leg,
	                         `index` as leg_index,
	                         unix_timestamp(last_checkpoint_time) as last_checkpoint_time_epoch
	                         from teams
	                         join routes on routes.route_name = teams.route
	                         and routes.leg_name = teams.current_leg
	                         where completed < 1");
	my $sth_update = database->prepare("update teams set next_checkpoint_expected_time = from_unixtime(?), finish_expected_time = from_unixtime(?) where team_number = ?");
	$sth->execute();
	my $teams = $sth->fetchall_hashref('team_number');
	foreach my $team_number (keys(%{$teams})){
		info("Team $team_number");
		# First, time expected at next checkpoint
		info("epoch: $teams->{$team_number}->{last_checkpoint_time_epoch} leg: $legs{ $teams->{$team_number}->{current_leg} }");
		my $next_checkpoint_expected_time = $teams->{$team_number}->{last_checkpoint_time_epoch} + $legs{ $teams->{$team_number}->{current_leg} };

		# Now time expected at finish
		my $leg_index = $teams->{$team_number}->{leg_index};
		info("Team: $team_number; Leg: $teams->{$team_number}->{current_leg}, Route: $teams->{$team_number}->{route}; idx: $leg_index");
		my $seconds_to_finish = $legs{$leg_index};
		while($index_to_leg{ $teams->{ $team_number}->{ route } }->{$leg_index} ){
			my $leg = $index_to_leg{ $teams->{ $team_number }->{route} }->{$leg_index};
			info("Adding $legs{$leg} seconds for leg $leg");
			$seconds_to_finish += $legs{$leg};
			$leg_index++;
		}
		my $finish_expected_time = $teams->{ $team_number }->{last_checkpoint_time_epoch} + $seconds_to_finish;
		info("$team_number: $next_checkpoint_expected_time, $finish_expected_time");
		$sth_update->execute( $next_checkpoint_expected_time, $finish_expected_time, $team_number);
	}
}

# # # # # DATA MUNGING

sub to_hhmm{
	my $epoch_time = shift;
	my ($h,$m) = (localtime($epoch_time))[2,1];
	return(sprintf("%02s:%02s", $h, $m));
}

sub get_percentile{
	my $n = shift;
	my @numbers = sort(@{$n});
	my $percentile = vars->{percentile};
	if(scalar(@numbers) <=4){
		#info("Not enough samples for pcile, getting mean of ".scalar(@numbers)." numbers: ".join(', ', @numbers));
		my $sum = 0;
		map { $sum += $_ } @numbers;
		return $sum / scalar(@numbers);
	}
	my $index = int(($percentile/100) * $#numbers - 1);
	return $numbers[$index];
}
