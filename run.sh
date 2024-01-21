#! /bin/bash

export MYSQL_USERNAME=fellscout-dev
export MYSQL_PASSWORD=1Password
export MYSQL_HOST=localhost
export MYSQL_PORT=3006
export MYSQL_DATABASE_NAME=fellscout-dev

export SKIP_FETCH_FROM_FELLTRACK=1

cd FellScout
plackup ./bin/app.psgi
