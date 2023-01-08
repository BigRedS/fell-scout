package FellScout;

use Dancer2;
# https://stackoverflow.com/questions/15770114/prototype-mismatch-error-perl
use JSON qw//;
use Data::Dumper;
use POSIX qw(strftime);
use Cwd;

our $VERSION = '0.1';

hook 'before' => sub{
  my $progress_data = load_progress_csv();
  var entrants_progress => $progress_data->{entrants};
  my $ignore_teams = config->{ignore_teams};
  foreach my $team_number (keys(%{$ignore_teams})){
    delete($progress_data->{teams}->{$team_number});
  }
  var teams_progress => $progress_data->{teams};
  var route_checkpoints => get_route_checkpoints_hash();
};

get '/legs' => sub {
  template 'legs';
};

get '/api/legs' => sub{
  my $entrants_progress = vars->{entrants_progress};
  header 'Content-Type' => 'application/json';
  encode_json(get_checkpoint_times( $entrants_progress ));
};

get '/' => sub{
  my $entrants_progress = vars->{entrants_progress};
  my $teams_progress = vars->{teams_progress};
  my $routes_cps = vars->{route_checkpoints};
  my $checkpoint_times = get_checkpoint_times( $entrants_progress );

  $teams_progress = add_checkpoint_expected_at_times( $teams_progress, $checkpoint_times);
  #header 'Content-Type' => 'application/json';

  my $summary = get_summary($teams_progress);

  return template 'summary.tt', {test => "test", summary => $summary};

  encode_json($summary);
};

get '/api/legs/table' => sub{
  my $entrants_progress = vars->{entrants_progress};
  my $teams_progress = vars->{teams_progress};
  my $checkpoint_times = get_checkpoint_times( $entrants_progress );
  $teams_progress = add_checkpoint_expected_at_times( $teams_progress, $checkpoint_times);
  my $times = get_checkpoint_times ( $entrants_progress );
  return encode_json(create_checkpoint_legs_summary_table($entrants_progress, $teams_progress, $times));
};

sub create_checkpoint_legs_summary_table{
  my $entrants_progress = shift;
  my $teams_progress = shift;
  my $times = shift;

  my %routes_per_leg;
  my %teams_per_leg;
  foreach my $team_number (sort(keys(%{$teams_progress}))){
    my $cur_leg = $teams_progress->{$team_number}->{last_checkpoint}.' '.$teams_progress->{$team_number}->{next_checkpoint};
    $teams_per_leg{$cur_leg}++;

    $routes_per_leg{ $teams_progress->{$team_number}->{route} }++;
  }
  my @rows;
  foreach my $leg (sort(keys(%{$times}))){
    push(@rows, [$leg, sprintf("%0.0f", $times->{$leg}->{ninetieth_percentile} / 60), $teams_per_leg{$leg}] );
  }
  return \@rows;
};

sub load_progress_csv {

  my $cmd = join(' ',
    cwd().'/bin/progress-to-json ',
    config->{commands}->{progress_to_json_args },
    '--file '.cwd().'/'.config->{progress_csv_path}
  );
  info(" Running command '$cmd'");
  my $json = `$cmd`;
  info(" got ".length($json)." bytes of JSON");
  my $progress_data = decode_json( $json );
  return $progress_data;
}
# # # # # ENTRANTS
# # # #
# # #

get '/api/entrants' => sub {
  my $entrants_progress = vars->{entrants_progress};
  header 'Content-Type' => 'application/json';
  encode_json($entrants_progress);
};

# # # # # TEAMS
# # # #
# # #

get '/teams' => sub {
  template 'teams';
};

get '/api/teams' => sub {
  my $entrants_progress = vars->{entrants_progress};
  my $teams_progress = vars->{teams_progress};
  my $routes_cps = vars->{route_checkpoints};
  my $checkpoint_times = get_checkpoint_times( $entrants_progress );

  $teams_progress = add_checkpoint_expected_at_times( $teams_progress, $checkpoint_times);
  header 'Content-Type' => 'application/json';
  encode_json($teams_progress);
};

