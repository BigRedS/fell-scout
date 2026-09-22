package FellScout;

use Dancer2;
use Dancer2::Plugin::Database;
use POSIX qw(strftime);
use Cwd;

use FellScout::Data qw(
	get_status
	get_summary
	get_laterunners
	get_lateness_thresholds
	get_routes_map
	get_config
	update_config
	get_logs
	get_routes_checkpoints
	import_checkpoints_csv
	get_legs
	get_checkpoints
	get_checkpoint_details
	get_checkpoint_arrivals
	get_entrants
	get_teams
	get_team
	get_problems
	clear_cache
	delete_scratch_team
	update_scratch_team
	get_scratch_teams
);
use FellScout::Sync qw(run_cronjobs);

setting('plugins')->{'Database'}->{'host'}=$ENV{'MYSQL_HOST'};
setting('plugins')->{'Database'}->{'database'}=$ENV{MYSQL_DATABASE};
setting('plugins')->{'Database'}->{'username'}=$ENV{MYSQL_USERNAME};
setting('plugins')->{'Database'}->{'password'}=$ENV{MYSQL_PASSWORD};
setting('plugins')->{'Database'}->{'port'}=$ENV{MYSQL_PORT};

our $VERSION = '0.1';


hook 'before' => sub {
	response_header 'Content-Type' => 'application/json' if request->path =~ m{^/api/};

	my $sth = database->prepare("select name, value from config");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		var $row->{name} => $row->{value};
	}

	$sth = database->prepare("select
	                          date_format( timediff(now(), time ), \"%kh%im\") as time_since_last_felltrack_update,
	                          timestampdiff(SECOND, time, CURTIME()) as seconds_since_last_felltrack_update
	                          from logs
	                          where
	                          name = 'periodic-jobs'");
	$sth->execute();
	my $page = $sth->fetchrow_hashref();
	$page->{auto_refresh} = param('auto_refresh') if param('auto_refresh') and param('auto_refresh') > 0;

	$page->{google_maps_url} = vars->{'google_maps_url'} if vars->{'google_maps_url'};

	var page => $page;
};

# A few functions run FellScout::Sync::run_cronjobs() on completion (it's
# essentially a refresh-cache call)
# Here we expose a function to grab the various required settings from
# Dancer's vars keyword
sub _sync_config {
	return (
		felltrack_owner           => vars->{felltrack_owner},
		felltrack_username        => vars->{felltrack_username},
		felltrack_password        => vars->{felltrack_password},
		ignore_future_events      => vars->{ignore_future_events},
		skip_fetch_from_felltrack => vars->{skip_fetch_from_felltrack},
		progress_csv_path         => setting('progress_csv_path'),
		percentile                => vars->{percentile},
		percentile_min_sample     => vars->{percentile_min_sample},
		percentile_sample_size    => vars->{percentile_sample_size},
		leg_estimate_multiplier   => vars->{leg_estimate_multiplier},
	);
}

# # # # # SUMMARY

any ['get', 'post'] => '/api/summary' => sub{
	encode_json(get_summary(database));
};

any ['get'] => '/api/status' => sub{
	my $status = get_status(database);
	$status->{google_maps_url} = vars->{google_maps_url};
	$status->{stale_after_seconds} = 600;
	return encode_json($status);
};

# Temporary, for comparing against the new Vue summary page page-by-page
# during the frontend migration - delete once the Summary page is trusted
# to have full parity with this.
any ['get', 'post'] => '/summary-old' => sub{
	my $return = {
		summary => get_summary(database),
		page => vars->{page},
	};
	$return->{page}->{title} = 'Event Summary (old)';
	return template 'summary.tt', $return;
};

# # # # # laterunners

any ['get', 'post'] => '/laterunners' => sub {
	if(param('threshold') and param('threshold') =~ m/^\d+(m|pc)$/){
		redirect "/laterunners/".param('threshold');
	}else{
		redirect "/laterunners/0";
	}
};
any ['get', 'post'] => '/laterunners/:threshold?' => sub {
	my $return = {
		laterunners => get_laterunners(database, param('threshold')),
		threshold => param('threshold'),
		page => vars->{page}
	};
	my $sth = database->prepare("select name,value from config where name like 'lateness_percent_%'");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		$return->{page}->{ $row->{name} } = $row->{value};
	}
	$return->{page}->{enable_fancytable} = 1;
	$return->{page}->{table_sort_column} = 8;
	$return->{page}->{table_sort_order} = 'desc';
	$return->{page}->{title} = 'Late Runners';
	return template 'laterunners.tt', $return;
};
any ['get', 'post'] => '/api/laterunners/' => sub {
	return encode_json({
		laterunners => get_laterunners( database, param('threshold') ),
		%{ get_lateness_thresholds(database) },
	});
};

