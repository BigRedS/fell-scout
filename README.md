# FellScout

This is a continuation of the 'felltrack scripts'; some tools that we use at the Chiltern 20 and Southern 50
events around the FellTrack system:

https://github.com/BigRedS/felltrack

https://felltrack.com

It's called 'FellScout' because we're Scouts and that sounded less creepy than ScoutTrack.

# What is it?

Fell Track is a great system for running the event and tracking hundreds of entrants and various supporting functions.

What it's not so great at is displaying information for people other than those strictly running the event. Fell Scout aims to provide some better views of this information

# Running

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

You need to set a few fields for Fell Scout to work. 

First, the routes; each is defined with a simple space-separated (ordered) list of those checkpoints that make up the route.

For the Fell Track sync to work, you need to set the `felltrack_owner`, `felltrack_password` and `felltrack_username`. They, 
(or Central Control) will have given you the username and password.

The owner can be found by poking about in the source of https://felltrack.com. Alternatively, visit https://felltrack.com and
run the `felltrack.sh` script with the text from the button for your event as its arguments.

Also, while here, set `skip_fetch_from_felltrack` to `off` to enable the fetching from felltrack.

Now click the `Trigger a (manual) update from Felltrack` link at the bottom of the page, and have a look at the app logs to see how it went








Ideally, in the root of the repo

```
./run.sh
```

Which will set the right env vars. More-directly:

```
cd FellScout
plackup bin/app.psgi
```
