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
	/api/config
	/api/logs
);
# /clear-cache wipes every table, so it must run last, after every other
# route has had a chance to exercise the seeded data.
push @get_routes, '/clear-cache';

for my $path (@get_routes) {
	my $res = $test->request( GET $path );
	ok( $res->is_success, "[GET $path] successful" ) or diag($res->status_line, "\n", $res->content);
}

done_testing();