get '/api/teams/progress' => sub {
  my $entrants_progress = vars->{entrants_progress};
  my $teams_progress = vars->{teams_progress};
  my $routes_cps = vars->{route_checkpoints};
  my $checkpoint_times = get_checkpoint_times( $entrants_progress );
  $teams_progress = add_checkpoint_expected_at_times( $teams_progress, $checkpoint_times);
  header 'Content-Type' => 'application/json';
  return encode_json($teams_progress);
};

get '/api/teams/table' => sub {
  my $entrants_progress = vars->{entrants_progress};
  my $teams_progress = vars->{teams_progress};
  my $routes_cps = vars->{route_checkpoints};
  my $checkpoint_times = get_checkpoint_times( $entrants_progress );

  $teams_progress = add_checkpoint_expected_at_times( $teams_progress, $checkpoint_times);
  header 'Content-Type' => 'application/json';
  return encode_json(create_team_summary_table($teams_progress));
};


true;

# Headings:
# Team Number | Team Name | Route | Last checkpoint | Next chekpoint | time expected at next |  How late they are
sub create_team_summary_table{
  my $teams_progress = shift;
  my @table;
  foreach my $team_number (sort(keys(%{$teams_progress}))){
    my $t = $teams_progress->{$team_number};
    #debug("[create_team_summary_table] Team $team_number: $t->{team_name}");

    my $expected_at_next = -1;
    my $lateness_at_last = -1;
    my $checkin_at_last = -1;

    if($t->{checkpoints}->{ $t->{next_checkpoint} }->{expected_time}){
      $expected_at_next = $t->{checkpoints}->{ $t->{next_checkpoint} }->{expected_time};
      $lateness_at_last = int((time() - $expected_at_next) / 60);
    }else{
      error("Team $team_number ($t->{team_name}) has no expected_time for next checkpoint");
    }

    if($t->{checkpoints}->{ $t->{last_checkpoint} }->{arrived_time}){
      $checkin_at_last = $t->{checkpoints}->{ $t->{last_checkpoint} }->{arrived_time}
    }else{
      error("Team $team_number ($t->{team_name}) has no arrived_time for last checkpoint");
    }

    my @row = ($team_number, $t->{team_name}, $t->{route}, strftime("%H:%M", localtime($checkin_at_last))." ($t->{last_checkpoint})", $t->{next_checkpoint}, strftime("%H:%M", localtime($expected_at_next)), $lateness_at_last);

    #info(" [create_team_summary_table] Team $team_number; next: $t->{next_checkpoint}; last: $t->{last_checkpoint}");
    push(@table, \@row);
  }
  return \@table;
}


