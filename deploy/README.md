# Deployment
This directory has some of the different ideas I've had in the past on how to deploy this.

Any production deployment requires a proxy that can do HTTP Auth, since that is where the users come
from (Fell Scout doesn't do users, it just reads them from the proxy). See below for proxying options.

Fellscout itself is three components:

* `web` runs the perl backend and Vue frontend
* `cron` routinely fetches new data from FellTrack
* `db` is the mariadb database behind it

## docker-compose
`compose.yaml` is a docker-compose file to bring up the required stack. Copy `.env.example` to `.env`
and edit it to set a mysql password.

Then bring it up:

```
docker compose -f deploy/compose.yaml up -d --build
```

and then point your proxy at http://localhost:5001/

Users are configured in your proxy, see below.

## Kubernetes

`k8s/` is a kustomization for the same stack, using the image GitHub Actions pushes to ghcr. Currently, this is Traefik-specific.

Two secrets are required, as is a namespace:

```
kubectl create namespace fellscout
```

First, generate a mysql db password with something like

```
kubectl -n fellscout create secret generic fellscout-db --from-literal=password="$(openssl rand -base64 24)"
```

And then use `htpasswd` to create an htpasswd file and create a secret from that:

```
htpasswd -c users <user1>
htpasswd users <user2>
[...]
kubectl -n fellscout create secret generic fellscout-htpasswd --from-file=users
```

Set the hostname and image tag in `k8s/kustomization.yaml`, then apply it:

```
kubectl kustomize --load-restrictor LoadRestrictionsNone deploy/k8s | kubectl apply -f -
```

You can't just `kubectl apply -k` because that won't let us read `build/sql/all.sql`, which we need
to initialise the db.


Add users or change passwords by updating that users file and recreating the secret from it:

```
kubectl -n fellscout create secret generic fellscout-htpasswd --from-file=users --dry-run=client -o yaml | kubectl apply -f -
```

This brings up four components (the three bits of FellScout plus a Traefik Middleware):

* `db` is a single-replica MariaDB StatefulSet, initialised from
  `build/sql/all.sql` via a ConfigMap.
* `web` is a Deployment.
* `cron` is a CronJob that hits `/cron` once a minute.
* Traefik does the logins: a basicAuth Middleware with `headerField: X-Remote-User`, which overwrites any value the client sent.

# Proxying
FellScout doesn't manage logins, it depends on an HTTP proxy in front of it that will:

- authenticate users;
- send the username to FellScout in an `X-Remote-User` header, overwriting any value the client sent
  (otherwise anyone can impersonate anyone else)

Some configs for doing this are

## Apache

Use the config in `./apache.conf`. Enable the required Apache modules:

```
a2enmod proxy proxy_http headers auth_basic authn_file
```

and then create users:

```
htpasswd -c /etc/apache2/fellscout-htpasswd <username>
```

remember to not use the `-c` when a user already exists!

