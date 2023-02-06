FROM debian:bullseye-slim
RUN apt-get update && \
    apt-get -y install cpanminus vim build-essential libdancer2-perl libtext-csv-perl
#RUN cpanm --notest -L /usr/local/lib/site_perl Dancer2 && \
#    cpanm --notest -L /usr/local/lib/site_perl Text::CSV ;

WORKDIR /app
COPY FellScout /app
EXPOSE 5000/tcp

ENTRYPOINT ["/usr/bin/plackup", "bin/app.psgi"]
