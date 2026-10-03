use strict;
use warnings;

# deploy/k8s/all.sql has to be a copy of build/sql/all.sql (kustomize can't
# read outside deploy/k8s - see the comment in its kustomization.yaml), so
# make a schema change that's only made in one of them fail loudly.

use Test::More tests => 1;
use FindBin;

my $repo = "$FindBin::Bin/../..";

sub slurp {
	my $path = shift;
	open(my $fh, '<', $path) or die "Can't read $path: $!";
	local $/;
	return <$fh>;
}

ok(slurp("$repo/build/sql/all.sql") eq slurp("$repo/deploy/k8s/all.sql"),
	'deploy/k8s/all.sql matches build/sql/all.sql - copy it over after changing the schema');
