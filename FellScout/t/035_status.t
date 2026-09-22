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
use JSON qw(decode_json);

TestDB->reset;

my $app  = FellScout->to_app;
my $test = Plack::Test->create($app);

my $res = $test->request( GET '/api/status' );
ok($res->is_success, '[GET /api/status] successful') or diag($res->status_line, "\n", $res->content);

my $status = decode_json($res->content);

ok(defined $status->{last_sync_epoch}, 'status: last_sync_epoch is present');
ok(
	abs(time() - $status->{last_sync_epoch}) < 60,
	'status: last_sync_epoch reflects the just-seeded logs row (within a minute of now)'
) or diag("last_sync_epoch was $status->{last_sync_epoch}, now is " . time());

is($status->{stale_after_seconds}, 600, 'status: stale_after_seconds matches the threshold used elsewhere');
ok(exists $status->{google_maps_url}, 'status: google_maps_url key is present (even if unset)');

is($status->{incidents_enabled}, 1, 'status: incidents_enabled reflects the config default (on)');
is($status->{retirements_enabled}, 1, 'status: retirements_enabled reflects the config default (on)');

TestDB->seed_config(enable_incidents => '');
my $status2 = decode_json( $test->request( GET '/api/status' )->content );
is($status2->{incidents_enabled}, 0, 'status: incidents_enabled reflects config turned off');
is($status2->{retirements_enabled}, 1, 'status: retirements_enabled is independent of incidents_enabled');

done_testing();
