#! /bin/bash

export ROUTE_50mile="1 2 3 4 5 6 8 9 10 11 12 13 14 15 16 17"
export ROUTE_50km="1 2 3 4 5 6 8 9 14 15 16 17"
export ROUTE_30km="1 2 3 4 5 6 7 17"

cd FellScout

plackup ./bin/app.psgi
