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
use JSON qw(decode_json encode_json);

TestDB->reset;
TestDB->seed_config(admins => 'testadmin');

my $app  = FellScout->to_app;
my $test = Plack::Test->create($app);

# Every route in this file is admin-only (config includes FellTrack
# credentials; logs are bundled onto the same page) - one header, here.
sub get_json {
	my ($path) = @_;
	my $res = $test->request( GET($path, 'X-Remote-User' => 'testadmin') );
	ok( $res->is_success, "[GET $path] successful" ) or diag($res->status_line, "\n", $res->content);
	return decode_json($res->content);
}

# --- GET /api/config ---
{
	my $config = get_json('/api/config');
	is($config->{percentile}->{value}, '95', 'config: percentile baseline value');
	ok(exists $config->{percentile}->{notes}, 'config: notes key present (even if empty)');
}

# --- PATCH /api/config ---
{
	my $req = PATCH(
		'/api/config',
		'Content-Type' => 'application/json',
		'X-Remote-User' => 'testadmin',
		Content        => encode_json({ percentile => '90', not_a_real_config_key => 'ignored' }),
	);
	my $res = $test->request($req);
	ok($res->is_success, '[PATCH /api/config] successful') or diag($res->status_line, "\n", $res->content);

	my $result = decode_json($res->content);
	is_deeply($result->{changes}, ["Updated percentile to '90' from '95'"], 'config: change message for the one real, changed key');

	my $config = get_json('/api/config');
	is($config->{percentile}->{value}, '90', 'config: percentile actually updated in the DB');
	ok(!exists $config->{not_a_real_config_key}, "config: an unknown key isn't silently created");
}

# --- PATCH /api/config with no actual change is a no-op ---
{
	my $req = PATCH(
		'/api/config',
		'Content-Type' => 'application/json',
		'X-Remote-User' => 'testadmin',
		Content        => encode_json({ percentile => '90' }),
	);
	my $res = $test->request($req);
	my $result = decode_json($res->content);
	is_deeply($result->{changes}, [], 'config: submitting the same value again reports no changes');
}

# --- GET /api/logs ---
{
	my $logs = get_json('/api/logs');
	my ($periodic_jobs) = grep { $_->{name} eq 'periodic-jobs' } @$logs;
	ok(defined $periodic_jobs, 'logs: the periodic-jobs row (seeded by TestDB->reset) is present');
	ok(exists $periodic_jobs->{time} && exists $periodic_jobs->{time_since}, 'logs: time and time_since are present');
}

done_testing();
