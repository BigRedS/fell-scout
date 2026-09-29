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

TestDB->reset;
TestDB->seed_sample_world;
TestDB->seed_config(admins => 'testadmin');

my $app  = FellScout->to_app;
my $test = Plack::Test->create($app);

# Smoke test: every /api/* route should render without dying, for both the
# in-progress team (1), the finished/retired/small/scratch/no-predictions
# edge cases baked into seed_sample_world. The app itself is a single-page
# app now - every other path (server-rendered pages, the old redirect
# helpers) is gone, superseded by the catch-all route serving the SPA shell;
# t/002_index_route.t and t/003_app_psgi.t already cover that.
my @get_routes = qw(
	/api/summary
	/api/status
	/api/teams
	/api/team/1
	/api/legs
	/api/checkpoints
	/api/checkpoint/1
	/api/arrivals/1
	/api/laterunners/
	/api/entrants
	/api/problems
	/api/map
	/api/checkpoints/routes
	/api/scratch-teams
);
# /api/config and /api/logs are admin-only reads (config includes FellTrack
# credentials) - same header on every request here rather than a second list.
my @admin_get_routes = qw(
	/api/config
	/api/logs
);

for my $path (@get_routes) {
	my $res = $test->request( GET $path );
	ok( $res->is_success, "[GET $path] successful" ) or diag($res->status_line, "\n", $res->content);
}
for my $path (@admin_get_routes) {
	my $res = $test->request( GET($path, 'X-Remote-User' => 'testadmin') );
	ok( $res->is_success, "[GET $path] successful" ) or diag($res->status_line, "\n", $res->content);
}

# /clear-cache wipes every table, so it must run last, after every other
# route has had a chance to exercise the seeded data. Admin-only and
# POST-only.
{
	my $res = $test->request( POST('/clear-cache', 'X-Remote-User' => 'testadmin') );
	ok( $res->is_success, '[POST /clear-cache] successful' ) or diag($res->status_line, "\n", $res->content);
}

done_testing();
