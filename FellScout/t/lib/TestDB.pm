package TestDB;
use strict;
use warnings;
use DBI;
use Cwd qw(abs_path);
use File::Basename qw(dirname);

my $REPO_ROOT = dirname(dirname(dirname(dirname(abs_path(__FILE__)))));

use constant {
	HOST     => '127.0.0.1',
	PORT     => 3307,
	DATABASE => 'fellscout',
	USERNAME => 'root',
	PASSWORD => 'test',
};

my @TABLES = qw(
	checkpoints checkpoints_teams checkpoints_teams_predictions config
	entrants legs logs routes routes_checkpoints
	scratch_team_entrants scratch_teams teams
);

# Baseline config rows, mirroring build/sql/all.sql but with deterministic
# values (fixed past event_start_date, no time_shift) so fixture timestamp
# maths in tests stay simple. Individual tests override via seed_config.
my %BASELINE_CONFIG = (
	route_50mile               => '',
	route_50km                 => '',
	route_30km                 => '',
	percentile                 => '95',
	felltrack_owner             => '',
	felltrack_username          => '',
	felltrack_password          => '',
	ignore_teams                => '',
	ignore_future_events         => 'on',
	skip_fetch_from_felltrack    => 'on',
	lateness_percent_amber       => '30',
	lateness_percent_red         => '80',
	percentile_sample_size       => '40',
	percentile_min_sample        => '10',
	leg_estimate_multiplier      => '1.2',
	google_maps_url              => '',
	event_start_date             => '2020-01-01',
	time_shift_events            => '0:00',
);

my $dbh;

sub _try_connect {
	my $h = DBI->connect(
		"dbi:MariaDB:database=" . DATABASE . ";host=" . HOST . ";port=" . PORT,
		USERNAME, PASSWORD,
		{ RaiseError => 0, PrintError => 0 },
	);
	return $h;
}

sub ensure_running {
	my $class = shift;
	$dbh = _try_connect();
	return if $dbh;

	system('docker', 'compose', '-f', "$REPO_ROOT/compose.yaml", 'up', '-d', 'db-test') == 0
		or die "TestDB: failed to start db-test via docker compose\n";

	my $deadline = time() + 30;
	until ($dbh = _try_connect()) {
		die "TestDB: timed out waiting for db-test to accept connections\n" if time() > $deadline;
		sleep 1;
	}
}

sub dbh {
	my $class = shift;
	$class->ensure_running unless $dbh;
	return $dbh;
}

sub set_env {
	$ENV{MYSQL_HOST}     = HOST;
	$ENV{MYSQL_PORT}     = PORT;
	$ENV{MYSQL_DATABASE} = DATABASE;
	$ENV{MYSQL_USERNAME} = USERNAME;
	$ENV{MYSQL_PASSWORD} = PASSWORD;
	$ENV{DANCER_ENVIRONMENT} = 'test';
}

sub reset {
	my $class = shift;
	my $h = $class->dbh;
	foreach my $table (@TABLES) {
		$h->do("truncate table $table");
	}
	$class->seed_config();
	$h->do("replace into logs (name, message, time) values ('periodic-jobs', 'seeded', now())");
}

sub seed_config {
	my ($class, %overrides) = @_;
	my %config = (%BASELINE_CONFIG, %overrides);
	my $sth = $class->dbh->prepare("replace into config (name, value) values (?, ?)");
	foreach my $name (keys %config) {
		$sth->execute($name, $config{$name});
	}
}

sub insert_route {
	my ($class, $route_name, $checkpoints, %opts) = @_;
	my $seconds_for = $opts{seconds} || {};
	my $routes_sth = $class->dbh->prepare(
		"insert into routes (route_name, `index`, leg_name, leg_from, leg_to) values (?,?,?,?,?)"
	);
	my $legs_sth = $class->dbh->prepare(
		"replace into legs (`from`, `to`, leg_name, seconds) values (?,?,?,?)"
	);
	for my $i (0 .. $#$checkpoints - 1) {
		my ($from, $to) = @{$checkpoints}[$i, $i + 1];
		my $leg_name = "$from-$to";
		$routes_sth->execute($route_name, $i, $leg_name, $from, $to);
		$legs_sth->execute($from, $to, $leg_name, $seconds_for->{$leg_name});
	}
}

