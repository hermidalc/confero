package Confero::DB::Result::ContrastDataSet;

use strict;
use warnings;
use base 'DBIx::Class::Core';

our $VERSION = '0.8';

__PACKAGE__->table('contrast_data_set');
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
    'collapsing_method' => {
        data_type         => 'varchar',
        size              => 100,
        is_nullable       => 0,
    },
    'creation_time' => {
        data_type         => 'timestamp',
        is_nullable       => 0,
        default_value     => \'now()',
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
    #'analysis_id' => {
    #    accessor          => 'analysis',
    #    data_type         => 'integer',
    #    is_nullable       => 0,
    #    is_foreign_key    => 1,
    #    extra             => { unsigned => 1 },
    #},
);
__PACKAGE__->set_primary_key('id');
__PACKAGE__->add_unique_constraint(contrast_data_set_un_name => [qw( name )]);
__PACKAGE__->belongs_to('organism' => 'Confero::DB::Result::Organism', 'organism_id');
#__PACKAGE__->belongs_to('analysis' => 'Confero::DB::Result::Analysis', 'analysis_id');
__PACKAGE__->has_one('source_data_file' => 'Confero::DB::Result::ContrastDataSetSourceDataFile', 'contrast_data_set_id');
__PACKAGE__->has_many('contrasts' => 'Confero::DB::Result::Contrast', 'contrast_data_set_id');
__PACKAGE__->has_many('annotations' => 'Confero::DB::Result::ContrastDataSetAnnotation', 'contrast_data_set_id');

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    #$sqlt_table->add_index(name => 'contrast_data_set_idx_name', fields => [qw( name )]);
    $sqlt_table->add_index(name => 'contrast_data_set_idx_source_data_file_id_type', fields => [qw( source_data_file_id_type )]);
}

1;
