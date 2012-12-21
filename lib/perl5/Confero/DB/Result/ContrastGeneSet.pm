package Confero::DB::Result::ContrastGeneSet;

use strict;
use warnings;
use base 'DBIx::Class::Core';

our $VERSION = '0.8';

__PACKAGE__->table('contrast_gene_set');
__PACKAGE__->add_columns(
    'id' => {
        data_type         => 'integer',
        is_nullable       => 0,
        is_auto_increment => 1,
        extra             => { unsigned => 1 },
    },
    'type' => {
        #data_type         => "enum('UP', 'DN', 'AR')",
        data_type         => 'varchar',
        size              => 10,
        is_nullable       => 0,
    },
    'contrast_id' => {
        accessor          => 'contrast',
        data_type         => 'integer',
        is_nullable       => 0,
        is_foreign_key    => 1,
        extra             => { unsigned => 1 },
    },
);
__PACKAGE__->set_primary_key('id');
__PACKAGE__->add_unique_constraint(contrast_gene_set_un_contrast_gene_set_type => [qw( contrast_id type )]);
__PACKAGE__->belongs_to('contrast' => 'Confero::DB::Result::Contrast', 'contrast_id');
__PACKAGE__->has_many('gene_set_genes' => 'Confero::DB::Result::ContrastGeneSetGene', 'contrast_gene_set_id');

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    #$sqlt_table->add_index(name => 'contrast_gene_set_contrast_gene_set_type', fields => [qw( contrast_id type )]);
}

1;
