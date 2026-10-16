use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use TestDB;

BEGIN {
	TestDB->ensure_running;
}

use Test::More tests => 2;

# The other tests seed their own config (TestDB's baseline), so nothing else
# checks the defaults a real install gets from build/sql/all.sql. This does that.

my $sql = do {
	open(my $fh, '<', "$FindBin::Bin/../../build/sql/all.sql") or die "Can't read all.sql: $!";
	local $/;
	<$fh>;
};
my ($insert) = $sql =~ m/(INSERT INTO `config` VALUES.*?\);)\s*$/ms
	or die "No config INSERT found in all.sql";
$insert =~ s/INSERT INTO `config`/INSERT INTO `config_defaults`/;

my $dbh = TestDB->dbh;
$dbh->do('create temporary table config_defaults like config') or die $dbh->errstr;
$dbh->do($insert) or die $dbh->errstr;

my $defaults = $dbh->selectall_hashref('select name, value from config_defaults', 'name');

ok(exists $defaults->{time_shift_events}, 'all.sql seeds time_shift_events');
tis($defaults->{time_shift_events}{value}, '', '...with no shift, so check-in times are left as FellTrack gives them');
