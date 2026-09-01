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

# Smoke test: every route should render without dying, for both the
# in-progress team (1), the finished/retired/small/scratch/no-predictions
# edge cases baked into seed_sample_world, and the corresponding /api/* JSON
# counterpart.
my @get_routes = qw(
	/
	/teams
	/team/1
	/team/2
	/team/3
	/team/4
	/team/-5
	/team/6
	/checkpoints
	/checkpoint/0
	/checkpoint/1
	/checkpoint/2
	/checkpoint/3
	/checkpoint/99
	/arrivals/1
	/legs
	/laterunners/0
	/laterunners/30m
	/laterunners/50pc
	/entrants
	/problems
	/map
	/scratch-teams
	/admin
	/admin/checkpoints
	/api/summary
	/api/teams
	/api/team/1
	/api/legs
	/api/checkpoints
	/api/checkpoint/1
	/api/arrivals/1
	/api/laterunners/
	/api/entrants
	/api/problems
);
# /clear-cache wipes every table, so it must run last, after every other
# route has had a chance to exercise the seeded data.
push @get_routes, '/clear-cache';

for my $path (@get_routes) {
	my $res = $test->request( GET $path );
	ok( $res->is_success, "[GET $path] successful" ) or diag($res->status_line, "\n", $res->content);
}

# jQuery used to be loaded twice (two different versions - the second,
# loaded later, silently winning over the first). Only one now.
{
	my $res = $test->request( GET '/' );
	my @jquery_core_includes = $res->content =~ m{<script src="[^"]*code\.jquery\.com/jquery-[^"]*"}g;
	is(scalar(@jquery_core_includes), 1, 'the layout includes jQuery core exactly once');
}

# These routes redirect based on a query param rather than rendering
# directly - smoke test that the redirect itself doesn't crash.
for my $case (
	['/laterunners', 302],
	['/team?team=1', 302],
	['/checkpoint?checkpoint=1', 302],
) {
	my ($path, $expected_code) = @$case;
	my $res = $test->request( GET $path );
	is( $res->code, $expected_code, "[GET $path] redirects" ) or diag($res->status_line, "\n", $res->content);
}

done_testing();
