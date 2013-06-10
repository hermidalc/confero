#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use sigtrap qw(handler sig_handler normal-signals error-signals ALRM);
use Confero::DB;
use Confero::Config qw(%CTK_ENTREZ_GENE_ORGANISM_DATA);
use Pod::Usage qw(pod2usage);

sub sig_handler {
    die "\n\n$0 program exited gracefully [", scalar localtime, "]\n\n";
}

our $VERSION = '0.1';

# Unbuffer error and output streams (make sure STDOUT is last so that it remains the default filehandle)
select(STDERR); $| = 1;
select(STDOUT); $| = 1;

print "#", '-' x 120, "#\n",
      "# Confero Organism Loader [" . scalar localtime() . "]\n\n";
eval {
    my $cfo_db = Confero::DB->new();
    $cfo_db->txn_do(sub {
        print "Loading/updating organism definitions in Confero DB:\n";
        for my $organism_name (sort keys %CTK_ENTREZ_GENE_ORGANISM_DATA) {
            print "$organism_name [$CTK_ENTREZ_GENE_ORGANISM_DATA{$organism_name}{tax_id}]\n";
            $cfo_db->resultset('Organism')->update_or_create({
                name => $organism_name,
                tax_id => $CTK_ENTREZ_GENE_ORGANISM_DATA{$organism_name}{tax_id},
            },{
                key => 'organism_un_tax_id',
            });
        }
        print "\n";
    });
};
if ($@) {
    my $message = "ERROR: Confero database transaction failed";
    $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
    die "\n\n$message: $@\n";
}
print "Confero Organism Loader complete [", scalar localtime, "]\n\n";
exit;
