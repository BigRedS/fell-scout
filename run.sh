#! /bin/bash

export MYSQL_USERNAME=fellscout-dev
export MYSQL_PASSWORD=1Password
# If this is set to 'localhost', progress-to-db fails, since you may not
# set a port when host is 'localhost'
export MYSQL_HOST=127.0.0.1
export MYSQL_PORT=3306
export MYSQL_DATABASE=fellscout-dev

export SKIP_FETCH_FROM_FELLTRACK=1

cd FellScout
plackup ./bin/app.psgi
