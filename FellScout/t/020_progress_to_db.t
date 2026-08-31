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
use POSIX qw(strftime);

my $SCRIPT   = "$FindBin::Bin/../bin/progress-to-db";
my $FIXTURES = "$FindBin::Bin/fixtures";

sub run_progress_to_db {
	my ($fixture) = @_;
	my $output = `"$^X" "$SCRIPT" "$FIXTURES/$fixture" 2>&1`;
	my $exit = $? >> 8;
	return ($exit, $output);
}

sub seed_default_route {
	TestDB->insert_route('50km', [0, 1, 2, 3, 99]);
}

# --- normal progress: two entrants in one team, neither finished ---
{
	TestDB->reset;
	seed_default_route();

	my ($exit, $output) = run_progress_to_db('normal.csv');
	is($exit, 0, 'normal.csv: script exits 0') or diag($output);

	my $team = TestDB->dbh->selectrow_hashref('select * from teams where team_number = 1');
	is($team->{route}, '50km', 'normal.csv: team route');
	is($team->{last_checkpoint}, 2, 'normal.csv: team last_checkpoint is furthest-forward entrant (both at cp2, first alphabetically wins ties)');
	is($team->{next_checkpoint}, 3, 'normal.csv: team next_checkpoint');
	is($team->{current_leg}, '2-3', 'normal.csv: team current_leg');
	is($team->{completed}, 0, 'normal.csv: team not completed');

	my $entrants = TestDB->dbh->selectall_hashref('select * from entrants where team = 1', 'code');
	is(scalar(keys %$entrants), 2, 'normal.csv: both entrants recorded');
	is($entrants->{'1A'}->{last_checkpoint}, 2, 'normal.csv: 1A last_checkpoint');
	is($entrants->{'1B'}->{last_checkpoint}, 2, 'normal.csv: 1B last_checkpoint');

	my ($cp_count) = TestDB->dbh->selectrow_array('select count(*) from checkpoints_teams where team_number = 1');
	is($cp_count, 3, 'normal.csv: representative entrant\'s 3 checkpoint arrivals recorded (cp0,cp1,cp2)');
}

# --- retired entrant ---
{
	TestDB->reset;
	seed_default_route();

	my ($exit, $output) = run_progress_to_db('retired.csv');
	is($exit, 0, 'retired.csv: script exits 0') or diag($output);

	my $entrant = TestDB->dbh->selectrow_hashref("select * from entrants where code = '2A'");
	is($entrant->{last_checkpoint}, 1, 'retired.csv: entrant last_checkpoint is the last one actually reached');
	is($entrant->{retired}, 2, 'retired.csv: entrant retired column stores the checkpoint they retired at');

	my $team = TestDB->dbh->selectrow_hashref('select * from teams where team_number = 2');
	is($team->{last_checkpoint}, 1, 'retired.csv: team last_checkpoint');
	is($team->{completed}, 1, 'retired.csv: team marked completed (retirement counts as completion)');
	is($team->{retired}, 1, 'retired.csv: team marked retired');
}

# --- missed checkpoint (skipped, not recorded as an arrival) ---
{
	TestDB->reset;
	seed_default_route();

	my ($exit, $output) = run_progress_to_db('missed_checkpoint.csv');
	is($exit, 0, 'missed_checkpoint.csv: script exits 0') or diag($output);

	my ($cp2_count) = TestDB->dbh->selectrow_array(
		'select count(*) from checkpoints_teams where team_number = 3 and checkpoint = 2'
	);
	is($cp2_count, 0, 'missed_checkpoint.csv: the missed checkpoint is not recorded as an arrival');

	my $cp3 = TestDB->dbh->selectrow_hashref(
		'select * from checkpoints_teams where team_number = 3 and checkpoint = 3'
	);
	is($cp3->{previous_checkpoint}, 1, 'missed_checkpoint.csv: gap is measured from the last real checkpoint, not the missed one');
	is($cp3->{seconds_since_previous_checkpoint}, 8100, 'missed_checkpoint.csv: 08:00 -> 10:15 is 2h15m regardless of the missed cp in between');
}

# --- midnight rollover ---
{
	TestDB->reset;
	seed_default_route();

	my ($exit, $output) = run_progress_to_db('midnight_rollover.csv');
	is($exit, 0, 'midnight_rollover.csv: script exits 0') or diag($output);

	my $cp2 = TestDB->dbh->selectrow_hashref(
		'select * from checkpoints_teams where team_number = 4 and checkpoint = 2'
	);
	is($cp2->{seconds_since_previous_checkpoint}, 2700, '23:30 -> 00:15 is 45 minutes once the day rollover is accounted for, not a huge/negative gap');
}

# --- entrant re-assigned to a scratch team ---
{
	TestDB->reset;
	seed_default_route();
	TestDB->dbh->do("replace into scratch_teams (team_number, team_name) values (100, 'Scratch Squad')");
	TestDB->dbh->do(
		"replace into scratch_team_entrants (team_number, entrant_code, previous_team_number) values (100, '5A', 5)"
	);

	my ($exit, $output) = run_progress_to_db('scratch_team.csv');
	is($exit, 0, 'scratch_team.csv: script exits 0') or diag($output);

	my $entrant = TestDB->dbh->selectrow_hashref("select * from entrants where code = '5A'");
	is($entrant->{team}, -100, 'scratch_team.csv: entrant is filed under the negative scratch-team number');

	my $scratch_team_row = TestDB->dbh->selectrow_hashref('select * from teams where team_number = -100');
	is($scratch_team_row->{team_name}, 'Scratch Squad', 'scratch_team.csv: scratch team row created with the scratch team name');

	my ($original_team_count) = TestDB->dbh->selectrow_array('select count(*) from teams where team_number = 5');
	is($original_team_count, 0, 'scratch_team.csv: original team number never gets its own team row');
}

# --- ignored team ---
{
	TestDB->reset;
	seed_default_route();
	TestDB->seed_config(ignore_teams => '6');

	my ($exit, $output) = run_progress_to_db('ignored_team.csv');
	is($exit, 0, 'ignored_team.csv: script exits 0') or diag($output);

	my ($ignored_count) = TestDB->dbh->selectrow_array("select count(*) from entrants where code = '6A'");
	is($ignored_count, 0, 'ignored_team.csv: ignored team\'s entrant is not written at all');

	my ($counted_count) = TestDB->dbh->selectrow_array("select count(*) from entrants where code = '7A'");
	is($counted_count, 1, 'ignored_team.csv: non-ignored team\'s entrant is still written');
}

# --- future-dated checkpoint, skipped when ignore_future_events is on ---
{
	TestDB->reset;
	seed_default_route();
	my $tomorrow = strftime('%Y-%m-%d', localtime(time() + 86400));
	TestDB->seed_config(event_start_date => $tomorrow, ignore_future_events => 'on');

	my ($exit, $output) = run_progress_to_db('future_checkpoint.csv');
	is($exit, 0, 'future_checkpoint.csv: script exits 0') or diag($output);

	my $entrant = TestDB->dbh->selectrow_hashref("select * from entrants where code = '8A'");
	ok(defined $entrant, 'future_checkpoint.csv: entrant row still written');
	is($entrant->{last_checkpoint}, undef, 'future_checkpoint.csv: the future checkpoint was skipped, so no checkpoint is recorded');
}

done_testing();