# Given three arguments - a teams_progress hash as returned from the progress-to-csv tool, a
# routes_checkpoints hash as returned by the get_routes_checkpoints_hash() function and a
# checkpoint_times hash as returned by get_checkpoint_times - will return that teams_progress
# hash with the addition of expected_time hashes on every checkpoint for which it can be
# calculated, based on the 90th percentile of the times taken betwen checkpoints.
#
sub add_checkpoint_expected_at_times {
  my $teams_progress = shift;
  my $checkpoint_times = shift;

  my $routes_cps = vars->{route_checkpoints};
  foreach my $team_number (keys(%{$teams_progress})){
    my $route_name = $teams_progress->{$team_number}->{route};
    #debug("[add_checkpoint_expected_at_times] Adding checkpoint times for team '$team_number' on route '$route_name'");
    my @route_cps = @{ $routes_cps->{$route_name} };
    #debug("[add_checkpoint_expected_at_times] Team $team_number checkpoints: ".join(" ", @route_cps));

    $teams_progress->{$team_number}->{route_checkpoints} = \@route_cps;

    for (my $cp=1; $cp<=$#route_cps; $cp++){
      my $this_cp = $route_cps[$cp];
      my $prev_cp = $route_cps[$cp -1 ];
      my $leg = "$prev_cp $this_cp";
      my $time_from = undef;

      if($teams_progress->{$team_number}->{checkpoints}->{$this_cp}->{missed}){
        debug("Team '$team_number' skipped checkpoint '$this_cp' ");
        $teams_progress->{$team_number}->{checkpoints}->{$this_cp}->{arrived_time} = $teams_progress->{$team_number}->{checkpoints}->{$prev_cp}->{arrived_time} + 10;
      }

      if(!$teams_progress->{$team_number}->{checkpoints}->{$prev_cp}->{arrived_time} and !$teams_progress->{$team_number}->{checkpoints}->{$prev_cp}->{expected_time}){
        error("Missing expected_time and arrived_time for team $team_number at previous checkpoint $prev_cp");
        next;
      }
#     #debug("[add_checkpoint_expected_at_times] Team_number: $team_number, prev_cp: $prev_cp");
      if($teams_progress->{$team_number}->{checkpoints}->{$prev_cp}->{arrived_time}){
        $time_from = $teams_progress->{$team_number}->{checkpoints}->{$prev_cp}->{arrived_time};
      }else{
        $time_from = $teams_progress->{$team_number}->{checkpoints}->{$prev_cp}->{expected_time};
      }

      my $diff = $checkpoint_times->{$leg}->{ninetieth_percentile};
      if (!$diff or $diff == 0){
        error("Got zero diff for leg '$leg'");
        next;
      }

      #debug("[add_checkpoint_expected_at_times] Expected time between checkpoints '$leg' is $diff seconds");

      my $expected = $time_from + $diff;

      #debug("From: '$time_from', diff: '$diff'");

      $teams_progress->{$team_number}->{checkpoints}->{$this_cp}->{expected_time} = $expected;
      $teams_progress->{$team_number}->{checkpoints}->{$this_cp}->{expected_localtime} = localtime($expected);
#      #debug("[add_checkpoint_expected_at_times] Team $team_number is expected at $this_cp at ".strftime("%y-%m-%d %H:%M", localtime($expected))." ($expected)");
    }

    for (my $i=1; $i<=$#route_cps; $i++){
      my $cp = $route_cps[$i];
      next if ($teams_progress->{$team_number}->{checkpoints}->{$cp}->{arrived_time});
      $teams_progress->{$team_number}->{next_checkpoint} = $cp;
      $teams_progress->{$team_number}->{last_checkpoint} = $route_cps[$i - 1];
      last;
    }
  }

  return $teams_progress;
}


# Given an entrants_progress hash, iterates through all the entrants and tots up how long each took
# to do each leg, then calculates the 90th percentile of those figures (using get_percentile() and
# creates a hash checkpoint_times, with keys that are the leg (from-cp and to-cp separated by a
# single space)
#
sub get_checkpoint_times {
  my $entrants = shift;
  my $checkpoint_times = {};

  my $route_cps = vars->{route_checkpoints};

  # Foreach entrant...
  foreach my $code (keys(%{$entrants})){
    my $entrant = $entrants->{$code};
    # An array of numbers, the list of checkpoints this entrant should check-in at
    my @route_cps = @{$route_cps->{ $entrant->{route} } };

    my $routes_per_leg = get_routes_per_leg();

    for (my $cp=1; $cp<=$#route_cps; $cp++){
      my $this_cp = $route_cps[$cp];
      my $prev_cp = $route_cps[$cp -1 ];
      my $leg = "$prev_cp $this_cp";

      if(!$entrant->{checkpoints}->{$this_cp}->{arrived_time}){
        #error("[get_checkpoint_times] Missing this_cp arrived_time for cp $this_cp on leg $leg");
        next;
      }
      if(!$entrant->{checkpoints}->{$prev_cp}->{arrived_time}){
        #error("[get_checkpoint_times] Missing prev_cp arrived time for cp $prev_cp (this is $this_cp) on leg $leg");
        next;
      }

      my $diff = $entrant->{checkpoints}->{$this_cp}->{arrived_time} - $entrant->{checkpoints}->{$prev_cp}->{arrived_time};
      #debug("[get_checkpoint_times] Entrant $code; cp: $this_cp; this_arr: ".$entrant->{checkpoints}->{ $this_cp }->{arrived_time}."; prev arr: ". $entrant->{checkpoints}->{$prev_cp}->{arrived_time});

      if($diff <= 0 ){
        error("Bad diff for $entrant->{code} between $prev_cp and $this_cp: $diff ($entrant->{checkpoints}->{ $this_cp }->{arrived_time} - $entrant->{checkpoints}->{$prev_cp}->{arrived_time})");
        $diff = 1;
      }
        push(@{$checkpoint_times->{$leg}->{diffs}}, $diff);
    }

    foreach my $leg (keys(%{$checkpoint_times})){
      if(scalar(keys(@{$checkpoint_times->{$leg}->{diffs}})) >= 4 ){
        $checkpoint_times->{$leg}->{ninetieth_percentile} = get_percentile(90, $checkpoint_times->{$leg}->{diffs});
        #debug("[get_checkpoint_times] 90th percentile for '$leg': $checkpoint_times->{$leg}->{ninetieth_percentile}");
      }else{
#        #debug("[get_checkpoint_times] Not enough data for percentiles for leg $leg");
        $checkpoint_times->{$leg}->{ninetieth_percentile} = 0;
      }
      my @sorted_cp_times = sort{ $a <=> $b } @{$checkpoint_times->{$leg}->{diffs}};
      $checkpoint_times->{$leg}->{min} = $sorted_cp_times[0];
      $checkpoint_times->{$leg}->{max} = $sorted_cp_times[-1];

      @{$checkpoint_times->{$leg}->{routes}} = sort(@{$routes_per_leg->{$leg}});

    }
  }
  #foreach my $leg (sort(keys(%{$checkpoint_times}))){
  #  my @numbers = @{$checkpoint_times->{$leg}->{diffs}};
  #  #debug("[get_checkpoint_times] Leg $leg; percentile: $checkpoint_times->{$leg}->{ninetieth_percentile}; sample: ".$#numbers);
  #}
  return $checkpoint_times;
}

