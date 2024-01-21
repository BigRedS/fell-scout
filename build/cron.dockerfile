FROM alpine:latest
RUN apk add bash curl
COPY cron.sh /
ENTRYPOINT /cron.sh
