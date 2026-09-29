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
use HTTP::Request::Common qw(GET PATCH POST);
use JSON qw(decode_json encode_json);

# The route-level tests elsewhere (t/037, t/038, t/031, t/036, t/039, t/040)
# each already exercise their own route as the right tier - this file is
# about the gate itself: missing/unrecognised identities, the wrong tier,
# and the admin-implies-controller hierarchy, using one representative admin
# route and one representative controller route rather than repeating this
# for every gated route.

TestDB->reset;
TestDB->seed_config(admins => 'root', controllers => 'ops');
# get_checkpoint_details() (and so update_checkpoint_status()) returns undef
# for a checkpoint_number with no row/routes - a real, pre-existing bug
# (encode_json(undef) then 500s), unrelated to access control. Insert one so
# the controller-route assertions below test the gate, not that bug.
TestDB->insert_checkpoint(checkpoint_number => 1, description => 'Test CP');

my $app  = FellScout->to_app;
my $test = Plack::Test->create($app);

sub as {
	my ($user, $req) = @_;
	$req->header('X-Remote-User' => $user) if defined $user;
	return $test->request($req);
}

my $ADMIN_ROUTE = sub { PATCH('/api/config', 'Content-Type' => 'application/json', Content => encode_json({})) };
my $CONTROLLER_ROUTE = sub {
	PATCH('/api/checkpoint/1/status', 'Content-Type' => 'application/json', Content => encode_json({ status => 'open' }))
};

# --- no header at all ---
{
	is(as(undef, $ADMIN_ROUTE->())->code, 403, 'admin route: no X-Remote-User header -> 403');
	is(as(undef, $CONTROLLER_ROUTE->())->code, 403, 'controller route: no X-Remote-User header -> 403');
}

# --- a recognised proxy user who isn't on either list ---
{
	is(as('some_random_user', $ADMIN_ROUTE->())->code, 403, 'admin route: unlisted user -> 403');
	is(as('some_random_user', $CONTROLLER_ROUTE->())->code, 403, 'controller route: unlisted user -> 403');
}

# --- a controller is not an admin ---
{
	is(as('ops', $ADMIN_ROUTE->())->code, 403, 'admin route: controller-only user -> 403');
	my $res = as('ops', $CONTROLLER_ROUTE->());
	ok($res->is_success, 'controller route: controller user -> success') or diag($res->status_line, "\n", $res->content);
}

# --- admin implies controller, without being separately listed there ---
{
	my $res = as('root', $ADMIN_ROUTE->());
	ok($res->is_success, 'admin route: admin user -> success') or diag($res->status_line, "\n", $res->content);
	$res = as('root', $CONTROLLER_ROUTE->());
	ok($res->is_success, 'controller route: admin user -> success (admin implies controller)') or diag($res->status_line, "\n", $res->content);
}

# --- reads stay open regardless of identity - no tier required ---
# (/api/incidents, not /api/teams: get_teams() has the same pre-existing
# undef-on-no-rows bug as get_checkpoint_details() above, on a table this
# test never populates - unrelated to this test's own purpose.)
{
	is(as(undef, GET('/api/incidents'))->code, 200, 'a plain read route needs no identity at all');
}

# --- /api/status reflects the caller's own tier ---
{
	my $status = sub {
		my ($user) = @_;
		my $req = GET('/api/status');
		$req->header('X-Remote-User' => $user) if defined $user;
		return decode_json($test->request($req)->content);
	};
	is_deeply([map { $_ ? 1 : 0 } @{$status->('root')}{qw(is_admin is_controller)}], [1, 1], 'status: admin is both is_admin and is_controller');
	is_deeply([map { $_ ? 1 : 0 } @{$status->('ops')}{qw(is_admin is_controller)}], [0, 1], 'status: controller is is_controller but not is_admin');
	is_deeply([map { $_ ? 1 : 0 } @{$status->('nobody')}{qw(is_admin is_controller)}], [0, 0], 'status: unlisted user is neither');
}

# --- dev_mode: with no proxy in front (no header), fall back to admin ---
{
	# The dev_mode fallback identity is the literal string 'admin' (see
	# FellScout.pm's _remote_user) - has to be on the admins list itself.
	TestDB->seed_config(admins => 'root admin', controllers => 'ops', dev_mode => 'on');
	is(as(undef, $ADMIN_ROUTE->())->code, 200, 'dev_mode on, no header: admin route succeeds (dev/demo fallback)');

	# The fallback only kicks in when there's no header - an explicit
	# unrecognised identity is still refused, dev_mode or not.
	is(as('some_random_user', $ADMIN_ROUTE->())->code, 403, 'dev_mode on, unlisted header still present: still 403');
}

done_testing();