# # # # # LEGS + CHECKPOINTS
any ['get', 'post'] => '/legs' => sub {
	my $return = {
		legs => get_legs(database),
		page => vars->{page},
	};
	$return->{page}->{title} = 'Legs';
	return template 'legs.tt', $return;
};

any ['get', 'post'] => '/api/legs' => sub{
	return encode_json( get_legs(database) );
};

# # # # # map
any ['get', 'post'] => '/map' => sub {
	my $return = {
		checkpoints => get_checkpoints(database),
		page => vars->{page},
	};

	my @colours = qw/red blue green yellow orange/;

	my $sth = database->prepare('select distinct route_name from routes order by route_name asc');
	my $sth_cps = database->prepare('select leg_to from routes where route_name = ? order by `index` asc');
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		my $route_name = $row->{route_name};
		$return->{routes}->{$route_name}->{colour} = shift(@colours);
		push(@{ $return->{routes}->{$route_name}->{checkpoints} }, 0);
		$sth_cps->execute($route_name);
		while (my $cp = $sth_cps->fetchrow_hashref()){
			push(@{$return->{routes}->{$route_name}->{checkpoints}}, $cp->{leg_to});
		}
	}

	$return->{page}->{title} = 'Map';
	return template 'map.tt', $return;
};


# # # # # checkpoints
any ['get', 'post'] => '/checkpoints' => sub {
	my $return = {
		checkpoints => get_checkpoints(database),
		page => vars->{page},
	};
	$return->{page}->{title} = 'Checkpoints';
	return template 'checkpoints.tt', $return;
};

any ['get', 'post'] => '/api/checkpoints' => sub{
	return encode_json( get_checkpoints(database) );
};

any ['get'] => '/api/map' => sub{
	return encode_json( get_routes_map(database) );
};

any ['get'] => '/api/checkpoints/routes' => sub{
	return encode_json( get_routes_checkpoints(database) );
};

any ['post'] => '/api/checkpoints/import' => sub{
	my $upload = request->upload('csv');
	unless($upload){
		status(400);
		return encode_json({ error => 'No csv file uploaded (expected a multipart field named "csv")' });
	}
	my $result = import_checkpoints_csv(database, $upload->tempname);
	return encode_json($result);
};

any ['get'] => '/api/config' => sub{
	return encode_json( get_config(database) );
};

any ['patch'] => '/api/config' => sub{
	my $body = decode_json( request->body || '{}' );
	my $changes = update_config(database, $body);
	return encode_json({ changes => $changes });
};

any ['get'] => '/api/logs' => sub{
	return encode_json( get_logs(database) );
};

any ['get', 'post'] => '/checkpoint' => sub {
	my $checkpoint = param('checkpoint');
	if($checkpoint =~ m/^\d+$/){
		redirect "/checkpoint/$checkpoint";
	}else{
		redirect "/checkpoints";
	}
};

