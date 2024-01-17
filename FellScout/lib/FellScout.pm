package FellScout;

use Dancer2;
use Dancer2::Plugin::Database;
use Data::Dumper;
use POSIX qw(strftime);
use Cwd;

our $VERSION = '0.1';
#TODO: Ignore teams configures as being for-ignoring
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
  my $sth = database->prepare("select concat(`from`, '-', `to`) as leg, seconds from legs;");
  $sth->execute();
  my $legs = $sth->fetchall_hashref("leg");
  $sth = database->prepare("select team_number , team_name, route, district, unit, last_checkpoint, next_checkpoint,
                              concat(last_checkpoint, '-', next_checkpoint) as leg,
                              date_format(last_checkpoint_time, \"%H:%i\") as last_checkpoint_time_hhmm,
                              timestampdiff(SECOND, last_checkpoint_time, CURTIME()) as seconds_since_checkpoint,
                              unix_timestamp(last_checkpoint_time) as last_checkpoint_time_epoch
                              from teams where completed = 0");
  $sth->execute();
  my $teams = $sth->fetchall_hashref('team_number');
  foreach my $team_number (keys(%{$teams})){
    my $expected_epoch = $teams->{$team_number}->{last_checkpoint_time_epoch} + $legs->{ $teams->{$team_number}->{leg} }->{seconds};
    $teams->{$team_number}->{next_checkpoint_expected_hhmm} = sprintf("%02d:%02d", (localtime($expected_epoch))[2,1]);
    $teams->{$team_number}->{next_checkpoint_lateness} = int((time() - $expected_epoch) / 60);
    #TODO: Add expected-at-finish
    #TODO: another page (/all-teams?) to show also those teams who have already finished
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
  $team_number =~ s/[^\d]+//;

  my %team;
  my @entrants;
  my $sth = database->prepare("select * from teams where team_number = ?");
  $sth->execute($team_number);
  %team = %{$sth->fetchall_hashref('team_number')};

  $sth = database->prepare("select * from entrants where team = ?");
  $sth->execute($team_number);
  while(my $row = $sth->fetchrow_hashref()){
   $team{$team_number}->{entrants}->{ $row->{code} } = $row->{entrant_name};
  }
  return $team{$team_number};

  #TODO: Sub out next-checkpoint-expected time & lateness
  #TODO: Sub out expected-at-finish time
  #TODO: Sub out remaining legs
};

# # # # # CRON JOBS
get '/cron/legs' => sub {
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
    # TODO: Make this a config option
    my $expected_seconds = get_percentile(90, $legs->{$leg});
    $sth->execute($leg, $from, $to, $expected_seconds);
  }
};
# # # # # DATA MUNGING

sub to_hhmm{
  my $epoch_time = shift;
  my ($h,$m) = (localtime($epoch_time))[2,1];
  return(sprintf("%02s:%02s", $h, $m));
}

sub get_percentile{
  my $percentile = shift;
  my $n = shift;
  my @numbers = sort(@{$n});
  if(scalar(@numbers) <=4){
    #info("Not enough samples for pcile, getting mean of ".scalar(@numbers)." numbers: ".join(', ', @numbers));
    my $sum = 0;
    map { $sum += $_ } @numbers;
    return $sum / scalar(@numbers);
  }
  my $index = int(($percentile/100) * $#numbers - 1);
  return $numbers[$index];
}
