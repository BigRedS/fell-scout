#! /bin/sh

if [ "" = "$CRON_INTERVAL_SECONDS" ]; then
	CRON_INTERVAL_SECONDS=4
fi

while true; do
	curl http://web:5000/cron
	sleep $CRON_INTERVAL_SECONDS
done
