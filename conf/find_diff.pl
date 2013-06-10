#!/usr/bin/env perl

use strict;
use warnings;

my %modules1;
open(my $fh1, '<', $ARGV[0]);
while (<$fh1>) {
    s/\s+//g;
    $modules1{$_} = $.;
}
close($fh1);
my %modules2;
open(my $fh2, '<', $ARGV[1]);
while (<$fh2>) {
    s/\s+//g;
    $modules2{$_} = $.;
}
close($fh2);
print "Modules1 unique:\n";
for my $module (sort keys %modules1) {
    print "$module\n" unless $modules2{$module};
}
print "\nModules2 unique:\n";
for my $module (sort keys %modules2) {
    print "$module\n" unless $modules1{$module};
}
