package Confero::DB::Result::ContrastDataSetAnnotation;

use strict;
use warnings;
use base 'DBIx::Class::Core';

our $VERSION = '0.8';

__PACKAGE__->table('contrast_data_set_annotation');
__PACKAGE__->add_columns(
    'id' => {
        data_type         => 'integer',
        is_nullable       => 0,
        is_auto_increment => 1,
        extra             => { unsigned => 1 },
    },
    'name' => {
        data_type         => 'varchar',
        size              => 100,
        is_nullable       => 0,
    },
    'value' => {
        data_type         => 'varchar',
        size              => 4000,
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
__PACKAGE__->belongs_to('data_set' => 'Confero::DB::Result::ContrastDataSet', 'contrast_data_set_id');

1;
