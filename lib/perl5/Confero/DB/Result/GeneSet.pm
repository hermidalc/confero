package Confero::DB::Result::GeneSet;

use strict;
use warnings;
use base 'DBIx::Class::Core';

our $VERSION = '0.1';

__PACKAGE__->table('gene_set');
__PACKAGE__->add_columns(
    'id' => {
        data_type         => 'integer',
        is_nullable       => 0,
        is_auto_increment => 1,
        extra             => { unsigned => 1 },
    },
    'name' => {
        data_type         => 'varchar',
        size              => 200,
        is_nullable       => 0,
    },
    'source_data_file_id_type' => {
        data_type         => 'varchar',
        size              => 100,
        is_nullable       => 0,
    },
    'source_data_file_name' => {
        data_type         => 'varchar',
        size              => 1000,
        is_nullable       => 0,
    },
    'creation_time' => {
        data_type         => 'timestamp',
        is_nullable       => 0,
        default_value     => \'now()',
    },
    'contrast_name' => {
        data_type         => 'varchar',
        size              => 200,
        is_nullable       => 1,
    },
    'type' => {
        #data_type         => "enum('UP', 'DN', 'AR')",
        data_type         => 'varchar',
        size              => 10,
        is_nullable       => 1,
    },
    'description' => {
        data_type         => 'text',
        is_nullable       => 1,
    },
    'data_processing_report' => {
        data_type         => 'text',
        is_nullable       => 1,
    },
    'organism_id' => {
        accessor          => 'organism',
        data_type         => 'integer',
        is_nullable       => 0,
        is_foreign_key    => 1,
        extra             => { unsigned => 1 },
    },
);
__PACKAGE__->set_primary_key('id');
__PACKAGE__->add_unique_constraint(gene_set_un_name_contrast_name_type => [qw( name contrast_name type )]);
__PACKAGE__->belongs_to('organism' => 'Confero::DB::Result::Organism', 'organism_id');
__PACKAGE__->has_one('source_data_file' => 'Confero::DB::Result::GeneSetSourceDataFile', 'gene_set_id');
__PACKAGE__->has_many('gene_set_genes' => 'Confero::DB::Result::GeneSetGene', 'gene_set_id');
__PACKAGE__->has_many('annotations' => 'Confero::DB::Result::GeneSetAnnotation', 'gene_set_id');

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    #$sqlt_table->add_index(name => 'gene_set_idx_name', fields => [qw( name contrast_name type )]);
    $sqlt_table->add_index(name => 'gene_set_idx_source_data_file_id_type', fields => [qw( source_data_file_id_type )]);
}

1;
