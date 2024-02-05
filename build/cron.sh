#! /bin/sh

if [ "" = "$CRON_INTERVAL_SECONDS" ]; then
	CRON_INTERVAL_SECONDS=60
fi

while true; do
	curl -qs http://web:5000/cron > /dev/null
	sleep $CRON_INTERVAL_SECONDS
done