sub insert_team {
	my ($class, %f) = @_;
	die "insert_team requires team_number" unless defined $f{team_number};
	$class->dbh->do(
		"replace into teams (team_number, team_name, unit, district, representative_entrant,
		                     route, last_checkpoint, last_checkpoint_time, next_checkpoint,
		                     current_leg, current_leg_index, completed, retired)
		 values (?,?,?,?,?,?,?,?,?,?,?,?,?)",
		undef,
		$f{team_number},
		$f{team_name} // "Team $f{team_number}",
		$f{unit} // 'unit',
		$f{district} // 'district',
		$f{representative_entrant},
		$f{route},
		$f{last_checkpoint} // 0,
		$f{last_checkpoint_time},
		$f{next_checkpoint},
		$f{current_leg},
		$f{current_leg_index},
		$f{completed} // 0,
		$f{retired} // 0,
	);
}

sub insert_entrant {
	my ($class, %f) = @_;
	die "insert_entrant requires code" unless defined $f{code};
	$class->dbh->do(
		"replace into entrants (team, entrant_name, unit, district, completed, retired,
		                        code, last_checkpoint, last_checkpoint_time)
		 values (?,?,?,?,?,?,?,?,?)",
		undef,
		$f{team},
		$f{entrant_name} // "Entrant $f{code}",
		$f{unit} // 'unit',
		$f{district} // 'district',
		$f{completed} // 0,
		$f{retired} // 0,
		$f{code},
		$f{last_checkpoint} // 0,
		$f{last_checkpoint_time},
	);
}

sub insert_checkpoint {
	my ($class, %f) = @_;
	die "insert_checkpoint requires checkpoint_number" unless defined $f{checkpoint_number};
	$class->dbh->do(
		"replace into checkpoints (checkpoint_number, description, manager, mobile, type,
		                           os_grid, latitude, longitude, what3words)
		 values (?,?,?,?,?,?,?,?,?)",
		undef,
		$f{checkpoint_number}, $f{description}, $f{manager}, $f{mobile}, $f{type},
		$f{os_grid}, $f{latitude}, $f{longitude}, $f{what3words},
	);
}

sub insert_prediction {
	my ($class, %f) = @_;
	die "insert_prediction requires checkpoint and team_number"
		unless defined $f{checkpoint} && defined $f{team_number};
	$class->dbh->do(
		"replace into checkpoints_teams_predictions (checkpoint, team_number, expected_time)
		 values (?,?,?)",
		undef,
		$f{checkpoint}, $f{team_number}, $f{expected_time},
	);
}

sub offset_datetime {
	my ($class, $minutes) = @_;
	# Computed via the database's own NOW(), not the host's localtime - the
	# db-test container's clock/timezone need not match the host's, and
	# every time comparison in FellScout.pm's SQL is relative to the DB's
	# NOW() anyway.
	my ($dt) = $class->dbh->selectrow_array(
		"select date_format(now() + interval ? minute, '%Y-%m-%d %H:%i:%s')", undef, $minutes
	);
	return $dt;
}

