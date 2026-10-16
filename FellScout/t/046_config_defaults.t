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
use FellScout::ConfigDefaults qw(@CONFIG_DEFAULTS ensure_config_defaults);
use Test::More;
use Plack::Test;
use HTTP::Request::Common;

# Config defaults come from FellScout::ConfigDefaults, inserted by the app,
# because a database initialised from an older all.sql never got rows added
# since - one from 2025 had no `admins` row, so nobody could reach the Admin
# page to add it.

my %default = map { $_->[0] => $_ } @CONFIG_DEFAULTS;
my $dbh = TestDB->dbh;
my $config = sub { $dbh->selectall_hashref('select name, value, notes from config', 'name') };

# time_shift_events was once shipped as '18:00' - a testing leftover that
# shifted every check-in time on every fresh install by 18 hours.
is($default{time_shift_events}[1], '', 'time_shift_events defaults to no shift');

# --- ensure_config_defaults fills gaps without overwriting ---
TestDB->reset;
$dbh->do("delete from config where name in ('admins', 'enable_incidents')");
$dbh->do("update config set value = 'someone', notes = 'my own note' where name = 'controllers'");

ensure_config_defaults($dbh);
my $after = $config->();

is($after->{admins}{value}, $default{admins}[1], 'a missing row is added with its default value');
is($after->{admins}{notes}, $default{admins}[2], '...and its notes');
is($after->{enable_incidents}{value}, 'on', 'every missing row is added');
is($after->{controllers}{value}, 'someone', 'an existing value is left alone');
is($after->{controllers}{notes}, 'my own note', '...as are its notes');
is(scalar(keys %{$after}), scalar(@CONFIG_DEFAULTS), 'one row per default, no duplicates');

# --- the app does it itself, on its first request ---
TestDB->reset;
$dbh->do("delete from config where name = 'admins'");

my $test = Plack::Test->create(FellScout->to_app);
my $res = $test->request(GET '/api/status');
ok($res->is_success, '[GET /api/status] successful') or diag($res->status_line);
ok(exists $config->()->{admins}, "the app's first request adds the missing row");

# --- all.sql no longer carries its own copy ---
my $sql = do {
	open(my $fh, '<', "$FindBin::Bin/../../build/sql/all.sql") or die "Can't read all.sql: $!";
	local $/;
	<$fh>;
};
unlike($sql, qr/INSERT INTO `config`/i, 'all.sql seeds no config rows, so the defaults have one home');

done_testing;
