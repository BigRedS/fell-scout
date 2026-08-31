use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use TestDB;

BEGIN {
	TestDB->ensure_running;
	TestDB->set_env;
}

use FellScout::Sync qw(add_expected_times_to_teams);
use Test::More;

# add_expected_times_to_teams() takes $dbh and config as plain arguments -
# no Dancer2 at all - so unlike run_cronjobs() as a whole, it can be called
# directly against a seeded database without going through Plack::Test/HTTP.
# This is a faster, more focused layer under t/032_cron.t's full-pipeline
# coverage.

TestDB->reset;
TestDB->insert_route('50km', [0, 1, 2, 3, 99], seconds => { '1-2' => 3600 });
TestDB->insert_team(
	team_number => 1, team_name => 'Team One', route => '50km',
	last_checkpoint => 1, last_checkpoint_time => TestDB->offset_datetime(-30),
	next_checkpoint => 2, current_leg => '1-2', completed => 0, retired => 0,
);

add_expected_times_to_teams(TestDB->dbh, 1.2);

my $prediction = TestDB->dbh->selectrow_hashref(
	'select * from checkpoints_teams_predictions where team_number = 1 and checkpoint = 2'
);
ok(defined $prediction, 'a prediction was written for the team\'s next checkpoint');

my ($last_checkpoint_epoch) = TestDB->dbh->selectrow_array(
	'select unix_timestamp(last_checkpoint_time) from teams where team_number = 1'
);
my ($expected_epoch) = TestDB->dbh->selectrow_array(
	'select unix_timestamp(expected_time) from checkpoints_teams_predictions where team_number = 1 and checkpoint = 2'
);
is(
	$expected_epoch - $last_checkpoint_epoch,
	3600 * 1.2,
	'expected_time is last_checkpoint_time plus the leg seconds scaled by leg_estimate_multiplier'
);

# A team on a route/leg combination that doesn't exist in `routes` fails the
# query's join silently - add_expected_times_to_teams should just skip it,
# not die and take every other team's predictions down with it.
TestDB->insert_team(
	team_number => 2, team_name => 'Team Two', route => 'nonexistent-route',
	last_checkpoint => 0, last_checkpoint_time => TestDB->offset_datetime(-5),
	next_checkpoint => 1, current_leg => 'nonexistent-leg', completed => 0, retired => 0,
);
my $ok = eval { add_expected_times_to_teams(TestDB->dbh, 1.2); 1 };
ok($ok, 'a team with no matching route/leg data does not make the whole run die') or diag($@);

my ($team2_predictions) = TestDB->dbh->selectrow_array(
	'select count(*) from checkpoints_teams_predictions where team_number = 2'
);
is($team2_predictions, 0, 'team 2 (unmatched route/leg) got no predictions, but did not block team 1\'s');

my ($team1_predictions) = TestDB->dbh->selectrow_array(
	'select count(*) from checkpoints_teams_predictions where team_number = 1'
);
is($team1_predictions, 1, 'team 1 still has its prediction after the second run');

done_testing();
