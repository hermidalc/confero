#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use sigtrap qw(handler sig_handler normal-signals error-signals ALRM);
use Confero::EntrezGene;
use Confero::DB;
use Confero::Utils qw(construct_id);
use Getopt::Long qw(:config auto_help auto_version);
use Pod::Usage qw(pod2usage);
use Sort::Key qw(nkeysort);
use Sort::Key::Natural qw(natkeysort rnatkeysort);

our $VERSION = '0.1';

sub sig_handler {
    die "\n\n$0 program exited gracefully [", scalar localtime, "]\n\n";
}

# Unbuffer error and output streams (make sure STDOUT is last so that it remains the default filehandle)
select(STDERR); $| = 1;
select(STDOUT); $| = 1;

my $as_gene_symbols = 0;
my $order_by_rank = 0;
GetOptions(
    'as-gene-symbols' => \$as_gene_symbols,
    'order-by-rank'   => \$order_by_rank,
) || pod2usage(-verbose => 0);
#print "#", '-' x 120, "#\n",
#      "# Confero Gene Set DB Exporter [" . scalar localtime() . "]\n\n";
# this code will likely be refactored to a library function soon since used in two other places in Confero
eval {
    my $cfo_db = Confero::DB->new();
    $cfo_db->txn_do(sub {
        #if ($export_cfo_db_contrasts) {
            my @contrast_datasets = $cfo_db->resultset('ContrastDataSet')->search(undef, {
                prefetch => [qw( organism annotations )],
            })->all();
            CONTRAST_DATASET: for my $contrast_dataset (@contrast_datasets) {
            # enable filters later
            #    next CONTRAST_DATASET if %filter_organisms and !exists $filter_organisms{$contrast_dataset->organism->name};
                my @contrasts = $contrast_dataset->contrasts(undef, {
                    prefetch => {
                        'gene_sets' => { 'gene_set_genes' => 'gene' },
                    },
                })->all();
                CONTRAST: for my $contrast (@contrasts) {
            #        next CONTRAST if %filter_contrast_names and !exists $filter_contrast_names{$contrast->name};
                    my %contrast_dataset_annotations = map { $_->name => $_->value } $contrast_dataset->annotations;
            #        for my $annotation_name (keys %filter_annotations) {
            #            next CONTRAST if %filter_annotations and (!defined $contrast_dataset_annotations{$annotation_name} or 
            #                $contrast_dataset_annotations{$annotation_name} ne $filter_annotations{$annotation_name});
            #        }
                    CONTRAST_GENE_SET: for my $gene_set (rnatkeysort { $_->type } $contrast->gene_sets) {
            #            next CONTRAST_GENE_SET if %filter_gene_set_types and !exists $filter_gene_set_types{$gene_set->type};
                        my $gene_set_id = construct_id($contrast_dataset->name, $contrast->name, $gene_set->type);
            #            next CONTRAST_GENE_SET if %filter_contrast_gene_set_ids and !exists $filter_contrast_gene_set_ids{$gene_set_id};
                        my @gene_ids = map {
                            $as_gene_symbols ? $_->gene->symbol : $_->gene->id
                        } (
                            $order_by_rank   ? nkeysort { $_->rank } $gene_set->gene_set_genes :
                            $as_gene_symbols ? natkeysort { $_->gene->symbol } $gene_set->gene_set_genes :
                                               nkeysort { $_->gene->id } $gene_set->gene_set_genes
                        );
                        print 
                            ">$gene_set_id | ", 
                            $contrast_dataset->organism->name, ' | ', 
                            $contrast_dataset->source_data_file_id_type, ' | ',
                            $contrast_dataset->description || '', "\n", 
                            join(' ', @gene_ids), "\n";
                    }
                }
            }
        #}
        #if ($export_cfo_db_uploads) {
            my @gene_sets = $cfo_db->resultset('GeneSet')->search(undef, {
                prefetch => [qw( organism annotations )],
            })->all();
            GENE_SET: for my $gene_set (@gene_sets) {
                my $gene_set_id = construct_id($gene_set->name, $gene_set->contrast_name, $gene_set->type);
            # enable filters later
            #    next GENE_SET if (%filter_organisms and !exists $filter_organisms{$gene_set->organism->name}) or
            #                     (%filter_contrast_names and (!defined $gene_set->contrast_name or !exists $filter_contrast_names{$gene_set->contrast_name})) or
            #                     (%filter_gene_set_types and (!defined $gene_set->type or !exists $filter_gene_set_types{$gene_set->type})) or 
            #                     (%filter_gene_set_ids and !exists $filter_gene_set_ids{$gene_set_id});
                my %gene_set_annotations = map { $_->name => $_->value } $gene_set->annotations;
            #    for my $annotation_name (keys %filter_annotations) {
            #        next GENE_SET if %filter_annotations and (!defined $gene_set_annotations{$annotation_name} or 
            #            $gene_set_annotations{$annotation_name} ne $filter_annotations{$annotation_name});
            #    }
                my @gene_set_genes = $gene_set->gene_set_genes(undef, {
                    prefetch => 'gene',
                })->all();
                # all gene set genes should have ranks or none (maybe not best way to figure that out)
                my $have_ranks = grep { defined $_->rank } @gene_set_genes;
                my @gene_ids = map {
                    $as_gene_symbols ? $_->gene->symbol : $_->gene->id
                } (
                    ($order_by_rank and $have_ranks) ? nkeysort { $_->rank } @gene_set_genes :
                    $as_gene_symbols                 ? natkeysort { $_->gene->symbol } @gene_set_genes :
                                                       nkeysort { $_->gene->id } @gene_set_genes
                );
                print 
                    ">$gene_set_id | ", 
                    $gene_set->organism->name, ' | ', 
                    $gene_set->source_data_file_id_type, ' | ',
                    $gene_set->description || '', "\n", 
                    join(' ', @gene_ids), "\n";
            }
        #}
    });
};
if ($@) {
    my $message = "ERROR: Confero database transaction failed";
    $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
    die "\n\n$message: $@\n";
}
#print "\nConfero Gene Set DB Exporter complete [", scalar localtime, "]\n\n";
exit;

__END__

=head1 NAME 

cfo_export_gene_set_db.pl - Confero Gene Set DB Exporter

=head1 SYNOPSIS

 cfo_export_gene_set_db.pl [options] <output file>

 Options:
     --as-gene-symbols      Export gene sets as gene symbols (default off, export as Entrez Gene IDs)
     --order-by-rank        Export gene sets with genes listed in rank order if ranks exist for gene set (default off, genes listed in natural order)
     --help                 Display usage and exit
     --version              Display program version and exit

=cut
