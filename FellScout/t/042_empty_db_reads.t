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
use HTTP::Request::Common qw(GET PATCH);
use JSON qw(decode_json);

# get_teams() and get_checkpoint_details() used to return undef, not {},
# when their query matched zero rows - fine in Perl, but the routes then do
# encode_json($that), and encode_json(undef) dies rather than producing
# "{}". A brand-new event before any progress data is loaded, or a
# checkpoint status update for a checkpoint number with no routes yet, hit
# this for real (not a contrived case).

TestDB->reset;
TestDB->seed_config(controllers => 'testcontroller');

my $app  = FellScout->to_app;
my $test = Plack::Test->create($app);

# --- GET /api/teams on a completely empty teams table ---
{
	my $res = $test->request( GET '/api/teams' );
	ok($res->is_success, '[GET /api/teams] on an empty database is a 200, not a 500') or diag($res->status_line, "\n", $res->content);
	is_deeply(decode_json($res->content), {}, 'GET /api/teams: empty database gives {}, not null');
}

# --- PATCH .../status for a checkpoint number with no row/routes at all ---
{
	my $req = PATCH(
		'/api/checkpoint/1/status',
		'Content-Type' => 'application/json',
		'X-Remote-User' => 'testcontroller',
		Content        => '{"status":"open"}',
	);
	my $res = $test->request($req);
	ok($res->is_success, '[PATCH /api/checkpoint/1/status] for an unknown checkpoint is a 200, not a 500')
		or diag($res->status_line, "\n", $res->content);
	is_deeply(decode_json($res->content), {}, 'PATCH .../status: unknown checkpoint gives {}, not null');
}

done_testing();
