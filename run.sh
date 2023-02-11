#! /bin/bash

export ROUTE_50mile="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19"
export ROUTE_50km="3 4 5 6 7 8 12 13 14 15 16 17 18 19"
export ROUTE_30km="3 4 5 14 15 16 17 18 19"

#export IGNORE_122="on bus but not retired"

cd FellScout

plackup ./bin/app.psgi
