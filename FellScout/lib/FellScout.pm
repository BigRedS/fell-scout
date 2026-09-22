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

	# Every config row is exposed as a Dancer var - _sync_config() and
	# /api/status both read specific ones back out by name.
	my $sth = database->prepare("select name, value from config");
	$sth->execute();
	while(my $row = $sth->fetchrow_hashref()){
		var $row->{name} => $row->{value};
	}
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

# # # # # laterunners

any ['get', 'post'] => '/api/laterunners/' => sub {
	return encode_json({
		laterunners => get_laterunners( database, param('threshold') ),
		%{ get_lateness_thresholds(database) },
	});
};

# # # # # LEGS + CHECKPOINTS

any ['get', 'post'] => '/api/legs' => sub{
	return encode_json( get_legs(database) );
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

any ['get', 'post'] => '/api/checkpoint/:checkpoint' => sub{
	my $checkpoint = param('checkpoint');
	my $return = {
		arrivals => get_checkpoint_arrivals(database, $checkpoint),
		details => get_checkpoint_details(database, $checkpoint),
	};
	return encode_json($return);
};

any ['get', 'post'] => '/api/arrivals/:checkpoint' => sub{
	return encode_json( get_checkpoint_arrivals(database, param('checkpoint')));
};

# # # # # ENTRANTS

any ['get', 'post'] => '/api/entrants' => sub {
	return encode_json(get_entrants(database));
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

any ['get', 'post'] => '/api/teams' => sub {
	return encode_json(get_teams(database));
};

any ['get', 'post'] => '/api/team/:team' => sub {
	return encode_json(get_team(database, param('team')));
};

any ['get', 'post'] => '/api/problems' => sub{
	return encode_json( get_problems(database) );
};

# # # # # UTILITIES

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

# Vue app shell - serves the SPA for every page (client-side routing then
# takes over), so a hard refresh on any path still works. Must stay last:
# every /api/* route above needs first-match priority over this.
any ['get'] => qr{^(?!/api/).*} => sub {
	send_file('index.html');
};

1;
