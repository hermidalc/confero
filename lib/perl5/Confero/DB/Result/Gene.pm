package Confero::DB::Result::Gene;

use strict;
use warnings;
use base 'DBIx::Class::Core';

our $VERSION = '0.8';

__PACKAGE__->table('gene');
__PACKAGE__->add_columns(
    'id' => {
        data_type         => 'integer',
        is_nullable       => 0,
        extra             => { unsigned => 1 },
    },
    'symbol' => {
        data_type         => 'varchar',
        size              => 100,
        is_nullable       => 0,
    },
    'status' => {
        data_type         => 'varchar',
        size              => 30,
        is_nullable       => 1,
    },
    'synonyms' => {
        data_type         => 'varchar',
        size              => 4000,
        is_nullable       => 1,
    },
    'description' => {
        data_type         => 'varchar',
        size              => 4000,
        is_nullable       => 1,
    },
);
__PACKAGE__->set_primary_key('id');
#__PACKAGE__->add_unique_constraint(gene_un_symbol => [qw( symbol )]);
__PACKAGE__->has_many('gene_set_genes' => 'Confero::DB::Result::GeneSetGene', 'gene_id');
__PACKAGE__->has_many('contrast_gene_set_genes' => 'Confero::DB::Result::ContrastGeneSetGene', 'gene_id');

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->add_index(name => 'gene_idx_symbol', fields => [qw( symbol )]);
    #$sqlt_table->add_index(name => 'gene_idx_status', fields => [qw( status )]);
}

1;
