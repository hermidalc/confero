#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use sigtrap qw(handler sig_handler normal-signals error-signals ALRM);
use Confero::Cmd;
use Getopt::Long qw(:config auto_help auto_version pass_through);
use Pod::Usage qw(pod2usage);

sub sig_handler {
    die "\n\nConfero $0 command exited gracefully [", scalar localtime, "]\n\n";
}

our $VERSION = '0.1';

Confero::Cmd->process_data_file();
exit;

__END__

=head1 NAME

cfo_process_data_file.pl - Confero Data File Processor

=head1 SYNOPSIS

 cfo_process_data_file.pl [options]

 Options:
   --data-file          Path to input data file (required)
   --data-type          Data file type, currently one of 'IdMAPS', 'IdList', 'RankedList' (required)
   --id-type            Data file ID type, e.g. HG-U133_Plus_2, GeneSymbol, MOE430_2 (only required if not in data file header)
   --report-file        Output report file path (required)
   --output-file        Output processed data file path
   --debug-file         Debug object dump file path
   --help               Print usage message and exit

=cut
