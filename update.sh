#! /bin/bash

export MYSQL_DATABASE=fellscout-dev
export MYSQL_HOST=127.0.0.1
export MYSQL_PORT=3306
export MYSQL_USERNAME=fellscout-dev
export MYSQL_PASSWORD=1Password

cd ./FellScout

./bin/progress-to-db
