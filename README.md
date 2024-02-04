# FellScout

This is a continuation of the '[felltrack script](https://github.com/BigRedS/felltrack)'; some tools that we use at the Chiltern 20 and Southern 50
events around the FellTrack system: https://felltrack.com

It's called 'FellScout' because we're Scouts and that sounded less creepy than ScoutTrack.

# What is it?

Fell Track is a great system for running the event and tracking hundreds of entrants and various supporting functions.

What it's not so great at is displaying information for people other than those strictly running the event. 

Fell Scout aims to provide some better views of this information.

Central Control get a 'late running teams' display, using data from earlier teams to estimate how long it should take to get to a given checkpoint:

<img width="480" alt="image" src="https://github.com/BigRedS/fell-scout/assets/128592/25569742-553f-4c02-bbc2-8096553363ec">

Each checkpoint gets an 'arrivals board' showing every team that hasn't got to that checkpoint yet, and when they're expected (not enough teams have finished yet for there to be finish estimates here):

<img width="480" alt="image" src="https://github.com/BigRedS/fell-scout/assets/128592/20e3a06f-30ec-4e63-a016-c519d09fa7f7">

For general queries, there is a filterable 'teams' table rather than FellTrack's all-entrants one:

<img width="480" alt="image" src="https://github.com/BigRedS/fell-scout/assets/128592/3cc6e72c-c175-47b5-9f0a-ebc065651a6e">

With a team details page:

<img width="480" alt="image" src="https://github.com/BigRedS/fell-scout/assets/128592/84abcbc8-cfad-4834-961c-d1d3b03b82bd">

And, answering the greatest number of individual requests, an event-overview page:

<img width="480" alt="image" src="https://github.com/BigRedS/fell-scout/assets/128592/5b45b785-62c8-445a-a0ff-6ed1b27a4cae">

## Scratch Teams

The one feature that FellScout 'adds' is the notion of a Scratch Team. This is a team made up of two or more entrants, who have left their team(s) and created a new one; most-often it happens when two in a team of four are faster than other two, or when the slowest member of each of two teams leave their teams to join a new one.

In FellScout, the Scratch Teams page allows for the creation of these. Teams have a name, and are defined with a space-separated list of entrants:

<img width="480" alt="image" src="https://github.com/BigRedS/fell-scout/assets/128592/0e23f988-4a89-4249-a29a-30bb5d2987a3">

Scratch teams can be identified by their ID being negative:

<img width="480" alt="image" src="https://github.com/BigRedS/fell-scout/assets/128592/5fa85988-1c2d-4db8-a533-c888e4c191e9">

And then they behave like a normal team; viewable in the /teams page, listed in the checkpoints arrivals board, and with their own team info page:

<img width="480" alt="image" src="https://github.com/BigRedS/fell-scout/assets/128592/128f8a74-f2c4-434a-87ac-8005b3ac5ccb">

# How does it work?

FellTrack provides an 'Entrants Progress' CSV export, which contains every entrant and their progress. 

FellScout periodically downloads this CSV file, processes it and writes all the data to a local database. Outside of Scratch Teams, all it does is cache and display data that is in FellTrack.

That update is run automatically by the `cron` container in the docker-compose setup, by requesting `/cron` from the webapp. It can be run manually from /admin, too, if need be.

Sometimes. a change on FellTrack itself may cause some confusion; nothing is ever _removed_ from FellScout by the update process, so a team or entrant being renamed will lead to duplicates, for example. In these instances the normal approach is to clear the database; aside from Scratch Teams, everything will be reinstated on the next update from FellTrack.

During this update, the CSV file is processed and every entrant is read from it. They are sorted into 'teams' based on their entrant code, and the details of the entrant with the most-recent and furthest-forward check in is used as the details of the team. Each entrant's times at each checkpoint is examined, and these records are used to calculate an average time to go between checkpoints, which is how all the predictions are calculated. The CSV file only give the hour and minute of any event, so midnight is detected by the point during an entrant's event where the time goes backwards. Currently events with two midnights in are not supported.

# Configuration Options

Most of the configuration is done on the page at /admin, these are all simply the `config` mysql table. Some of those options explained:

None of these have a default in the sense that some other value is used when they are unset; `default` here refers to the number they are set to on initial setup.

## `felltrack_username`, `felltrack_password`, `felltrack_owner`

No default.

The credentials for logging in to FellTrack. For the owner, you can view the source of the https://felltrack.com.

## `ignore_future_events`

Defaults to `off`

On update from FellTrack, every record in the progress.csv file is processed and put into the database if this is set to 'off', when set to 'on' it will stop if it meets a checkin that has a time in the future.
This _should_ only be of use when testing with the test progress.csv file, but could conceivably be useful if something goes odd in Felltrack.

