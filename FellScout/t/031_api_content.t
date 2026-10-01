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
use FellScout::Data qw(get_legs);
use Test::More;
use Plack::Test;
use HTTP::Request::Common;
use JSON qw(decode_json encode_json);

TestDB->reset;
TestDB->seed_sample_world;
TestDB->seed_config(controllers => 'testcontroller');

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

	# Per-route checkpoint lines: route order (the start drops out - it's
	# never a leg's destination), with each checkpoint's status/progress as
	# get_checkpoint_details gives it. The progress rules themselves are
	# t/043's job.
	my @cps = @{ $summary->{routes}->{'50km'}->{checkpoints} };
	is_deeply([ map { $_->{checkpoint} } @cps ], [1, 2, 3, 99], 'summary: 50km checkpoints, in route order');
	for my $cp (@cps){
		my $d = FellScout::Data::get_checkpoint_details(TestDB->dbh, $cp->{checkpoint});
		is_deeply(
			[ $cp->{status}, $cp->{progress} ],
			[ $d->{status}, $d->{progress} ],
			"summary: 50km checkpoint $cp->{checkpoint} status/progress match get_checkpoint_details"
		);
	}
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

# --- /api/teams/export ---
{
	my $res = $test->request( GET '/api/teams/export' );
	ok($res->is_success, '[GET /api/teams/export] successful') or diag($res->status_line, "\n", $res->content);
	like($res->header('Content-Type'), qr{^text/csv}, 'teams export: Content-Type is text/csv');
	like($res->header('Content-Disposition'), qr{attachment}, 'teams export: served as an attachment');

	my @lines = split(/\r\n/, $res->content);
	my @header = split(/,/, $lines[0]);
	ok((grep { $_ eq 'team_number' } @header), 'teams export: header includes team_number');
	ok((grep { $_ eq 'team_name' } @header), 'teams export: header includes team_name');
	# header + one row per team (seed_sample_world's 6, plus 7 and 120 added above)
	is(scalar(@lines), 9, 'teams export: one row per team, plus the header');
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

# --- /api/checkpoint/1 (bundles get_checkpoint_arrivals + get_checkpoint_details) ---
{
	my $checkpoint = get_json('/api/checkpoint/1');

	is_deeply(
		[ sort keys %{ $checkpoint->{arrivals}->{teams} } ],
		[6],
		'checkpoint/1: arrivals sub-shape matches /api/arrivals/1 (only team 6)'
	);

	my $details = $checkpoint->{details};
	is($details->{checkpoint_number}, 1, 'checkpoint/1 details: checkpoint_number');
	is_deeply([ sort @{ $details->{routes} } ], ['30km', '50km'], 'checkpoint/1 details: routes');
	is_deeply($details->{previous}, { '30km' => 0, '50km' => 0 }, 'checkpoint/1 details: previous checkpoint per route');
	is_deeply($details->{next}, { '30km' => 3, '50km' => 2 }, 'checkpoint/1 details: next checkpoint per route');

	is_deeply(
		[ sort { $a <=> $b } @{ $details->{teams}->{past}->{'50km'} } ],
		[-5, 1, 3, 7, 120],
		'checkpoint/1 details: teams.past.50km - everyone who has already been through checkpoint 1'
	);
	is_deeply(
		$details->{teams}->{next}->{'30km'},
		[6],
		'checkpoint/1 details: teams.next.30km - team 6, for whom this is the next checkpoint'
	);
	is_deeply(
		$details->{teams}->{future}->{'30km'},
		[6],
		'checkpoint/1 details: teams.future.30km'
	);

	is($details->{status}, 'open', 'checkpoint/1 details: status defaults to open');
	is($details->{status_notes}, undef, 'checkpoint/1 details: status_notes defaults to unset');
}

# --- PATCH /api/checkpoint/:checkpoint/status ---
{
	my $req = PATCH(
		'/api/checkpoint/1/status',
		'Content-Type' => 'application/json',
		'X-Remote-User' => 'testcontroller',
		Content        => encode_json({ status => 'issue', notes => 'Poor phone signal' }),
	);
	my $res = $test->request($req);
	ok($res->is_success, '[PATCH /api/checkpoint/1/status] successful') or diag($res->status_line, "\n", $res->content);

	my $details = decode_json($res->content);
	is($details->{status}, 'issue', 'checkpoint status: updated value returned directly');
	is($details->{status_notes}, 'Poor phone signal', 'checkpoint status: notes returned directly');
	ok($details->{status_updated_at}, 'checkpoint status: status_updated_at is set');

	my $refetched = get_json('/api/checkpoint/1')->{details};
	is($refetched->{status}, 'issue', 'checkpoint status: change persists on a fresh GET');

	# An invalid status is a 400, not a 500 or a silently-accepted garbage value.
	my $bad_req = PATCH(
		'/api/checkpoint/1/status',
		'Content-Type' => 'application/json',
		'X-Remote-User' => 'testcontroller',
		Content        => encode_json({ status => 'on_fire', notes => '' }),
	);
	my $bad_res = $test->request($bad_req);
	is($bad_res->code, 400, '[PATCH /api/checkpoint/1/status] with an invalid status returns 400');
}

# --- /api/checkpoints (every checkpoint at once) ---
{
	my $checkpoints = get_json('/api/checkpoints');

	# Checkpoint 0 is never a leg's destination (`leg_to`), only ever a
	# leg's origin - get_checkpoints() only loops over distinct `leg_to`
	# values, so 0 is special-cased to carry just `details`, with none of
	# the routes/past/future/arrivals/departures keys the other checkpoints
	# get. A real (if minor and long-standing) gap, not something this port
	# should silently paper over - documented here so it's a known, tested
	# shape rather than a surprise.
	is_deeply(
		[ sort keys %{ $checkpoints->{0} } ],
		['details'],
		'checkpoints: checkpoint 0 (never a leg_to) only has a details key, unlike every other checkpoint'
	);
	is($checkpoints->{0}->{details}->{checkpoint_number}, 0, 'checkpoints: checkpoint 0 details still populated');

	my $cp1 = $checkpoints->{1};
	is_deeply([ sort @{ $cp1->{routes} } ], ['30km', '50km'], 'checkpoints: checkpoint 1 routes');
	is_deeply(
		[ sort { $a <=> $b } @{ $cp1->{past}->{'50km'} } ],
		[-5, 1, 7, 120],
		'checkpoints: checkpoint 1 past.50km - not-yet-finished 50km teams already through checkpoint 1'
	);
	is_deeply($cp1->{future}->{'30km'}, [6], 'checkpoints: checkpoint 1 future.30km - team 6, approaching');
	ok(!exists $cp1->{future}->{'50km'}, 'checkpoints: checkpoint 1 future.50km is absent (no 50km team approaching)');

	is_deeply(
		[ map { $_->{team_number} } @{ $cp1->{arrivals} } ],
		[6],
		'checkpoints: checkpoint 1 arrivals lists team 6'
	);
	is_deeply(
		[ sort { $a <=> $b } map { $_->{team_number} } @{ $cp1->{departures} } ],
		[-5, 1, 4, 7],
		'checkpoints: checkpoint 1 departures - teams that left checkpoint 1 (both routes)'
	);
}

# --- /api/entrants ---
{
	my $entrants = get_json('/api/entrants');

	ok(exists $entrants->{'1A'}, 'entrants: 1A present');
	is($entrants->{'1A'}->{team_number}, 1, 'entrants: 1A team_number');
	is($entrants->{'1A'}->{team_name}, 'In Progress Team', 'entrants: 1A team_name');
	is($entrants->{'1A'}->{route}, '50km', 'entrants: 1A route');
	is($entrants->{'1A'}->{retired}, 0, 'entrants: 1A not retired');

	# team 3 (retired) - the entrant's own retired-at-checkpoint value, not
	# the team's, is what the old page (and this port) displays.
	is($entrants->{'3A'}->{retired}, 2, 'entrants: 3A retired at checkpoint 2');
	is($entrants->{'3A'}->{entrant_last_checkpoint}, 1, 'entrants: 3A entrant_last_checkpoint');

	# get_entrants() used to omit `completed` entirely, so a finished
	# entrant (team 2's, per seed_sample_world) was indistinguishable from
	# an active one from this endpoint alone.
	is($entrants->{'2A'}->{completed}, 1, "entrants: 2A completed (get_entrants didn't used to select this at all)");
	is($entrants->{'1A'}->{completed}, 0, 'entrants: 1A (still active) not completed');

	# get_entrants() used to INNER JOIN on routes via
	# `teams.last_checkpoint = routes.leg_from` - checkpoint 99 (the finish)
	# is never a leg_from, so every entrant of every finished team (2A here)
	# was silently missing from the whole endpoint.
	ok(exists $entrants->{'2A'}, 'entrants: 2A (finished team) is present at all');

	# get_entrants()'s prediction join used to match on checkpoint number
	# alone (not team_number too), so any team sharing a next_checkpoint
	# with another team could show that other team's expected time. Teams 1
	# and 7 both have next_checkpoint 2 with deliberately different
	# predictions (+15min vs -15min) - each entrant must show their own
	# team's.
	isnt(
		$entrants->{'1A'}->{expected_hhmm}, $entrants->{'7A'}->{expected_hhmm},
		"entrants: 1A and 7A (different teams, same next_checkpoint) get their own team's prediction, not each other's"
	);
}

# --- /api/entrants/export ---
{
	my $res = $test->request( GET '/api/entrants/export' );
	ok($res->is_success, '[GET /api/entrants/export] successful') or diag($res->status_line, "\n", $res->content);
	like($res->header('Content-Type'), qr{^text/csv}, 'entrants export: Content-Type is text/csv');

	my @lines = split(/\r\n/, $res->content);
	my @header = split(/,/, $lines[0]);
	ok((grep { $_ eq 'code' } @header), 'entrants export: header includes code');
	ok((grep { $_ eq 'completed' } @header), 'entrants export: header includes completed');
}

# --- /api/legs ---
{
	my $legs = get_json('/api/legs');

	ok(!exists $legs->{'0000'}, "legs: the '0-0' leg is filtered out");

	is($legs->{'0102'}->{leg_name}, '1-2', 'legs: 0102 key is leg 1-2');
	is($legs->{'0102'}->{time}, '1h 00m', 'legs: 0102 average time (1 hour, per the fixture route)');
	is_deeply(
		[ sort { $a <=> $b } @{ $legs->{'0102'}->{teams} } ],
		[-5, 1, 7],
		'legs: 0102 teams currently on this leg'
	);

	ok(!exists $legs->{'0203'}->{teams}, 'legs: 0203 (2-3) has no teams currently on it');
}

# --- leg durations don't depend on the database's time zone ---
# get_legs used to format them via from_unixtime(), which shifted them by the
# session's zone (on a +05:30 zone a 1h leg showed as 6h 30m). Set on the test's own
# connection and pass it in directly - the app's connection isn't ours to change.
{
	my $dbh = TestDB->dbh;
	$dbh->do("set time_zone = '+05:30'");
	my $legs = get_legs($dbh);
	$dbh->do("set time_zone = SYSTEM");

	is($legs->{'0102'}->{time}, '1h 00m', 'get_legs: a one-hour leg reads 1h 00m whatever the database time zone');
}

# --- /api/map (route-ordered checkpoint lists + colours, for the Map page) ---
{
	my $routes = get_json('/api/map');

	is_deeply($routes->{'30km'}->{checkpoints}, [0, 1, 3, 99], 'map: 30km checkpoint order');
	is_deeply($routes->{'50km'}->{checkpoints}, [0, 1, 2, 3, 99], 'map: 50km checkpoint order');

	# '30km' sorts before '50km', so the fixed 5-colour palette is assigned
	# in that order - not asserting the exact colours (an implementation
	# detail), just that every route gets a distinct one.
	isnt($routes->{'30km'}->{colour}, $routes->{'50km'}->{colour}, 'map: each route gets a distinct colour');
	ok(defined $routes->{'30km'}->{colour} && defined $routes->{'50km'}->{colour}, 'map: colours are set');
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

	# Bundled alongside the list itself, so the row-colouring thresholds the
	# old HTML-only page fetched separately are available to the Vue port.
	is($laterunners->{lateness_percent_amber}, '30', 'laterunners: lateness_percent_amber bundled in the response');
	is($laterunners->{lateness_percent_red}, '80', 'laterunners: lateness_percent_red bundled in the response');
}

# --- /api/team/:team for an existing team (the Vue team-detail page's data) ---
{
	my $team = get_json('/api/team/1');

	is($team->{team_number}, 1, 'team/1: team_number');
	is($team->{team_name}, 'In Progress Team', 'team/1: team_name');
	is($team->{route}, '50km', 'team/1: route');
	is($team->{last_checkpoint}, 1, 'team/1: last_checkpoint');
	is($team->{next_checkpoint}, 2, 'team/1: next_checkpoint');

	is_deeply(
		[ sort keys %{ $team->{entrants} } ],
		['1A', '1B', '1C'],
		'team/1: all three entrants present'
	);
	is($team->{entrants}->{'1A'}->{entrant_name}, 'Entrant 1A', 'team/1: entrant name');
	is($team->{active_entrants}, '1C', 'team/1: active_entrants is the last non-retired entrant seen');

	ok(exists $team->{remaining_checkpoints}->{2}, 'team/1: remaining_checkpoints includes the next checkpoint (2)');
	ok(exists $team->{remaining_checkpoints}->{99}, 'team/1: remaining_checkpoints includes the finish (99)');
	is($team->{remaining_checkpoints}->{2}->{expected_hhmm}, $team->{next_checkpoint_expected_hhmm},
		'team/1: remaining_checkpoints.2 matches next_checkpoint_expected_hhmm');

	is_deeply($team->{previous_checkpoints}, {}, 'team/1: no previous_checkpoints recorded by this fixture');
}

# --- /api/team/:team for a scratch team ---
{
	my $team = get_json('/api/team/-5');

	is($team->{team_number}, -5, 'team/-5: team_number is negative');
	is($team->{team_name}, 'Scratch Squad', 'team/-5: team_name');
	is_deeply(
		[ sort keys %{ $team->{entrants} } ],
		['9A', '9B'],
		'team/-5: both scratch-team entrants present'
	);
	# seed_sample_world's scratch entrants reference previous_team_number 9/10,
	# which aren't real seeded teams - so previous_team_name/number cross-link
	# fields (only populated via a join to an existing teams row) are absent
	# here. Not exercised by this test; see t/034_scratch_teams.t for the
	# Data.pm-level scratch-team mutation coverage.
}

# --- /api/problems ---
{
	my $problems = get_json('/api/problems');

	is_deeply(
		[ sort { $a <=> $b } map { $_->{team} } @{ $problems->{'small team'} } ],
		[-5, 4, 6, 7, 120],
		'problems: small team - every team with fewer than 3 active entrants'
	);

	is_deeply(
		$problems->{'split team'},
		[ { team => 4, message => 'is split between checkpoints 0, 1' } ],
		'problems: split team - team 4, whose two entrants are at different checkpoints'
	);
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
