package FellScout::ConfigDefaults;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(@CONFIG_DEFAULTS ensure_config_defaults);

# Every config row FellScout knows about, with its default value and the
# description shown on the Admin page.
#
# This, not build/sql/all.sql, is where they live: MariaDB only runs all.sql
# on an empty volume and there are no migrations, so a row added to all.sql
# would never reach an existing database. ensure_config_defaults() runs when
# the app starts instead, and only ever adds missing rows - existing values,
# and existing notes, are left alone. So a new setting is added here, and an
# existing one's default changed here only affects new installs.
our @CONFIG_DEFAULTS = (
	# [ name, default value, notes ]
	[ 'route_50mile', '',
		'space-separated list of checkpoints on 50 mile route' ],
	[ 'route_50km', '',
		'space-separated list of checkpoints on 50km route' ],
	[ 'route_30km', '',
		'space-separated list of checkpoints on 30km route' ],
	[ 'percentile', '95',
		'When calculating expected times for legs, we use this percentile. Normally 90' ],
	[ 'felltrack_owner', '',
		undef ],
	[ 'felltrack_username', '',
		undef ],
	[ 'felltrack_password', '',
		undef ],
	[ 'ignore_teams', '',
		'A space-separated list of teams to ignore' ],
	[ 'ignore_future_events', 'on',
		'Skip any events that appear to have happened in the future. Should only be useful when testing with old data. Always on when dev_mode is on' ],
	[ 'skip_fetch_from_felltrack', 'on',
		'Set to \'on\' to not download fresh data from felltrack; will continue to use the last-downloaded CSV file. Always on when dev_mode is on' ],
	[ 'lateness_percent_amber', '30',
		'When a team is on the laterunners page, if thir percent-lateness is higher than this and lower than lateness_percent_red, they will be highlighted in yellow. Normally 30' ],
	[ 'lateness_percent_red', '80',
		'When a team is on the laterunners page, if their percent-lateness is higher than this they will be highlighted in red. Normally 80' ],
	[ 'percentile_sample_size', '40',
		'When calculating the expected times for legs we want to favour the more-recent teams; this sets the size of the most-recent percentile of the sample set that we go on to take the time-taken percentile of. Normally 60' ],
	[ 'percentile_min_sample', '10',
		'When calculating a percentile, after applying any percentile_sample_size, if the number of samples is less than this a simple mean will be taken instead. Normally 10' ],
	[ 'leg_estimate_multiplier', '1.2',
		'Multiply the naive estimate of a leg time by this to increase it to account for later teams being slower than earlier ones' ],
	[ 'google_maps_url', '',
		'address of the route on Google Maps route' ],
	[ 'event_start_date', '2025-10-15',
		'The date of the start of the event, presumed to be the date on which any team checks into their first checkpoint. This is silently overriden by \'dev_mode\'' ],
	[ 'time_shift_events', '',
		'Time to add (begin with a "-" to remove) to each checkpoint check-in time. Mostly for testing' ],
	[ 'enable_incidents', 'on',
		'Set to \'on\' to enable the Incidents feature - when off, the page is hidden and its API refuses requests' ],
	[ 'enable_retirements', 'on',
		'Set to \'on\' to enable the Retirements feature - when off, the page is hidden and its API refuses requests' ],
	[ 'dev_mode', '',
		'Set to \'on\' to override the date with today\'s date and only show events in the past. This will silently override \'event_start_date\', \'ignore_future_events\' and \'skip_fetch_from_felltrack\'. With no X-Remote-User header (no proxy in front), this also grants admin access, so the dev/demo stack is fully usable on its own' ],
	[ 'admins', 'admin',
		'A space-separated list of usernames (from the X-Remote-User header set by the reverse proxy) who get admin access - config, logs, clearing the database, importing the checkpoints CSV. Being an admin also grants everything \'controllers\' does' ],
	[ 'controllers', 'central control',
		'A space-separated list of usernames who get controller access - scratch teams, incidents, retirements, checkpoint status. Everyone else (anyone the proxy authenticates who isn\'t listed here or in \'admins\') gets read-only access' ],
);

sub ensure_config_defaults {
	my $dbh = shift;
	my $sth = $dbh->prepare("insert ignore into config (name, value, notes) values (?, ?, ?)");
	foreach my $row (@CONFIG_DEFAULTS) {
		$sth->execute(@{$row});
	}
}

1;
