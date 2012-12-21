#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use sigtrap qw(handler sig_handler normal-signals error-signals ALRM);
use Confero::Config qw(:gsea);
use File::Basename qw(basename);
use Sort::Key::Natural qw(natsort);
use File::Glob qw(:globally :nocase);
use Getopt::Long qw(:config auto_help auto_version);
use Pod::Usage qw(pod2usage);

our $VERSION = '0.0.1';

sub sig_handler {
    die "\n\n$0 program exited gracefully [", scalar localtime, "]\n\n";
}

# Unbuffer error and output streams (make sure STDOUT is last so that it remains the default filehandle)
select(STDERR); $| = 1;
select(STDOUT); $| = 1;
my $man = 0;
GetOptions(
    'man' => \$man,
) || pod2usage(-verbose => 0);
pod2usage(-exitstatus => 0, -verbose => 2) if $man;
print "#", '-' x 100, "#\n",
      "# Confero MSigDB C2 AR (all regulated) GMT Database Builder/Updater [" . scalar localtime() . "]\n\n";
my @c2_file_paths = grep { m/c2\.(all|cgp)\.v.+?\.gmt/i } <$CTK_GSEA_GENE_SET_DB_DIR/c2.*.gmt>;
for my $c2_file_path (@c2_file_paths) {
    print "Parsing $c2_file_path:\n";
    my ($gsdb_file_name_beginning, $gsdb_file_name_ending) = basename($c2_file_path) =~ /^(.+?)\.(v\d+\.\d+\..+?)$/i;
    my (%gene_sets, $num_gene_sets_parsed);
    open(GSDBFILE, '<', $c2_file_path) or die "Could not open $c2_file_path: $!\n";
    while (<GSDBFILE>) {
        m/^\s*$/ && next;
        my ($gene_set_name, $gene_set_url, @gene_ids) = split /\t+/;
        if (my ($gene_set_base_name) = $gene_set_name =~ /^(.+?)_(?:UP|DN)$/i) {
            for (@gene_ids) {
                s/\s+//g;
                # common typo in MSigDB files
                s/\/+$//;
                s/\/\/\// \/\/\/ /g;
            }
            push @{$gene_sets{$gene_set_base_name}}, @gene_ids;
        }
        $num_gene_sets_parsed++;
    }
    close(GSDBFILE);
    my $num_ar_gene_sets = 0;
    open(OUTFILE, '>', "$CTK_GSEA_GENE_SET_DB_DIR/$gsdb_file_name_beginning.ar.$gsdb_file_name_ending") 
        or die "Could not create $CTK_GSEA_GENE_SET_DB_DIR/$gsdb_file_name_beginning.ar.$gsdb_file_name_ending: $!\n";
    for my $gene_set_base_name (natsort keys %gene_sets) {
        my %unique_gene_ids = map { $_ => 1 } @{$gene_sets{$gene_set_base_name}};
        print OUTFILE "${gene_set_base_name}_AR\tNA\t", join("\t", natsort keys %unique_gene_ids), "\n";
        $num_ar_gene_sets++;
    }
    close(OUTFILE);
    print "$num_gene_sets_parsed gene sets parsed, $num_ar_gene_sets written\n";
}
print "\nConfero MSigDB C2 AR (all regulated) GMT Database Builder/Updater complete [", scalar localtime, "]\n\n";
exit;

__END__

=head1 NAME 

cfo_build_msigdb_c2_ar_gmt.pl - Confero MSigDB C2 AR (all regulated) GMT Database Builder/Updater

=head1 SYNOPSIS

 cfo_build_msigdb_c2_ar_gmt.pl [options]

 Options:
     --help        Display usage and exit
     --man         Display full program documentation
     --version     Display program version and exit

=cut
