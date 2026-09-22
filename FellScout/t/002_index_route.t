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
use Test::More tests => 2;
use Plack::Test;
use HTTP::Request::Common;
use Ref::Util qw<is_coderef>;

TestDB->reset;

my $app = FellScout->to_app;
ok( is_coderef($app), 'Got app' );

my $test = Plack::Test->create($app);

# '/' is the Vue SPA shell (served by the catch-all route, via index.html
# from the frontend build) - no DB-backed page data is rendered server-side
# here any more, so nothing needs seeding.
my $res  = $test->request( GET '/' );

ok( $res->is_success, '[GET /] successful' ) or diag($res->content);
