use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use TestDB;

BEGIN {
	TestDB->ensure_running;
	TestDB->set_env;
}

use Test::More;
use Plack::Test;
use Plack::Util;
use HTTP::Request::Common;

# Every other test file builds the app via FellScout->to_app directly, which
# bypasses bin/app.psgi entirely - so nothing else in the suite would catch
# a regression in the Cache-Control middleware wrapped around the app there.
# Load the real entry point instead, via Plack::Util::load_psgi.

TestDB->reset;

my $app  = Plack::Util::load_psgi("$FindBin::Bin/../bin/app.psgi");
my $test = Plack::Test->create($app);

my $css_res = $test->request( GET '/css/style.css' );
ok($css_res->is_success, '[GET /css/style.css] successful');
is(
	$css_res->header('Cache-Control'),
	'public, max-age=604800',
	'static assets get a long Cache-Control - devices get one reliable connection (start/finish), then poor-to-none at checkpoints'
);

my $route_res = $test->request( GET '/' );
ok($route_res->is_success, '[GET /] successful') or diag($route_res->content);
is(
	$route_res->header('Cache-Control'),
	undef,
	'dynamic routes are untouched by the static-asset cache middleware'
);

done_testing();
