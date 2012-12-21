package Confero::DB::Result::Contrast;

use strict;
use warnings;
use base 'DBIx::Class::Core';

our $VERSION = '0.8';

__PACKAGE__->table('contrast');
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
    'contrast_data_set_id' => {
        accessor          => 'data_set',
        data_type         => 'integer',
        is_nullable       => 0,
        is_foreign_key    => 1,
        extra             => { unsigned => 1 },
    },
);
__PACKAGE__->set_primary_key('id');
__PACKAGE__->add_unique_constraint(contrast_un_contrast_data_set_contrast_name => [qw( contrast_data_set_id name )]);
__PACKAGE__->belongs_to('data_set' => 'Confero::DB::Result::ContrastDataSet', 'contrast_data_set_id');
__PACKAGE__->has_one('data_file' => 'Confero::DB::Result::ContrastDataFile', 'contrast_id');
__PACKAGE__->has_many('gene_sets' => 'Confero::DB::Result::ContrastGeneSet', 'contrast_id');

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    #$sqlt_table->add_index(name => 'contrast_idx_name', fields => [qw( name )]);
}

1;
