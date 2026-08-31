use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use TestDB;

BEGIN {
	TestDB->ensure_running;
	TestDB->set_env;
}

use FellScout;
use Test::More;
use Plack::Test;
use HTTP::Request::Common;

# run_cronjobs() (the guts of /cron) shells out to bin/get-data and
# bin/progress-to-db via `cwd()."/bin/..."`, and passes progress-to-db the
# configured `progress_csv_path` setting as its CSV argument. Left at its
# config.yml default ('../progress.csv', relative to the app's cwd), that
# would resolve to the real, gitignored progress.csv at the repo root - real
# participant PII, and not something a test should ever read. Overriding the
# setting to an absolute path here sidesteps that entirely; no chdir or
# symlink tricks needed.
FellScout::setting('progress_csv_path', "$FindBin::Bin/fixtures/cron_pipeline.csv");

TestDB->reset;
# Leg "0-1" is left with no seconds - it gets one computed from this run's
# own checkpoints_teams history (get_percentile). Leg "1-2" (team 1's
# *upcoming* leg once it reaches checkpoint 1) needs a seconds value seeded
# up front, since nothing in this fixture ever completes it - that's what
# add_expected_times_to_teams needs to be able to predict anything at all.
TestDB->insert_route('50km', [0, 1, 2, 3, 99], seconds => { '1-2' => 3600 });

my $app  = FellScout->to_app;
my $test = Plack::Test->create($app);

my $res = $test->request( GET '/cron' );

ok( $res->is_success, '[GET /cron] successful' ) or diag($res->status_line, "\n", $res->content);
like( $res->content, qr/Cronjobs done/, '/cron ran the full pipeline (get-data -> progress-to-db -> legs/predictions)' );

my $team = TestDB->dbh->selectrow_hashref('select * from teams where team_number = 1');
ok(defined $team, '/cron: progress-to-db populated the team from the synthetic progress.csv')
	or diag(explain_missing());
is($team->{last_checkpoint}, 1, '/cron: team last_checkpoint reflects the CSV data') if $team;

my $leg = TestDB->dbh->selectrow_hashref("select * from legs where leg_name = '0-1'");
ok(defined $leg && $leg->{seconds}, '/cron: run_cronjobs computed a seconds value for the completed leg (get_percentile, via live route context)');

my $prediction = TestDB->dbh->selectrow_hashref('select * from checkpoints_teams_predictions where team_number = 1 and checkpoint = 2');
ok(defined $prediction, '/cron: add_expected_times_to_teams predicted arrival at the next checkpoint, using the seeded leg-2 duration');

sub explain_missing {
	return "No team row was written - the pipeline likely didn't run against the synthetic CSV as expected.";
}

done_testing();
