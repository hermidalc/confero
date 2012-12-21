package Confero::Utils;

use strict;
use warnings;
use Carp qw(confess);
use Confero::Config qw(@CTK_DATA_CONTRAST_GENE_SET_TYPE_SUFFIXES);
use Confero::LocalConfig qw(:web);
use Const::Fast;
use Utils qw(curr_sub_name);
require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    construct_id
    deconstruct_id
    is_valid_id
    fix_galaxy_replaced_chars
);
our $VERSION = '0.0.1';

const my $CTK_DISPLAY_ID_GENE_SET_SUFFIX_PATTERN => join('|', map(quotemeta, @CTK_DATA_CONTRAST_GENE_SET_TYPE_SUFFIXES));
const my $CTK_DISPLAY_ID_REGEXP => 
    qr/^(?:\Q${CTK_DISPLAY_ID_PREFIX}${CTK_DISPLAY_ID_SPACER}\E|)(.+?)
        (?:\Q${CTK_DISPLAY_ID_SPACER}$CTK_DISPLAY_ID_CONTRAST_SURROUND_CHARS[0]\E(.+?)\Q$CTK_DISPLAY_ID_CONTRAST_SURROUND_CHARS[1]\E|)
        (?:\Q${CTK_DISPLAY_ID_SPACER}\E($CTK_DISPLAY_ID_GENE_SET_SUFFIX_PATTERN)|)$/xio;

sub construct_id {
    my ($dataset_name, $contrast_name, $gene_set_type) = @_;
    confess(curr_sub_name() . '() not passed any dataset name') unless defined $dataset_name;
    for ($dataset_name, $contrast_name, $gene_set_type) {
        if (defined) {
            s/^\s+//;
            s/\s+$//;
        }
    }
    $dataset_name =~ s/\s/$CTK_DISPLAY_ID_SPACER/go;
    my $display_id = "${CTK_DISPLAY_ID_PREFIX}${CTK_DISPLAY_ID_SPACER}${dataset_name}";
    if (defined $contrast_name) {
        $contrast_name =~ s/\s/$CTK_DISPLAY_ID_SPACER/go;
        $display_id .= "${CTK_DISPLAY_ID_SPACER}$CTK_DISPLAY_ID_CONTRAST_SURROUND_CHARS[0]${contrast_name}$CTK_DISPLAY_ID_CONTRAST_SURROUND_CHARS[1]";
    }
    if (defined $gene_set_type) {
        $display_id .= "${CTK_DISPLAY_ID_SPACER}${gene_set_type}";
    }
    return $display_id;
}

sub deconstruct_id {
    my ($id_str) = @_;
    confess(curr_sub_name() . '() not passed any ID string') unless defined $id_str;
    $id_str =~ s/^\s+//;
    $id_str =~ s/\s+$//;
    my ($dataset_name, $contrast_name, $gene_set_type) = $id_str =~ /$CTK_DISPLAY_ID_REGEXP/o;
    $dataset_name =~ s/$CTK_DISPLAY_ID_SPACER/ /go;
    $contrast_name =~ s/$CTK_DISPLAY_ID_SPACER/ /go if defined $contrast_name;
    return wantarray ? ($dataset_name, $contrast_name, $gene_set_type) : $dataset_name;
}

sub is_valid_id {
    my ($id_str) = @_;
    confess(curr_sub_name() . '() not passed any ID string') unless defined $id_str;
    $id_str =~ s/^\s+//;
    $id_str =~ s/\s+$//;
    return $id_str =~ /$CTK_DISPLAY_ID_REGEXP/o ? 1 : 0;
}

# Galaxy specific characters during command generation 
# (internal carriage returns, backslashes, double quotes, single quotes, brackets, greater than, less than)
sub fix_galaxy_replaced_chars {
    my ($str, $skip) = @_;
    $skip || $str =~ s/XX/ /g;
    $skip || $str =~ s/X/\\/g;
    $str =~ s/__dq__/"/g;
    $str =~ s/__sq__/'/g;
    $str =~ s/__ob__/[/g;
    $str =~ s/__cb__/]/g;
    $str =~ s/__lt__/</g;
    $str =~ s/__gt__/>/g;
    return $str;
}

1;
