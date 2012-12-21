package Confero::DB::Result::ContrastDataFile;

use strict;
use warnings;
use base 'DBIx::Class::Core';

our $VERSION = '0.8';

__PACKAGE__->table('contrast_data_file');
__PACKAGE__->add_columns(
    'contrast_id' => {
        accessor          => 'contrast',
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
__PACKAGE__->set_primary_key('contrast_id');
__PACKAGE__->belongs_to('contrast' => 'Confero::DB::Result::Contrast', 'contrast_id');

1;
