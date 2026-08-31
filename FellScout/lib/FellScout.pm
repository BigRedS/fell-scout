package FellScout;

use Dancer2;
use Dancer2::Plugin::Database;
use POSIX qw(strftime);
use Text::CSV qw/csv/;
use Cwd;

use FellScout::Data qw(
	get_summary
	get_laterunners
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
any ['get', 'post'] => '/' => sub{
	my $return = {
		summary => get_summary(database),
		page => vars->{page},
	};
	$return->{page}->{title} = 'Event Summary';
	return template 'summary.tt', $return;
};

any ['get', 'post'] => '/api/summary' => sub{
	encode_json(get_summary(database));
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
	return encode_json({ laterunners => get_laterunners( database, param('threshold') ) })
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

any ['get', 'post'] => '/checkpoint' => sub {
	my $checkpoint = param('checkpoint');
	if($checkpoint =~ m/^\d+$/){
		redirect "/checkpoint/$checkpoint";
	}else{
		redirect "/checkpoints";
	}
	redirect "/checkpoint/$checkpoint";
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
	my $upload;
	if($upload = request->upload('csv')){
		# TODO: Think about where to put this file, when and how to delete it
		unlink('/tmp/checkpoints.csv');
		if($upload->link_to('/tmp/checkpoints.csv')){
			info("wrote /tmp/checkpoints.csv");
		}else{
			info("Failed to write /tmp/checkpoints.csv: $!");
		}
		my $checkpoints = csv( in => '/tmp/checkpoints.csv', encoding => 'UTF-8', detect_bom => 1);
		my $query = "replace into checkpoints (checkpoint_number, description, manager, mobile, type, os_grid, latitude, longitude, what3words)";

		$query.=" values (?, ?, ?, ?, ?, ?, ?, ?, ?)";
		my $sth = database->prepare($query);

		my %routes;
		foreach my $row (@{$checkpoints}){
			my $cp = $row->{'cp'};
			next unless $cp and $cp =~ m/\w+/;
			$cp =~ s/CP//;
			$cp =~ s/^0//;
			$cp = 0 if $cp =~ m/Start/i;
			$cp = 99 if $cp =~ m/Finish/i;
			$sth->execute($cp, $row->{description}, $row->{'checkpoint manager'}, $row->{mobile}, $row->{'type of checkpoint'}, $row->{'grid reference'}, $row->{'latitude'}, $row->{longitude}, $row->{what3words});

			foreach my $field (sort(keys(%{$row}))){
				if ($field =~ /^(\S+) leg distance/){
					my $route_name = lc($1);
					if($row->{$field} =~ m/\d+/){
						push(@{$routes{$route_name}}, $cp);
					}
				}
			}
		}
		my $del_sth = database->prepare('delete from routes');
		$del_sth->execute();
		my $routes_query = 'insert into routes(`route_name`, `leg_name`, `leg_from`, `leg_to`, `index`) values (?, ?, ?, ?, ?)';
		my $routes_sth = database->prepare($routes_query);
		foreach my $route (keys(%routes)){
			my @cps = @{$routes{$route}};

			for my $idx (0 .. $#cps){
				my $leg_to;
				if($cps[$idx + 1]){
					$leg_to = $cps[$idx + 1];
				}else{
					$leg_to = '99';
				}
				my $leg_name = $cps[$idx] . '-' . $leg_to;
				next if $leg_name eq '99-99';
				info("$route $leg_name $idx");
				$routes_sth->execute($route, $leg_name, $cps[$idx], $leg_to, $idx);
			}
		}

	}

	my $routes_sth = database->prepare('select distinct route_name from routes');
	$routes_sth->execute();

	my $cps_sth = database->prepare('select leg_name from routes where route_name = ? order by `index` asc');

	my %routes_cps;
	while( my $row =  $routes_sth->fetchrow_arrayref() ){
		my $route = $row->[0];
		$cps_sth->execute($route);
		while( my $r = $cps_sth->fetchrow_arrayref() ){
			my $cp = $r->[0];
			$cp =~ s/^\d+-//;
			push(@{$routes_cps{$route}}, $cp);
		}
	}

	my $return;
	$return->{routes_cps} = \%routes_cps;

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

1;
