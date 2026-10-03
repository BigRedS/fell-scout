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

`k8s/` is a kustomize base for the same stack, using the image GitHub Actions pushes to ghcr.
Currently, this is Traefik-specific. It's meant to be pulled in by the repo that deploys it; see
[farfaraway's `fellscout/`](https://github.com/BigRedS/farfaraway/tree/main/fellscout) for a
real one:

```
resources:
  - _namespace.yaml
  - github.com/BigRedS/fell-scout//deploy/k8s?ref=master
  - ingress.yaml
```

The base brings up:

* `db`, a single-replica MariaDB StatefulSet, initialised from `k8s/all.sql` via a ConfigMap.
  That's a copy of `build/sql/all.sql`, because kustomize won't read outside `k8s/`; copy it
  over after changing the schema (a test fails until you do).
* `web`, a Deployment.
* `cron`, a CronJob that hits `/cron` once a minute.
* `auth`, a Traefik basicAuth Middleware with `headerField: X-Remote-User`, which overwrites any
  value the client sent.

The deploying repo has to provide:

* the `fellscout` namespace. The Ingress annotation below includes the namespace name, so
  use a different one only if you change that too.
* an Ingress pointing at the `web` Service, port 5000, with
  `traefik.ingress.kubernetes.io/router.middlewares: fellscout-auth@kubernetescrd`. Without
  that annotation there are no logins and nobody gets any role.
* a `fellscout-db` Secret with a `password` key. MariaDB only reads it when it first
  initialises its volume, so changing it later won't change the database's password.
* a `fellscout-htpasswd` Secret with a `users` key holding htpasswd lines:

  ```
  htpasswd -c users <user1>
  htpasswd users <user2>
  ```

* an image tag: pin `ghcr.io/bigreds/fell-scout` to a `sha-<short>` tag rather than `latest`.

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

