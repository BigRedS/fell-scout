use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use TestDB;

BEGIN {
	TestDB->ensure_running;
	TestDB->set_env;
}

use FellScout::Data qw(get_checkpoint_details);
use Test::More;

# get_checkpoint_details' `progress` (and the `leaving` list it depends on):
# whether a checkpoint is safe for Control to close.

TestDB->reset;
TestDB->seed_sample_world;
my $dbh = TestDB->dbh;

sub details { get_checkpoint_details($dbh, shift) }

# In seed_sample_world, checkpoint 1's leavers are teams 1, -5 (50km) and 4
# (30km); team 3 also last checked in there but is retired, so can't turn back.
is_deeply(
	{ map { $_ => [ sort { $a <=> $b } @{ details(1)->{teams}->{leaving}->{$_} } ] } keys %{ details(1)->{teams}->{leaving} } },
	{ '50km' => [-5, 1], '30km' => [4] },
	'leaving: active teams whose last checkpoint is this one, not the retired team'
);

is(details(2)->{progress}, 'unvisited', 'checkpoint 2: teams due, none been yet -> unvisited');
is(details(1)->{progress}, undef, 'checkpoint 1: team 6 still due and others past -> no progress state');
# Team 6 set off from the start and could still turn back to it
is(details(0)->{progress}, 'passed', 'checkpoint 0: nobody due, but team 6 is on a leg from it -> passed');
is(details(99)->{progress}, undef, 'finish: no routes leave it, so no progress state');

# Team 6 reaches checkpoint 1: nobody's left to arrive there, but teams are
# still on legs out of it; and nobody is on a leg from the start any more.
$dbh->do("update teams set last_checkpoint = 1, next_checkpoint = 3, current_leg = '1-3' where team_number = 6");
is(details(1)->{progress}, 'passed', 'checkpoint 1: nobody due, teams on legs from it -> passed');
is(details(0)->{progress}, 'clear', 'checkpoint 0: nobody due, nobody on a leg from it -> clear');

done_testing;
