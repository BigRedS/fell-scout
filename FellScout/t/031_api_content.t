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
use HTTP::Request::Common;
use JSON qw(decode_json);

TestDB->reset;
TestDB->seed_sample_world;

# A team that's overdue at its next checkpoint, for the laterunners assertions.
TestDB->insert_team(
	team_number => 7, team_name => 'Overdue Team', route => '50km',
	last_checkpoint => 1, last_checkpoint_time => TestDB->offset_datetime(-95),
	next_checkpoint => 2, current_leg => '1-2', completed => 0, retired => 0,
);
TestDB->insert_entrant(code => '7A', team => 7, last_checkpoint => 1, completed => 0, retired => 0);
TestDB->insert_prediction(checkpoint => 2, team_number => 7, expected_time => TestDB->offset_datetime(-15));

# seed_sample_world's team 6 deliberately has no prediction (that's its own
# edge case, for t/030_routes.t); give it one here so it can appear in the
# "still approaching checkpoint 1" arrivals assertion below.
TestDB->insert_prediction(checkpoint => 1, team_number => 6, expected_time => TestDB->offset_datetime(10));

my $app  = FellScout->to_app;
my $test = Plack::Test->create($app);

sub get_json {
	my ($path) = @_;
	my $res = $test->request( GET $path );
	ok( $res->is_success, "[GET $path] successful" ) or diag($res->status_line, "\n", $res->content);
	return decode_json($res->content);
}

# --- /api/summary ---
{
	my $summary = get_json('/api/summary');

	is($summary->{general}->{num_finished}, 1, 'summary: one finished team (team 2)');
	is($summary->{general}->{num_retired}, 1, 'summary: one retired team (team 3)');
	is($summary->{general}->{num_not_completed}, 5, 'summary: five not-completed teams (1, 4, -5, 6, 7)');
	is_deeply(
		[ sort { $a <=> $b } @{ $summary->{general}->{teams_out} } ],
		[-5, 1, 4, 6, 7],
		'summary: teams_out lists exactly the not-completed teams'
	);
	is($summary->{general}->{earliest_finish}->{team_number}, 1, 'summary: only team 1 has a finish prediction, so it is both earliest and latest');
	is($summary->{general}->{latest_finish}->{team_number}, 1, 'summary: latest_finish matches earliest_finish when only one team has a prediction');

	is($summary->{routes}->{'50km'}->{num_not_completed}, 3, 'summary: 50km has three not-completed teams (1, -5, 7)');
	is($summary->{routes}->{'30km'}->{num_not_completed}, 2, 'summary: 30km has two not-completed teams (4, 6)');
}

# --- /api/teams ---
{
	my $teams = get_json('/api/teams');

	ok(exists $teams->{1},  'teams: team 1 present');
	ok(exists $teams->{2},  'teams: team 2 present');
	ok(exists $teams->{4},  'teams: team 4 present');
	ok(exists $teams->{-5}, 'teams: scratch team -5 present');
	is($teams->{4}->{route}, '30km', 'teams: team 4 route');
	is($teams->{-5}->{team_name}, 'Scratch Squad', 'teams: scratch team name');
}

# --- /api/arrivals/1 (checkpoint 1) ---
{
	my $arrivals = get_json('/api/arrivals/1');
	my @team_numbers = map { $_->{team_number} } values %{ $arrivals->{teams} };

	ok(
		( grep { $_ == 6 } @team_numbers ),
		'arrivals/1: team 6 (still approaching checkpoint 1) is listed'
	);
	ok(
		!( grep { $_ == 1 } @team_numbers ),
		'arrivals/1: team 1 (already past checkpoint 1, heading to 2) is not listed'
	);
}

# --- /api/laterunners/ ---
{
	my $laterunners = get_json('/api/laterunners/');
	my ($team7) = grep { $_->{team_number} == 7 } @{ $laterunners->{laterunners} };

	ok(defined $team7, 'laterunners: overdue team 7 is listed');
	ok($team7->{minutes_late} >= 25 && $team7->{minutes_late} <= 35, 'laterunners: team 7 is roughly 30 minutes late')
		or diag("minutes_late was $team7->{minutes_late}");

	my ($team1) = grep { $_->{team_number} == 1 } @{ $laterunners->{laterunners} };
	ok(!defined $team1, 'laterunners: team 1, not yet due, is not listed');
}

done_testing();
