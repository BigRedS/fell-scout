#! /bin/bash

# Entrypoint of compose.dev.yaml's `reseed` service. Seeds the dev database
# now and then again every local midnight, so a long-running demo sheds any
# scratch teams, incidents, retirements etc. and starts each day afresh.
#
# In between, it runs the backend's sync (/cron) every SYNC_INTERVAL_SECONDS,
# like production's cron container. That matters here: with dev_mode the
# example event is dated today and ignore_future_events drops any check-in
# later than the current time, so right after a midnight reseed nothing has
# "happened" yet, and the event plays out through the day as syncs pick up
# each check-in as its time arrives.
#
# RESEED_INTERVAL_SECONDS overrides the wait until midnight; only useful for
# trying this out without waiting for a real midnight.

cd /repo

SYNC_INTERVAL_SECONDS="${SYNC_INTERVAL_SECONDS:-60}"

while true; do
	echo "$(date '+%F %T') Reseeding..."
	if ! ./dev-seed.sh; then
		# The backend may not have been quite ready; don't leave the demo
		# empty for a whole day because of that.
		echo "$(date '+%F %T') Reseed FAILED, retrying in 30s"
		sleep 30
		continue
	fi

	now=$(date +%s)
	next=$(date -d 'tomorrow 00:00' +%s)
	# +5: sleep can wake a moment early, and 'tomorrow 00:00' computed at
	# 23:59:59 is the same midnight again - that would reseed twice, the
	# first time with yesterday's date.
	deadline=$((now + ${RESEED_INTERVAL_SECONDS:-$((next - now + 5))}))
	echo "$(date '+%F %T') Next reseed at $(date -d "@$deadline" '+%F %T'), syncing every ${SYNC_INTERVAL_SECONDS}s until then"

	while true; do
		remaining=$((deadline - $(date +%s)))
		[ "$remaining" -le 0 ] && break
		sleep $((remaining < SYNC_INTERVAL_SECONDS ? remaining : SYNC_INTERVAL_SECONDS))
		[ "$(date +%s)" -ge "$deadline" ] && break
		curl -fsS --max-time 120 -o /dev/null "$DEV_BACKEND_URL/cron" ||
			echo "$(date '+%F %T') Sync FAILED"
	done
done