# A broad, reusable dataset for route-level tests: two routes, and teams
# covering the edge cases the route handlers branch on (in-progress,
# finished, retired, split, small, scratch, and a team with no predictions
# computed yet).
sub seed_sample_world {
	my $class = shift;

	$class->insert_route('50km', [0, 1, 2, 3, 99], seconds => { '0-1' => 3600, '1-2' => 3600, '2-3' => 3600, '3-99' => 3600 });
	$class->insert_route('30km', [0, 1, 3, 99],    seconds => { '0-1' => 3600, '1-3' => 7200, '3-99' => 3600 });

	for my $cp (0, 1, 2, 3, 99) {
		$class->insert_checkpoint(checkpoint_number => $cp, description => "Checkpoint $cp");
	}

	# team 1: in progress, three entrants together
	$class->insert_team(
		team_number => 1, team_name => 'In Progress Team', route => '50km',
		last_checkpoint => 1, last_checkpoint_time => $class->offset_datetime(-30),
		next_checkpoint => 2, current_leg => '1-2', completed => 0, retired => 0,
	);
	for my $code (qw(1A 1B 1C)) {
		$class->insert_entrant(code => $code, team => 1, last_checkpoint => 1, completed => 0, retired => 0);
	}
	$class->insert_prediction(checkpoint => 2, team_number => 1, expected_time => $class->offset_datetime(15));
	$class->insert_prediction(checkpoint => 99, team_number => 1, expected_time => $class->offset_datetime(120));

	# team 2: finished
	$class->insert_team(
		team_number => 2, team_name => 'Finished Team', route => '50km',
		last_checkpoint => 99, last_checkpoint_time => $class->offset_datetime(-10),
		next_checkpoint => 0, current_leg => '', completed => 1, retired => 0,
	);
	$class->insert_entrant(code => '2A', team => 2, last_checkpoint => 99, completed => 1, retired => 0);

	# team 3: retired
	$class->insert_team(
		team_number => 3, team_name => 'Retired Team', route => '50km',
		last_checkpoint => 1, last_checkpoint_time => $class->offset_datetime(-60),
		next_checkpoint => 2, current_leg => '1-2', completed => 1, retired => 1,
	);
	$class->insert_entrant(code => '3A', team => 3, last_checkpoint => 1, completed => 1, retired => 2);

	# team 4: small AND split (two entrants, at different checkpoints) - /problems fodder
	$class->insert_team(
		team_number => 4, team_name => 'Small Split Team', route => '30km',
		last_checkpoint => 1, last_checkpoint_time => $class->offset_datetime(-20),
		next_checkpoint => 3, current_leg => '1-3', completed => 0, retired => 0,
	);
	$class->insert_entrant(code => '4A', team => 4, last_checkpoint => 0, completed => 0, retired => 0);
	$class->insert_entrant(code => '4B', team => 4, last_checkpoint => 1, completed => 0, retired => 0);
	$class->insert_prediction(checkpoint => 3, team_number => 4, expected_time => $class->offset_datetime(45));

	# team -5: a scratch team, regrouped from two originally-different teams
	$class->dbh->do("replace into scratch_teams (team_number, team_name) values (5, 'Scratch Squad')");
	$class->insert_team(
		team_number => -5, team_name => 'Scratch Squad', route => '50km',
		last_checkpoint => 1, last_checkpoint_time => $class->offset_datetime(-15),
		next_checkpoint => 2, current_leg => '1-2', completed => 0, retired => 0,
	);
	$class->insert_entrant(code => '9A', team => -5, last_checkpoint => 1, completed => 0, retired => 0);
	$class->insert_entrant(code => '9B', team => -5, last_checkpoint => 1, completed => 0, retired => 0);
	$class->dbh->do(
		"replace into scratch_team_entrants (team_number, entrant_code, previous_team_number) values (5, '9A', 9)"
	);
	$class->dbh->do(
		"replace into scratch_team_entrants (team_number, entrant_code, previous_team_number) values (5, '9B', 10)"
	);
	$class->insert_prediction(checkpoint => 2, team_number => -5, expected_time => $class->offset_datetime(20));

	# team 6: just started, no predictions computed yet (edge case for LEFT JOINs)
	$class->insert_team(
		team_number => 6, team_name => 'Fresh Start Team', route => '30km',
		last_checkpoint => 0, last_checkpoint_time => $class->offset_datetime(-2),
		next_checkpoint => 1, current_leg => '0-1', completed => 0, retired => 0,
	);
	$class->insert_entrant(code => '6A', team => 6, last_checkpoint => 0, completed => 0, retired => 0);
}

1;
