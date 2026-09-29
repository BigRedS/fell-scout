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
TestDB->seed_config(controllers => 'testcontroller');

my $app  = FellScout->to_app;
my $test = Plack::Test->create($app);

sub json_request {
	my ($method, $path, $body) = @_;
	my $req = $method->(
		$path,
		'Content-Type' => 'application/json',
		'X-Remote-User' => 'testcontroller',
		Content        => encode_json($body // {}),
	);
	return $test->request($req);
}

# --- GET /api/incidents (empty) ---
{
	my $res = $test->request( GET '/api/incidents' );
	ok($res->is_success, '[GET /api/incidents] successful') or diag($res->status_line, "\n", $res->content);
	is_deeply(decode_json($res->content), {}, 'no incidents yet');
}

# --- POST /api/incidents (create) ---
my $id;
{
	my $res = json_request(\&POST, '/api/incidents', {
		type => 'Medical', description => 'Twisted ankle', checkpoint_number => 3,
		team_number => 5, owner => 'First Aid Team',
	});
	ok($res->is_success, '[POST /api/incidents] successful') or diag($res->status_line, "\n", $res->content);

	my $incident = decode_json($res->content);
	is($incident->{type}, 'Medical', 'created incident: type');
	is($incident->{owner}, 'First Aid Team', 'created incident: owner');
	is($incident->{status}, 'Open', 'created incident: defaults to Open status');
	ok($incident->{id}, 'created incident: has an id');
	$id = $incident->{id};
}

# --- GET /api/incidents (one present) ---
{
	my $incidents = decode_json( $test->request( GET '/api/incidents' )->content );
	ok(exists $incidents->{$id}, 'the new incident shows up in a follow-up GET');
	is($incidents->{$id}->{checkpoint_number}, 3, 'incident: checkpoint_number round-trips');
	is($incidents->{$id}->{team_number}, 5, 'incident: team_number round-trips');
}

# --- PUT /api/incidents/:id (status change) ---
{
	my $res = json_request(\&PUT, "/api/incidents/$id", {
		type => 'Medical', description => 'Twisted ankle', checkpoint_number => 3,
		team_number => 5, owner => 'First Aid Team', status => 'Resolved',
	});
	ok($res->is_success, '[PUT /api/incidents/:id] successful') or diag($res->status_line, "\n", $res->content);

	my $incidents = decode_json( $test->request( GET '/api/incidents' )->content );
	is($incidents->{$id}->{status}, 'Resolved', 'incident status updated');
}

# --- PUT /api/incidents/:id (owner changes across a shift handover) ---
{
	my $res = json_request(\&PUT, "/api/incidents/$id", {
		type => 'Medical', description => 'Twisted ankle', checkpoint_number => 3,
		team_number => 5, owner => 'Night Shift Medic', status => 'Resolved',
	});
	ok($res->is_success, '[PUT /api/incidents/:id] owner handover successful') or diag($res->status_line, "\n", $res->content);

	my $incidents = decode_json( $test->request( GET '/api/incidents' )->content );
	is($incidents->{$id}->{owner}, 'Night Shift Medic', 'owner is independently updateable, not just set at creation');
}

# --- DELETE /api/incidents/:id ---
{
	my $res = json_request(\&DELETE, "/api/incidents/$id");
	ok($res->is_success, '[DELETE /api/incidents/:id] successful') or diag($res->status_line, "\n", $res->content);

	my $incidents = decode_json( $test->request( GET '/api/incidents' )->content );
	ok(!exists $incidents->{$id}, 'incident is gone after DELETE');
}

# --- disabled via config: the API refuses, not just the nav link hiding it ---
{
	# seed_config re-applies the full baseline plus these overrides each
	# call, so controllers has to be repeated here or it'd reset to empty.
	TestDB->seed_config(enable_incidents => '', controllers => 'testcontroller');

	my $get_res = $test->request( GET '/api/incidents' );
	is($get_res->code, 403, '[GET /api/incidents] returns 403 when disabled');

	my $post_res = json_request(\&POST, '/api/incidents', { type => 'Medical', description => 'test' });
	is($post_res->code, 403, '[POST /api/incidents] returns 403 when disabled');

	TestDB->seed_config(enable_incidents => 'on', controllers => 'testcontroller');
	my $reenabled_res = $test->request( GET '/api/incidents' );
	ok($reenabled_res->is_success, '[GET /api/incidents] works again once re-enabled');
}

done_testing();
