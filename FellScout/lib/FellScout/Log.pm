package FellScout::Log;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(info error debug);

# Small standalone stand-ins for the Dancer2 logging keywords that
# FellScout::Data and FellScout::Sync used to get from Dancer.
sub info  { warn "INFO: $_[0]\n" }
sub error { warn "ERROR: $_[0]\n" }
sub debug { return unless $ENV{DEBUG}; warn "DEBUG: $_[0]\n" }

1;
