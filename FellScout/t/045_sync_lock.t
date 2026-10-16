use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use TestDB;

BEGIN {
	TestDB->ensure_running;
	TestDB->set_env;
}

use FellScout::Sync qw(run_cronjobs);
use Test::More;
use Time::HiRes qw(time);

# Under a multi-worker server (Starman) two syncs could otherwise run at once
# and both write progress.csv while progress-to-db reads it. run_cronjobs
# takes a MariaDB lock; this holds that lock from a second connection - as
# another worker mid-sync would - and checks run_cronjobs waits, then gives up
# without running anything.

TestDB->reset;

my $other_worker = TestDB::_try_connect() or die "Couldn't open a second connection";
my ($held) = $other_worker->selectrow_array("select get_lock('fellscout_sync', 0)");
ok($held, 'second connection holds the sync lock');

my $logs_before = TestDB->dbh->selectrow_array('select count(*) from logs');
my $start = time();
my $result = run_cronjobs(TestDB->dbh, lock_timeout => 1, skip_fetch_from_felltrack => 'on', felltrack_owner => '', felltrack_username => '', felltrack_password => '');
my $waited = time() - $start;

is($result, undef, 'run_cronjobs gives up while another sync holds the lock');
cmp_ok($waited, '>=', 0.9, '...after waiting for the lock_timeout');
is(TestDB->dbh->selectrow_array('select count(*) from logs'), $logs_before, '...without running any of the sync');

$other_worker->do("select release_lock('fellscout_sync')");
$other_worker->disconnect;

# With the lock free it runs, and releases the lock afterwards. (The output
# itself is t/032_cron.t's concern.)
my $csv = "$FindBin::Bin/fixtures/cron_pipeline.csv";
ok(defined run_cronjobs(TestDB->dbh, lock_timeout => 1, skip_fetch_from_felltrack => 'on', felltrack_owner => '', felltrack_username => '', felltrack_password => '', progress_csv_path => $csv),
	'run_cronjobs runs once the lock is free');
is(TestDB->dbh->selectrow_array("select is_free_lock('fellscout_sync')"), 1, '...and releases the lock when done');

done_testing;