any ['get', 'post'] => '/arrivals/:checkpoint' => sub {
	my $return = {
		checkpoint => get_checkpoint_arrivals(database, param('checkpoint')),
		page => vars->{page},
	};
	$return->{page}->{title} = 'Arrivals for checkpoint '.param('checkpoint');
	$return->{page}->{enable_fancytable} = 1;
	$return->{page}->{table_is_searchable} = 'false';
	return template 'arrivals.tt', $return;
};


any ['get', 'post'] => '/api/checkpoint/:checkpoint' => sub{
	my $checkpoint = param('checkpoint');
	my $return = {
		arrivals => get_checkpoint_arrivals(database, $checkpoint),
		details => get_checkpoint_details(database, $checkpoint),
	};
	return encode_json($return);
};

any ['get', 'post'] => '/checkpoint/:checkpoint' => sub{
	my $checkpoint = param('checkpoint');

	my $return = {
		arrivals => get_checkpoint_arrivals(database, $checkpoint),
		details => get_checkpoint_details(database, $checkpoint),
		page => vars->{page},
	};
	$return->{page}->{title} = 'Checkpoint '.param('checkpoint');
	$return->{page}->{enable_fancytable} = 0;
	$return->{page}->{table_sort_column} = 1;
	$return->{page}->{table_sort_order} = 'asc';

	return template 'checkpoint.tt', $return;
};

any ['get', 'post'] => '/api/arrivals/:checkpoint' => sub{
	return encode_json( get_checkpoint_arrivals(database, param('checkpoint')));
};

# # # # # ENTRANTS

any ['get', 'post'] => '/api/entrants' => sub {
	return encode_json(get_entrants(database));
};

any ['get', 'post'] => '/entrants' => sub {
	my $return = {
		page => vars->{page},
		entrants => get_entrants(database),
	};
	$return->{page}->{enable_fancytable} = 1;
	$return->{page}->{title} = 'entrants';
	return template 'entrants.tt', $return;
};

# # # # # TEAMS

any ['get'] => '/api/scratch-teams' => sub{
	return encode_json( get_scratch_teams(database) );
};

any ['post'] => '/api/scratch-teams' => sub{
	my $body = decode_json( request->body || '{}' );
	my $result = update_scratch_team(database,
		team_number => undef,
		team_name   => $body->{team_name} // '',
		entrants    => $body->{entrants} // '',
		add         => 1,
	);
	run_cronjobs(database, _sync_config());
	return encode_json($result);
};

any ['put'] => '/api/scratch-teams/:team_number' => sub{
	my $body = decode_json( request->body || '{}' );
	my $entrants = $body->{entrants} // '';
	my $result;
	if($entrants eq ''){
		# Matches the old form's behaviour: clearing every entrant out of a
		# scratch team is how you delete it, and (like the old page) that
		# path skips the felltrack re-sync below - there's nothing for it
		# to usefully recompute once the team's gone.
		$result = delete_scratch_team(database, param('team_number'));
	}else{
		$result = update_scratch_team(database,
			team_number => param('team_number'),
			team_name   => '',
			entrants    => $entrants,
			add         => 0,
		);
		run_cronjobs(database, _sync_config());
	}
	return encode_json($result);
};

any ['delete'] => '/api/scratch-teams/:team_number' => sub{
	my $result = delete_scratch_team(database, param('team_number'));
	return encode_json($result);
};

any ['get','post'] => '/scratch-teams' => sub {

	my %return;

	if(param('update') or param('add')){
		my $result;
		if(param('entrants') eq ''){
			$result = delete_scratch_team(database, param('team_number'));
		}else{
			$result = update_scratch_team(database,
				team_number => param('team_number'),
				team_name   => param('team_name'),
				entrants    => param('entrants'),
				add         => param('add'),
			);
			info("Triggering cron");
			run_cronjobs(database, _sync_config());
		}
		$return{$_} = $result->{$_} for keys %$result;
	}

	$return{teams} = get_scratch_teams(database);
	$return{page} = vars->{page},
	$return{page}->{title} = 'Scratch Teams';
	return template 'scratch-teams.tt', \%return;
};

