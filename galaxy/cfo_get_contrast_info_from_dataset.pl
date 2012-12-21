#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use Confero::DB;
use Confero::LocalConfig qw($CTK_DISPLAY_ID_SPACER);
use Confero::Utils qw(deconstruct_id);
use Getopt::Long qw(:config auto_help auto_version);
use JSON qw(encode_json);
use Pod::Usage qw(pod2usage);

our $VERSION = '0.0.1';

my $as_tuples = 0;
my $get_idxs  = 0;
my $get_names = 0;
my $dataset_file_path;
my $dataset_id;
GetOptions(
    'as-tuples'      => \$as_tuples,
    'get-idxs'       => \$get_idxs,
    'get-names'      => \$get_names,
    'dataset-file=s' => \$dataset_file_path,
    'dataset-id=s'   => \$dataset_id,
) || pod2usage(-verbose => 0);
pod2usage(-message => 'Missing required parameter: --dataset-file or --dataset-id', -verbose => 0) unless defined $dataset_file_path or defined $dataset_id;
pod2usage(-message => 'Bad parameters: only of of --dataset-file or --dataset-id', -verbose => 0) if defined $dataset_file_path and defined $dataset_id;
pod2usage(-message => 'Missing required parameter: --get-names or --get-idxs', -verbose => 0) unless $get_names or $get_idxs;
pod2usage(-message => 'Bad parameters: only of of --get-names or --get-idxs', -verbose => 0) if $get_names and $get_idxs;
pod2usage(-message => 'Dataset file path not a valid file', -verbose => 0) if defined $dataset_file_path and !-f $dataset_file_path;
$get_idxs = 0 if $get_names;
$get_names = 1 unless $get_idxs;
my @tuples;
#push @tuples, [ '', '', JSON::true ] if $as_tuples;
if ($dataset_file_path) {
    open(my $contrast_dataset_fh, '<', $dataset_file_path) or die "ERROR: could not open $dataset_file_path: $!\n";
    while (<$contrast_dataset_fh>) {
        s/^\s+//;
        s/\s+$//;
        if (my ($contrast_names_str) = m/^#%contrast_names?=(.+)$/i) {
            $contrast_names_str =~ s/^(?:"|')|(?:"|')$//g;
            my @contrast_names = split m/(?:"|'),(?:"|')/, $contrast_names_str;
            for my $i (0 .. $#contrast_names) {
                $contrast_names[$i] =~ s/$CTK_DISPLAY_ID_SPACER/ /go;
                push @tuples, $as_tuples ? [ $contrast_names[$i], $get_idxs ? "$i" : $contrast_names[$i], $i == 0 ? JSON::true : JSON::false ] : $get_idxs ? $i : $contrast_names[$i];
            }
        }
    }
    close($contrast_dataset_fh);
}
elsif (defined $dataset_id) {
    $dataset_id =~ s/\s+//g;
    my ($dataset_name) = deconstruct_id($dataset_id);
    my $ctk_db = Confero::DB->new();
    if (my $dataset = $ctk_db->resultset('ContrastDataSet')->find({
            name => $dataset_name,
        },{
            prefetch => 'contrasts',
            order_by => 'contrasts.id',
        })
    ) {
        my @contrasts = $dataset->contrasts;
        for my $i (0 .. $#contrasts) {
            push @tuples, $as_tuples ? [ $contrasts[$i]->name, $get_idxs ? "$i" : $contrasts[$i]->name, $i == 0 ? JSON::true : JSON::false ] : $get_idxs ? $i : $contrasts[$i]->name;
        }
    }
    else {
        pod2usage(-message => "Confero dataset ID '$dataset_id' not found in database", -verbose => 0);
    }
}
print encode_json(\@tuples);
exit;
