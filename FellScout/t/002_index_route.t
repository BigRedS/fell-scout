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
TestDB->insert_route('50km', [0, 1, 99]);
TestDB->insert_team(team_number => 1, route => '50km', last_checkpoint => 1, current_leg => '1-99');

my $app = FellScout->to_app;
ok( is_coderef($app), 'Got app' );

my $test = Plack::Test->create($app);
my $res  = $test->request( GET '/' );

ok( $res->is_success, '[GET /] successful' ) or diag($res->content);
