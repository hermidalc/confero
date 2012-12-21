package Confero::DB::Result::GeneSetGene;

use strict;
use warnings;
use base 'DBIx::Class::Core';

our $VERSION = '0.8';

__PACKAGE__->table('gene_set_gene');
__PACKAGE__->add_columns(
    'gene_set_id' => {
        accessor          => 'gene_set',
        data_type         => 'integer',
        is_nullable       => 0,
        is_foreign_key    => 1,
        extra             => { unsigned => 1 },
    },
    'gene_id' => {
        accessor          => 'gene',
        data_type         => 'integer',
        is_nullable       => 0,
        is_foreign_key    => 1,
        extra             => { unsigned => 1 },
    },
    'rank' => {
        data_type         => 'integer',
        is_nullable       => 1,
        extra             => { unsigned => 1 },
    },
);
__PACKAGE__->set_primary_key(qw( gene_set_id gene_id ));
__PACKAGE__->add_unique_constraint(
    gene_set_gene_un_gene_set_rank => [qw( gene_set_id rank )],
);
__PACKAGE__->belongs_to('gene_set' => 'Confero::DB::Result::GeneSet', 'gene_set_id' );
__PACKAGE__->belongs_to('gene'     => 'Confero::DB::Result::Gene',    'gene_id'     );

1;