## `ignore_teams`

No default.

Sometimes a manual update to a team ends up with some strange data in the CSV file, especially where they have improperly retired. These teams can be listed here (a space-separated list of the team numbers) which causes their rows to be skipped in the processing of the CSV; it is as if the team doesn't exist.

## `lateness_percent_amber` and `lateness_percent_red`

Defaults to `30` and `80` respectively

On the /laterunners page, teams that are later than lateness_percent_red percent are highlighted in red. Those that are not that late, but later than lateness_percent_amber are highlighted in amber.

## `percentile`

Defaults to `90`

We calculate the expected time for teams to traverse legs by taking an average of the times entrants have already taken; the average we take is the fastest nth percentile, and this is where we set the n. 

## `percentile_min_sample`

Defaults to `10`

If the number of entrants who have already traversed a leg is too low, we can't calculate a meaningful percentile. If there are fewer than this, we just take a normal mean.

## `percentile_sample_size`

Defaults to `60`

In general, the further into the event we are, the slower the remaining teams are. When calculating the averages, then, we should favour the more-recent teams. Before taking the fastest mth percentile of the set of all entrants on a leg, we take the most-recent nth percentile, and this is where we set that n.

This only applies if the sample after taking the most-recent mth percentile would still be bigger than `percentile_min_sample`.

## `route_30km` `route_50km` `route_50mile`

Defines the routes of the event. The logic in the app is that any config named `route_*` defines a route, named for whatever's after that first underscore; you can add more routes by manually inserting that into the db.

Each route is defined as a space-separated ordered list of checkpoint numbers. 

## `skip_fetch_from_felltrack`

Default: `on`

This controls whether any requests are actually sent to felltrack. It is set to `on` by default to prevent hammering FellTrack before the event is ready and configured.

Set to `off` once you've got the username, password and owner set properly.

# Installing/Running


## Docker Compose

cd into the repo, then do:

    docker-compose build
    docker-compose up

And it will be up, listening on port 5001. It will listen on the address 127.0.0.1, though,
so is only accessible from the localhost. Edit `compose.yaml` if you want to change this.

There is a /admin page that is linked-to from the webUI, and also a /clear-cache that isn't,
so you may wish to restrict access to these. I use this in Apache:

    <Virtualhost *:80>
            ServerName fellscout.avi.st
    
            Proxypass / http://localhost:5001/
            proxypassreverse / http://localhost:5001/
    
            <location />
                    authtype basic
                    authname Fell Scout
                    authuserfile /etc/apache2/fellscout-htpasswd
                    require valid-user
            </location>
            <location /admin>
                    authtype basic
                    authname Fell Scout Admin
                    authuserfile /etc/apache2/fellscout-htpasswd
                    require user admin
            </location>
    </Virtualhost>

You can then visit http://<your felltrack URL>/admin where you'll see this form:

<img width="480" alt="image" src="https://github.com/BigRedS/fell-scout/assets/128592/4feb6dbd-fd08-4f92-803a-5aa86e0690fd">

You need to set a few fields for Fell Scout to work. 

First, the routes; each is defined with a simple space-separated (ordered) list of those checkpoints that make up the route:

<img width="480" alt="image" src="https://github.com/BigRedS/fell-scout/assets/128592/82faae07-a1e4-4650-bedf-bf3b77e96e26">

For the Fell Track sync to work, you need to set the `felltrack_owner`, `felltrack_password` and `felltrack_username`. They 
(or Central Control) will have given you the username and password.

The owner can be found by poking about in the source of https://felltrack.com. Alternatively, visit https://felltrack.com and
run the `felltrack.sh` script with the text from the button for your event as its arguments.

Also, while here, set `skip_fetch_from_felltrack` to `off` to enable the fetching from felltrack.

Now click the `Update from Felltrack` link at the bottom of the page, and have a look at the app logs to see how it went.

## Dev tips

### Running without Docker Compose
* Create a database to suit the details in the top of `run.sh` and `build.sh`
* Put a `progress.csv` downloaded from FellTrack in the root of the repo. Link to `example-progress.csv` to use an anoymised one from 2023.
* From the root of the repo run `./un.sh` to bring up the webapp on port `5001`.  
* Run (or cron) `./update.sh` to run the process to update from the CSV file to the DB.

Use the `./FellScout/bin/get-data` scipt to actually download from FellTrack; see the script for required env vars.

### Docker Compose Tips

To feed an example CSV to it, do: `docker cp example-progress.csv fell-scout_web_1:/progress.csv`
