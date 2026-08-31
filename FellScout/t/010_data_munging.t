use strict;
use warnings;

use Test::More;
use Time::Local qw(timelocal);

use FellScout::Data qw(to_hh_mm);
use FellScout::Sync qw(get_percentile);

# to_hh_mm and get_percentile are the only functions in the split-out
# FellScout::Data / FellScout::Sync modules that need neither a database
# handle nor Dancer2's `vars`/`param` - genuinely pure functions, testable
# directly. Everything else needs a database (see t/lib/TestDB.pm,
# t/033_add_expected_times.t) or a live route context (see t/030_routes.t).
#
# Build epoch times via timelocal so expectations don't depend on the host's
# timezone matching some hardcoded assumption.

my @cases = (
	[0, 0, '0h 00m'],
	[1, 5, '1h 05m'],
	[14, 37, '14h 37m'],
	[23, 59, '23h 59m'],
);

for my $case (@cases) {
	my ($h, $m, $expected_hh_mm) = @$case;
	my $epoch = timelocal(0, $m, $h, 15, 5, 2020); # 15 Jun 2020

	is(to_hh_mm($epoch), $expected_hh_mm, "to_hh_mm($h:$m)");
}

# --- get_percentile ---
{
	is(
		get_percentile([100, 90, 80, 70, 60, 50, 40, 30, 20, 10], percentile => 50),
		40,
		'get_percentile: plain percentile over the full (reversed) sample, no min/sample_size set'
	);

	is(
		get_percentile([10, 20, 30], min_sample => 10),
		20,
		'get_percentile: falls back to the mean when the sample is smaller than min_sample'
	);

	is(
		get_percentile([5, 15, 25, 35, 45]),
		25,
		'get_percentile: percentile defaults to 90 when not given'
	);
}

done_testing();
