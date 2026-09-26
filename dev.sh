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

"$REPO_ROOT/dev-seed.sh"

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

# Leg times and finish predictions come from the backend's sync, which needs
# the backend up first.
echo "Waiting for the backend, then running the sync..."
for _ in $(seq 1 60); do
	curl -fsS -o /dev/null http://127.0.0.1:5000/api/status 2>/dev/null && break
	sleep 1
done
curl -fsS --max-time 120 -o /dev/null http://127.0.0.1:5000/cron

echo
echo "Dev environment is up - frontend: http://localhost:5173  backend: http://127.0.0.1:5000"
echo "DB is seeded with the anonymised S50 example data."
echo "Ctrl-C to stop everything."

wait
