#! /bin/bash

# Reset the dev/demo database to a known state: wipe it, load the anonymised
# S50 example data, and - if DEV_BACKEND_URL is set - run the backend's sync
# (the same thing as the admin page's "Felltrack update") so leg times and
# finish predictions get calculated.
#
# Used by dev.sh and by compose.dev.yaml (once at startup, then nightly).
#
# The database is db-test's (127.0.0.1:3307) unless DEV_DB_HOST/DEV_DB_PORT
# say otherwise. This wipes it: never point it at a database you care about.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_HOST="${DEV_DB_HOST:-127.0.0.1}"
DB_PORT="${DEV_DB_PORT:-3307}"

# TestDB.pm has its own idea of where the test DB is; see the comment there.
export FELLSCOUT_TEST_DB_HOST="$DB_HOST" FELLSCOUT_TEST_DB_PORT="$DB_PORT"

echo "Seeding $DB_HOST:$DB_PORT with the S50 example data (wipes everything in it)..."
perl -I"$REPO_ROOT/FellScout/lib" -I"$REPO_ROOT/FellScout/t/lib" \
	-MTestDB -MFellScout::Data=import_checkpoints_csv \
	-e '
		TestDB->reset;
		# admins/controllers default to empty in TestDB (deliberately, for test
		# isolation) - seed the same names all.sql ships in production so the
		# dev_mode header-less fallback (which only fabricates the identity
		# "admin", not admin rights themselves) actually lands in a populated list.
		TestDB->seed_config(dev_mode => "on", admins => "admin", controllers => "central control");
		import_checkpoints_csv(TestDB->dbh, shift);
	' "$REPO_ROOT/s50-example-checkpoints.csv"

# The backend's sync reads ../progress.csv (relative to its own working
# directory, FellScout/), so the example has to be there for it as well as
# for the direct run below.
cp "$REPO_ROOT/s50-example-progress.csv" "$REPO_ROOT/progress.csv"
(
	cd "$REPO_ROOT/FellScout"
	env \
		MYSQL_HOST="$DB_HOST" MYSQL_PORT="$DB_PORT" MYSQL_DATABASE=fellscout \
		MYSQL_USERNAME=root MYSQL_PASSWORD=test \
		./bin/progress-to-db "$REPO_ROOT/progress.csv"
)

if [ -n "$DEV_BACKEND_URL" ]; then
	echo "Running the sync via $DEV_BACKEND_URL/cron ..."
	curl -fsS --max-time 120 -o /dev/null "$DEV_BACKEND_URL/cron"
fi

echo "Seeded."
