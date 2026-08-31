use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use TestDB;

BEGIN {
	TestDB->ensure_running;
	TestDB->set_env;
}

use FellScout::Data qw(delete_scratch_team update_scratch_team get_scratch_teams);
use Test::More;

# These used to be ~150 lines of business logic inline in the /scratch-teams
# route (only reachable via a full HTTP POST), including the foreach/while
# bug documented as improvements.md #2. Now they're plain functions taking
# $dbh, so they get direct coverage here instead of only the HTTP-level
# smoke test in t/030_routes.t.
#
# update_scratch_team()/delete_scratch_team() only maintain the
# scratch_teams/scratch_team_entrants tables - entrants.team getting set to
# the negative scratch number is progress-to-db's job on the next sync
# (triggered by run_cronjobs right after, in the real route), not this
# function's. delete_scratch_team() is the exception: it resets entrants.team
# directly, since there's no later sync step that would do it otherwise.

# --- delete: every entrant gets reset, not just the first (the bug #2 fix) ---
{
	TestDB->reset;
	TestDB->dbh->do("replace into scratch_teams (team_number, team_name) values (5, 'Scratch Squad')");
	TestDB->insert_entrant(code => '9A', team => -5, last_checkpoint => 1);
	TestDB->insert_entrant(code => '9B', team => -5, last_checkpoint => 1);
	TestDB->dbh->do("replace into scratch_team_entrants (team_number, entrant_code, previous_team_number) values (5, '9A', 9)");
	TestDB->dbh->do("replace into scratch_team_entrants (team_number, entrant_code, previous_team_number) values (5, '9B', 10)");
	TestDB->insert_team(team_number => -5, team_name => 'Scratch Squad');

	my $result = delete_scratch_team(TestDB->dbh, 5);
	is(scalar(@{$result->{successes}}), 1, 'delete_scratch_team reports one success message');

	my ($team_9a) = TestDB->dbh->selectrow_array("select team from entrants where code = '9A'");
	my ($team_9b) = TestDB->dbh->selectrow_array("select team from entrants where code = '9B'");
	is($team_9a, 9, '9A reset to its original team');
	is($team_9b, 9, '9B (same numeric prefix) also reset - not left stranded');

	my ($remaining) = TestDB->dbh->selectrow_array('select count(*) from scratch_team_entrants where team_number = 5');
	is($remaining, 0, 'scratch_team_entrants rows removed');
	my ($team_row) = TestDB->dbh->selectrow_array('select count(*) from teams where team_number = -5');
	is($team_row, 0, 'the negative team row is removed too');
}

# --- add: a brand new scratch team from two entrant codes ---
{
	TestDB->reset;
	TestDB->insert_entrant(code => '11A', team => 11, last_checkpoint => 1);
	TestDB->insert_entrant(code => '12B', team => 12, last_checkpoint => 1);

	my $result = update_scratch_team(TestDB->dbh,
		team_number => undef,
		team_name   => 'New Squad',
		entrants    => '11A 12B',
		add         => 1,
	);
	ok(!($result->{errors} && @{$result->{errors}}), 'no errors creating a new scratch team') or diag(join(', ', @{$result->{errors}}));

	my ($new_number) = TestDB->dbh->selectrow_array("select team_number from scratch_teams where team_name = 'New Squad'");
	ok(defined $new_number, 'scratch_teams row created');

	my $members = TestDB->dbh->selectall_hashref(
		'select entrant_code, previous_team_number from scratch_team_entrants where team_number = ?',
		'entrant_code', undef, $new_number
	);
	is_deeply(
		[ sort keys %$members ],
		['11A', '12B'],
		'both entrants recorded against the new scratch team'
	);
	is($members->{'11A'}->{previous_team_number}, 11, "11A's previous team recorded from its code prefix");

	my $listing = get_scratch_teams(TestDB->dbh);
	is($listing->{$new_number}->{entrants}, '11A 12B', 'get_scratch_teams lists both entrant codes');
}

# --- update: swap one entrant for another on an existing scratch team ---
{
	TestDB->reset;
	TestDB->dbh->do("replace into scratch_teams (team_number, team_name) values (20, 'Existing Squad')");
	TestDB->insert_entrant(code => '21A', team => -20, last_checkpoint => 1);
	TestDB->insert_entrant(code => '22B', team => 22, last_checkpoint => 1);
	TestDB->dbh->do("replace into scratch_team_entrants (team_number, entrant_code, previous_team_number) values (20, '21A', 21)");

	my $result = update_scratch_team(TestDB->dbh,
		team_number => 20,
		team_name   => 'Existing Squad',
		entrants    => '22B', # 21A dropped, 22B added
	);
	ok(!($result->{errors} && @{$result->{errors}}), 'no errors updating the membership') or diag(join(', ', @{$result->{errors}}));

	my ($team_21a) = TestDB->dbh->selectrow_array("select team from entrants where code = '21A'");
	is($team_21a, 21, '21A, dropped from the scratch team, is put back into its original team');

	my $members = TestDB->dbh->selectall_hashref(
		'select entrant_code from scratch_team_entrants where team_number = 20', 'entrant_code'
	);
	is_deeply([ keys %$members ], ['22B'], 'only the current entrant list remains');
}

# --- validation: a non-existent entrant code is rejected, not silently dropped ---
{
	TestDB->reset;

	my $result = update_scratch_team(TestDB->dbh,
		team_number => undef,
		team_name   => 'Doomed Squad',
		entrants    => '99Z',
		add         => 1,
	);
	ok($result->{errors} && @{$result->{errors}}, 'an error is reported for the unknown entrant code');

	my ($team_row) = TestDB->dbh->selectrow_array("select count(*) from scratch_teams where team_name = 'Doomed Squad'");
	is($team_row, 0, 'no scratch team is created when validation fails');
}

done_testing();
