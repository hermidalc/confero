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

my $cmd = shift @ARGV;
pod2usage(
    -verbose => 0,
    -message => 'No command',
) unless defined $cmd;
pod2usage(
    -verbose => 0,
) if $cmd =~ /-h|--help/i;
pod2usage(
    -verbose => 0,
    -message => "Invalid command '$cmd'",
) unless Confero::Cmd->can($cmd);
Confero::Cmd->$cmd();
exit;

__END__

=head1 NAME

cfo_run_cmd.pl - Confero Command Runner

=head1 SYNOPSIS

 cfo_run_cmd.pl [command] [options]

 Commands:
     process_data_file                  Check and process a data file (e.g. contrast data set, gene set list)
     process_submit_data_file           Check, process and submit a data file (e.g. contrast data set, gene set list)
     create_rnk_deg_lists               Create ranked or DEG lists from a contrast dataset or contrast file or one in Confero DB
     analyze_data                       Analyze data for gene set enrichment using Confero DB, MSigDB, GeneSigDB, etc. gene set collections
     extract_gsea_leading_edge_matrix   Extract GSEA leading edge matrix from a GSEA result
     extract_gsea_results_matrix        Extract GSEA results data matrix from one or more GSEA results
     extract_ora_results_matrix         Extract ORA results data matrix from one or more ORA results
     extract_gene_set_matrix            Extract gene set matrix from specific gene sets or one or more gene set databases
     extract_gene_set_overlap_matrix    Extract gene set overlap matrix from a gene set matrix or GSEA leading edge matrix
     extract_contrast_data_subset       Extract a subset of contrasts from an contrast dataset file or one in Confero DB
 
 Options:
     --help                             Print usage message and exit
 
 Run cfo_run_cmd.pl [command] --help for command options

=cut
