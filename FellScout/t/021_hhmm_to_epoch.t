use strict;
use warnings;

use FindBin;
use Test::More;
use Time::Local qw(timelocal);

# bin/progress-to-db has a run() entry point guarded by `run() unless
# caller;`, so requiring it (require, not `perl bin/progress-to-db`) loads
# its subs without connecting to a database or touching any file. That lets
# hhmm_to_epoch()'s date math get tested directly and fast, on top of (not
# instead of) the black-box coverage in t/020_progress_to_db.t.
require "$FindBin::Bin/../bin/progress-to-db";

my $start = timelocal(0, 0, 0, 15, 5, 2020); # midnight, 15 Jun 2020

is(
	main::hhmm_to_epoch('0930', 0, $start, undef),
	timelocal(0, 30, 9, 15, 5, 2020),
	'same day, no day added, no time shift'
);

is(
	main::hhmm_to_epoch('0015', 1, $start, undef),
	timelocal(0, 15, 0, 16, 5, 2020),
	'added_days=1 (midnight rollover) moves to the next calendar day'
);

is(
	main::hhmm_to_epoch('0930', 0, $start, '1:30'),
	timelocal(0, 30, 9, 15, 5, 2020) + (1 * 3600 + 30 * 60),
	'a positive time_shift_events value shifts the result later'
);

is(
	main::hhmm_to_epoch('0930', 0, $start, '-1:30'),
	timelocal(0, 30, 9, 15, 5, 2020) - (1 * 3600 + 30 * 60),
	'a negative (leading "-") time_shift_events value shifts the result earlier'
);

is(
	main::hhmm_to_epoch('0930', 0, $start, ''),
	timelocal(0, 30, 9, 15, 5, 2020),
	'an empty time_shift_events value is a no-op'
);

done_testing();
