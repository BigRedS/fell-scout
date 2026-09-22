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
use HTTP::Request::Common qw(GET POST PUT DELETE);
use JSON qw(decode_json encode_json);

TestDB->reset;

my $app  = FellScout->to_app;
my $test = Plack::Test->create($app);

sub json_request {
	my ($method, $path, $body) = @_;
	my $req = $method->(
		$path,
		'Content-Type' => 'application/json',
		Content        => encode_json($body // {}),
	);
	return $test->request($req);
}

# --- GET /api/retirements (empty) ---
{
	my $res = $test->request( GET '/api/retirements' );
	ok($res->is_success, '[GET /api/retirements] successful') or diag($res->status_line, "\n", $res->content);
	is_deeply(decode_json($res->content), {}, 'no retirements yet');
}

# --- POST /api/retirements (create) ---
my $id;
{
	my $res = json_request(\&POST, '/api/retirements', {
		entrant_code => '3a', team_number => 3, checkpoint_number => 2, reason => 'Ankle injury',
	});
	ok($res->is_success, '[POST /api/retirements] successful') or diag($res->status_line, "\n", $res->content);

	my $retirement = decode_json($res->content);
	is($retirement->{entrant_code}, '3A', 'created retirement: entrant_code is uppercased');
	is($retirement->{status}, 'Awaiting pickup', 'created retirement: defaults to Awaiting pickup');
	ok($retirement->{id}, 'created retirement: has an id');
	$id = $retirement->{id};
}

# --- GET /api/retirements (one present) ---
{
	my $retirements = decode_json( $test->request( GET '/api/retirements' )->content );
	ok(exists $retirements->{$id}, 'the new retirement shows up in a follow-up GET');
	is($retirements->{$id}->{team_number}, 3, 'retirement: team_number round-trips');
	is($retirements->{$id}->{checkpoint_number}, 2, 'retirement: checkpoint_number round-trips');
}

# --- PUT /api/retirements/:id (assign a vehicle, change status) ---
{
	my $res = json_request(\&PUT, "/api/retirements/$id", {
		entrant_code => '3A', team_number => 3, checkpoint_number => 2, reason => 'Ankle injury',
		vehicle => 'Bus 3', status => 'Assigned',
	});
	ok($res->is_success, '[PUT /api/retirements/:id] successful') or diag($res->status_line, "\n", $res->content);

	my $retirements = decode_json( $test->request( GET '/api/retirements' )->content );
	is($retirements->{$id}->{status}, 'Assigned', 'retirement status updated');
	is($retirements->{$id}->{vehicle}, 'Bus 3', 'retirement vehicle assigned');
}

# --- DELETE /api/retirements/:id ---
{
	my $res = json_request(\&DELETE, "/api/retirements/$id");
	ok($res->is_success, '[DELETE /api/retirements/:id] successful') or diag($res->status_line, "\n", $res->content);

	my $retirements = decode_json( $test->request( GET '/api/retirements' )->content );
	ok(!exists $retirements->{$id}, 'retirement is gone after DELETE');
}

done_testing();
