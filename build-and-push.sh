#! /bin/bash

aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws/c1i0s5p6

docker build -t fellscout .

docker tag fellscout:latest public.ecr.aws/c1i0s5p6/fellscout:latest

docker push public.ecr.aws/c1i0s5p6/fellscout:latest
