#! /bin/bash

# Quickly bring up a dev environment:
#
# * db-test from docker, seeded from the c50 example CSVs
# * plackup the Perl in front of it
# * Vite frontend dev-server in front
#
# Hot-reloads, hopefully :)

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Bringing up db-test..."
perl -I"$REPO_ROOT/FellScout/lib" -I"$REPO_ROOT/FellScout/t/lib" -MTestDB -e 'TestDB->ensure_running'

echo "Seeding db-test with the S50 example data (wipes any previous db-test data)..."
perl -I"$REPO_ROOT/FellScout/lib" -I"$REPO_ROOT/FellScout/t/lib" \
	-MTestDB -MFellScout::Data=import_checkpoints_csv \
	-e '
		TestDB->reset;
		import_checkpoints_csv(TestDB->dbh, shift);
	' "$REPO_ROOT/s50-example-checkpoints.csv"

(
	cd "$REPO_ROOT/FellScout"
	env \
		MYSQL_HOST=127.0.0.1 MYSQL_PORT=3307 MYSQL_DATABASE=fellscout \
		MYSQL_USERNAME=root MYSQL_PASSWORD=test \
		./bin/progress-to-db "$REPO_ROOT/s50-example-progress.csv"
)

echo "Starting backend (plackup) on http://127.0.0.1:5000 ..."
(
	cd "$REPO_ROOT/FellScout"
	exec env \
		MYSQL_HOST=127.0.0.1 MYSQL_PORT=3307 MYSQL_DATABASE=fellscout \
		MYSQL_USERNAME=root MYSQL_PASSWORD=test DANCER_ENVIRONMENT=test \
		plackup bin/app.psgi
) &
BACKEND_PID=$!

echo "Starting frontend (vite) on http://localhost:5173 ..."
(
	cd "$REPO_ROOT/frontend"
	# Calling vite directly, not via `npm run dev` - npm wraps the actual
	# process in its own shell, which then doesn't reliably die when this
	# script's trap below tries to kill it.
	exec ./node_modules/.bin/vite
) &
FRONTEND_PID=$!

cleanup() {
	echo
	echo "Stopping..."
	kill "$BACKEND_PID" "$FRONTEND_PID" 2>/dev/null
}
trap cleanup INT TERM EXIT

echo
echo "Dev environment is up - frontend: http://localhost:5173  backend: http://127.0.0.1:5000"
echo "DB is seeded with the anonymised S50 example data."
echo "Ctrl-C to stop everything."

wait
