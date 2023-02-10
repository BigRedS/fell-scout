FROM debian:bullseye-slim
RUN apt-get update && \
    apt-get -y install \
      libdancer2-perl \
      libtext-csv-perl

WORKDIR /app
COPY FellScout /app
EXPOSE 5000/tcp

ENTRYPOINT ["/usr/bin/plackup", "bin/app.psgi"]
