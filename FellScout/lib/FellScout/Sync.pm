package FellScout::Sync;

use strict;
use warnings;
use Exporter 'import';
use Cwd;
use FellScout::Log qw(info error debug);

our @EXPORT_OK = qw(run_cronjobs add_expected_times_to_teams get_percentile);

# Run_cronjobs is basically a 'refresh cache'; it's called by the cronjob runner,
# but also whenever we do a thing that affects teams or entrants - create a scratch
# team, say - and need to update the legs data and similar.
#
# %config keys: felltrack_owner, felltrack_username, felltrack_password,
# ignore_future_events, skip_fetch_from_felltrack, progress_csv_path,
# percentile, percentile_min_sample, percentile_sample_size,
# leg_estimate_multiplier.
sub run_cronjobs{
	my $dbh = shift;
	my %config = @_;

	my $cmd = join(" ", cwd()."/bin/get-data", $config{felltrack_owner}, $config{felltrack_username}, $config{felltrack_password});

	my $sth_log = $dbh->prepare("replace into logs (`message`, `name`) values (?, ?)");

	if ($config{ignore_future_events} and $config{ignore_future_events} eq 'on'){
		$ENV{IGNORE_FUTURE_EVENTS} = 'on';
	}
	if ($config{skip_fetch_from_felltrack} and $config{skip_fetch_from_felltrack} eq 'on'){
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
	if ($config{progress_csv_path}) {
		$cmd .= " $config{progress_csv_path}";
	}
	info("Cron: Updating DB from CSV : $cmd");
	$output = '';
	foreach my $line (qx/$cmd/){
		chomp($line);
		$output .= $line;
		info(">  $line");
	}
	$sth_log->execute($output, 'progress-to-db');
	info("Exited: $?");


	info("Cron: Updating legs");

	# First, get every possible leg given the routes definition into the legs table
	my $sth = $dbh->prepare("select name, value from config where name like 'route%'");
	my $sth_update = $dbh->prepare("replace into legs (`from`, `to`, `leg_name`) values (?, ?, ?)");
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
	$sth = $dbh->prepare("select checkpoint, previous_checkpoint, seconds_since_previous_checkpoint from checkpoints_teams order by time desc");
	$sth->execute();
	while (my $row = $sth->fetchrow_hashref()){
		my $leg_name = $row->{previous_checkpoint}."-".$row->{checkpoint};
		push(@{$legs->{$leg_name}}, $row->{seconds_since_previous_checkpoint});
	}
	# And then update the legs table to add a 'seconds' value for those legs that teams
	# have completed, by calculating an average time taken
	$sth = $dbh->prepare("replace into legs (`leg_name`, `from`, `to`, `seconds`) values (?, ?, ?, ?)");
	foreach my $leg(keys(%{$legs})){
		my ($from,$to) = split(m/-/, $leg);
		my $expected_seconds = get_percentile($legs->{$leg},
			percentile  => $config{percentile},
			min_sample  => $config{percentile_min_sample},
			sample_size => $config{percentile_sample_size},
		);
		next if $leg eq '0-0';
		$sth->execute($leg, $from, $to, $expected_seconds);
	}

	#info("Cron: Adding expected times to teams");
	add_expected_times_to_teams($dbh, $config{leg_estimate_multiplier});
	$sth_log->execute('completed', 'periodic-jobs');
	info("Finished crons");
	return $output;
}

sub add_expected_times_to_teams {
	my $dbh = shift;
	my $leg_estimate_multiplier = shift;

	# First, a couple of look-up hashes which we'll use to estimate time-to-finish. We need to find out where in the ordered list
	# of legs for a given route the current leg comes, and then retrieve each of those that come after it.
	my %index_to_leg;
	my %leg_to_index;
	my %legs;
	my $sth = $dbh->prepare("select * from routes join legs on routes.leg_name = legs.leg_name");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		$index_to_leg{ $row->{route_name} }->{ $row->{index} } = $row->{leg_name};
		$leg_to_index{ $row->{route_name} }->{ $row->{leg_name} } = $row->{index};
		$legs{ $row->{leg_name} } = $row;
	}

	$sth = $dbh->prepare("select team_number, route, last_checkpoint, next_checkpoint, current_leg,
	                         `index` as leg_index,
	                         unix_timestamp(last_checkpoint_time) as last_checkpoint_time_epoch
	                         from teams
	                         join routes on routes.route_name = teams.route
	                           and routes.leg_name = teams.current_leg
	                         where completed < 1");
	my $sth_update = $dbh->prepare("replace into checkpoints_teams_predictions set checkpoint = ?,
	team_number = ?, expected_time = from_unixtime(?)");
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
		unless($leg_index){ error("Failed to get leg index from current leg: $team{current_leg} on route $team{route} ")}
		while(my $leg_name = $index_to_leg{ $team{route} }->{$leg_index} ){
			my $seconds;
			unless($legs{$leg_name}->{to}){
				error("No next-checkpoint for team $team_number on leg $leg_name on route $team{route}");
				next;
			}
			if($legs{$leg_name}->{seconds}){
				$expected_time += $legs{$leg_name}->{seconds} * $leg_estimate_multiplier;
				$sth_update->execute($legs{$leg_name}->{to}, $team_number, $expected_time);

			}else{
				#info("No prediction data for leg $leg_name for team $team_number; skipping the rest of the legs");
				last;
			}

			$leg_index++;
		}
	}
}

sub get_percentile{
	my @in = @{$_[0]};
	my %opts = @_[1 .. $#_];

	my $percentile = $opts{percentile} || 90;
	my $min_sample = $opts{min_sample};
	my $sample_size = $opts{sample_size};

	my @numbers;
	# If the whole set of numbers we have is already smaller than the percentile_min_sample
	# then we do not want to shrink it further by taking only the most-recent percentile_sample_size
	if ($min_sample and scalar(@in) >= $min_sample and
	    $sample_size and $sample_size > 0 ){
		#info("Pcile sample before: ".scalar(@in));
		my $index = int(($sample_size/100) * $#in - 1 );
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
	if ($min_sample and scalar(@numbers) < $min_sample ){
		#info("Not enough samples for pcile (".scalar(@numbers)." < percentile_min_sample of $min_sample), using mean");
		my $sum = 0;
		map { $sum += $_ } @in;
		return $sum / scalar(@in);
	}

	my $index = int(($percentile/100) * $#numbers - 1);
	return $numbers[$index];
}

1;
