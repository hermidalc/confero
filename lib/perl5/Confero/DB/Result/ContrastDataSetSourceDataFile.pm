package Confero::DB::Result::ContrastDataSetSourceDataFile;

use strict;
use warnings;
use base 'DBIx::Class::Core';

our $VERSION = '0.8';

__PACKAGE__->table('contrast_data_set_source_data_file');
__PACKAGE__->add_columns(
    'contrast_data_set_id' => {
        accessor          => 'data_set',
        data_type         => 'integer',
        is_nullable       => 0,
        is_foreign_key    => 1,
        extra             => { unsigned => 1 },
    },
    'data' => {
        data_type         => 'longtext',
        is_nullable       => 0,
    },
);
__PACKAGE__->set_primary_key('contrast_data_set_id');
__PACKAGE__->belongs_to('data_set' => 'Confero::DB::Result::ContrastDataSet', 'contrast_data_set_id');

1;
