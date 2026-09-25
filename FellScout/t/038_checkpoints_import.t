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
use FellScout::Data qw(update_checkpoint_status);
use Test::More;
use Plack::Test;
use HTTP::Request::Common qw(GET POST);
use JSON qw(decode_json);

# The CSV-parsing + checkpoints/routes-rebuild logic (import_checkpoints_csv,
# extracted from what used to be ~100 lines inline in the /admin/checkpoints
# route) had zero test coverage before this - the upload branch was never
# exercised by any existing test. This is the first.

TestDB->reset;

my $app  = FellScout->to_app;
my $test = Plack::Test->create($app);

my $csv_path = "$FindBin::Bin/fixtures/checkpoints_admin.csv";

my $req = POST(
	'/api/checkpoints/import',
	Content_Type => 'form-data',
	Content      => [ csv => [$csv_path, 'checkpoints.csv'] ],
);
my $res = $test->request($req);
ok($res->is_success, '[POST /api/checkpoints/import] successful') or diag($res->status_line, "\n", $res->content);

my $result = decode_json($res->content);
is($result->{checkpoints}, 4, 'import: four checkpoint rows processed (Start, CP1, CP2, Finish)');
is($result->{routes}, 2, 'import: two routes found (50km, 30km)');
is($result->{legs}, 5, 'import: five legs total (three for 50km, two for 30km)');

# --- checkpoints table populated correctly, CPxx/Start/Finish normalised ---
{
	my $cp1 = TestDB->dbh->selectrow_hashref("select * from checkpoints where checkpoint_number = 1");
	is($cp1->{description}, 'Checkpoint One', 'import: CP1 description');
	is($cp1->{manager}, 'Bob', 'import: CP1 manager');
	is($cp1->{latitude} + 0, 54.2, 'import: CP1 latitude');

	my $start = TestDB->dbh->selectrow_hashref("select * from checkpoints where checkpoint_number = 0");
	is($start->{description}, 'Start Field', "import: 'Start' normalised to checkpoint 0");

	my $finish = TestDB->dbh->selectrow_hashref("select * from checkpoints where checkpoint_number = 99");
	is($finish->{description}, 'Finish Field', "import: 'Finish' normalised to checkpoint 99");
}

# --- routes table rebuilt: CP2 is only on 50km (its 30km distance was blank) ---
{
	# get_routes_checkpoints() lists leg *destinations* in order (matching
	# the admin_checkpoints page's own badge list) - checkpoint 0 is always
	# a leg's start, never its destination, so it never appears here.
	my $routes = decode_json( $test->request( GET '/api/checkpoints/routes' )->content );
	is_deeply($routes->{'50km'}, [1, 2, 99], 'import: 50km leg destinations in CSV order');
	is_deeply($routes->{'30km'}, [1, 99], 'import: 30km skips CP2 (blank leg distance)');
}

# --- a second import fully replaces the routes table, not just adds to it ---
{
	my $req2 = POST(
		'/api/checkpoints/import',
		Content_Type => 'form-data',
		Content      => [ csv => [$csv_path, 'checkpoints.csv'] ],
	);
	$test->request($req2);
	my ($route_count) = TestDB->dbh->selectrow_array('select count(distinct route_name) from routes');
	is($route_count, 2, 'import: re-importing the same CSV does not duplicate routes');

	# checkpoints.checkpoint_number used to have no primary/unique key at
	# all, so `replace into` behaved like a plain insert - re-importing (or
	# just uploading a corrected CSV a second time, the normal case) would
	# silently duplicate every checkpoint row instead of updating it.
	my ($cp_row_count) = TestDB->dbh->selectrow_array('select count(*) from checkpoints');
	is($cp_row_count, 4, 'import: re-importing the same CSV does not duplicate checkpoint rows either');
}

# --- re-importing must not reset an operational status Control has set ---
{
	update_checkpoint_status(TestDB->dbh, 1, 'closed', 'Bridge washed out');

	my $req = POST(
		'/api/checkpoints/import',
		Content_Type => 'form-data',
		Content      => [ csv => [$csv_path, 'checkpoints.csv'] ],
	);
	$test->request($req);

	my $cp1 = TestDB->dbh->selectrow_hashref("select * from checkpoints where checkpoint_number = 1");
	is($cp1->{status}, 'closed', 're-importing the CSV does not reset a checkpoint status Control set');
	is($cp1->{status_notes}, 'Bridge washed out', '...or the notes that went with it');
}

# --- lat/long come from the grid reference when the CSV doesn't supply them ---
{
	my $req = POST(
		'/api/checkpoints/import',
		Content_Type => 'form-data',
		Content      => [ csv => ["$FindBin::Bin/fixtures/checkpoints_grid_only.csv", 'checkpoints.csv'] ],
	);
	my $res = $test->request($req);
	ok($res->is_success, '[POST /api/checkpoints/import] grid-ref-only CSV successful') or diag($res->status_line, "\n", $res->content);

	my $cp1 = TestDB->dbh->selectrow_hashref("select * from checkpoints where checkpoint_number = 1");
	is(sprintf('%.3f', $cp1->{latitude}), '51.788', 'grid ref only: CP1 latitude worked out from SP 9242 1076');
	is(sprintf('%.3f', $cp1->{longitude}), '-0.661', 'grid ref only: CP1 longitude worked out from SP 9242 1076');

	my $cp2 = TestDB->dbh->selectrow_hashref("select * from checkpoints where checkpoint_number = 2");
	is($cp2->{latitude}, undef, 'grid ref only: an unreadable grid ref leaves latitude empty rather than failing the import');
	is($cp2->{longitude}, undef, 'grid ref only: ...and longitude');

	my $finish = TestDB->dbh->selectrow_hashref("select * from checkpoints where checkpoint_number = 99");
	is($finish->{latitude} + 0, 51.5, 'grid ref only: latitude given in the CSV is used as-is, not overwritten from the grid ref');
	is($finish->{longitude} + 0, -0.5, 'grid ref only: ...and so is longitude');
}

# --- a request with no file is a 400, not a crash ---
{
	my $req3 = POST('/api/checkpoints/import', Content_Type => 'form-data', Content => []);
	my $res3 = $test->request($req3);
	is($res3->code, 400, '[POST /api/checkpoints/import] with no file returns 400');
}

done_testing();
