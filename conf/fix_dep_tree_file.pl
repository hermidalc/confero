#!/usr/bin/env perl

use strict;
use warnings;

while (<>) {
    next if m/^\s*$/;
    s/^\s+//;
    my (undef, undef, $module_str) = split ' ';
    my @module_parts = split /-/, $module_str;
    print join('::', @module_parts[0 .. $#module_parts - 1]), '@', $module_parts[$#module_parts], "\n";
}