sub get_percentile{
  my $percentile = shift;
  my $n = shift;
  my @numbers = sort(@{$n});
  my $index = int(($percentile/100) * $#numbers - 1);
  return $numbers[$index];
}


# Convert from the
#   $routes->{route_name} = "1 2 3 4 5"
# that comes from the config file to
#   $routes->{route_name} = (1, 2, 3, 4, 5);
# that's eaier to iterate over

sub get_route_checkpoints_hash{
  my $route_cps = {};
  my $route_config = config->{routes};
  foreach my $route_name (keys(%{$route_config})){
    @{$route_cps->{$route_name}} = split(m/\s+/, $route_config->{$route_name}->{checkpoints});
    #debug("[get_route_checkpoints_hash] Found route '$route_name': ".join(', ', @{$route_cps->{$route_name}}));
  }
  return $route_cps;
}

sub get_routes_per_leg {
  my $route_config = config->{routes};
  my $legs;
  foreach my $route_name (sort(keys(%{$route_config}))){
    my @route_cps = split(m/\s+/, $route_config->{$route_name}->{checkpoints});
    # An array of numbers, the list of checkpoints this entrant should check-in at
    for (my $cp=1; $cp<=$#route_cps; $cp++){
      my $this_cp = $route_cps[$cp];
      my $prev_cp = $route_cps[$cp -1 ];
      my $leg = "$prev_cp $this_cp";
      push(@{$legs->{$leg}}, $route_name);
    }
  }
  return $legs;
}

sub get_summary {
  my $teams = shift;

  my $s;
  foreach my $team_name (keys(%{$teams})){
    my $t = $teams->{$team_name};
    my $route = $t->{route};
    # Furthest ahead and furthest behind teams

    if($s->{routes}->{$route}->{max_cp} < $t->{last_checkpoint} or !$s->{routes}->{$route}->{max_cp}){
      $s->{routes}->{$route}->{max_cp} = $t->{last_checkpoint};
    }
    if($s->{routes}->{$route}->{min_cp} > $t->{last_checkpoint} or !$s->{routes}->{$route}->{min_cp}){
      $s->{routes}->{$route}->{min_cp} = $t->{last_checkpoint};
    }

    # Number of teams out/completed
    if($t->{completed_time} and $t->{completed_time} > 0){
      $s->{routes}->{$route}->{num_completed}++;
    }else{
      $s->{routes}->{$route}->{num_not_completed}++;
    }
  }

  foreach my $team_name (keys(%{$teams})){
    my $t = $teams->{$team_name};
    if($s->{routes}->{ $t->{route} }->{min_cp} == $t->{next_cp} ){
      push(@{$s->{routes}->{teams_at_min_cp}}, $team_name);
    }elsif($s->{routes}->{ $t->{route} }->{max_cp} == $t->{next_cp} ){
      push(@{$s->{routes}->{teams_at_max_cp}}, $team_name);
    }
  }

  return $s;
}
