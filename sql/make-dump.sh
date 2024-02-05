#!/bin/bash

echo "create database if not exists fellscout;"

echo "use fellscout;";

sudo mysqldump --no-data fellscout-dev | perl -p -e 's/AUTO_INCREMENT=\d+/AUTO_INCREMENT=0/';

sudo mysqldump fellscout-dev config

