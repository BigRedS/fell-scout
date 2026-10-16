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
use HTTP::Request::Common qw(GET POST);

# Two clears: /clear-felltrack-data drops only what the next sync rebuilds;
# /clear-database also drops what people entered into FellScout itself.
# Neither touches config.

my $dbh  = TestDB->dbh;
my $test = Plack::Test->create(FellScout->to_app);

my $count = sub { scalar $dbh->selectrow_array("select count(*) from $_[0]") };

sub seed {
	TestDB->reset;
	TestDB->seed_config(admins => 'root', controllers => 'ops', route_50km => '0 1 2 3 99');
	TestDB->seed_sample_world;
	$dbh->do("insert into checkpoints_teams (checkpoint, team_number, time, previous_checkpoint) values (1, 1, now(), 0)");
	$dbh->do("insert into scratch_teams (team_number, team_name) values (1, 'Scratch One')");
	$dbh->do("insert into scratch_team_entrants (team_number, entrant_code, previous_team_number) values (1, '1A', 1)");
	$dbh->do("insert into incidents (type, description) values ('medical', 'blister')");
	$dbh->do("insert into retirements (entrant_code, reason) values ('1B', 'tired')");
}

my @felltrack_tables = qw/teams entrants legs routes checkpoints_teams checkpoints_teams_predictions/;
my @fellscout_tables = qw/scratch_teams scratch_team_entrants checkpoints incidents retirements/;

seed();
for my $table (@felltrack_tables, @fellscout_tables) {
	cmp_ok($count->($table), '>', 0, "seeded: $table has rows");
}

# --- admin-only, POST-only ---
for my $path ('/clear-felltrack-data', '/clear-database') {
	is($test->request(POST($path, 'X-Remote-User' => 'ops'))->code, 403, "[POST $path] refused for a controller");
	is($test->request(POST($path))->code, 403, "[POST $path] refused with no user");
	# A GET falls through to the SPA's catch-all route
	$test->request(GET($path, 'X-Remote-User' => 'root'));
}
for my $table (@felltrack_tables, @fellscout_tables) {
	cmp_ok($count->($table), '>', 0, "refused requests and GETs cleared nothing: $table");
}

# --- clear FellTrack data ---
my $res = $test->request(POST('/clear-felltrack-data', 'X-Remote-User' => 'root'));
ok($res->is_success, '[POST /clear-felltrack-data] successful') or diag($res->status_line);
for my $table (@felltrack_tables) {
	is($count->($table), 0, "clear-felltrack-data: $table emptied");
}
for my $table (@fellscout_tables) {
	cmp_ok($count->($table), '>', 0, "clear-felltrack-data: $table kept");
}
is(scalar $dbh->selectrow_array("select value from config where name = 'route_50km'"), '0 1 2 3 99', 'clear-felltrack-data: config kept');

# --- clear database ---
seed();
$res = $test->request(POST('/clear-database', 'X-Remote-User' => 'root'));
ok($res->is_success, '[POST /clear-database] successful') or diag($res->status_line);
for my $table (@felltrack_tables, @fellscout_tables) {
	is($count->($table), 0, "clear-database: $table emptied");
}
is(scalar $dbh->selectrow_array("select value from config where name = 'admins'"), 'root', 'clear-database: config kept');

done_testing;
