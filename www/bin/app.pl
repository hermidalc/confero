#!/usr/bin/env perl

use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use Dancer;
use Confero::Web;

our $VERSION = '0.0.1';

dance;
