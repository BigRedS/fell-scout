#! /bin/bash

string="$@";
curl https://felltrack.com/ -s -o- | grep -i -B1 -- "$string" | head -n1 | awk -F'value=' '{print $2}' | awk -F'"' '{print $2}'