any ['get', 'post'] => '/api/teams' => sub {
	return encode_json(get_teams(database));
};

any ['get', 'post'] => '/teams' => sub {
	my $return = {
		teams => get_teams(database),
		page => vars->{page},
	};
	$return->{page}->{enable_fancytable} = 1;
	$return->{page}->{title} = 'Teams';
	return template 'teams.tt', $return;
};

any ['get', 'post'] => '/team' => sub {
	my $team = param('team');
	if($team =~ m/^-?\d+$/){
		redirect "/team/$team";
	}else{
		redirect "/teams";
	}
};

any ['get', 'post'] => '/api/team/:team' => sub {
	return encode_json(get_team(database, param('team')));
};

any ['get', 'post'] => '/team/:team' => sub {
	my $return = {
		page => vars->{page},
		team => get_team(database, param('team') ),
	};
	$return->{page}->{title} = 'Team ' . $return->{team}->{team_name};
	return template 'team.tt', $return;
};

any ['get', 'post'] => '/api/problems' => sub{
	return encode_json( get_problems(database) );
};

any ['get', 'post'] => '/problems' => sub {
	my $return = {
		page => vars->{page},
		problems => get_problems(database),
	};
	$return->{page}->{title} = 'problems';
	return template 'problems.tt', $return;
};

# # # # # UTILITIES
any ['get','post'] => '/admin' => sub {
	my $sth = database->prepare("select name, value, notes from config");
	my %return;
	if(param('do') and param('do') eq 'crons'){
		my $output = run_cronjobs(database, _sync_config());
		$return{'done'} = 'Updated from felltrack: '.$output;
		$return{page}->{time_since_last_felltrack_update} = '0h0m';
		$return{page}->{seconds_since_last_felltrack_update} = '1';

	}
	if(param('do') and param('do') eq 'clear-database'){
		clear_cache(database);
		$return{'done'} = 'Cleared database tables';
	}
	if(param('update')){
		my $sth_update = database->prepare("update config set value = ? where name = ?");

		$sth->execute();
		while (my $row = $sth->fetchrow_hashref()){
			unless(param($row->{name}) eq $row->{value}){
				debug("Updating config setting $row->{name} to '".param($row->{name})."' from '$row->{value}'");
				push(@{$return{changes}}, "Updated $row->{name} to '".param($row->{name})."' from '$row->{value}'");
				$sth_update->execute( param($row->{name}), $row->{name} );
			}
		}
	}
	$sth->execute();
	$return{config} = $sth->fetchall_hashref('name');

	$sth = database->prepare("select name, message,
	                          date_format(time, \"%H:%i\") as time,
	                          date_format( timediff(now(), time ), \"%kh%im\") as time_since
				  from logs order by time desc");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		push(@{ $return{logs} }, $row);
	}

	$return{page} = vars->{page};
	$return{page}->{title} = 'Admin';
	return template 'admin.tt', \%return;
};

any ['get', 'post'] => '/admin/checkpoints' => sub {
	if(my $upload = request->upload('csv')){
		import_checkpoints_csv(database, $upload->tempname);
	}

	my $return;
	$return->{routes_cps} = get_routes_checkpoints(database);

	$return->{page}->{title} = 'Checkpoint Admin';
	return template 'admin_checkpoints.tt', $return;
};

any ['get', 'post'] => '/clear-cache' => sub {
	clear_cache(database);
	return "Cleanup done, you can now click 'back' to get back to where you were";
};

any ['get', 'post'] => '/cron' => sub {
	run_cronjobs(database, _sync_config());
	if(request_header('referer')){
		redirect request_header('referer');
	}
	return "Cronjobs done, you can now click 'back' to get back to where you were";
};

# Vue app shell - serves the SPA for '/' and any other non-API,
# non-still-server-rendered path, so client-side routing survives a hard
# refresh. Must stay last: every route above needs first-match priority.
any ['get'] => qr{^(?!/api/).*} => sub {
	send_file('index.html');
};

1;
