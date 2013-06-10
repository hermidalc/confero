#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use sigtrap qw(handler sig_handler normal-signals error-signals ALRM);
use Confero::Config qw(:gsea);
use Getopt::Long qw(:config auto_help auto_version);
use Pod::Usage qw(pod2usage);
use Sort::Key::Natural qw(natsort);

sub sig_handler {
    die "\n\n$0 program exited gracefully [", scalar localtime, "]\n\n";
}

our $VERSION = '0.1';

# Unbuffer error and output streams (make sure STDOUT is last so that it remains the default filehandle)
select(STDERR); $| = 1;
select(STDOUT); $| = 1;

my $man = 0;
GetOptions(
    'man' => \$man,
) || pod2usage(-verbose => 0);
pod2usage(-exitstatus => 0, -verbose => 2) if $man;
print "#", '-' x 120, "#\n",
      "# Confero Gene Set DB Galaxy Options Creator/Updater [" . scalar localtime() . "]\n\n";
my %gene_set_names;
my $num_total_gene_sets_parsed = 0;
for my $gsdb_file_name (natsort values %CTK_GSEA_GSDBS) {
    # skip the msigdb all gmt
    next unless $gsdb_file_name =~ /^(c|g)/;
    my $gsdb_file_path = "$CTK_GSEA_GENE_SET_DB_DIR/$gsdb_file_name";
    my $num_gene_sets_parsed = 0;
    print "Parsing $gsdb_file_name: ";
    open(my $gsdb_fh, '<', $gsdb_file_path) or die "Could not open $gsdb_file_path: $!\n";
    while (<$gsdb_fh>) {
        m/^\s*$/ && next;
        my ($gene_set_name) = split /\t+/;
        $gene_set_names{$gene_set_name}++;
        $num_gene_sets_parsed++;
    }
    close($gsdb_fh);
    print "$num_gene_sets_parsed gene sets\n";
    $num_total_gene_sets_parsed += $num_gene_sets_parsed;
}
print "--> $num_total_gene_sets_parsed <-- total gene sets parsed\nWriting Galaxy options file id_options_gsdb_gene_sets.txt\n";
if (!-e "$FindBin::Bin/../galaxy/data") {
    mkdir "$FindBin::Bin/../galaxy/data" or die "ERROR: Could not create directory $FindBin::Bin/../galaxy/data: $!\n";
}
open(my $opts_fh, '>', "$FindBin::Bin/../galaxy/data/id_options_gsdb_gene_sets.txt") 
    or die "ERROR: Could not create $FindBin::Bin/../galaxy/data/id_options_gsdb_gene_sets.txt: $!\n";
print $opts_fh "# Confero Galaxy Drop-down Menu Options\n",
               "# IMPORTANT: this file is generated automatically do not alter manually\n",
               "-\tSelect from list...\n";
print $opts_fh "$_\t$_\n" for natsort keys %gene_set_names;
close($opts_fh);
print "\nConfero Gene Set DB Galaxy Options Creator/Updater complete [", scalar localtime, "]\n\n";
exit;

__END__

=head1 NAME 

cfo_create_gsdb_gene_set_galaxy_opts.pl - Confero Gene Set DB Galaxy Options Creator/Updater

=head1 SYNOPSIS

 cfo_create_gsdb_gene_set_galaxy_opts.pl [options]

 Options:
     --help        Display usage and exit
     --man         Display full program documentation
     --version     Display program version and exit

=cut
