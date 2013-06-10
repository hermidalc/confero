#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use sigtrap qw(handler sig_handler normal-signals error-signals ALRM);
use Confero::Config qw(:gsea);
use Confero::LocalConfig qw(:general);
use Const::Fast;
use File::Basename qw(basename);
use File::Copy qw(move);
use File::Fetch;
use Getopt::Long qw(:config auto_help auto_version);

sub sig_handler {
    die "\n\n$0 program exited gracefully [", scalar localtime, "]\n\n";
}

our $VERSION = '0.1';

# Unbuffer error and output streams (make sure STDOUT is last so that it remains the default filehandle)
select(STDERR); $| = 1;
select(STDOUT); $| = 1;

const my $PUBMED_BASEURL => 'http://www.pubmed.org/';

print "#", '-' x 120, "#\n",
      "# Confero GeneSigDB GMT Downloader/Processor [" . scalar localtime() . "]\n\n";
my $tmp_dir = File::Temp->newdir('X' x 10, DIR => $CTK_TEMP_DIR);
my $ff = File::Fetch->new(uri => $CTK_GSEA_GENESIGDB_FILE_URI) or die "\n\nERROR: File::Fetch object constructor error\n\n";
my $gs_file_name = basename($CTK_GSEA_GENESIGDB_FILE_URI);
print "Fetching GeneSigDB v$CTK_GSEA_GENESIGDB_VERSION ($gs_file_name)\n";
$ff->fetch(to => $tmp_dir) or die "\n\nERROR: File::Fetch fetch error: ", $ff->error, "\n\n";
open(my $gs_out_fh, '>', "$tmp_dir/$CTK_GSEA_GSDBS{genesigdb}") or die "Could not create $tmp_dir/$CTK_GSEA_GSDBS{genesigdb}: $!\n";
open(my $gs_in_fh, '<', "$tmp_dir/$gs_file_name") or die "Could not open $tmp_dir/$gs_file_name: $!\n";
print "Processing file... ";
while(<$gs_in_fh>) {
    m/^\s*$/ && next;
    my ($gene_set_id, $gene_set_name, $line) = split /\t/, $_, 3;
    my ($pubmed_id) = split /-/, $gene_set_id, 2;
    $gene_set_name =~ s/\s+/_/g;
    print $gs_out_fh "$gene_set_name\t$PUBMED_BASEURL$pubmed_id\t$line";
}
close($gs_in_fh);
close($gs_out_fh);
print "done!\n";
move("$tmp_dir/$CTK_GSEA_GSDBS{genesigdb}", "$CTK_GSEA_GENE_SET_DB_DIR/$CTK_GSEA_GSDBS{genesigdb}") or die "Could not move $CTK_GSEA_GSDBS{genesigdb}: $!";
print "\nConfero GeneSigDB GMT Downloader/Processor complete [", scalar localtime, "]\n\n";
exit;

__END__

=head1 NAME 

cfo_fetch_process_genesigdb.pl - Confero GeneSigDB Downloader/Processor

=head1 SYNOPSIS

 cfo_fetch_process_genesigdb.pl.pl

=cut
