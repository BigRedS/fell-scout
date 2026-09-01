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

# A second team with a finish prediction, sooner than team 1's (+120min), so
# earliest_finish/latest_finish genuinely differ - team 1 alone can't tell
# the two apart.
TestDB->insert_team(
	team_number => 120, team_name => 'Front Runner Team', route => '50km',
	last_checkpoint => 3, next_checkpoint => 99, current_leg => '3-99', completed => 0, retired => 0,
);
TestDB->insert_entrant(code => '120A', team => 120, last_checkpoint => 3, completed => 0, retired => 0);
TestDB->insert_prediction(checkpoint => 99, team_number => 120, expected_time => TestDB->offset_datetime(10));

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
	is($summary->{general}->{num_not_completed}, 6, 'summary: six not-completed teams (1, 4, -5, 6, 7, 120)');
	is_deeply(
		[ sort { $a <=> $b } @{ $summary->{general}->{teams_out} } ],
		[-5, 1, 4, 6, 7, 120],
		'summary: teams_out lists exactly the not-completed teams'
	);
	is($summary->{general}->{earliest_finish}->{team_number}, 120, 'summary: earliest_finish is team 120 (+10min), not team 1 (+120min)');
	is($summary->{general}->{latest_finish}->{team_number}, 1, 'summary: latest_finish is team 1 (+120min), the later of the two predictions');

	is($summary->{routes}->{'50km'}->{num_not_completed}, 4, 'summary: 50km has four not-completed teams (1, -5, 7, 120)');
	is($summary->{routes}->{'30km'}->{num_not_completed}, 2, 'summary: 30km has two not-completed teams (4, 6)');
	is($summary->{routes}->{'50km'}->{earliest_finish}->{team_number}, 120, 'summary: per-route earliest_finish also correctly picks team 120');
	is($summary->{routes}->{'50km'}->{latest_finish}->{team_number}, 1, 'summary: per-route latest_finish also correctly picks team 1');
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

# --- /api/arrivals/5 on a there-and-back route (improvements.md #4) ---
# A route that revisits a checkpoint (out-and-back) makes "the leg ending at
# checkpoint 5" ambiguous - here legs "0-5" and "10-5" both end at 5. Used to
# crash outright ("Subquery returns more than 1 row"); now resolved by
# picking the *last* occurrence (`order by index desc limit 1`), so the
# board shows everyone who hasn't passed checkpoint 5 for the final time yet
# - including teams on their way back out to it a second time.
{
	TestDB->insert_route('outback', [0, 5, 10, 5, 99]);
	my %legs_by_team = (
		101 => ['0-5', 5],   # approaching checkpoint 5 for the first time
		102 => ['5-10', 10], # between the two visits
		103 => ['10-5', 5],  # approaching checkpoint 5 for the second/last time
		104 => ['5-99', 99], # already past checkpoint 5 for good
	);
	for my $team_number (sort keys %legs_by_team) {
		my ($current_leg, $next_checkpoint) = @{ $legs_by_team{$team_number} };
		TestDB->insert_team(
			team_number => $team_number, route => 'outback', last_checkpoint => 5,
			next_checkpoint => $next_checkpoint, current_leg => $current_leg, completed => 0, retired => 0,
		);
		TestDB->insert_prediction(checkpoint => $next_checkpoint, team_number => $team_number, expected_time => TestDB->offset_datetime(10));
	}

	my $arrivals = get_json('/api/arrivals/5');
	my @team_numbers = sort { $a <=> $b } map { $_->{team_number} } values %{ $arrivals->{teams} };

	is_deeply(
		\@team_numbers,
		[101, 102, 103],
		'arrivals/5: everyone before the last visit to checkpoint 5 is listed, but not team 104 (already past it for good)'
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

# --- /api/team/:team for a team that doesn't exist ---
# get_team()'s error path used to `return %team` instead of `return \%team`,
# so a nonexistent team collapsed to an empty list rather than an empty
# hashref - encode_json(get_team(...)) then got zero arguments and 500'd
# ("hash- or arrayref expected, not a simple scalar").
{
	my $res = $test->request( GET '/api/team/99999' );
	ok($res->is_success, '[GET /api/team/99999] does not 500 for a nonexistent team')
		or diag($res->status_line, "\n", $res->content);
	is_deeply(decode_json($res->content), {}, 'a nonexistent team serialises to an empty JSON object');
}

done_testing();
