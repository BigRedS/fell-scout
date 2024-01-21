FROM debian:bullseye-slim
RUN apt-get update && \
    apt-get -y install vim \
      libdancer2-perl \
      libtext-csv-perl \
      libjson-perl \
      cron

WORKDIR /app
COPY FellScout /app
EXPOSE 5000/tcp

ENTRYPOINT ["/usr/bin/plackup", "bin/app.psgi"]
