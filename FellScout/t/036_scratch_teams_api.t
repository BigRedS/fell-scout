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

# run_cronjobs() shells out and would otherwise default to the real,
# gitignored progress.csv - point it at a harmless fixture instead, same
# approach as t/032_cron.t. skip_fetch_from_felltrack is on by default
# (TestDB's baseline config), so get-data itself is a no-op; this only
# matters for the progress-to-db step run_cronjobs also triggers.
FellScout::setting('progress_csv_path', "$FindBin::Bin/fixtures/cron_pipeline.csv");

TestDB->reset;
TestDB->insert_entrant(code => '11A', team => 11, last_checkpoint => 1);
TestDB->insert_entrant(code => '12B', team => 12, last_checkpoint => 1);
TestDB->insert_entrant(code => '13C', team => 13, last_checkpoint => 1);
TestDB->dbh->do("replace into scratch_teams (team_number, team_name) values (30, 'Existing Squad')");
TestDB->insert_entrant(code => '31A', team => -30, last_checkpoint => 1);
TestDB->dbh->do("replace into scratch_team_entrants (team_number, entrant_code, previous_team_number) values (30, '31A', 31)");

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

# --- GET /api/scratch-teams ---
{
	my $res = $test->request( GET '/api/scratch-teams' );
	ok($res->is_success, '[GET /api/scratch-teams] successful') or diag($res->status_line, "\n", $res->content);

	my $teams = decode_json($res->content);
	is($teams->{30}->{team_name}, 'Existing Squad', 'scratch-teams: existing team listed');
	is($teams->{30}->{entrants}, '31A', 'scratch-teams: existing team entrants');
}

# --- POST /api/scratch-teams (create) ---
my $new_team_number;
{
	my $res = json_request(\&POST, '/api/scratch-teams', { team_name => 'New Squad', entrants => '11A 12B' });
	ok($res->is_success, '[POST /api/scratch-teams] successful') or diag($res->status_line, "\n", $res->content);

	my $result = decode_json($res->content);
	ok(!($result->{errors} && @{$result->{errors}}), 'creating a new scratch team reports no errors')
		or diag(join(', ', @{$result->{errors}}));

	my $teams = decode_json($test->request( GET '/api/scratch-teams' )->content);
	my ($created) = grep { $teams->{$_}->{team_name} eq 'New Squad' } keys %$teams;
	ok(defined $created, 'the new team shows up in a follow-up GET');
	is($teams->{$created}->{entrants}, '11A 12B', 'both entrants recorded');
	$new_team_number = $created;
}

# --- PUT /api/scratch-teams/:team_number (update membership) ---
{
	my $res = json_request(\&PUT, "/api/scratch-teams/$new_team_number", { entrants => '11A 13C' });
	ok($res->is_success, '[PUT /api/scratch-teams/:id] successful') or diag($res->status_line, "\n", $res->content);

	my $teams = decode_json($test->request( GET '/api/scratch-teams' )->content);
	is($teams->{$new_team_number}->{entrants}, '11A 13C', '12B swapped out for 13C');

	my ($team_12b) = TestDB->dbh->selectrow_array("select team from entrants where code = '12B'");
	is($team_12b, 12, '12B, dropped from the scratch team, is put back into its original team');
}

# --- PUT with empty entrants deletes the team ---
{
	my $res = json_request(\&PUT, "/api/scratch-teams/$new_team_number", { entrants => '' });
	ok($res->is_success, '[PUT /api/scratch-teams/:id] with empty entrants successful') or diag($res->status_line, "\n", $res->content);

	my $teams = decode_json($test->request( GET '/api/scratch-teams' )->content);
	ok(!exists $teams->{$new_team_number}, 'the team is gone after clearing its entrants');
}

# --- DELETE /api/scratch-teams/:team_number ---
{
	my $res = json_request(\&DELETE, '/api/scratch-teams/30');
	ok($res->is_success, '[DELETE /api/scratch-teams/:id] successful') or diag($res->status_line, "\n", $res->content);

	my $teams = decode_json($test->request( GET '/api/scratch-teams' )->content);
	ok(!exists $teams->{30}, 'team 30 is gone after DELETE');

	my ($team_31a) = TestDB->dbh->selectrow_array("select team from entrants where code = '31A'");
	is($team_31a, 31, '31A reset to its original team');
}

# --- validation: an unknown entrant code is rejected, not silently dropped ---
{
	my $res = json_request(\&POST, '/api/scratch-teams', { team_name => 'Doomed Squad', entrants => '99Z' });
	ok($res->is_success, '[POST /api/scratch-teams] with a bad entrant code still returns 200 (errors in the body, not an HTTP failure)')
		or diag($res->status_line, "\n", $res->content);

	my $result = decode_json($res->content);
	ok($result->{errors} && @{$result->{errors}}, 'an error is reported for the unknown entrant code');

	my $teams = decode_json($test->request( GET '/api/scratch-teams' )->content);
	ok(!(grep { $teams->{$_}->{team_name} eq 'Doomed Squad' } keys %$teams), 'no scratch team is created when validation fails');
}

done_testing();
