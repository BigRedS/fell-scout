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
use FellScout::Sync qw(get_percentile);
use Test::More;
use Plack::Test;
use HTTP::Request::Common;

# Regression tests for bugs already catalogued in improvements.md, written
# to assert *correct* behaviour. They are expected to fail against the
# current code - that's the point: they prove the bug is real and give a
# concrete way to confirm the fix later.
#
# improvements.md #2 (scratch-team deletion only resetting the first
# entrant) used to have a test here too; it's fixed now (see
# FellScout::Data::delete_scratch_team) and its regression coverage lives in
# t/034_scratch_teams.t instead, alongside the rest of that module's tests.

my $app  = FellScout->to_app;
my $test = Plack::Test->create($app);

# --- improvements.md #4: leg-matching LIKE pattern is too broad ---
# The single-dash "$from-$to" leg-naming scheme means `LIKE '%-$checkpoint'`
# only ever matches leg_name values that genuinely end at $checkpoint, so it
# turns out to be equivalent to `leg_to = ?` in every case except one: a
# there-and-back route that revisits a checkpoint (e.g. legs "0-5" and
# "10-5" both end at checkpoint 5). There, the scalar subquery
# `(select index from ... where ...)` genuinely has two matching rows -
# confirmed directly against the test DB ("Subquery returns more than 1
# row") - and *neither* the LIKE pattern nor the `leg_to = ?` fix suggested
# in improvements.md resolves that, since leg_to for checkpoint 5 really is
# ambiguous on this route. That's a narrower, harder problem than #4
# describes: the subquery-for-an-index approach can't represent "the leg
# ending at checkpoint X" when X is visited more than once. This test
# documents the crash either way.
{
	TestDB->reset;
	TestDB->insert_route('outback', [0, 5, 10, 5, 99]);
	TestDB->insert_team(
		team_number => 50, team_name => 'There And Back Team', route => 'outback',
		last_checkpoint => 5, next_checkpoint => 10, current_leg => '5-10', completed => 0, retired => 0,
	);
	TestDB->insert_entrant(code => '50A', team => 50, last_checkpoint => 5, completed => 0, retired => 0);

	my $res = $test->request( GET '/api/arrivals/5' );
	ok($res->is_success, '[GET /api/arrivals/5] does not die when a route revisits the requested checkpoint')
		or diag($res->status_line, "\n", $res->content);
}

# --- improvements.md #3: get_percentile() pushes the same element N times ---
# `for(0 .. $index){ push(@numbers, $in[$index]) }` should be `$in[$_]` - it
# builds @numbers as N copies of a single element instead of a slice of the
# most-recent $index+1 elements. Now that get_percentile() takes its config
# as plain arguments (no `vars` needed), this is testable directly.
{
	# 20 samples, most-recent-first; sample_size=40% -> take the first 7
	# (index 0..6), then the 95th percentile of that slice.
	my @in = (1 .. 20);

	my $correct = do {
		my @slice = sort { $a <=> $b } @in[0 .. 6];
		$slice[ int((95 / 100) * $#slice - 1) ];
	};

	is(
		get_percentile(\@in, percentile => 95, min_sample => 5, sample_size => 40),
		$correct,
		'get_percentile takes a slice of the most-recent sample_size%, not N copies of one element'
	);
}

done_testing();
