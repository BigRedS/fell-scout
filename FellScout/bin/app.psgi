#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";

use FellScout;
use Plack::Builder;

# Static assets (public/) are served by Dancer2's own Plack::App::File
# handler, which runs before any of FellScout's hooks - so this can't be
# done as a Dancer2 `hook 'after'`. Devices running this app get one
# reliable connection (at the start/finish) and then poor-to-none at
# checkpoints for the rest of the event; without an explicit Cache-Control,
# browsers fall back to a heuristic (and often short) freshness guess. A
# week comfortably covers a single event without meaningful staleness risk,
# since the Docker image is rebuilt fresh before each one anyway.
builder {
	enable sub {
		my $app = shift;
		sub {
			my $env = shift;
			my $res = $app->($env);
			if ($env->{PATH_INFO} =~ m{\.(?:css|js|jpe?g|png|gif|svg|ico|woff2?)$}) {
				push @{ $res->[1] }, 'Cache-Control', 'public, max-age=604800';
			}
			return $res;
		};
	};
	FellScout->to_app;
};
