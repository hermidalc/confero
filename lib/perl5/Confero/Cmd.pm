package Confero::Cmd;

use strict;
use warnings;
use Carp qw(croak confess);
use Cwd qw(cwd);
use File::Basename qw(fileparse);
use File::Copy qw(copy move);
use File::Copy::Recursive qw(dirmove);
use File::Path qw(mkpath rmtree);
use File::Temp ();  # () for OO-interface
use File::Spec;
use Confero::Config qw(:data :gsea :galaxy %CTK_ENTREZ_GENE_ORGANISM_DATA);
use Confero::LocalConfig qw(:general :data :gsea :web);
use Confero::DataFile;
use Confero::DB;
use Confero::EntrezGene;
use Confero::Utils qw(construct_id deconstruct_id is_valid_id fix_galaxy_replaced_chars);
use Const::Fast;
use Getopt::Long qw(:config auto_help auto_version);
use HTML::TreeBuilder;
use List::Util qw(sum max min);
use Math::Round qw(round);
use Parse::BooleanLogic;
use Pod::Usage qw(pod2usage);
use Sort::Key qw(nsort nkeysort rnkeysort rnkeysort_inplace);
use Sort::Key::Natural qw(natsort);
use Sort::Key::Multi qw(srnkeysort nrnkeysort_inplace);
use Statistics::Basic qw(median);
use Text::CSV;
use Utils qw(curr_sub_name is_integer is_numeric intersect_arrays remove_shell_metachars escape_shell_metachars);
use Data::Dumper;

$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Terse = 1;
$Data::Dumper::Deepcopy = 1;

our $VERSION = '0.1';

const my $WORKING_DIR => cwd();
const my $CTK_DISPLAY_ID_GENE_SET_SUFFIX_PATTERN => join('|', map(quotemeta, @CTK_DATA_CONTRAST_GENE_SET_TYPE_SUFFIXES));
const my $CTK_DISPLAY_ID_GENE_SET_REGEXP => qr/^(\Q$CTK_DISPLAY_ID_PREFIX\E.+?)\Q$CTK_DISPLAY_ID_SPACER\E(?:$CTK_DISPLAY_ID_GENE_SET_SUFFIX_PATTERN)$/io;

sub process_submit_data_file {
    my $self = shift;
    # arguments
    # required: [input data file path], [data type], [report file path]
    # optional: [original input data file name], [id type], [collapsing method], [organism name], [dataset name], [dataset description], [src2gene id best map]
    # reprocess_submission: [Confero DB object], [existing dataset | gene set object], [gene objects hashref]
    # additional optional: [skip threshold checks flag], [overwrite existing flag], [output report as HTML flag], [output file path], [debug file path]
    my ($input_file_path, $data_type, $report_file_path, $orig_input_file_name, $id_type, $collapsing_method, $organism_name, $dataset_name, $dataset_desc, 
        $src2gene_id_bestmap, $cfo_db, $set_db_obj, $genes_hashref, $skip_threshold_checks, $overwrite_existing, $output_as_html, $output_file_path, 
        $no_processed_file_output, $debug_file_path);
    if (@_) {
        ($input_file_path, $data_type, $report_file_path, $orig_input_file_name, $id_type, $collapsing_method, $organism_name, $dataset_name, $dataset_desc, 
         $src2gene_id_bestmap, $cfo_db, $set_db_obj, $genes_hashref, $skip_threshold_checks, $overwrite_existing, $output_as_html, $output_file_path, 
         $no_processed_file_output, $debug_file_path) = @_;
    }
    else {
        Getopt::Long::Configure('no_pass_through');
        GetOptions(
            'data-file=s'                   => \$input_file_path,
            'report-file=s'                 => \$report_file_path,
            'report-as-html'                => \$output_as_html,
            'orig-filename=s'               => \$orig_input_file_name,
            'data-type=s'                   => \$data_type,
            'id-type=s'                     => \$id_type,
            'organism-name=s'               => \$organism_name,
            'dataset-name|gene-set-name:s'  => \$dataset_name,
            'dataset-desc|gene-set-desc:s'  => \$dataset_desc,
            'collapsing-method=s'           => \$collapsing_method,
            'skip-threshold-checks'         => \$skip_threshold_checks,
            'overwrite-existing'            => \$overwrite_existing,
            'processsed-file|output-file=s' => \$output_file_path,
            'no-processed-file-output'      => \$no_processed_file_output,
            'debug-file=s'                  => \$debug_file_path,
        ) || pod2usage(-verbose => 0);
        pod2usage(-message => 'Missing required parameter --data-file', -verbose => 0) unless defined $input_file_path;
        pod2usage(-message => 'Missing required parameter --data-type', -verbose => 0) unless defined $data_type;
    }
    return $self->submit_data_file(
        $self->process_data_file(
            $input_file_path, $data_type, $report_file_path, $orig_input_file_name, $id_type, $collapsing_method, $organism_name, $dataset_name, 
            $dataset_desc, $src2gene_id_bestmap, $skip_threshold_checks, $output_as_html, $output_file_path, $no_processed_file_output, $debug_file_path, 
        ),
        $cfo_db, $set_db_obj, $genes_hashref, $overwrite_existing, 
    );
}

sub process_data_file {
    my $self = shift;
    # arguments
    # required: [input data file path], [data type], [report file path]
    # optional: [original input data file name], [id type], [collapsing method], [organism name], [dataset name], [dataset description]
    # additional optional:  [skip threshold checks flag], [output report as HTML flag], [debug file path], [output as gene symbols flag]
    my ($input_file_path, $data_type, $report_file_path, $orig_input_file_name, $id_type, $collapsing_method, $organism_name, $dataset_name, 
        $dataset_desc, $src2gene_id_bestmap, $skip_threshold_checks, $output_as_html, $output_file_path, $no_processed_file_output, $debug_file_path, 
        $output_as_gene_symbols);
    if (@_) {
        ($input_file_path, $data_type, $report_file_path, $orig_input_file_name, $id_type, $collapsing_method, $organism_name, $dataset_name, 
         $dataset_desc, $src2gene_id_bestmap, $skip_threshold_checks, $output_as_html, $output_file_path, $no_processed_file_output, $debug_file_path, 
         $output_as_gene_symbols) = @_;
    }
    else {
        Getopt::Long::Configure('no_pass_through');
        GetOptions(
            'data-file=s'                  => \$input_file_path,
            'report-file=s'                => \$report_file_path,
            'report-as-html'               => \$output_as_html,
            'orig-filename=s'              => \$orig_input_file_name,
            'data-type=s'                  => \$data_type,
            'id-type=s'                    => \$id_type,
            'organism-name=s'              => \$organism_name,
            'collapsing-method=s'          => \$collapsing_method,
            'skip-threshold-checks'        => \$skip_threshold_checks,
            'processed-file|output-file=s' => \$output_file_path,
            'no-processed-file-output'     => \$no_processed_file_output,
            'debug-file=s'                 => \$debug_file_path,
            'output-as-gene-symbols'       => \$output_as_gene_symbols,
        ) || pod2usage(-verbose => 0);
        pod2usage(-message => 'Missing required parameter --data-file', -verbose => 0) unless defined $input_file_path;
        pod2usage(-message => 'Missing required parameter --data-type', -verbose => 0) unless defined $data_type;
    }
    $skip_threshold_checks = 0 if !defined $skip_threshold_checks or $skip_threshold_checks ne '1';
    # don't throw error here anymore, contrast file could have dataset name metadata header
    #confess('Dataset name cannot be empty') if $dataset_name =~ m/^(\s*|none)$/i;
    $orig_input_file_name = fix_galaxy_replaced_chars($orig_input_file_name) if defined $orig_input_file_name;
    $dataset_name = fix_galaxy_replaced_chars($dataset_name) if defined $dataset_name;
    $dataset_desc = fix_galaxy_replaced_chars($dataset_desc) if defined $dataset_desc;
    # set optional parameters to undef if "empty"
    for my $param ($id_type, $organism_name, $dataset_name, $dataset_desc) {
        $param = undef if defined $param and $param =~ m/^(\s*|none|\?)$/i;
    }
    # create data file object and load/check/process data
    my $input_data_file = Confero::DataFile->new(
        $input_file_path, $data_type, $orig_input_file_name, $id_type, $collapsing_method, 
        1, $organism_name, $dataset_name, $dataset_desc, $src2gene_id_bestmap,
    );
    if (!@{$input_data_file->data_errors}) {
        my ($gene_sets_arrayref, @gene_set_errors);
        # contrast dataset
        if ($input_data_file->isa('Confero::DataFile::IdMAPS')) {
            my $gs_min_size = defined $input_data_file->metadata->{gs_min_size}
                            ? $input_data_file->metadata->{gs_min_size}
                            : $CTK_DATA_FILE_MIN_GENE_SET_SIZE;
            my $gs_max_size = defined $input_data_file->metadata->{gs_max_size}
                            ? $input_data_file->metadata->{gs_max_size}
                            : $CTK_DATA_FILE_MAX_GENE_SET_SIZE;
            # create gene sets per contrast
            for my $contrast_idx (0 .. $#{$input_data_file->processed_data}) {
                # create gene sets using any gs_* metadata if specified
                if ((defined $input_data_file->metadata->{gs_all_default}) or
                    (defined $input_data_file->metadata->{gs_up_sizes} and 
                     defined $input_data_file->metadata->{gs_up_sizes}->[$contrast_idx] and
                     is_numeric($input_data_file->metadata->{gs_up_sizes}->[$contrast_idx])) or
                    (defined $input_data_file->metadata->{gs_dn_sizes} and 
                     defined $input_data_file->metadata->{gs_dn_sizes}->[$contrast_idx] and
                     is_numeric($input_data_file->metadata->{gs_dn_sizes}->[$contrast_idx])) or
                    (defined $input_data_file->metadata->{gs_m_val_thres} and 
                     defined $input_data_file->metadata->{gs_m_val_thres}->[$contrast_idx] and
                     is_numeric($input_data_file->metadata->{gs_m_val_thres}->[$contrast_idx])) or
                    (defined $input_data_file->metadata->{gs_a_val_thres} and 
                     defined $input_data_file->metadata->{gs_a_val_thres}->[$contrast_idx] and
                     is_numeric($input_data_file->metadata->{gs_a_val_thres}->[$contrast_idx])) or
                    (defined $input_data_file->metadata->{gs_p_val_thres} and 
                     defined $input_data_file->metadata->{gs_p_val_thres}->[$contrast_idx]) and
                     is_numeric($input_data_file->metadata->{gs_p_val_thres}->[$contrast_idx])) {
                    # get target up and down gene set sizes if specified
                    my %target_gs_sizes;
                    $target_gs_sizes{up} = $input_data_file->metadata->{gs_up_sizes}->[$contrast_idx]
                        if defined $input_data_file->metadata->{gs_up_sizes} and 
                           defined $input_data_file->metadata->{gs_up_sizes}->[$contrast_idx] and
                           is_numeric($input_data_file->metadata->{gs_up_sizes}->[$contrast_idx]);
                    $target_gs_sizes{dn} = $input_data_file->metadata->{gs_dn_sizes}->[$contrast_idx]
                        if defined $input_data_file->metadata->{gs_dn_sizes} and 
                           defined $input_data_file->metadata->{gs_dn_sizes}->[$contrast_idx] and
                           is_numeric($input_data_file->metadata->{gs_dn_sizes}->[$contrast_idx]);
                    # check to make sure target gene set sizes are not bigger than number of entries in file
                    # and are also within the range set by min and max gene set size
                    for my $gs_type (qw(up dn)) {
                        if (defined $target_gs_sizes{$gs_type}) {
                            if ($target_gs_sizes{$gs_type} > scalar(@{$input_data_file->processed_data->[$contrast_idx]})) {
                                confess("Target gene set size ($target_gs_sizes{$gs_type}) bigger than Entrez Gene mapped file data (" . 
                                    scalar(@{$input_data_file->processed_data->[$contrast_idx]}) . ") size");
                            }
                            if ($target_gs_sizes{$gs_type} < $gs_min_size or $target_gs_sizes{$gs_type} > $gs_max_size) {
                                confess("Target gene set size ($target_gs_sizes{$gs_type}) not within minimum ($gs_min_size) and maximum ($gs_max_size) gene set size range");
                            }
                        }
                    }
                    my $split_num = (defined $input_data_file->metadata->{gs_data_split_meths} and defined $input_data_file->metadata->{gs_data_split_meths}->[$contrast_idx])
                                  ? $input_data_file->metadata->{gs_data_split_meths}->[$contrast_idx] eq 'zero'
                                      ? 0
                                      : $input_data_file->metadata->{gs_data_split_meths}->[$contrast_idx] eq 'median_m'
                                          ? median(map { $_->[$input_data_file->M_idx] } @{$input_data_file->processed_data->[$contrast_idx]})
                                          : confess("Invalid specified contrast data file split method: $input_data_file->metadata->{gs_data_split_meths}->[$contrast_idx]")
                                  : $CTK_DATA_FILE_SPLIT_METHOD eq 'zero'
                                      ? 0
                                      : $CTK_DATA_FILE_SPLIT_METHOD eq 'median_m'
                                          ? median(map { $_->[$input_data_file->M_idx] } @{$input_data_file->processed_data->[$contrast_idx]})
                                          : confess("Invalid configured contrast data file split method: $CTK_DATA_FILE_SPLIT_METHOD");
                    my (%gene_set_data, %gene_set_original_size);
                    # create gene set using P value methodology if available
                    if (defined $input_data_file->P_idx) {
                        my %file_data;
                        # split file data rows into two parts by M value using zero or median M value as split number
                        @{$file_data{up}} = grep { $_->[$input_data_file->M_idx] >  $split_num } @{$input_data_file->processed_data->[$contrast_idx]};
                        @{$file_data{dn}} = grep { $_->[$input_data_file->M_idx] <= $split_num } @{$input_data_file->processed_data->[$contrast_idx]};
                        # make ar file data exactly like gene data except abs(M)
                        for my $input_data_file_row_arrayref (@{$input_data_file->processed_data->[$contrast_idx]}) {
                            # must copy row arrayref so as to not alter gene data file data
                            my @ar_file_data_row = @{$input_data_file_row_arrayref};
                            $ar_file_data_row[$input_data_file->M_idx] = abs($ar_file_data_row[$input_data_file->M_idx]);
                            push @{$file_data{ar}}, \@ar_file_data_row;
                        }
                        # create gene sets using M-A-P thresholds if specified
                        if ((defined $input_data_file->metadata->{gs_m_val_thres} and
                             defined $input_data_file->metadata->{gs_m_val_thres}->[$contrast_idx] and
                             is_numeric($input_data_file->metadata->{gs_m_val_thres}->[$contrast_idx])) or
                            (defined $input_data_file->metadata->{gs_a_val_thres} and
                             defined $input_data_file->metadata->{gs_a_val_thres}->[$contrast_idx] and
                             is_numeric($input_data_file->metadata->{gs_a_val_thres}->[$contrast_idx])) or
                            (defined $input_data_file->metadata->{gs_p_val_thres} and
                             defined $input_data_file->metadata->{gs_p_val_thres}->[$contrast_idx] and
                             is_numeric($input_data_file->metadata->{gs_p_val_thres}->[$contrast_idx]))) {
                            my %ranked_gene_set_data_id_arrays;
                            # filter and sort data by each column M, A, P independently
                            if (defined $input_data_file->metadata->{gs_m_val_thres} and
                                defined $input_data_file->metadata->{gs_m_val_thres}->[$contrast_idx] and
                                is_numeric($input_data_file->metadata->{gs_m_val_thres}->[$contrast_idx])) {
                                my %m_ranked_gene_set_data_ids;
                                @{$m_ranked_gene_set_data_ids{up}} = 
                                     map { $_->[0] } 
                                    sort { $b->[$input_data_file->M_idx] <=> $a->[$input_data_file->M_idx] }
                                    grep { $_->[$input_data_file->M_idx] >=  $input_data_file->metadata->{gs_m_val_thres}->[$contrast_idx] } 
                                    @{$file_data{up}};
                                @{$m_ranked_gene_set_data_ids{dn}} = 
                                     map { $_->[0] } 
                                    sort { $a->[$input_data_file->M_idx] <=> $b->[$input_data_file->M_idx] }
                                    grep { $_->[$input_data_file->M_idx] <= -$input_data_file->metadata->{gs_m_val_thres}->[$contrast_idx] } 
                                    @{$file_data{dn}};
                                @{$m_ranked_gene_set_data_ids{ar}} = 
                                     map { $_->[0] } 
                                    sort { $b->[$input_data_file->M_idx] <=> $a->[$input_data_file->M_idx] }
                                    grep { $_->[$input_data_file->M_idx] >=  $input_data_file->metadata->{gs_m_val_thres}->[$contrast_idx] } 
                                    @{$file_data{ar}};
                                push @{$ranked_gene_set_data_id_arrays{$_}}, $m_ranked_gene_set_data_ids{$_} for qw(up dn ar);
                            }
                            if (defined $input_data_file->metadata->{gs_a_val_thres} and
                                defined $input_data_file->metadata->{gs_a_val_thres}->[$contrast_idx] and
                                is_numeric($input_data_file->metadata->{gs_a_val_thres}->[$contrast_idx])) {
                                my %a_ranked_gene_set_data_ids;
                                @{$a_ranked_gene_set_data_ids{up}} = 
                                     map { $_->[0] } 
                                    sort { $b->[$input_data_file->A_idx] <=> $a->[$input_data_file->A_idx] } 
                                    grep { $_->[$input_data_file->A_idx] >= $input_data_file->metadata->{gs_a_val_thres}->[$contrast_idx] } 
                                    @{$file_data{up}};
                                @{$a_ranked_gene_set_data_ids{dn}} = 
                                     map { $_->[0] } 
                                    sort { $b->[$input_data_file->A_idx] <=> $a->[$input_data_file->A_idx] } 
                                    grep { $_->[$input_data_file->A_idx] >= $input_data_file->metadata->{gs_a_val_thres}->[$contrast_idx] } 
                                    @{$file_data{dn}};
                                @{$a_ranked_gene_set_data_ids{ar}} = 
                                     map { $_->[0] } 
                                    sort { $b->[$input_data_file->A_idx] <=> $a->[$input_data_file->A_idx] } 
                                    grep { $_->[$input_data_file->A_idx] >= $input_data_file->metadata->{gs_a_val_thres}->[$contrast_idx] } 
                                    @{$file_data{ar}};
                                push @{$ranked_gene_set_data_id_arrays{$_}}, $a_ranked_gene_set_data_ids{$_} for qw(up dn ar);
                            }
                            if (defined $input_data_file->metadata->{gs_p_val_thres} and
                                defined $input_data_file->metadata->{gs_p_val_thres}->[$contrast_idx] and
                                is_numeric($input_data_file->metadata->{gs_p_val_thres}->[$contrast_idx])) {
                                my %p_ranked_gene_set_data_ids;
                                @{$p_ranked_gene_set_data_ids{up}} = 
                                     map { $_->[0] } 
                                    sort { $a->[$input_data_file->P_idx] <=> $b->[$input_data_file->P_idx] } 
                                    grep { $_->[$input_data_file->P_idx] <= $input_data_file->metadata->{gs_p_val_thres}->[$contrast_idx] } 
                                    @{$file_data{up}};
                                @{$p_ranked_gene_set_data_ids{dn}} = 
                                     map { $_->[0] } 
                                    sort { $a->[$input_data_file->P_idx] <=> $b->[$input_data_file->P_idx] } 
                                    grep { $_->[$input_data_file->P_idx] <= $input_data_file->metadata->{gs_p_val_thres}->[$contrast_idx] } 
                                    @{$file_data{dn}};
                                @{$p_ranked_gene_set_data_ids{ar}} = 
                                     map { $_->[0] } 
                                    sort { $a->[$input_data_file->P_idx] <=> $b->[$input_data_file->P_idx] } 
                                    grep { $_->[$input_data_file->P_idx] <= $input_data_file->metadata->{gs_p_val_thres}->[$contrast_idx] } 
                                    @{$file_data{ar}};
                                push @{$ranked_gene_set_data_id_arrays{$_}}, $p_ranked_gene_set_data_ids{$_} for qw(up dn ar);
                            }
                            for my $gene_set (qw(up dn ar)) {
                                # intersect data ID arrays
                                my %gene_set_ids = map { $_ => 1 } intersect_arrays(@{$ranked_gene_set_data_id_arrays{$gene_set}});
                                @{$gene_set_data{$gene_set}} = grep { $gene_set_ids{$_->[0]} } @{$file_data{$gene_set}};
                                my $gene_set_size = scalar(@{$gene_set_data{$gene_set}});
                                # check gene sets pass max size threshold and reduce using methodology below if needed
                                if ($gene_set_size > $gs_max_size) {
                                    $gene_set_original_size{$gene_set} = $gene_set_size;
                                    # rank filtered data by each column M, A, P independently
                                    my %gene_set_id_ranks;
                                    if (defined $input_data_file->metadata->{gs_m_val_thres} and 
                                        defined $input_data_file->metadata->{gs_m_val_thres}->[$contrast_idx] and
                                        is_numeric($input_data_file->metadata->{gs_m_val_thres}->[$contrast_idx])) {
                                        my @m_ranked_gene_set_ids = 
                                             map { $_->[0] }
                                            sort {
                                                $gene_set eq 'up' ? $b->[$input_data_file->M_idx] <=> $a->[$input_data_file->M_idx] :
                                                $gene_set eq 'dn' ? $a->[$input_data_file->M_idx] <=> $b->[$input_data_file->M_idx] :
                                                $gene_set eq 'ar' ? $b->[$input_data_file->M_idx] <=> $a->[$input_data_file->M_idx] :
                                                confess("\U$gene_set\E not valid, there is a problem with code this should not happen")
                                            } @{$gene_set_data{$gene_set}};
                                        push @{$gene_set_id_ranks{$gene_set}{$m_ranked_gene_set_ids[$_]}}, $_ + 1 for 0 .. $#m_ranked_gene_set_ids;
                                    }
                                    if (defined $input_data_file->metadata->{gs_a_val_thres} and 
                                        defined $input_data_file->metadata->{gs_a_val_thres}->[$contrast_idx] and
                                        is_numeric($input_data_file->metadata->{gs_a_val_thres}->[$contrast_idx])) {
                                        my @a_ranked_gene_set_ids = 
                                             map { $_->[0] }
                                            sort {
                                                $gene_set eq 'up' ? $b->[$input_data_file->A_idx] <=> $a->[$input_data_file->A_idx] :
                                                $gene_set eq 'dn' ? $b->[$input_data_file->A_idx] <=> $a->[$input_data_file->A_idx] :
                                                $gene_set eq 'ar' ? $b->[$input_data_file->A_idx] <=> $a->[$input_data_file->A_idx] :
                                                confess("\U$gene_set\E not valid, there is a problem with code this should not happen")
                                            } @{$gene_set_data{$gene_set}};
                                        push @{$gene_set_id_ranks{$gene_set}{$a_ranked_gene_set_ids[$_]}}, $_ + 1 for 0 .. $#a_ranked_gene_set_ids;
                                    }
                                    if (defined $input_data_file->metadata->{gs_p_val_thres} and 
                                        defined $input_data_file->metadata->{gs_p_val_thres}->[$contrast_idx] and
                                        is_numeric($input_data_file->metadata->{gs_p_val_thres}->[$contrast_idx])) {
                                        my @p_ranked_gene_set_ids = 
                                             map { $_->[0] }
                                            sort {
                                                $gene_set eq 'up' ? $a->[$input_data_file->P_idx] <=> $b->[$input_data_file->P_idx] :
                                                $gene_set eq 'dn' ? $a->[$input_data_file->P_idx] <=> $b->[$input_data_file->P_idx] :
                                                $gene_set eq 'ar' ? $a->[$input_data_file->P_idx] <=> $b->[$input_data_file->P_idx] :
                                                confess("\U$gene_set\E not valid, there is a problem with code this should not happen")
                                            } @{$gene_set_data{$gene_set}};
                                        push @{$gene_set_id_ranks{$gene_set}{$p_ranked_gene_set_ids[$_]}}, $_ + 1 for 0 .. $#p_ranked_gene_set_ids;
                                    }
                                    # compute average rank from arrayref of ranks and replace arrayref with average rank
                                    $gene_set_id_ranks{$gene_set}{$_} = 
                                        round(sum(@{$gene_set_id_ranks{$gene_set}{$_}}) / scalar(@{$gene_set_id_ranks{$gene_set}{$_}})) 
                                        for keys %{$gene_set_id_ranks{$gene_set}};
                                    # sort and extract IDs by rank and remove lowest ranked IDs to get within $gs_max_size
                                    my %reduced_gene_set_ids = map { $_ => 1 } (
                                        sort { $gene_set_id_ranks{$gene_set}{$a} <=> $gene_set_id_ranks{$gene_set}{$b} }
                                        keys %{$gene_set_id_ranks{$gene_set}}
                                    )[0 .. $gs_max_size - 1];
                                    # create new reduced gene set
                                    @{$gene_set_data{"${gene_set}r"}} = grep { $reduced_gene_set_ids{$_->[0]} } @{$file_data{$gene_set}};
                                }
                                # check gene set pass min size threshold and throw gene set error if too small
                                elsif ($gene_set_size < $gs_min_size) {
                                    push @{$gene_set_errors[$contrast_idx]}, "\U$gene_set\E has a size of $gene_set_size which is below the minimum $gs_min_size";
                                }
                            }
                        }
                        # otherwise if no thresholds defined create gene sets using target sizes
                        else {
                            $target_gs_sizes{up} = $CTK_DATA_DEFAULT_GENE_SET_SIZE unless defined $target_gs_sizes{up};
                            $target_gs_sizes{dn} = $CTK_DATA_DEFAULT_GENE_SET_SIZE unless defined $target_gs_sizes{dn};
                            $target_gs_sizes{ar} = ($target_gs_sizes{up} + $target_gs_sizes{dn}) <= $gs_max_size
                                                 ? $target_gs_sizes{up} + $target_gs_sizes{dn}
                                                 : $gs_max_size;
                            # sort each file data part by P value in *ascending* order (lowest P) and then
                            # take first target_gs_up_size and target_gs_dn_size genes from each part
                            for my $gene_set (qw(up dn ar)) {
                                @{$gene_set_data{$gene_set}} = scalar(@{$file_data{$gene_set}}) > $target_gs_sizes{$gene_set}
                                    ? (sort { $a->[$input_data_file->P_idx] <=> $b->[$input_data_file->P_idx] } @{$file_data{$gene_set}})[0 .. $target_gs_sizes{$gene_set} - 1]
                                    : sort { $a->[$input_data_file->P_idx] <=> $b->[$input_data_file->P_idx] } @{$file_data{$gene_set}};
                            }
                        }
                    }
                    # otherwise do gene sets creation using M values
                    else {
                        # create gene sets using M-A-P thresholds if specified
                        if (0) {
                            # --> finish M value threshold methodology same as for P value above <--
                        }
                        # otherwise if no thresholds specified create gene sets using target sizes
                        else {
                            # sort file data rows by M value in *descending* order (highest M) and then
                            # take first target_gs_up_size genes and last target_gs_dn_size genes from sorted data
                            @{$gene_set_data{up}} = (
                                sort {
                                    $b->[$input_data_file->M_idx] <=> $a->[$input_data_file->M_idx]
                                } @{$input_data_file->processed_data->[$contrast_idx]}
                            )[0 .. $target_gs_sizes{up} - 1];
                            @{$gene_set_data{dn}} = (
                                sort {
                                    $a->[$input_data_file->M_idx] <=> $b->[$input_data_file->M_idx]
                                } @{$input_data_file->processed_data->[$contrast_idx]}
                            )[-$target_gs_sizes{dn} .. -1];
                            @{$gene_set_data{ar}} = (@{$gene_set_data{up}}, @{$gene_set_data{dn}});
                        }
                    }
                    # init @ar_gene_set_data if @up_gene_set_data or @dn_gene_set_data don't have anything
                    @{$gene_set_data{ar}} = () unless @{$gene_set_data{up}} and @{$gene_set_data{dn}};
                    for my $gene_set (map(lc, @CTK_DATA_CONTRAST_GENE_SET_TYPE_SUFFIXES)) {
                        next unless defined $gene_set_data{$gene_set};
                        # calculate some gene set stats and do some gene set checks
                        my %gene_set_stats;
                        my @gene_set_abs_ms = map { abs($_->[$input_data_file->M_idx]) } @{$gene_set_data{$gene_set}};
                        $gene_set_stats{$gene_set}{min_abs_m} = min(@gene_set_abs_ms);
                        $gene_set_stats{$gene_set}{max_abs_m} = max(@gene_set_abs_ms);
                        if (!$skip_threshold_checks and @{$gene_set_data{$gene_set}} and $gene_set_stats{$gene_set}{min_abs_m} < $CTK_DATA_GENE_SET_MIN_ABS_M) {
                            push @{$gene_set_errors[$contrast_idx]}, 
                                "\U$gene_set\E gene set has an abs M value $gene_set_stats{$gene_set}{min_abs_m} which is below minimum threshold of $CTK_DATA_GENE_SET_MIN_ABS_M";
                        }
                        if (defined $input_data_file->P_idx) {
                            my @gene_set_ps = map { $_->[$input_data_file->P_idx] } @{$gene_set_data{$gene_set}};
                            $gene_set_stats{$gene_set}{max_p} = max(@gene_set_ps);
                            if (!$skip_threshold_checks and @{$gene_set_data{$gene_set}} and $gene_set_stats{$gene_set}{max_p} > $CTK_DATA_GENE_SET_MAX_P) {
                                push @{$gene_set_errors[$contrast_idx]}, 
                                    "\U$gene_set\E gene set has a P value $gene_set_stats{$gene_set}{max_p} which is above maximum threshold of $CTK_DATA_GENE_SET_MAX_P";
                            }
                            # sort gene set by rank using P value then M
                            nrnkeysort_inplace { $_->[$input_data_file->P_idx], $_->[$input_data_file->M_idx] } @{$gene_set_data{$gene_set}};
                        }
                        else {
                            # sort gene set by rank using M
                            rnkeysort_inplace { $_->[$input_data_file->M_idx] } @{$gene_set_data{$gene_set}};
                        }
                        $gene_sets_arrayref->[$contrast_idx]->{$gene_set} = @{$gene_set_data{$gene_set}} ? {
                            original_size => $gene_set_original_size{$gene_set} || undef,
                            min_abs_m     => $gene_set_stats{$gene_set}{min_abs_m},
                            max_abs_m     => $gene_set_stats{$gene_set}{max_abs_m},
                            max_p         => $gene_set_stats{$gene_set}{max_p},
                            id_ranks      => { map { $gene_set_data{$gene_set}[$_][0] => $_ + 1 } 0 .. $#{$gene_set_data{$gene_set}} },
                        } : undef;
                    }
                    # for debugging
                    #print Dumper(\%gene_set_data, $gene_sets_arrayref);
                }
            }
        }
        # gene set
        elsif ($input_data_file->isa('Confero::DataFile::IdList')) {
            # no need to do anything for now
        }
        if (!@gene_set_errors) {
            # write output report file
            my $report_str = "Check/Map/Collapse " . $input_data_file->data_type_common_name . " Report:\n\n" . $input_data_file->report;
            if ($input_data_file->isa('Confero::DataFile::IdMAPS')) {
                #my $dataset_id = construct_id($input_data_file->dataset_name);
                #$report_str .= "\nGene Set Report:\n\nDataset $dataset_id\n\n";
                $report_str .= "\nGene Set Report:\n\n";
                for my $contrast_idx (0 .. $#{$input_data_file->processed_data}) {
                    my $contrast_id = construct_id($input_data_file->dataset_name, $input_data_file->metadata->{contrast_names}->[$contrast_idx]);
                    my $has_gene_set_data;
                    $report_str .= "Contrast $contrast_id\n";
                    for my $gene_set_type (@CTK_DATA_CONTRAST_GENE_SET_TYPE_SUFFIXES) {
                        my $gene_set_type_key = lc($gene_set_type);
                        next unless defined $gene_sets_arrayref->[$contrast_idx]->{$gene_set_type_key};
                        my $gene_set_id = construct_id($input_data_file->dataset_name, $input_data_file->metadata->{contrast_names}->[$contrast_idx], $gene_set_type);
                        $report_str .= (defined $gene_sets_arrayref->[$contrast_idx]->{$gene_set_type_key}
                                     ? "    Gene Set $gene_set_id\n" .
                                       "        Num Genes  = " . scalar(keys %{$gene_sets_arrayref->[$contrast_idx]->{$gene_set_type_key}->{id_ranks}}) . 
                                       #($gene_sets_arrayref->[$contrast_idx]->{$gene_set_key}->{original_size} 
                                       #  ? " (reduced from $gene_sets_arrayref->[$contrast_idx]->{$gene_set_type_key}->{original_size})" 
                                       #  : '') 
                                       "\n" .
                                       "        Min abs(M) = $gene_sets_arrayref->[$contrast_idx]->{$gene_set_type_key}->{min_abs_m}\n" .
                                       "        Max abs(M) = $gene_sets_arrayref->[$contrast_idx]->{$gene_set_type_key}->{max_abs_m}\n" .
                                       (defined $input_data_file->P_idx 
                                          ? 
                                       "        Max P      = $gene_sets_arrayref->[$contrast_idx]->{$gene_set_type_key}->{max_p}\n" 
                                          : '') 
                                     : '');
                        $has_gene_set_data++;
                    }
                    $report_str .= "        No gene sets generated (by request)\n" unless $has_gene_set_data;
                    $report_str .= "\n";
                }
            }
            else {
                #my $gene_set_id = construct_id($input_data_file->dataset_name);
                #$report_str .= "\n\nGene Set $gene_set_id\n\n";
            }
            # everything OK, write all outputs and return required data
            $report_file_path = \my $in_memory_report_file unless defined $report_file_path;
            $self->_write_report_file($report_file_path, $report_str, $output_as_html);
            $input_data_file->write_processed_file($output_file_path, $output_as_gene_symbols) unless $no_processed_file_output;
            $input_data_file->write_debug_file($debug_file_path) if defined $debug_file_path;
            return ($input_data_file, $report_file_path, $output_as_html, $gene_sets_arrayref);
        }
        # gene set errors
        else {
            # write output error report
            my $error_report_str = "Gene Set Errors:\n\n";
            for my $contrast_idx (0 .. $#{$input_data_file->processed_data}) {
                if (defined $gene_set_errors[$contrast_idx]) {
                    $error_report_str .= "Contrast " . ($contrast_idx + 1) . " [" . $input_data_file->metadata->{contrast_names}->[$contrast_idx] . 
                        "]:\n" . join("\n", @{$gene_set_errors[$contrast_idx]}) . "\n\n";
                }
            }
            $self->_append_to_report_file($report_file_path, "GENE SET CHECKS FAILED\n\n$error_report_str", $output_as_html) if defined $report_file_path;
            $input_data_file->write_debug_file($debug_file_path) if defined $debug_file_path;
            croak($error_report_str);
        }
    }
    # input data file errors
    else {
        # write output error report
        my $error_report_str = $input_data_file->data_type_common_name . " Data Errors:\n* " . join("\n* ", @{$input_data_file->data_errors});
        $self->_append_to_report_file($report_file_path, "DATA FILE CHECK/MAP FAILED\n\n$error_report_str\n", $output_as_html) if defined $report_file_path;
        $input_data_file->write_debug_file($debug_file_path) if defined $debug_file_path;
        croak($error_report_str);
    }
}

sub submit_data_file {
    my $self = shift;
    # arguments
    # required: [input data file object], [report file path], [output as HTML flag]
    # optional (for submission): [gene sets arrayref]
    # reprocess_submission: [Confero DB object], [existing dataset or gene set object], [gene objects hashref]
    # additional optional: [gene info hashref], [overwrite existing flag]
    my ($input_data_file, $report_file_path, $output_as_html, $gene_sets_arrayref, $cfo_db, $set_db_obj, $genes_hashref, $overwrite_existing) = @_;
    $overwrite_existing = 0 if !defined $overwrite_existing or $overwrite_existing ne '1';
    my $reprocess_submission = (defined $cfo_db or defined $set_db_obj) ? 1 : 0;
    #my ($repo_source_file, @repo_mapped_files);
    eval {
        # instantiate a new Confero DB object only if I'm not reprocess submitting and don't have an existing DB object
        $cfo_db = Confero::DB->new() if !$reprocess_submission;
        my $submit_txn_coderef = sub {
            # not doing file system-based data file storage anymore
            # write out source data file to file repository directory
            #$repo_source_file = File::Temp->new(TEMPLATE => 'X' x 20,
            #                                    DIR      => $CTK_DATA_FILE_REPOSITORY_DIR,
            #                                    UNLINK   => 0);
            #                                    # SUFFIX   => '.txt');
            #open(my $source_fh, $input_data_file->file_path) or confess("Could not open ", $input_data_file->file_path, ": $!");
            #while (<$source_fh>) {
            #    print $repo_source_file $_;
            #}
            #close($source_fh);
            #close($repo_source_file);
            #chmod 0640, $repo_source_file->filename;
            my $source_file_data;
            {
                local $/;
                # 3-arg form of open because file_path could be a scalar reference in-memory file
                open(my $source_fh, '<', $input_data_file->file_path) or confess("Could not open ", $input_data_file->file_path, ": $!");
                $source_file_data = <$source_fh>;
                close($source_fh);
            }
            my $report_str;
            if (defined $report_file_path) {
                {
                    local $/;
                    # 3-arg form of open because file_path could be a scalar reference in-memory file
                    open(my $report_fh, '<', $report_file_path) or confess("Could not open report ", $report_file_path, ": $!");
                    $report_str = <$report_fh>;
                    close($report_fh);
                }
                # strip any leading/trailing HTML
                $report_str =~ s/^\s*<pre>//i;
                $report_str =~ s/<\/pre>\s*$//i;
            }
            my $organism = $cfo_db->resultset('Organism')->find_or_create({
                name => $input_data_file->organism_name,
                tax_id => $input_data_file->organism_tax_id,
            },{
                key => 'organism_un_tax_id',
            });
            # contrast dataset submission
            if ($input_data_file->isa('Confero::DataFile::IdMAPS')) {
                # no need can do everything using DBIx::Class OO syntax and no SQL :)
                # DBIx::Class (or any ORM) is a too slow during full Confero data reprocessing and reload when it has to insert
                # many thousands of gene_set_gene entries using add_to_genes method.  So I don't use
                # DBIx::Class here and go straight for the underlying DBI calls to speed up performance greatly
                #my $sth_insert_contrast_gene_set_gene = 
                #    $cfo_db->storage->dbh->prepare_cached('INSERT INTO contrast_gene_set_gene (contrast_gene_set_id, gene_id, rank) VALUES (?,?,?)');
                # if I have a new submission then create new dataset and source data file DB objects
                if (!$reprocess_submission) {
                    if (my $existing_db_obj = $cfo_db->resultset('ContrastDataSet')->find({
                        name => $input_data_file->dataset_name,
                    })) {
                        $overwrite_existing
                            ? $existing_db_obj->delete()
                            : croak(
                                $input_data_file->data_type_common_name, " '", 
                                construct_id($input_data_file->dataset_name), 
                                "' already exists in the database. To overwrite, enable flag to overwrite existing data."
                              );
                    }
                    $set_db_obj = $cfo_db->resultset('ContrastDataSet')->create({
                        name                     => $input_data_file->dataset_name,
                        source_data_file_id_type => $input_data_file->id_type,
                        source_data_file_name    => $input_data_file->orig_file_name,
                        collapsing_method        => $input_data_file->collapsing_method,
                        description              => $input_data_file->dataset_desc,
                        data_processing_report   => $report_str,
                        organism                 => $organism,
                        source_data_file         => {
                            data => $source_file_data,
                        },
                    });
                    # annotations
                    for my $field_name (keys %{$input_data_file->metadata}) {
                        next unless exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name} and exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_annot};
                        if (exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name} and exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_multi}) {
                            for my $field_value (@{$input_data_file->metadata->{$field_name}}) {
                                $cfo_db->resultset('ContrastDataSetAnnotation')->create({
                                    name     => $field_name,
                                    value    => $field_value,
                                    data_set => $set_db_obj,
                                });
                            }
                        }
                        else {
                            $cfo_db->resultset('ContrastDataSetAnnotation')->create({
                                name     => $field_name,
                                value    => $input_data_file->metadata->{$field_name},
                                data_set => $set_db_obj,
                            });
                        }
                    }
                }
                # for reprocessing only need to update contrast dataset data processing report
                else {
                    $set_db_obj->update({
                        data_processing_report => $report_str,
                    });
                }
                # get EntrezGene singleton data
                my $gene_info_hashref = Confero::EntrezGene->instance()->gene_info;
                my $add_gene_info_hashref = Confero::EntrezGene->instance()->add_gene_info;
                # submit each contrast in dataset
                for my $contrast_idx (0 .. $#{$input_data_file->processed_data}) {
                    # not doing file system-based data file storage anymore
                    # write out mapped gene contrast file to file repository directory
                    #my $repo_mapped_file = File::Temp->new(TEMPLATE => 'X' x 20,
                    #                                       DIR      => $CTK_DATA_FILE_REPOSITORY_DIR,
                    #                                       UNLINK   => 0);
                    #                                       #SUFFIX   => '.txt');
                    #push @repo_mapped_files, $repo_mapped_file;
                    #print $repo_mapped_file "Gene ID\t", join("\t", @{$input_data_file->column_headers}), "\n";
                    #for my $row_data (@{$input_data_file->processed_data->[$contrast_idx]}) {
                    #    print $repo_mapped_file join("\t", @{$row_data}), "\n";
                    #}
                    #close($repo_mapped_file);
                    #chmod 0640, $repo_mapped_file->filename;
                    # need to do this special initialization instead of just putting the 'my' within the 
                    # open statement because of Perl in-memory file weirdness and initialization warnings
                    # in 5.8.x, fixed by 5.10.x and 5.12.x
                    my $processed_file_data = '';
                    open(my $processed_fh, '>', \$processed_file_data) or confess("Could not create mappped contrast file data in-memory file: $!");
                    print $processed_fh "Gene ID\tGene Symbol\tDescription\t", join("\t", @{$input_data_file->column_headers}), "\n";
                    for my $row_data (@{$input_data_file->processed_data->[$contrast_idx]}) {
                        print $processed_fh join("\t", 
                            $row_data->[0], 
                            $gene_info_hashref->{$row_data->[0]}->{symbol},
                            $add_gene_info_hashref->{$row_data->[0]}->{description} || '', @{$row_data}[1 .. $#{$row_data}]
                        ), "\n";
                    }
                    close($processed_fh);
                    # if I have a new submission then create new contrast and data file DB objects
                    my $contrast;
                    if (!$reprocess_submission) {
                        $contrast = $cfo_db->resultset('Contrast')->create({
                            name      => $input_data_file->metadata->{contrast_names}->[$contrast_idx],
                            data_set  => $set_db_obj,
                            data_file => {
                                data => $processed_file_data,
                            },
                        });
                    }
                    # for reprocess_submission update existing contrast and data file DB
                    # objects and delete existing contrast gene sets which will
                    # be recreated
                    else {
                        $contrast = $set_db_obj->contrasts->find({
                            name => $input_data_file->metadata->{contrast_names}->[$contrast_idx],
                        });
                        $contrast->update({
                            name => $input_data_file->metadata->{contrast_names}->[$contrast_idx],
                        });
                        $contrast->data_file->update({
                            data => $processed_file_data,
                        });
                        # delete old contrast gene sets, they will be recreated below
                        $contrast->gene_sets->delete();
                    }
                    # create gene sets in DB if gene set data exists for contrast
                    for my $gene_set_type (@CTK_DATA_CONTRAST_GENE_SET_TYPE_SUFFIXES) {
                        my $gene_set_type_key = lc($gene_set_type);
                        if (defined $gene_sets_arrayref->[$contrast_idx] and defined $gene_sets_arrayref->[$contrast_idx]->{$gene_set_type_key}) {
                            my $gene_set = $cfo_db->resultset('ContrastGeneSet')->create({
                                type     => $gene_set_type,
                                contrast => $contrast,
                            });
                            my @gene_set_gene_data = 
                                map { [ $gene_set->id, $_ , $gene_sets_arrayref->[$contrast_idx]->{$gene_set_type_key}->{id_ranks}->{$_} ] } 
                                nsort keys %{$gene_sets_arrayref->[$contrast_idx]->{$gene_set_type_key}->{id_ranks}};
                            $cfo_db->populate('ContrastGeneSetGene', [
                                [qw( contrast_gene_set_id gene_id rank )],
                                @gene_set_gene_data,
                            ]);
                            # better faster populate used above
                            #for my $gene_id (@{$gene_sets_arrayref->[$contrast_idx]->{$gene_set_type_key}->{ids}}) {
                            #    $sth_insert_contrast_gene_set_gene->execute($gene_set->id, $gene_id, $rank);
                            #    #my $gene = defined $genes_hashref 
                            #    #         ? $genes_hashref->{$gene_id}
                            #    #         : $cfo_db->resultset('Gene')->find($gene_id);
                            #    #$gene_set->add_to_genes($gene);
                            #}
                        }
                    }
                }
            }
            # gene set submission
            else {
                # not needed anymore, efficient and fast DBIx::Class methods used now
                # DBIx::Class (or any ORM) is a too slow during full CTK data reprocessing and reload when it has to insert
                # many thousands of gene_set_gene entries using add_to_genes method.  So I don't use
                # DBIx::Class here and go straight for the underlying DBI calls to speed up performance greatly
                #my $sth_insert_gene_set_gene = $cfo_db->storage->dbh->prepare_cached('INSERT INTO gene_set_gene (gene_set_id, gene_id, rank) VALUES (?,?,?)');
                # for new submission create new gene set
                if (!$reprocess_submission) {
                    # MySQL has broken logic for multi-column UNIQUE CONSTRAINTs/KEYs/INDEXs if you have NULL values, 
                    # i.e. it does not just check non-NULL constraint columns for uniqueness and considers NULLs not
                    # the same but unique; so must do this logic in application code to always prevent duplicates from being inserted
                    if (my $existing_db_obj = $cfo_db->resultset('GeneSet')->find({
                        name => $input_data_file->gene_set_name,
                        contrast_name => $input_data_file->contrast_name,
                        type => $input_data_file->gene_set_type,
                    })) {
                        $overwrite_existing
                            ? $existing_db_obj->delete()
                            : croak(
                                $input_data_file->data_type_common_name, " '", 
                                construct_id($input_data_file->gene_set_name, $input_data_file->contrast_name, $input_data_file->gene_set_type), 
                                "' already exists in the database. To overwrite, enable flag to overwrite existing data."
                              );
                    }
                    $set_db_obj = $cfo_db->resultset('GeneSet')->create({
                        name                     => $input_data_file->gene_set_name,
                        source_data_file_id_type => $input_data_file->id_type,
                        source_data_file_name    => $input_data_file->orig_file_name,
                        contrast_name            => $input_data_file->contrast_name,
                        type                     => $input_data_file->gene_set_type,
                        description              => $input_data_file->gene_set_desc,
                        data_processing_report   => $report_str,
                        organism                 => $organism,
                        source_data_file         => {
                            data => $source_file_data,
                        },
                    });
                    # annotations
                    for my $field_name (keys %{$input_data_file->metadata}) {
                        next unless exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name} and exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_annot};
                        if (exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name} and exists $CTK_DATA_FILE_METADATA_FIELDS{$field_name}{is_multi}) {
                            for my $field_value (@{$input_data_file->metadata->{$field_name}}) {
                                $cfo_db->resultset('GeneSetAnnotation')->create({
                                    name     => $field_name,
                                    value    => $field_value,
                                    data_set => $set_db_obj,
                                });
                            }
                        }
                        else {
                            $cfo_db->resultset('GeneSetAnnotation')->create({
                                name     => $field_name,
                                value    => $input_data_file->metadata->{$field_name},
                                data_set => $set_db_obj,
                            });
                        }
                    }
                }
                # for reprocessing only need to update gene set data processing report
                else {
                    $set_db_obj->update({
                        data_processing_report => $report_str,
                    });
                }
                # delete old gene_set_genes
                $set_db_obj->gene_set_genes->delete();
                my $rank_counter;
                my @gene_set_gene_data = $input_data_file->metadata->{gs_is_ranked}
                                       ? map { [ $set_db_obj->id, $_, ++$rank_counter ] }       map { $_->[0] } @{$input_data_file->processed_data}
                                       : map { [ $set_db_obj->id, $_, undef           ] } nsort map { $_->[0] } @{$input_data_file->processed_data};
                # create new gene_set_genes
                # old method not used anymore, better and faster populate() method used instead
                #for my $gene_id (nsort map { $_->[0] } @{$input_data_file->processed_data}) {
                #    $sth_insert_gene_set_gene->execute($set_db_obj->id, $gene_id);
                #}
                $cfo_db->populate('GeneSetGene', [
                    [qw( gene_set_id gene_id rank )],
                    @gene_set_gene_data,
                ]);
            }
        };
        # start a new transaction if I'm not reprocess submitting, otherwise just execute coderef because I'm already in a transaction
        !$reprocess_submission ? $cfo_db->txn_do($submit_txn_coderef) : &$submit_txn_coderef();
    };
    if ($@) {
        # Not doing file system-based data file storage and management anymore
        #unlink $repo_source_file->filename;
        #unlink map { $_->filename } @repo_mapped_files;
        my $message = "Confero DB transaction failed";
        $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
        $self->_append_to_report_file($report_file_path, "$message, please contact $CTK_ADMIN_EMAIL_ADDRESS:\n$@", $output_as_html) if defined $report_file_path;
        confess("$message, please contact $CTK_ADMIN_EMAIL_ADDRESS:\n$@");
    }
    else {
        my $display_id = $input_data_file->isa('Confero::DataFile::IdMAPS') 
            ? construct_id($input_data_file->dataset_name)
            : construct_id($input_data_file->gene_set_name, $input_data_file->contrast_name, $input_data_file->gene_set_type);
        my $report_str = ($input_data_file->isa('Confero::DataFile::IdMAPS')
                           ? "Dataset '$display_id' incl. all contrasts and gene sets"
                           : "Gene set '$display_id'") . " successfully submitted to database\n\n";
        $self->_prepend_to_report_file($report_file_path, $report_str, $output_as_html) if defined $report_file_path;
    }
    return $set_db_obj;
}

sub create_rnk_deg_lists {
    my $self = shift;
    # arguments
    # required: [input contrast dataset file path] OR [Confero dataset or contrast ID], [ID type], [rank column], [output file path]
    # required only for multi ranked list creation: [output file directory path]
    # required only for multi ranked list creation from Galaxy: [output file Galaxy ID]
    # optional: [original contrast dataset file name]
    my ($input_file_path, $orig_input_file_name, $data_id, $rank_column, $output_id_type, $output_file_path, $output_file_galaxy_id, $output_dir_path);
    if (@_) {
        ($input_file_path, $orig_input_file_name, $data_id, $rank_column, $output_id_type, $output_file_path, $output_file_galaxy_id, $output_dir_path) = @_;
    }
    else {
        Getopt::Long::Configure('no_pass_through');
        GetOptions(
            'input-file=s'            => \$input_file_path,
            'orig-filename=s'         => \$orig_input_file_name,
            'data-id=s'               => \$data_id,
            'rank-column=s'           => \$rank_column,
            'output-file=s'           => \$output_file_path,
            'output-file-galaxy-id=i' => \$output_file_galaxy_id,
            'output-id-type=s'        => \$output_id_type,
            'output-dir=s'            => \$output_dir_path,
        ) || pod2usage(-verbose => 0);
        if (!defined $input_file_path and !defined $data_id) {
            pod2usage(-message => 'Missing required parameter: one of --input-file or --data-id', -verbose => 0);
        }
        if (defined $input_file_path and defined $data_id) {
            pod2usage(-message => 'Bad parameters: only one of --input-file or --data-id', -verbose => 0);
        }
        if (defined $output_dir_path and defined $output_file_path and !defined $output_file_galaxy_id) {
            pod2usage(-message => 'Bad parameters: only one of one of --output-file or --output-dir', -verbose => 0);
        }
        if (defined $output_file_galaxy_id and (!defined $output_dir_path or !defined $output_file_path)) {
            pod2usage(
                -message => 'Bad parameters: for Galaxy multiple ranked or DEG list output need all --output-file-galaxy-id, --output-file and --output-dir',
                -verbose => 0,
            );
        }
        if (defined $rank_column and $rank_column !~ /^(S|M|P)$/i) {
            pod2usage(-message => "Invalid rank column $rank_column")
        }
    }
    $rank_column ||= 'S';
    $rank_column = uc($rank_column);
    $output_id_type ||= 'EntrezGene';
    # get EntrezGene singleton data
    my $gene_info_hashref = Confero::EntrezGene->instance()->gene_info;
    my $add_gene_info_hashref = Confero::EntrezGene->instance()->add_gene_info;
    my ($dataset_name, $organism_name, $source_id_type, @contrast_data_hashrefs);
    my @input_errors;
    # input Confero data ID
    if (defined $data_id) {
        $data_id = fix_galaxy_replaced_chars($data_id, 1);
        if (is_valid_id($data_id)) {
            ($dataset_name, my $contrast_name) = deconstruct_id($data_id);
            eval {
                my $cfo_db = Confero::DB->new();
                $cfo_db->txn_do(sub {
                    # contrast dataset
                    if (defined $dataset_name and !defined $contrast_name) {
                        if (my $dataset = $cfo_db->resultset('ContrastDataSet')->find({
                            name => $dataset_name,
                        },{
                            prefetch => [
                                'organism', { 
                                    'contrasts' => 'data_file' 
                                },
                            ],
                            order_by => 'contrasts.id',
                        })) {
                            $organism_name = $dataset->organism->name;
                            $dataset_name = $dataset->name;
                            $source_id_type = $dataset->source_data_file_id_type;
                            my @contrasts = $dataset->contrasts;
                            for my $contrast (@contrasts) {
                                push @contrast_data_hashrefs, {
                                    name => $contrast->name,
                                    file_data_ref => \$contrast->data_file->data,
                                };
                            }
                        }
                        else {
                            push @input_errors, "Cannot find dataset '$dataset_name' in Confero DB";
                        }
                    }
                    # contrast
                    elsif (defined $dataset_name and defined $contrast_name) {
                        if (my $dataset = $cfo_db->resultset('ContrastDataSet')->find({
                                name => $dataset_name,
                            },{
                                prefetch => 'organism',
                        })) {
                            if (my $contrast = $dataset->contrasts->find({
                                    name => $contrast_name,
                                },{
                                    prefetch => 'data_file',
                            })) {
                                $organism_name = $dataset->organism->name;
                                $dataset_name = $dataset->name;
                                $source_id_type = $dataset->source_data_file_id_type;
                                push @contrast_data_hashrefs, {
                                    name => $contrast->name,
                                    file_data_ref => \$contrast->data_file->data,
                                };
                            }
                            else {
                                push @input_errors, "Cannot find dataset '$dataset_name' contrast '$contrast_name' in Confero DB";
                            }
                        }
                        else {
                            push @input_errors, "Cannot find dataset '$dataset_name' in Confero DB";
                        }
                    }
                });
            };
            if ($@) {
               my $message = "Confero DB transaction failed";
               $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
               confess("$message, please contact $CTK_ADMIN_EMAIL_ADDRESS: $@");
            }
        }
        else {
            push @input_errors, "ID '$data_id' is not a valid Confero ID";
        }
    }
    # input file
    else {
        $orig_input_file_name = fix_galaxy_replaced_chars($orig_input_file_name, 1) if defined $orig_input_file_name;
        my $input_data_file = Confero::DataFile->new($input_file_path, 'IdMAPS', $orig_input_file_name);
        if (!@{$input_data_file->data_errors}) {
            $dataset_name = $input_data_file->dataset_name;
            $organism_name = $input_data_file->organism_name;
            $source_id_type = $input_data_file->id_type;
            for my $contrast_idx (0 .. $#{$input_data_file->processed_data}) {
                # need to do this special initialization instead of just putting the 'my' within the 
                # open statement because of Perl in-memory file weirdness and initialization warnings
                # in 5.8.x, fixed by 5.10.x and 5.12.x
                my $processed_file_data = '';
                open(my $processed_fh, '>', \$processed_file_data) or confess("Could not create mappped contrast file data in-memory file: $!");
                print $processed_fh "Gene ID\tGene Symbol\tDescription\t", join("\t", @{$input_data_file->column_headers}), "\n";
                for my $row_data (@{$input_data_file->processed_data->[$contrast_idx]}) {
                    print $processed_fh join("\t", 
                        $row_data->[0], 
                        $gene_info_hashref->{$row_data->[0]}->{symbol},
                        $add_gene_info_hashref->{$row_data->[0]}->{description} || '', @{$row_data}[1 .. $#{$row_data}]
                    ), "\n";
                }
                close($processed_fh);
                push @contrast_data_hashrefs, {
                    name => $input_data_file->metadata->{contrast_names}->[$contrast_idx],
                    file_data_ref => \$processed_file_data,
                };
            }
        }
        # input data file errors
        else {
            push @input_errors, @{$input_data_file->data_errors};
        }
    }
    for my $contrast_data_hashref (@contrast_data_hashrefs) {
        open(my $contrast_fh, '<', $contrast_data_hashref->{file_data_ref}) or confess("Could not create contrast file data in-memory file: $!");
        my $header = <$contrast_fh>;
        close($contrast_fh);
        $header =~ s/\s+$//;
        my @header_fields = split /\t/, $header;
        my %column_header_idxs;
        $column_header_idxs{uc($header_fields[$_])} = $_ for 1 .. $#header_fields;
        if (!defined $column_header_idxs{$rank_column}) {
            push @input_errors, "Data column '$rank_column' doesn't exist in contrast file(s)";
        }
    }
    if ($output_id_type ne 'EntrezGene' and $output_id_type ne 'GeneSymbol') {
        push @input_errors, "Output ID type '$output_id_type' not valid, must be either EntrezGene or GeneSymbol";
    }
    if (defined $output_dir_path) {
        if (!-e $output_dir_path) {
            mkpath($output_dir_path, { mode => 0750 }) or confess("Could not create $output_dir_path ranked lists output directory: $!");
        }
        elsif (!-d $output_dir_path) {
            push @input_errors, "Output directory path $output_dir_path is not a valid directory";
        }
    }
    else {
        $output_dir_path = $WORKING_DIR;
    }
    if (!@input_errors) {
        for my $contrast_data_hashref (@contrast_data_hashrefs) {
            if (@contrast_data_hashrefs > 1) {
                $output_file_path = "$output_dir_path/" . (
                    defined $output_file_galaxy_id
                        ? "primary_${output_file_galaxy_id}_$contrast_data_hashref->{name}_visible_cfo" . 
                          (($rank_column eq 'S' or $rank_column eq 'M') ? 'rnk' : 'deg') . 'list'
                        : construct_id($dataset_name, $contrast_data_hashref->{name}) . 
                          (($rank_column eq 'S' or $rank_column eq 'M') ? '.rnk' : '.txt')
                );
            }
            elsif (!defined $output_file_path) {
                $output_file_path = "$output_dir_path/" . 
                    construct_id($dataset_name, $contrast_data_hashref->{name}) .
                    (($rank_column eq 'S' or $rank_column eq 'M') ? '.rnk' : '.txt');
            }
            open(my $output_fh, '>', $output_file_path) or confess("Could not create output file $output_file_path: $!");
            # write out metadata header
            print $output_fh "#\%dataset_name=\"$dataset_name\"\n",
                             "#\%contrast_name=\"$contrast_data_hashref->{name}\"\n",
                             "#\%organism=\"$organism_name\"\n",
                             "#\%id_type=$output_id_type\n",
                             "#\%source_id_type=$source_id_type\n",
                             "#\%rank_column=$rank_column\n";
            open(my $contrast_fh, '<', $contrast_data_hashref->{file_data_ref}) or confess("Could not create contrast file data in-memory file: $!");
            my $header = <$contrast_fh>;
            $header =~ s/\s+$//;
            my @header_fields = split /\t/, $header;
            my %column_header_idxs;
            $column_header_idxs{uc($header_fields[$_])} = $_ for 1 .. $#header_fields;
            while(<$contrast_fh>) {
                s/\s+$//;
                my @data_fields = split /\t/;
                print $output_fh $output_id_type eq 'EntrezGene' 
                        ? $data_fields[0] 
                        : $gene_info_hashref->{$data_fields[0]}->{symbol}, 
                    "\t", $data_fields[$column_header_idxs{uc($rank_column)}], "\n";
            }
            close($contrast_fh);
            close($output_fh);
        }
    }
    # input errors
    else {
        my $error_report_str = "Input Errors:\n* " . join("\n* ", @input_errors);
        $self->_write_report_file($output_file_path, $error_report_str, 0);
        croak($error_report_str);
    }
}

sub analyze_data {
    my $self = shift;
    # arguments
    # required: [input file path], , [data_type], [id type], [organism name], [report file path], [report directory path], [analysis algorithm]
    # optional: [analysis name], [filter annotations csv list] [filter organisms csv list] [filter gene set types csv], [filter boolean expression],
    # GSEA/ORA: [scoring scheme], [gene set db symbols comma separated list], [do AR analysis], [additional gene set db file paths arrayref] [p value cutoff]
    my ($input_file_path, $data_type, $id_type, $organism_name, $report_file_path, $report_dir_path, $working_dir_path, $analysis_algorithm, 
        $analysis_name, $filter_annotations_csv, $scoring_scheme, $gene_set_dbs_csv, $filter_organisms_csv, $filter_contrast_names_csv, 
        $filter_gene_set_types_csv, $filter_bool_expr_str, $do_ar_analysis, $gene_set_db_file_paths_arrayref, $p_val_cutoff, $debug);
    if (@_) {
        ($input_file_path, $data_type, $id_type, $organism_name, $report_file_path, $report_dir_path, $working_dir_path, $analysis_algorithm, 
         $analysis_name, $filter_annotations_csv, $scoring_scheme, $gene_set_dbs_csv, $filter_organisms_csv, $filter_contrast_names_csv, 
         $filter_gene_set_types_csv, $filter_bool_expr_str, $do_ar_analysis, $gene_set_db_file_paths_arrayref, $p_val_cutoff, $debug) = @_;
    }
    else {
        Getopt::Long::Configure('no_pass_through');
        GetOptions(
            'input-file|query-file=s'       => \$input_file_path,
            'report-file=s'                 => \$report_file_path,
            'analysis-name|orig-filename=s' => \$analysis_name,
            'data-type|query-type=s'        => \$data_type,
            'report-output-dir=s'           => \$report_dir_path,
            'working-dir=s'                 => \$working_dir_path,
            'id-type=s'                     => \$id_type,
            'organism=s'                    => \$organism_name,
            'analysis-algorithm=s'          => \$analysis_algorithm,
            'scoring-scheme=s'              => \$scoring_scheme,
            'gene-set-dbs=s'                => \$gene_set_dbs_csv,
            'gene-set-db-file=s@'           => \$gene_set_db_file_paths_arrayref,
            'filter-bool-expr=s'            => \$filter_bool_expr_str,
            'filter-annotations=s'          => \$filter_annotations_csv,
            'filter-organisms=s'            => \$filter_organisms_csv,
            'filter-contrast-names=s'       => \$filter_contrast_names_csv,
            'filter-gene-set-types=s'       => \$filter_gene_set_types_csv,
            'do-ar-analysis'                => \$do_ar_analysis,
            'p-val-cutoff=f'                => \$p_val_cutoff,
            'debug'                         => \$debug,
        ) || pod2usage(-verbose => 0);
        pod2usage(-message => 'Missing required parameter --input-file', -verbose => 0) unless defined $input_file_path;
        #pod2usage(-message => 'Missing required parameter --data-type', -verbose => 0) unless defined $data_type;
        #pod2usage(-message => 'Missing required parameter --analysis-algorithm', -verbose => 0) unless defined $analysis_algorithm;
    }
    $analysis_algorithm ||= 'GseaPreranked';
    $data_type ||= 'RankedList';
    my @input_errors;
    for my $gene_set_db_file_path (@{$gene_set_db_file_paths_arrayref}) {
        push @input_errors, "$gene_set_db_file_path not a valid file" unless -f $gene_set_db_file_path;
    }
    if (!$gene_set_dbs_csv and !@{$gene_set_db_file_paths_arrayref}) {
        push @input_errors, 'No gene set DBs specified, please specify at least one gene set DB via --gene-set-dbs or --gene-set-db-file';
    }
    # set working dir to abs path and check
    if (defined $working_dir_path) {
        $working_dir_path = File::Spec->rel2abs($working_dir_path);
        if (-e $working_dir_path and !-d $working_dir_path) {
            push @input_errors, "Working directory path $working_dir_path is not a valid directory";
        }
    }
    if ($analysis_algorithm =~ /GseaPreranked/i) {
        push @input_errors, "$CTK_GSEA_MAPPING_FILE_DIR/GeneSymbol.chip annotation file not found" unless -f "$CTK_GSEA_MAPPING_FILE_DIR/GeneSymbol.chip";
        push @input_errors, "$CTK_GSEA_MAPPING_FILE_DIR/EntrezGene.chip annotation file not found" unless -f "$CTK_GSEA_MAPPING_FILE_DIR/EntrezGene.chip";
    }
    if (!@input_errors) {
        if (defined $analysis_name) {
            # fix analysis_name for names generated by Galaxy dynamic multi-dataset output
            if ($analysis_name =~ /(Ranked|DEG)\s+List\s+for\s+/i) {
                $analysis_name =~ s/(Ranked|DEG)\s+List\s+for\s+//i;
                $analysis_name =~ s/\s+\((.+?)\)$/ \[$1\]/;
                #$analysis_name .= '.rnk';
            }
        }
        else {
            $analysis_name = fileparse($input_file_path, qr/\.[^.]*/);
        }
        # convert analysis name spaces
        $analysis_name =~ s/\s+/_/g;
        # set optional parameters to undef if "empty"
        for my $param ($filter_annotations_csv, $filter_organisms_csv, $filter_contrast_names_csv, $filter_gene_set_types_csv) {
            $param = undef if defined $param and $param =~ m/^(\s*|none|\?)$/i;
        }
        my %filter_annotations;
        if (defined $filter_annotations_csv) {
            for (split /,/, $filter_annotations_csv) {
                $_ = fix_galaxy_replaced_chars($_, 1);
                my ($name, $value) = split /$CTK_GALAXY_ANNOT_NV_SEPARATOR/o;
                $filter_annotations{$name} = $value;
            }
        }
        my %filter_organisms = map { fix_galaxy_replaced_chars($_, 1) => 1 } split /,/, $filter_organisms_csv if defined $filter_organisms_csv;
        my %filter_contrast_names = map { fix_galaxy_replaced_chars($_, 1) => 1 } split /,/, $filter_contrast_names_csv if defined $filter_contrast_names_csv;
        my %filter_gene_set_types = map { fix_galaxy_replaced_chars($_, 1) => 1 } split /,/, $filter_gene_set_types_csv if defined $filter_gene_set_types_csv;
        # create input file object and load/check/process data
        my $input_file = Confero::DataFile->new($input_file_path, $data_type, $analysis_name, $id_type, undef, 1, $organism_name);
        if (!@{$input_file->data_errors}) {
            if (defined $working_dir_path) {
                if (!-e $working_dir_path) {
                    mkpath($working_dir_path, { mode => 0750 }) or confess("Could not create $working_dir_path analysis working directory: $!");
                }
            }
            else {
                $working_dir_path = $WORKING_DIR;
            }
            # chdir to working dir
            chdir($working_dir_path) or confess("Could not chdir to $working_dir_path: $!");
            # GSEA Preranked analysis
            if ($analysis_algorithm =~ /GseaPreranked/i) {
                # GSEA needs file to end with .rnk extension and in Galaxy datafile doesn't have
                # original name so lets copy and rename Galaxy datafile and put it into the 
                # job working directory
                #my $input_file_basename = fileparse($input_file_path, qr/\.[^.]*/);
                #copy($input_file_path, "$working_dir_path/$input_file_basename.rnk") 
                #    or confess("Could not copy input file to job working directory: $!");
                #$input_file_path = "$working_dir_path/$input_file_basename.rnk";
                # make GSEA friendly; GSEA doesn't like hyphens/dashes
                $analysis_name =~ s/-/_/g;
                my $orig_input_file_basename = $analysis_name =~ /\.\w+$/ ? fileparse($analysis_name, qr/\.[^.]*/) : $analysis_name;
                #$input_file->write_processed_file("$working_dir_path/$orig_input_file_basename.rnk");
                #copy($input_file_path, "$working_dir_path/$orig_input_file_basename.rnk") 
                #    or confess("Could not copy input file to job working directory: $!");
                # fix rnk file for GSEA consumption
                $input_file->write_processed_file(\my $in_memory_gene_input_file_data);
                open(my $input_rnk_fh, '<', $input_file ? \$in_memory_gene_input_file_data : $input_file_path) 
                    or confess("Could not open ", $input_file ? 'in-memory file' : $input_file_path, ": $!");
                my @input_rnk_list_lines = <$input_rnk_fh>;
                close($input_rnk_fh);
                my $gene_info_hashref = Confero::EntrezGene->instance()->gene_info;
                my %output_rnk_list_data;
                my $output_rnk_list_order = 0;
                for (@input_rnk_list_lines) {
                    next if m/^#/;
                    s/\s+$//;
                    my ($gene_id, $rank) = split /\t/;
                    # check if ranked list could have gene IDs with additional species (e.g. controls like AFFX_MurIL10_at) which 
                    # then map to the same official gene symbol but we should only keep the data line of the organism of interest
                    # if GSEA has symbol duplicate lines it *arbitrarily* picks one which is *not* what we want
                    my $output_rnk_list_id = uc($input_file ? $gene_info_hashref->{$gene_id}->{symbol} : $gene_id);
                    if (!exists $output_rnk_list_data{$output_rnk_list_id}) {
                        @{$output_rnk_list_data{$output_rnk_list_id}}{qw(gene_id rank order)} = ($gene_id, $rank, ++$output_rnk_list_order);
                    }
                    # have duplicate ranked list ID
                    elsif ($gene_info_hashref->{$gene_id}->{organism_tax_id} ne 
                           $gene_info_hashref->{$output_rnk_list_data{$output_rnk_list_id}{gene_id}}->{organism_tax_id}) {
                        # if current data line is from organism of interest then replace previous ranked list data with 
                        # same ID with current data since previous data is from another organism
                        if ($gene_info_hashref->{$gene_id}->{organism_tax_id} eq $input_file->organism_tax_id) {
                            @{$output_rnk_list_data{$output_rnk_list_id}}{qw(gene_id rank order)} = ($gene_id, $rank, ++$output_rnk_list_order);
                        }
                    }
                    # duplicate ranked list ID error
                    else {
                        confess(
                            "Problem with ranked list, have two different data lines (gene IDs $gene_id, $output_rnk_list_data{$output_rnk_list_id}{gene_id}) ",
                            "which map to same gene symbol ($output_rnk_list_id) and are for same organism"
                        );
                    }
                }
                open(my $output_rnk_fh, '>', "$working_dir_path/$orig_input_file_basename.rnk") 
                    or confess("Could not create $working_dir_path/$orig_input_file_basename.rnk: $!");
                for my $output_rnk_list_id (nkeysort { $output_rnk_list_data{$_}{order} } keys %output_rnk_list_data) {
                    print $output_rnk_fh "$output_rnk_list_id\t", $do_ar_analysis 
                        ? abs($output_rnk_list_data{$output_rnk_list_id}{rank}) 
                        : $output_rnk_list_data{$output_rnk_list_id}{rank}, "\n";
                }
                close($output_rnk_fh);
                # check and then map gene set DBs to file paths and names
                my (@gene_set_db_files, $gene_set_db_files_csv, $do_cfo_db_contrasts_analysis, $do_cfo_db_uploads_analysis);
                if (defined $gene_set_dbs_csv) {
                    for my $gene_set_db (split /,/, $gene_set_dbs_csv) {
                        # Confero DB
                        if ($gene_set_db =~ /^cfodb/i) {
                            if ($gene_set_db =~ /^cfodb\.contrasts/i) {
                                $do_cfo_db_contrasts_analysis++;
                            }
                            elsif ($gene_set_db =~ /^cfodb\.uploads/i) {
                                $do_cfo_db_uploads_analysis++;
                            }
                            else {
                                $do_cfo_db_contrasts_analysis++;
                                $do_cfo_db_uploads_analysis++;
                            }
                        }
                        # MSigDB, GeneSigDB
                        else {
                            confess("Gene Set DB '$gene_set_db' not valid!") unless exists $CTK_GSEA_GSDBS{$gene_set_db} and defined $CTK_GSEA_GSDBS{$gene_set_db};
                            # change up for AR-only MSigDB analysis
                            $gene_set_db = "$1.ar" if $do_ar_analysis and $gene_set_db =~ /^(msigdb\.c2\.(?:|all|cgp))/i;
                            confess("Gene Set DB '$gene_set_db' file missing!") unless -f  "$CTK_GSEA_GENE_SET_DB_DIR/$CTK_GSEA_GSDBS{$gene_set_db}";
                            push @gene_set_db_files, "$CTK_GSEA_GENE_SET_DB_DIR/$CTK_GSEA_GSDBS{$gene_set_db}";
                        }
                    }
                }
                # additional specified gene set db file paths
                for my $gene_set_db_file_path (@{$gene_set_db_file_paths_arrayref}) {
                    # check for GSEA friendly paths and names and fix as necessary
                    if ($gene_set_db_file_path !~ /-/) {
                        push @gene_set_db_files, $gene_set_db_file_path;
                    }
                    else {
                        my $gene_set_db_file_name = fileparse($gene_set_db_file_path);
                        $gene_set_db_file_name =~ s/-/_/g;
                        copy($gene_set_db_file_path, "$working_dir_path/$gene_set_db_file_name") 
                            or confess("Could not copy gene set db file $gene_set_db_file_path");
                        push @gene_set_db_files, "$working_dir_path/$gene_set_db_file_name";
                    }
                }
                # create snapshot gmt file of Confero gene set DB collection(s)
                # temp file fh vars defined here because file gets deleted when out 
                # of scope and we need it all the way through the end of the analysis
                my ($cfo_db_contrasts_gmt_fh, $cfo_db_uploads_gmt_fh);
                if ($do_cfo_db_contrasts_analysis or $do_cfo_db_uploads_analysis) {
                    if ($do_cfo_db_contrasts_analysis) {
                        $cfo_db_contrasts_gmt_fh = File::Temp->new(
                            TEMPLATE => 'cfodb.contrasts.' . 'X' x 10,
                            DIR      => $working_dir_path,
                            SUFFIX   => '.gmt',
                            UNLINK   => $debug ? 0 : 1,
                        );
                        chmod(0640, $cfo_db_contrasts_gmt_fh->filename);
                    }
                    if ($do_cfo_db_uploads_analysis) {
                        $cfo_db_uploads_gmt_fh = File::Temp->new(
                            TEMPLATE => 'cfodb.uploads.' . 'X' x 10,
                            DIR      => $working_dir_path,
                            SUFFIX   => '.gmt',
                            UNLINK   => $debug ? 0 : 1,
                        );
                        chmod(0640, $cfo_db_uploads_gmt_fh->filename);
                    }
                    eval {
                        my $cfo_db = Confero::DB->new();
                        $cfo_db->txn_do(sub {
                            if ($do_cfo_db_contrasts_analysis) {
                                my @contrast_datasets = $cfo_db->resultset('ContrastDataSet')->search(undef, {
                                    prefetch => [
                                        'organism',
                                        { 'contrasts' => 'gene_sets' }
                                    ],
                                })->all();
                                CONTRAST_DATASET: for my $contrast_dataset (@contrast_datasets) {
                                    next CONTRAST_DATASET if %filter_organisms and !exists $filter_organisms{$contrast_dataset->organism->name};
                                    CONTRAST: for my $contrast ($contrast_dataset->contrasts) {
                                        next CONTRAST if %filter_contrast_names and !exists $filter_contrast_names{$contrast->name};
                                        my %contrast_dataset_annotations = map { $_->name => $_->value } $contrast_dataset->annotations;
                                        for my $annotation_name (keys %filter_annotations) {
                                            next CONTRAST if %filter_annotations and (!defined $contrast_dataset_annotations{$annotation_name} or 
                                                $contrast_dataset_annotations{$annotation_name} ne $filter_annotations{$annotation_name});
                                        }
                                        CONTRAST_GENE_SET: for my $gene_set ($contrast->gene_sets) {
                                            next CONTRAST_GENE_SET if (%filter_gene_set_types and !exists $filter_gene_set_types{$gene_set->type}) or
                                                                      # AR-only not selected skip all _AR(r)
                                                                      (!$do_ar_analysis and (defined $gene_set->type and $gene_set->type =~ /^AR(r|)$/i)) or
                                                                      # AR-only analysis selected so skip all thats not _AR(r)
                                                                      ($do_ar_analysis and (!defined $gene_set->type or $gene_set->type !~ /^AR(r|)$/i));
                                            my @gene_ids = map {
                                                $CTK_GSEA_GSDB_ID_TYPE eq 'entrez' ? $_->gene->id : uc($_->gene->symbol)
                                            } $gene_set->gene_set_genes;
                                            my $gene_set_id = construct_id($contrast_dataset->name, $contrast->name, $gene_set->type);
                                            print $cfo_db_contrasts_gmt_fh "\U$gene_set_id\E\thttp://$CTK_WEB_SERVER_HOST:$CTK_WEB_SERVER_PORT/view/contrast_gene_set/$gene_set_id\t", join("\t", natsort @gene_ids), "\n";
                                        }
                                    }
                                }
                                close($cfo_db_contrasts_gmt_fh);
                            }
                            if ($do_cfo_db_uploads_analysis) {
                                my @gene_sets = $cfo_db->resultset('GeneSet')->search(undef, {
                                    prefetch => [qw( organism annotations )],
                                })->all();
                                GENE_SET: for my $gene_set (@gene_sets) {
                                    next GENE_SET if (%filter_organisms and !exists $filter_organisms{$gene_set->organism->name}) or
                                                     (%filter_contrast_names and defined $gene_set->contrast_name and !exists $filter_contrast_names{$gene_set->contrast_name}) or
                                                     (%filter_gene_set_types and defined $gene_set->type and !exists $filter_gene_set_types{$gene_set->type}) or
                                                     # AR-only not selected so skip all _AR(r)
                                                     (!$do_ar_analysis and (defined $gene_set->type and $gene_set->type =~ /^AR(r|)$/i)) or
                                                     # AR-only analysis selected so skip all thats not _AR(r)
                                                     ($do_ar_analysis and (!defined $gene_set->type or $gene_set->type !~ /^AR(r|)$/i));
                                    my %gene_set_annotations = map { $_->name => $_->value } $gene_set->annotations;
                                    for my $annotation_name (keys %filter_annotations) {
                                        next GENE_SET if %filter_annotations and (!defined $gene_set_annotations{$annotation_name} or 
                                            $gene_set_annotations{$annotation_name} ne $filter_annotations{$annotation_name});
                                    }
                                    my @gene_ids = map {
                                        $CTK_GSEA_GSDB_ID_TYPE eq 'entrez' ? $_->gene->id : uc($_->gene->symbol)
                                    } $gene_set->gene_set_genes;
                                    my $gene_set_id = construct_id($gene_set->name, $gene_set->contrast_name, $gene_set->type);
                                    print $cfo_db_uploads_gmt_fh "\U$gene_set_id\E\thttp://$CTK_WEB_SERVER_HOST:$CTK_WEB_SERVER_PORT/view/gene_set/$gene_set_id\t", join("\t", natsort @gene_ids), "\n";
                                }
                                close($cfo_db_uploads_gmt_fh);
                            }
                        });
                    };
                    if ($@) {
                       my $message = "Confero DB transaction failed";
                       $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
                       confess("$message, please contact $CTK_ADMIN_EMAIL_ADDRESS: $@");
                    }
                    push(@gene_set_db_files, $cfo_db_contrasts_gmt_fh->filename) if $do_cfo_db_contrasts_analysis;
                    push(@gene_set_db_files, $cfo_db_uploads_gmt_fh->filename) if $do_cfo_db_uploads_analysis;
                    $gene_set_db_files_csv = join(',', @gene_set_db_files);
                }
                else {
                    $gene_set_db_files_csv = join(',', @gene_set_db_files);
                }
                # do free-text gene set DB filtering
                my $filtered_gsdb_gmt_fh;
                if (defined $filter_bool_expr_str) {
                    $filtered_gsdb_gmt_fh = File::Temp->new(
                        TEMPLATE => 'filtered.' . 'X' x 10,
                        DIR      => $working_dir_path,
                        SUFFIX   => '.gmt',
                        UNLINK   => $debug ? 0 : 1,
                    );
                    chmod(0640, $filtered_gsdb_gmt_fh->filename);
                    $filter_bool_expr_str = fix_galaxy_replaced_chars($filter_bool_expr_str, 1);
                    my (%filtered_gsdb_data, $current_operator);
                    my $bl_parser = Parse::BooleanLogic->new();
                    my $bl_expr_tree = $bl_parser->as_array($filter_bool_expr_str);
                    $bl_parser->walk($bl_expr_tree, {
                        #open_paren => sub {
                        #    
                        #},
                        #close_paren => sub {
                        #    
                        #},
                        operand => sub {
                            my %new_filtered_gsdb_data;
                            my $operand = $_[0]->{operand};
                            for my $gene_set_db_file (@gene_set_db_files) {
                                open(my $gsdb_fh, '<', $gene_set_db_file) or die "$!\n";
                                while (<$gsdb_fh>) {
                                    my ($gene_set_name) = split /\t/;
                                    next unless $gene_set_name =~ /$operand/i;
                                    # AND (intersect)
                                    if (defined $current_operator and uc($current_operator) eq 'AND') {
                                        $new_filtered_gsdb_data{$gene_set_name} = $_ if exists $filtered_gsdb_data{$gene_set_name};
                                    }
                                    # OR (union) or no current operator
                                    else {
                                        $filtered_gsdb_data{$gene_set_name} = $_;
                                    }
                                }
                                close($gsdb_fh);
                            }
                            %filtered_gsdb_data = %new_filtered_gsdb_data if defined $current_operator and uc($current_operator) eq 'AND';
                            # reset current operator
                            $current_operator = undef;
                        },
                        operator => sub {
                            $current_operator = $_[0];
                        },
                    });
                    print $filtered_gsdb_gmt_fh join('', values %filtered_gsdb_data) if %filtered_gsdb_data;
                    close($filtered_gsdb_gmt_fh);
                    $gene_set_db_files_csv = $filtered_gsdb_gmt_fh->filename;
                }
                # remove shell metacharacters in analysis name
                #$analysis_name = remove_shell_metachars($analysis_name);
                my $rnk_file_path = "$working_dir_path/$orig_input_file_basename.rnk";
                # set GSEA annotation chip file, currently now only GeneSymbol.chip
                # using my much better and up-to-date Confero created GeneSymbol.chip file instead of GSEA distribution GENE_SYMBOL.chip
                my @annot_files = "$CTK_GSEA_MAPPING_FILE_DIR/GeneSymbol.chip";
                my $annot_files_csv = join(',', @annot_files);
                # use system default scoring scheme if not specified
                $scoring_scheme ||= $CTK_GSEA_DEFAULT_SCORING_SCHEME;
                my $gsea_preranked_cmd = <<"                GSEA_CMD";
                $CTK_GSEA_JAVA_PATH -cp $CTK_GSEA_JAR_PATH \\
                -Xmx$CTK_GSEA_MAX_JAVA_HEAP_SIZE xtools.gsea.GseaPreranked \\
                -gmx "$gene_set_db_files_csv" \\
                -collapse false \\
                -mode Max_probe \\
                -norm meandiv \\
                -nperm $CTK_GSEA_NUM_PERMUTATIONS \\
                -rnk "$rnk_file_path" \\
                -scoring_scheme "$scoring_scheme" \\
                -rpt_label "${analysis_name}.analysis" \\
                -chip "$annot_files_csv" \\
                -include_only_symbols false \\
                -make_sets true \\
                -plot_top_x $CTK_GSEA_PLOT_TOP_X \\
                -rnd_seed timestamp \\
                -set_max $CTK_GSEA_GENE_SET_MAX \\
                -set_min $CTK_GSEA_GENE_SET_MIN \\
                -zip_report false \\
                -out $working_dir_path \\
                -gui false \\
                >> $working_dir_path/gsea.out 2>&1
                GSEA_CMD
                # Tidy up spaces for printing to gsea.out
                $gsea_preranked_cmd =~ s/^\s+//;
                $gsea_preranked_cmd =~ s/\s+$//;
                $gsea_preranked_cmd =~ s/ +/ /g;
                # Our GSEA needs these files in job working directory so it doesn't try to get them by FTP
                copy("$CTK_GSEA_MAPPING_FILE_DIR/GENE_SYMBOL.chip", "$working_dir_path/GENE_SYMBOL.chip") 
                    or confess("Could not copy $CTK_GSEA_MAPPING_FILE_DIR/GENE_SYMBOL.chip file to job working directory: $!");
                # not needed anymore
                #copy("$CTK_GSEA_MAPPING_FILE_DIR/SEQ_ACCESSION.chip", "$working_dir_path/SEQ_ACCESSION.chip") 
                #    or confess("Could not copy $CTK_GSEA_MAPPING_FILE_DIR/SEQ_ACCESSION.chip file to job working directory: $!");
                # Write full GSEA command to top of gsea.out
                open(my $gsea_trace_fh, '>', "$working_dir_path/gsea.out");
                print $gsea_trace_fh "$gsea_preranked_cmd\n";
                close($gsea_trace_fh);
                # Run GSEA command and if it flops get trace output
                if (system($gsea_preranked_cmd) != 0) {
                    my $trace;
                    {
                        local $/;
                        open(my $gsea_trace_fh, '<', "$working_dir_path/gsea.out");
                        $trace = <$gsea_trace_fh>;
                        close($gsea_trace_fh);
                    }
                    # not necessary anymore to clean up working directory (cannot be in the directory when trying to clean it)
                    #chdir "$working_dir_path/..";
                    #rmtree($working_dir_path, { keep_root => 1 });
                    confess("There was an error executing GSEA:\n$trace");
                }
                # clean up GENE_SYMBOL.chip local copy for Broad's GSEA broken jar
                unlink("$working_dir_path/GENE_SYMBOL.chip");
                # Now let's organize and move the analysis output
                opendir(my $working_dh, $working_dir_path) or confess("Could not open working directory: $!");
                my $analysis_results_dir = shift @{[grep { m/\Q$analysis_name\E\.analysis\.GseaPreranked\.\d+/i && -d } map { "$working_dir_path/$_" } readdir($working_dh)]};
                closedir($working_dh);
                # manipulate GSEA analysis result HTML files if we have an analysis Confero gene set DBs
                if ($do_cfo_db_contrasts_analysis or $do_cfo_db_uploads_analysis) {
                    opendir(my $results_dh, $analysis_results_dir) or confess("Could not open analysis results directory: $!");
                    my $html_file_na_pos_path = shift @{[ grep { m/gsea_report_for_na_pos_\d+\.html$/ && -f } map { "$analysis_results_dir/$_" } readdir($results_dh) ]};
                    seekdir($results_dh, 0) or confess("Could not reset analysis results directory for reading: $!");
                    my $html_file_na_neg_path = shift @{[ grep { m/gsea_report_for_na_neg_\d+\.html$/ && -f } map { "$analysis_results_dir/$_" } readdir($results_dh) ]};
                    closedir($results_dh);
                    $self->_modify_gsea_enrich_results_html_file($html_file_na_pos_path);
                    $self->_modify_gsea_enrich_results_html_file($html_file_na_neg_path);
                }
                # write ranked list metadata header to .confero_meta file
                open(my $cfo_meta_fh, '>', "$analysis_results_dir/.confero_meta") or confess("Could not create $analysis_results_dir/.confero_meta file: $!");
                print $cfo_meta_fh 
                    @{$input_file->_raw_metadata}
                        ? (join("\n", grep { !m/^#%\s*id_type=/i } @{$input_file->_raw_metadata}), "\n") 
                        : '', 
                    (!defined $input_file->metadata->{organism_name} and defined $input_file->organism_name) 
                        ? ("#\%organism=\"", $input_file->organism_name, "\"\n") 
                        : '',
                    (!defined $input_file->metadata->{contrast_names} and defined $input_file->contrast_name)
                        ? ("#\%contrast_name=\"", $input_file->contrast_name, "\"\n") 
                        : '',
                    @{$input_file->comments} 
                        ? (join("\n", @{$input_file->comments}), "\n") 
                        : '';
                close($cfo_meta_fh);
                if (defined $report_dir_path) {
                    dirmove($analysis_results_dir, $report_dir_path) or confess("Could not move analysis results directory: $!");
                }
                else {
                    $report_dir_path = $analysis_results_dir;
                }
                # manipulate GSEA analysis report summary file
                $self->_modify_gsea_results_summary_html_file("$report_dir_path/index.html");
                # not necessary anymore I can pass permanent output directory
                ## file path for the output directory passed to this program is the temporary one 
                ## that Galaxy creates inside the job working directory. After job completion it moves it 
                ## automatically to the permanent location
                ## example temp: /opt/galaxy/galaxy_dist/database/job_working_directory/${job_id}/dataset_63_files
                ## example perm: /opt/galaxy/galaxy_dist/database/files/000/dataset_63_files
                ## and I want the generate the permanent path from it:
                #my $perm_report_dir_path = $report_dir_path;
                #($perm_report_dir_path =~ s/job_working_directory\/\d+\/dataset/files\/\d+\/dataset/) or confess("Could not find permanent output directory path from $report_dir_path");
                # not necesary anymore
                #chdir($galaxy_files_dir) or confess("Could not chdir to $galaxy_files_dir: $!");
                # trick Galaxy by removing its master results output file and making a symlink to point to our GSEA master results file
                if (defined $report_file_path) {
                    unlink($report_file_path) or confess("Could not remove original master results file $report_file_path: $!");
                    my (undef, $galaxy_files_dir) = fileparse($report_file_path, qr/\.[^.]*/);
                    confess("Could not extract Galaxy files directory from $report_file_path") unless defined $galaxy_files_dir and -d $galaxy_files_dir;
                    my $master_results_file_relpath = File::Spec->abs2rel("$report_dir_path/index.html", $galaxy_files_dir) 
                        or confess("Could not generate relative path for $report_dir_path/index.html: $!");
                    symlink($master_results_file_relpath, $report_file_path) 
                        or confess("Could not create master result file symlink: $!");
                }
                # not needed because symlinking above works better compared to this original approach which doesn't display index.html into center frame properly
                #open(my $report_fh, ">$report_file_path") or confess("Could not create master output file: $!");
                #print $report_fh qq(<html><head><meta http-equiv="Refresh" content="0; url=file://$report_dir_path/index.html"></head></html>);
                #close($report_fh);
                # optional GSEA output trace
                #move("$working_dir_path/gsea.out", $output_trace) or confess("Could not move GSEA output trace: $!");
                # not needed, clean up working directory (cannot be in the directory when trying to clean it)
                #chdir "$working_dir_path/..";
                #rmtree($working_dir_path, { keep_root => 1 });
            }
            # ORA Hypergeometric Test
            elsif ($analysis_algorithm =~ /HyperGeoTest/i) {
                # need to know source ID type to determine ORA ID universe and should be in metadata header, if not assume all Entrez Gene IDs
                my $source_id_type = $input_file->metadata->{source_id_type} || 'EntrezGene';
                # generate ID universe file
                # for initial solution I open and parse the <source ID type>.map file, might be worth it in the future to uncomment creation 
                # of <source ID type>.map.pls serialized data structure in preprocessing admin script and load that (faster)
                # also in future probably want to check for validity of source_id_type before I get to the file open command above
                my %unique_gene_ids;
                open(my $src2gene_id_map_fh, '<', "$CTK_DATA_ID_MAPPING_FILE_DIR/${source_id_type}.map")
                    or confess("Could not open $CTK_DATA_ID_MAPPING_FILE_DIR/${source_id_type}.map, make sure $source_id_type is supported: $!");
                # read header
                <$src2gene_id_map_fh>;
                while (<$src2gene_id_map_fh>) {
                    s/\s+$//;
                    my (undef, @gene_ids) = split /\t/;
                    for my $gene_id (@gene_ids) {
                        $gene_id =~ s/\s+//g;
                        confess("Entrez Gene ID '$gene_id' in ${source_id_type}.map file is not valid") unless is_integer($gene_id);
                        $unique_gene_ids{$gene_id}++;
                    }
                }
                close($src2gene_id_map_fh);
                open(my $univ_gene_ids_fh, '>', "$working_dir_path/universe_gene_ids.txt")
                    or confess("Could not create $working_dir_path/universe_gene_ids.txt: $!");
                print $univ_gene_ids_fh join("\n", nsort keys %unique_gene_ids), "\n";
                close($univ_gene_ids_fh);
                $p_val_cutoff = 0.05 unless is_numeric($p_val_cutoff) and $p_val_cutoff >= 0 and $p_val_cutoff <= 1;
                my $r_cmd_str = '';
                if (system(split(' ', $r_cmd_str)) == 0) {
                    
                }
                else {
                    confess("There was an error executing $r_cmd_str, exit code: ", $? >> 8);
                }
            }
            # GSEA Simple
            elsif ($analysis_algorithm =~ /GseaSimple/i) {
                confess("Analysis algorithm '$analysis_algorithm' not currently supported");
            }
            # Running Fisher's
            elsif ($analysis_algorithm =~ /RunningFishers/i) {
                confess("Analysis algorithm '$analysis_algorithm' not currently supported");
            }
            #
            ## put more elsifs here to do different analysis algorithms
            #
            else {
                confess("Analysis algorithm '$analysis_algorithm' is not valid");
            }
        }
        # input input file errors
        else {
            # write output error report
            my $error_report_str = $input_file->data_type_common_name . " Data Errors:\n* " . join("\n* ", @{$input_file->data_errors});
            $self->_write_report_file($report_file_path, $error_report_str, 1) if defined $report_file_path;
            croak($error_report_str);
        }
    }
    # input errors
    else {
        # write output error report
        my $error_report_str = "Input Errors:\n* " . join("\n* ", @input_errors);
        $self->_write_report_file($report_file_path, $error_report_str, 0) if defined $report_file_path;
        croak($error_report_str);
    }
}

sub extract_gsea_leading_edge_matrix {
    my $self = shift;
    # arguments
    # required: [input HTML directory path], [FDR cutoff value], [enrichment type], [output matrix type], [output file path] [include annotations]
    my ($input_html_dir_path, $fdr_cutoff, $enrichment_type, $output_matrix_type, $output_file_path, $include_annots);
    if (@_) {
        ($input_html_dir_path, $fdr_cutoff, $enrichment_type, $output_matrix_type, $output_file_path, $include_annots) = @_;
    }
    else {
        Getopt::Long::Configure('no_pass_through');
        GetOptions(
            'gsea-results-dir|input-html-dir=s' => \$input_html_dir_path,
            'output-file=s'                     => \$output_file_path,
            'output-type=s'                     => \$output_matrix_type,
            'fdr-cutoff=f'                      => \$fdr_cutoff,
            'enrichment-type=s'                 => \$enrichment_type,
            'include-annots'                    => \$include_annots,
        ) || pod2usage(-verbose => 0);
        pod2usage(-message => 'Missing required parameter --gsea-results-dir', -verbose => 0) unless defined $input_html_dir_path;
        #pod2usage(-message => 'Missing required parameter --output-file', -verbose => 0) unless defined $output_file_path;
        pod2usage(-message => 'Missing required parameter --output-type', -verbose => 0) unless defined $output_matrix_type;
        pod2usage(-message => 'Missing required parameter --fdr-cutoff', -verbose => 0) unless defined $fdr_cutoff;
        #pod2usage(-message => 'Missing required parameter --enrichment-type', -verbose => 0) unless defined $enrichment_type;
    }
    $enrichment_type ||= 'all';
    $fdr_cutoff = undef unless is_numeric($fdr_cutoff) and $fdr_cutoff >= 0 and $fdr_cutoff <= 1;
    my @input_errors;
    push @input_errors, "Output matrix type not valid: $output_matrix_type" unless $output_matrix_type =~ /^(B|R|M)$/i;
    push @input_errors, "Enrichment type not valid: $enrichment_type" unless $enrichment_type =~ /^(all|pos|neg)$/i;
    push @input_errors, "$input_html_dir_path not a valid directory" unless -d $input_html_dir_path;
    # check and get metadata header if .confero_meta exists
    my ($organism_name, @metadata_header_lines);
    if (-f "$input_html_dir_path/.confero_meta") {
        open(my $cfo_meta_fh, '<', "$input_html_dir_path/.confero_meta") or confess("Could not open $input_html_dir_path/.confero_meta: $!");
        while (<$cfo_meta_fh>) {
            push @metadata_header_lines, $_;
            # extract organism name if exists
            if (!defined $organism_name and ($organism_name) = m/^#%\s*organism=(.+)$/i) {
                $organism_name =~ s/"//g;
                $organism_name =~ s/'//g;
                $organism_name =~ s/_/ /g;
                $organism_name =~ s/^\s+//;
                $organism_name =~ s/\s+$//;
            }
        }
        close($cfo_meta_fh);
        # check extracted organism name if exists
        if (defined $organism_name and !exists $CTK_ENTREZ_GENE_ORGANISM_DATA{$organism_name}) {
            push @input_errors, "GSEA results organism name '$organism_name' not valid";
        }
    }
    if (!@input_errors) {
        $output_matrix_type = uc($output_matrix_type);
        opendir(my $gsea_dh, $input_html_dir_path) or confess("Could not open directory $input_html_dir_path: $!");
        my @report_csv_file_paths = map { "$input_html_dir_path/$_" } grep { m/$CTK_GSEA_REPORT_FILE_NAME_REGEXP/o && -f "$input_html_dir_path/$_" } readdir($gsea_dh);
        scalar(@report_csv_file_paths) == 2 or confess("Incorrect number of GSEA report files found: " . join(',', @report_csv_file_paths));
        seekdir($gsea_dh, 0) or confess("Could not seekdir on $input_html_dir_path: $!");
        my @details_csv_file_paths = map { "$input_html_dir_path/$_" } natsort grep { m/$CTK_GSEA_DETAILS_FILE_NAME_REGEXP/o && -f "$input_html_dir_path/$_" } readdir($gsea_dh);
        closedir($gsea_dh);
        confess("Could not obtain GSEA result detail files paths") unless @details_csv_file_paths;
        #opendir(my $gsea_edb_dh, "$input_html_dir_path/edb") or confess("Could not open directory $input_html_dir_path/edb: $!");
        #my $rnk_file_path = shift @{[grep { m/^.+?\.rnk$/i && -f } map { "$input_html_dir_path/edb/$_" } readdir($gsea_edb_dh)]};
        #close($gsea_edb_dh);
        my (%leading_edge_data, %gene_set_data, %gene_set_names_in_results, %gene_symbols);
        #my $csv = Text::CSV->new({
        #    binary => 1,
        #    sep_char => "\t",
        #}) or confess("Cannot create Text::CSV object: " . Text::CSV->error_diag());
        #open(my $csv_fh, '<:encoding(utf8)', $rnk_file_path) or confess("Cannot open report CSV/XLS file $rnk_file_path: $!");
        #while (my $row_arrayref = $csv->getline($csv_fh)) {
        #    $gene_ids{$row_arrayref->[0]}++;
        #}
        #$csv->eof() or confess($csv->error_diag());
        #close($csv_fh);
        # get FDR q-values for gene sets from GSEA master reports
        for my $report_csv_file_path (@report_csv_file_paths) {
            my $report_csv_file_name = fileparse($report_csv_file_path);
            my ($report_type) = $report_csv_file_name =~ /$CTK_GSEA_REPORT_FILE_NAME_REGEXP/o;
            next if $enrichment_type ne 'all' and $report_type ne $enrichment_type;
            my $csv = Text::CSV->new({
                binary => 1,
                sep_char => "\t",
            }) or confess("Cannot create Text::CSV object: " . Text::CSV->error_diag());
            open(my $csv_fh, '<:encoding(utf8)', $report_csv_file_path) or confess("Cannot open report CSV/XLS file $report_csv_file_path: $!");
            my $header_row_arrayref = $csv->getline($csv_fh);
            my %col_idxs = map { uc($header_row_arrayref->[$_]) => $_ } 0 .. $#{$header_row_arrayref};
            confess("Bad column headers in report file $report_csv_file_path") unless defined $col_idxs{'NAME'} and
                                                                                      defined $col_idxs{'NES'} and
                                                                                      defined $col_idxs{'FDR Q-VAL'};
            while (my $row_arrayref = $csv->getline($csv_fh)) {
                $gene_set_data{$row_arrayref->[$col_idxs{'NAME'}]}{fdr} = $row_arrayref->[$col_idxs{'FDR Q-VAL'}];
                $gene_set_data{$row_arrayref->[$col_idxs{'NAME'}]}{nes} = $row_arrayref->[$col_idxs{'NES'}];
                if ($enrichment_type eq 'all') {
                    $gene_set_data{$row_arrayref->[$col_idxs{'NAME'}]}{dir} = $report_type eq 'pos' ? '+'
                                                                            : $report_type eq 'neg' ? '-'
                                                                            : confess("GSEA report file name is bad: $report_csv_file_path");
                }
            }
            $csv->eof() or confess($csv->error_diag());
            close($csv_fh);
        }
        # build results data matrix from GSEA detail reports
        for my $details_csv_file_path (@details_csv_file_paths) {
            my $gene_set_name = fileparse($details_csv_file_path, qr/\.[^.]*/);
            # don't parse detail report if we don't have gene set in master report data
            next unless defined $gene_set_data{$gene_set_name};
            my $csv = Text::CSV->new({
                binary => 1,
                sep_char => "\t",
            }) or confess("Cannot create Text::CSV object: " . Text::CSV->error_diag());
            open(my $csv_fh, '<:encoding(utf8)', $details_csv_file_path) or confess("Cannot open detail CSV/XLS file $details_csv_file_path: $!");
            my $header_row_arrayref = $csv->getline($csv_fh);
            my %col_idxs = map { uc($header_row_arrayref->[$_]) => $_ } 0 .. $#{$header_row_arrayref};
            confess("Bad column headers in detail file $details_csv_file_path") unless defined $col_idxs{'PROBE'} and
                                                                                       defined $col_idxs{'GENE SYMBOL'} and
                                                                                       defined $col_idxs{'CORE ENRICHMENT'} and
                                                                                       defined $col_idxs{'RANK METRIC SCORE'} and
                                                                                       defined $col_idxs{'RANK IN GENE LIST'};
            while (my $row_arrayref = $csv->getline($csv_fh)) {
                if ($row_arrayref->[$col_idxs{'CORE ENRICHMENT'}] =~ /y(es|)/i and $gene_set_data{$gene_set_name}{fdr} <= $fdr_cutoff) {
                    $leading_edge_data{$row_arrayref->[$col_idxs{'PROBE'}]}{$gene_set_name} = $output_matrix_type eq 'M'
                                                                                              # rank metric score
                                                                                            ? $row_arrayref->[$col_idxs{'RANK METRIC SCORE'}]
                                                                                            : $output_matrix_type eq 'R'
                                                                                              # rank in list; GSEA does 0-based ranks so add 1
                                                                                            ? $row_arrayref->[$col_idxs{'RANK IN GENE LIST'}] + 1
                                                                                              # boolean true
                                                                                            : 1;
                    $gene_set_names_in_results{$gene_set_name}++;
                    # get Entrez Gene ID gene symbols (easy in here instead of expensive DB call for gene objects)
                    $gene_symbols{$row_arrayref->[$col_idxs{'PROBE'}]} = $row_arrayref->[$col_idxs{'GENE SYMBOL'}];
                }
            }
            $csv->eof() or confess($csv->error_diag());
            close($csv_fh);
        }
        if (%leading_edge_data) {
            my $output_fh; 
            if (defined $output_file_path) {
                open($output_fh, '>', $output_file_path) or confess("Could not create $output_file_path: $!");
            }
            else {
                $output_fh = *STDOUT;
            }
            # include Confero metadata header if have metadata
            print $output_fh @metadata_header_lines if @metadata_header_lines;
            # include data matrix start column for R, 4 if including 1 ID + 2 annots columns, 2 if only 1 ID column
            print $output_fh "#\%matrix_start_column=", (defined $organism_name and defined $include_annots) ? '4' : '2', "\n";
            my ($gene_info_hashref, $add_gene_info_hashref, $uc_symbol2gene_ids_map);
            if (defined $organism_name and defined $include_annots) {
                $gene_info_hashref = Confero::EntrezGene->instance()->gene_info;
                $add_gene_info_hashref = Confero::EntrezGene->instance()->add_gene_info;
                $uc_symbol2gene_ids_map = Confero::EntrezGene->instance()->uc_symbol2gene_ids;
            }
            my @sorted_gene_set_column_names = $enrichment_type eq 'all' 
                                             ? map { "$_ ($gene_set_data{$_}{dir})" } 
                                               srnkeysort { $gene_set_data{$_}{dir}, abs($gene_set_data{$_}{nes}) } 
                                               keys %gene_set_names_in_results
                                             : rnkeysort { abs($gene_set_data{$_}{nes}) } 
                                               keys %gene_set_names_in_results;
            print $output_fh 
                (defined $organism_name and defined $include_annots)
                    ? "Gene ID\tGene Symbol\tDescription\t" 
                    : "Gene Symbol\t", 
                join("\t", @sorted_gene_set_column_names), "\n";
            # IMPORTANT: remember this $result_id is currently a gene symbol and NOT an Entrez Gene ID
            for my $result_id (natsort keys %leading_edge_data) {
                # when Broad makes available Entrez Gene ID-based gmt DBs we can use this instead of needing to to use $uc_symbol2gene_ids_map struct
                #print $output_fh "$gene_symbols{$result_id} [$result_id]";
                if (defined $organism_name and defined $include_annots) {
                    my $best_gene_id;
                    # if uc gene symbol maps to more than one gene ID find out which gene ID has it as its official symbol and use that
                    if (scalar(keys %{$uc_symbol2gene_ids_map->{$organism_name}->{$gene_symbols{$result_id}}}) > 1) {
                        # if uc gene symbol is synonym for all gene IDs then cannot set gene ID to display
                        for my $gene_id (keys %{$uc_symbol2gene_ids_map->{$organism_name}->{$gene_symbols{$result_id}}}) {
                            if (uc($gene_info_hashref->{$gene_id}->{symbol}) eq $gene_symbols{$result_id}) {
                                $best_gene_id = $gene_id;
                                last;
                            }
                        }
                    }
                    else {
                        ($best_gene_id) = keys %{$uc_symbol2gene_ids_map->{$organism_name}->{$gene_symbols{$result_id}}};
                    }
                    print $output_fh $best_gene_id || '', "\t$gene_symbols{$result_id}\t", $best_gene_id ? $add_gene_info_hashref->{$best_gene_id}->{description} : '';
                }
                else {
                    print $output_fh $gene_symbols{$result_id};
                }
                my @sorted_gene_set_names = $enrichment_type eq 'all'
                                          ? srnkeysort { $gene_set_data{$_}{dir}, abs($gene_set_data{$_}{nes}) } keys %gene_set_names_in_results
                                          : rnkeysort { abs($gene_set_data{$_}{nes}) } keys %gene_set_names_in_results;
                for my $gene_set_name (@sorted_gene_set_names) {
                    print $output_fh "\t",
                        exists $leading_edge_data{$result_id}{$gene_set_name}
                            ? $leading_edge_data{$result_id}{$gene_set_name}
                            : ($output_matrix_type eq 'M' or $output_matrix_type eq 'R')
                                # no value
                                ? ''
                                # boolean false
                                : 0;
                }
                print $output_fh "\n";
            }
            close($output_fh);
        }
        # write output error report
        else {
            my $error_report_str = 'No leading edge matrix data to generate, FDR cutoff is too stringent';
            $self->_append_to_report_file($output_file_path, $error_report_str, 0) if defined $output_file_path;
            croak($error_report_str);
        }
    }
    # write output error report
    else {
        my $error_report_str = "Input Errors:\n* " . join("\n* ", @input_errors);
        $self->_write_report_file($output_file_path, $error_report_str, 0) if defined $output_file_path;
        croak($error_report_str);
    }
}

sub extract_ora_results_matrix {
    my $self = shift;
    # arguments
    # required: [input results file paths arrayref], [output file path]
    my ($ora_results_file_paths_arrayref, $output_file_path);
    if (@_) {
        ($ora_results_file_paths_arrayref, $output_file_path) = @_;
    }
    else {
        Getopt::Long::Configure('no_pass_through');
        GetOptions(
            'ora-results-file=s@' => \$ora_results_file_paths_arrayref,
            'output-file=s'       => \$output_file_path,
        ) || pod2usage(-verbose => 0);
        pod2usage(-message => 'Missing required parameter --ora-results-file', -verbose => 0) 
            unless defined $ora_results_file_paths_arrayref and @{$ora_results_file_paths_arrayref};
        #pod2usage(-message => 'Missing required parameter --output-file', -verbose => 0) unless defined $output_file_path;
    }
    my @input_errors;
    for my $ora_results_file_path (@{$ora_results_file_paths_arrayref}) {
        push @input_errors, "$ora_results_file_path not a valid file" unless -f $ora_results_file_path;
    }
    if (!@input_errors) {
        ### process input here ###
        # generate output
        my $output_fh;
        if (defined $output_file_path) {
            open($output_fh, '>', $output_file_path) or confess("Could not create $output_file_path: $!");
        }
        else {
            $output_fh = *STDOUT;
        }
        print $output_fh "\n";
        close($output_fh);
    }
    else {
        # write output error report
        my $error_report_str = "Input Errors:\n* " . join("\n* ", @input_errors);
        $self->_write_report_file($output_file_path, $error_report_str, 0) if defined $output_file_path;
        croak($error_report_str);
    }
}

sub extract_gsea_results_matrix {
    my $self = shift;
    # arguments
    # required: [input HTML directory paths arrayref], [GSEA column names], [output file path]
    my ($input_html_dir_paths_arrayref, $column_names_csv, $output_file_path);
    if (@_) {
        ($input_html_dir_paths_arrayref, $column_names_csv, $output_file_path) = @_;
    }
    else {
        Getopt::Long::Configure('no_pass_through');
        GetOptions(
            'gsea-results-dir|input-html-dir=s@' => \$input_html_dir_paths_arrayref,
            'output-columns|columns=s'           => \$column_names_csv,
            'output-file=s'                      => \$output_file_path,
        ) || pod2usage(-verbose => 0);
        pod2usage(-message => 'Missing required parameter --gsea-results-dir', -verbose => 0) 
            unless defined $input_html_dir_paths_arrayref and @{$input_html_dir_paths_arrayref};
        #pod2usage(-message => 'Missing required parameter --output-file', -verbose => 0) unless defined $output_file_path;
    }
    $column_names_csv ||= 'NES,FDR q-val,RANK AT MAX';
    my @input_errors;
    for my $input_html_dir_path (@{$input_html_dir_paths_arrayref}) {
        push @input_errors, "$input_html_dir_path not a valid directory" unless -d $input_html_dir_path;
    }
    my @results_matrix_column_names = split(',', $column_names_csv);
    for my $col_name (@results_matrix_column_names) {
        $col_name = uc($col_name);
        push @input_errors, "$col_name name not a valid GSEA results column" unless $CTK_GSEA_RESULTS_COLUMN_NAMES{$col_name};
    }
    if (!@input_errors) {
        my (%results_data, @contrast_names);
        for my $input_html_dir_path (@{$input_html_dir_paths_arrayref}) {
            opendir(my $gsea_dh, $input_html_dir_path) or confess("Could not open directory $input_html_dir_path: $!");
            my @report_csv_file_paths = map { "$input_html_dir_path/$_" } grep { m/$CTK_GSEA_REPORT_FILE_NAME_REGEXP/o && -f "$input_html_dir_path/$_" } readdir($gsea_dh);
            scalar(@report_csv_file_paths) == 2 or confess("Incorrect number of GSEA report files found: " . join(',', @report_csv_file_paths));
            seekdir($gsea_dh, 0) or confess("Could not seekdir on $input_html_dir_path: $!");
            my $rpt_file_name = shift @{[ grep { m/\.rpt$/ && -f "$input_html_dir_path/$_" } readdir($gsea_dh) ]};
            confess("Could not find GSEA .rpt file in results at $input_html_dir_path") unless defined $rpt_file_name;
            closedir($gsea_dh);
            my ($contrast_id) = $rpt_file_name =~ /^(.+?)\.analysis.+$/;
            my (undef, $contrast_name) = deconstruct_id($contrast_id);
            # from command line users might not use Confero ID so could be undef and if so then use contrast ID
            $contrast_name ||= $contrast_id;
            push @contrast_names, $contrast_name;
            for my $report_csv_file_path (@report_csv_file_paths) {
                my $csv = Text::CSV->new({
                    binary => 1,
                    sep_char => "\t",
                }) or confess("Cannot create Text::CSV object: " . Text::CSV->error_diag());
                open(my $csv_fh, '<:encoding(utf8)', $report_csv_file_path) or confess("Cannot open report CSV/XLS file $report_csv_file_path: $!");
                my $header_row_arrayref = $csv->getline($csv_fh);
                my %col_idxs = map { uc($header_row_arrayref->[$_]) => $_ } 0 .. $#{$header_row_arrayref};
                while (my $row_arrayref = $csv->getline($csv_fh)) {
                    for my $col_name (@results_matrix_column_names) {
                        $results_data{$row_arrayref->[$col_idxs{'NAME'}]}{$col_name}{$contrast_name} = $row_arrayref->[$col_idxs{$col_name}];
                    }
                }
                $csv->eof() or confess($csv->error_diag());
                close($csv_fh);
            }
        }
        # generate output
        my $output_fh;
        if (defined $output_file_path) {
            open($output_fh, '>', $output_file_path) or confess("Could not create $output_file_path: $!");
        }
        else {
            $output_fh = *STDOUT;
        }
        print $output_fh 'NAME';
        for my $col_name (@results_matrix_column_names) {
            for my $contrast_name (@contrast_names) {
                print $output_fh "\t$col_name [$contrast_name]";
            }
        }
        print $output_fh "\n";
        for my $gene_set_name (natsort keys %results_data) {
            print $output_fh $gene_set_name;
            for my $col_name (@results_matrix_column_names) {
                for my $contrast_name (@contrast_names) {
                    print $output_fh defined $results_data{$gene_set_name}{$col_name}{$contrast_name}
                        ? "\t$results_data{$gene_set_name}{$col_name}{$contrast_name}"
                        : "\t";
                }
            }
            print $output_fh "\n";
        }
        close($output_fh);
    }
    else {
        # write output error report
        my $error_report_str = "Input Errors:\n* " . join("\n* ", @input_errors);
        $self->_write_report_file($output_file_path, $error_report_str, 0) if defined $output_file_path;
        croak($error_report_str);
    }
}

sub extract_gene_set_matrix {
    my $self = shift;
    # arguments
    # required: [gene set DB symbols comma separated list], [output file path] [include annotations]
    my ($gene_set_dbs_csv, $filter_annotations_csv, $filter_organisms_csv, $filter_contrast_names_csv, $filter_gene_set_types_csv, 
        $contrast_gene_set_ids_arrayref, $uploaded_gene_set_ids_arrayref, $gsdb_gene_set_ids_arrayref,  $output_file_path,
        $include_annots);
    if (@_) {
        ($gene_set_dbs_csv, $filter_annotations_csv, $filter_organisms_csv, $filter_contrast_names_csv, $filter_gene_set_types_csv, 
         $contrast_gene_set_ids_arrayref, $uploaded_gene_set_ids_arrayref, $gsdb_gene_set_ids_arrayref,  $output_file_path,
         $include_annots) = @_;
    }
    else {
        Getopt::Long::Configure('no_pass_through');
        GetOptions(
            'gene-set-dbs=s'          => \$gene_set_dbs_csv,
            'gsdb-gene-set-id=s@'     => \$gsdb_gene_set_ids_arrayref,
            'filter-annotations=s'    => \$filter_annotations_csv,
            'filter-organisms=s'      => \$filter_organisms_csv,
            'filter-contrast-names=s' => \$filter_contrast_names_csv,
            'filter-gene-set-types=s' => \$filter_gene_set_types_csv,
            'contrast-gene-set-id=s@' => \$contrast_gene_set_ids_arrayref,
            'uploaded-gene-set-id=s@' => \$uploaded_gene_set_ids_arrayref,
            'output-file=s'           => \$output_file_path,
            'include-annots'          => \$include_annots,
        ) || pod2usage(-verbose => 0);
        #pod2usage(-message => 'Missing required parameter --output-file', -verbose => 0) unless defined $output_file_path;
    }
    # set optional parameters to undef if "empty"
    for my $param ($gene_set_dbs_csv, $filter_annotations_csv, $filter_organisms_csv, $filter_contrast_names_csv, $filter_gene_set_types_csv) {
        $param = undef if defined $param and $param =~ m/^(\s*|none|\?)$/i;
    }
    my %filter_annotations;
    if (defined $filter_annotations_csv) {
        for (split /,/, $filter_annotations_csv) {
            $_ = fix_galaxy_replaced_chars($_, 1);
            my ($name, $value) = split /$CTK_GALAXY_ANNOT_NV_SEPARATOR/o;
            $filter_annotations{$name} = $value;
        }
    }
    my %filter_organisms = map { fix_galaxy_replaced_chars($_, 1) => 1 } split /,/, $filter_organisms_csv if defined $filter_organisms_csv;
    my %filter_contrast_names = map { fix_galaxy_replaced_chars($_, 1) => 1 } split /,/, $filter_contrast_names_csv if defined $filter_contrast_names_csv;
    my %filter_gene_set_types = map { fix_galaxy_replaced_chars($_, 1) => 1 } split /,/, $filter_gene_set_types_csv if defined $filter_gene_set_types_csv;
    my %filter_contrast_gene_set_ids = map { fix_galaxy_replaced_chars($_, 1) => 1 } @{$contrast_gene_set_ids_arrayref} if defined $contrast_gene_set_ids_arrayref;
    my %filter_gene_set_ids = map { fix_galaxy_replaced_chars($_, 1) => 1 } @{$uploaded_gene_set_ids_arrayref} if defined $uploaded_gene_set_ids_arrayref;
    my %gsdb_gene_set_ids = map { fix_galaxy_replaced_chars($_, 1) => 1 } @{$gsdb_gene_set_ids_arrayref} if defined $gsdb_gene_set_ids_arrayref;
    my @input_errors;
    if (!@input_errors) {
        # if specified gene set db IDs are requested then load all msigdb, genesigdb and special msigdb.c2.ar Confero msigdb collection
        $gene_set_dbs_csv = 'msigdb,genesigdb,msigdb.c2.ar' if !defined $gene_set_dbs_csv and %gsdb_gene_set_ids;
        # create snapshot gmt file of Confero DB gene sets
        # temp file fh vars defined here because file gets deleted when out 
        # of scope and we need it all the way through the end
        my ($create_cfo_db_contrasts, $create_cfo_db_uploads, $cfo_db_contrasts_gmt_fh, $cfo_db_uploads_gmt_fh, @gene_set_db_file_paths);
        if (defined $gene_set_dbs_csv or %filter_annotations or %filter_organisms or %filter_contrast_names or %filter_gene_set_types or %filter_contrast_gene_set_ids or %filter_gene_set_ids) {
            if (defined $gene_set_dbs_csv) {
                for my $gene_set_db (split /,/, $gene_set_dbs_csv) {
                    # Confero DB
                    if ($gene_set_db =~ /^cfodb/i) {
                        if ($gene_set_db =~ /^cfodb\.contrasts/i) {
                            $create_cfo_db_contrasts++;
                        }
                        elsif ($gene_set_db =~ /^cfodb\.uploads/i) {
                            $create_cfo_db_uploads++;
                        }
                        else {
                            $create_cfo_db_contrasts++;
                            $create_cfo_db_uploads++;
                        }
                    }
                    # MSigDB, GeneSigDB
                    else {
                        confess("Gene Set DB '$gene_set_db' not valid!") unless exists $CTK_GSEA_GSDBS{$gene_set_db} and defined $CTK_GSEA_GSDBS{$gene_set_db};
                        push @gene_set_db_file_paths, "$CTK_GSEA_GENE_SET_DB_DIR/$CTK_GSEA_GSDBS{$gene_set_db}";
                    }
                }
            }
            $create_cfo_db_contrasts++ if %filter_annotations or %filter_organisms or %filter_contrast_names or %filter_gene_set_types or %filter_contrast_gene_set_ids;
            $create_cfo_db_uploads++ if %filter_annotations or %filter_organisms or %filter_contrast_names or %filter_gene_set_types or %filter_gene_set_ids;
            if ($create_cfo_db_contrasts or $create_cfo_db_uploads) {
                $cfo_db_contrasts_gmt_fh = File::Temp->new(
                    TEMPLATE => 'cfodb.contrasts.' . 'X' x 10,
                    DIR      => $WORKING_DIR,
                    SUFFIX   => '.gmt',
                ) if $create_cfo_db_contrasts;
                $cfo_db_uploads_gmt_fh = File::Temp->new(
                    TEMPLATE => 'cfodb.uploads.' . 'X' x 10,
                    DIR      => $WORKING_DIR,
                    SUFFIX   => '.gmt',
                ) if $create_cfo_db_uploads;
                eval {
                    my $cfo_db = Confero::DB->new();
                    $cfo_db->txn_do(sub {
                        if ($create_cfo_db_contrasts) {
                            my @contrast_datasets = $cfo_db->resultset('ContrastDataSet')->search(undef, {
                                prefetch => [
                                    'organism',
                                    { 'contrasts' => 'gene_sets' }
                                ],
                            })->all();
                            CONTRAST_DATASET: for my $contrast_dataset (@contrast_datasets) {
                                next CONTRAST_DATASET if %filter_organisms and !exists $filter_organisms{$contrast_dataset->organism->name};
                                CONTRAST: for my $contrast ($contrast_dataset->contrasts) {
                                    next CONTRAST if %filter_contrast_names and !exists $filter_contrast_names{$contrast->name};
                                    my %contrast_dataset_annotations = map { $_->name => $_->value } $contrast_dataset->annotations;
                                    for my $annotation_name (keys %filter_annotations) {
                                        next CONTRAST if %filter_annotations and (!defined $contrast_dataset_annotations{$annotation_name} or 
                                            $contrast_dataset_annotations{$annotation_name} ne $filter_annotations{$annotation_name});
                                    }
                                    CONTRAST_GENE_SET: for my $gene_set ($contrast->gene_sets) {
                                        next CONTRAST_GENE_SET if %filter_gene_set_types and !exists $filter_gene_set_types{$gene_set->type};
                                        my $gene_set_id = construct_id($contrast_dataset->name, $contrast->name, $gene_set->type);
                                        next CONTRAST_GENE_SET if %filter_contrast_gene_set_ids and !exists $filter_contrast_gene_set_ids{$gene_set_id};
                                        my @gene_ids = map { $_->gene->id } $gene_set->gene_set_genes;
                                        print $cfo_db_contrasts_gmt_fh "$gene_set_id\thttp://$CTK_WEB_SERVER_HOST:$CTK_WEB_SERVER_PORT/view/contrast_gene_set/$gene_set_id\t", join("\t", nsort @gene_ids), "\n";
                                    }
                                }
                            }
                            close($cfo_db_contrasts_gmt_fh);
                        }
                        if ($create_cfo_db_uploads) {
                            my @gene_sets = $cfo_db->resultset('GeneSet')->search(undef, {
                                prefetch => [qw( organism annotations )],
                            })->all();
                            GENE_SET: for my $gene_set (@gene_sets) {
                                my $gene_set_id = construct_id($gene_set->name, $gene_set->contrast_name, $gene_set->type);
                                next GENE_SET if (%filter_organisms and !exists $filter_organisms{$gene_set->organism->name}) or
                                                 (%filter_contrast_names and (!defined $gene_set->contrast_name or !exists $filter_contrast_names{$gene_set->contrast_name})) or
                                                 (%filter_gene_set_types and (!defined $gene_set->type or !exists $filter_gene_set_types{$gene_set->type})) or 
                                                 (%filter_gene_set_ids and !exists $filter_gene_set_ids{$gene_set_id});
                                my %gene_set_annotations = map { $_->name => $_->value } $gene_set->annotations;
                                for my $annotation_name (keys %filter_annotations) {
                                    next GENE_SET if %filter_annotations and (!defined $gene_set_annotations{$annotation_name} or 
                                        $gene_set_annotations{$annotation_name} ne $filter_annotations{$annotation_name});
                                }
                                my @gene_ids = map { $_->gene->id } $gene_set->gene_set_genes;
                                print $cfo_db_uploads_gmt_fh "$gene_set_id\thttp://$CTK_WEB_SERVER_HOST:$CTK_WEB_SERVER_PORT/view/gene_set/$gene_set_id\t", join("\t", nsort @gene_ids), "\n";
                            }
                            close($cfo_db_uploads_gmt_fh);
                        }
                    });
                };
                if ($@) {
                   my $message = "Confero DB transaction failed";
                   $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
                   confess("$message, please contact $CTK_ADMIN_EMAIL_ADDRESS: $@");
                }
                push(@gene_set_db_file_paths, $cfo_db_contrasts_gmt_fh->filename) if $create_cfo_db_contrasts;
                push(@gene_set_db_file_paths, $cfo_db_uploads_gmt_fh->filename) if $create_cfo_db_uploads;
            }
        }
        # parse gene set DBs and build data structure
        my (%gene_set_matrix_data, %gene_set_names);
        for my $gene_set_db_file_path (@gene_set_db_file_paths) {
            open(my $gsdb_fh, '<', $gene_set_db_file_path) or confess("Could not open $gene_set_db_file_path: $!");
            while (<$gsdb_fh>) {
                m/^\s*$/ && next;
                my ($gene_set_name, undef, @gene_id_strs) = split /\t+/;
                if (%gsdb_gene_set_ids) {
                    $gene_set_names{$gene_set_name}++ if $gsdb_gene_set_ids{$gene_set_name};
                }
                else {
                    $gene_set_names{$gene_set_name}++;
                }
                for (@gene_id_strs) {
                    my @gene_ids = split /\/\/\//;
                    for my $gene_id (@gene_ids) {
                        $gene_id =~ s/\s+//g;
                        # common typo in MSigDB files
                        $gene_id =~ s/\/+$//;
                        next if $gene_id eq '';
                        if (%gsdb_gene_set_ids) {
                            $gene_set_matrix_data{$gene_id}{$gene_set_name}++ if $gsdb_gene_set_ids{$gene_set_name};
                        }
                        else {
                            $gene_set_matrix_data{$gene_id}{$gene_set_name}++;
                        }
                    }
                }
            }
            close($gsdb_fh);
        }
        if (%gene_set_matrix_data) {
            my $output_fh;
            if (defined $output_file_path) {
                open($output_fh, '>', $output_file_path) or confess("Could not create $output_file_path: $!");
            }
            else {
                $output_fh = *STDOUT;
            }
            # include data matrix start column for R, 4 if including 1 ID + 2 annots columns, 2 if only 1 ID column
            print $output_fh "#\%matrix_start_column=", ($create_cfo_db_contrasts or $create_cfo_db_uploads) ? '4' : '2', "\n";
            my ($gene_info_hashref, $add_gene_info_hashref, $uc_symbol2gene_ids_map);
            if ($create_cfo_db_contrasts or $create_cfo_db_uploads) {
                $gene_info_hashref = Confero::EntrezGene->instance()->gene_info;
                $add_gene_info_hashref = Confero::EntrezGene->instance()->add_gene_info;
                $uc_symbol2gene_ids_map = Confero::EntrezGene->instance()->uc_symbol2gene_ids;
            }
            my @sorted_gene_set_names = natsort keys %gene_set_names;
            print $output_fh 
                ($create_cfo_db_contrasts or $create_cfo_db_uploads) 
                    ? "Gene ID\tGene Symbol\tDescription\t" 
                    : "Gene Symbol\t",
                join("\t", @sorted_gene_set_names), "\n"; 
            for my $gene_id (natsort keys %gene_set_matrix_data) {
                # for performance, otherwise so many prints is way too slow
                my @line_parts;
                push @line_parts, $gene_id;
                if ($create_cfo_db_contrasts or $create_cfo_db_uploads) {
                    push @line_parts, 
                        $gene_info_hashref->{$gene_id}->{symbol}, 
                        $add_gene_info_hashref->{$gene_id}->{description} || '' 
                }
                for my $gene_set_name (@sorted_gene_set_names) {
                    push @line_parts, exists $gene_set_matrix_data{$gene_id}{$gene_set_name} ? 1 : 0;
                }
                print $output_fh join("\t", @line_parts), "\n";
            }
            close($output_fh);
        }
        # write output error report
        else {
            my $error_report_str = "No gene set matrix could be generated because no gene set data exists for filter(s) selected";
            $self->_write_report_file($output_file_path, $error_report_str, 0) if defined $output_file_path;
            croak($error_report_str);
        }
    }
    else {
        # write output error report
        my $error_report_str = "Input Errors:\n* " . join("\n* ", @input_errors);
        $self->_write_report_file($output_file_path, $error_report_str, 0) if defined $output_file_path;
        croak($error_report_str);
    }
}

sub extract_gene_set_overlap_matrix {
    my $self = shift;
    # arguments
    # required: [input gene set/leading edge matrix file path], [output matrix type], [output gene set overlap matrix file path]
    my ($input_matrix_file_path, $output_matrix_type, $output_file_path);
    if (@_) {
        ($input_matrix_file_path, $output_matrix_type, $output_file_path) = @_;
    }
    else {
        Getopt::Long::Configure('no_pass_through');
        GetOptions(
            'input-file=s'  => \$input_matrix_file_path,
            'output-file=s' => \$output_file_path,
            'output-type=s' => \$output_matrix_type,
        ) || pod2usage(-verbose => 0);
        pod2usage(-message => 'Missing required parameter --input-file', -verbose => 0) unless defined $input_matrix_file_path;
        pod2usage(-message => 'Missing required parameter --output-type', -verbose => 0) unless defined $output_matrix_type;
        #pod2usage(-message => 'Missing required parameter --output-file', -verbose => 0) unless defined $output_file_path;
    }
    my @input_errors;
    push @input_errors, "Output matrix type not valid: $output_matrix_type" unless $output_matrix_type =~ /^(num|pct)_overlap$/i;
    if (!@input_errors) {
        $output_matrix_type = lc($output_matrix_type);
        my $csv = Text::CSV->new({
            binary => 1,
            sep_char => "\t",
        }) or confess("Cannot create Text::CSV object: " . Text::CSV->error_diag());
        open(my $csv_fh, '<:encoding(utf8)', $input_matrix_file_path) or confess("Cannot open matrix file: $input_matrix_file_path: $!");
        my $header_row_arrayref = $csv->getline($csv_fh);
        # we have minimum a gene ID or symbol first column, determine how many additional 
        # gene columns we might have before gene set matrix columns (max 3 total)
        my $data_start_col_idx = 1;
        for my $col_idx (1..2) {
            $data_start_col_idx = $col_idx + 1 if $header_row_arrayref->[$col_idx] =~ /^\s*((gene|)(symbol|description)|title)\s*$/io;
        }
        # build gene set data
        my %gene_set_data;
        while (my $row_arrayref = $csv->getline($csv_fh)) {
            for my $col_idx ($data_start_col_idx .. $#{$row_arrayref}) {
                # add gene ID/symbol to gene set if field value is not blank and not zero (i.e. where value is true)
                $gene_set_data{$header_row_arrayref->[$col_idx]}{$row_arrayref->[0]}++ if $row_arrayref->[$col_idx];
            }
        }
        $csv->eof() or confess($csv->error_diag());
        close($csv_fh);
        # compute matrix and write output file
        my %transposed_matrix_values;
        my $output_fh;
        if (defined $output_file_path) {
            open($output_fh, '>', $output_file_path) or confess("Could not create $output_file_path: $!");
        }
        else {
            $output_fh = *STDOUT;
        }
        print $output_fh "\t", join("\t", @{$header_row_arrayref}[$data_start_col_idx .. $#{$header_row_arrayref}]), "\n";
        for my $row_gene_set_name (@{$header_row_arrayref}[$data_start_col_idx .. $#{$header_row_arrayref}]) {
            # for performance, otherwise so many prints is way too slow
            my @line_parts;
            push @line_parts, $row_gene_set_name;
            for my $col_gene_set_name (@{$header_row_arrayref}[$data_start_col_idx .. $#{$header_row_arrayref}]) {
                my $field_value;
                if ($row_gene_set_name ne $col_gene_set_name) {
                    if (!defined $transposed_matrix_values{$row_gene_set_name} or !defined $transposed_matrix_values{$row_gene_set_name}{$col_gene_set_name}) {
                        my @row_gene_set_genes = keys %{$gene_set_data{$row_gene_set_name}};
                        my @col_gene_set_genes = keys %{$gene_set_data{$col_gene_set_name}};
                        # num overlap == intersect(GSx,GSy)
                        my $num_overlap = grep { $gene_set_data{$row_gene_set_name}{$_} } @col_gene_set_genes;
                        # way slower method than grepping on keys to compare and intersect lists so not used
                        #my $num_overlap = scalar(@{intersect_arrays(\@row_gene_set_genes, \@col_gene_set_genes)});
                        $field_value = $output_matrix_type eq 'num_overlap'
                            ? $num_overlap
                            # percentage (%) overlap == intersect(GSx,GSy) / min(GSx,GSy) * 100
                            : round($num_overlap / min(scalar(@row_gene_set_genes), scalar(@col_gene_set_genes)) * 100);
                        # store computed value for transposed matrix field so that we don't need to recompute
                        $transposed_matrix_values{$col_gene_set_name}{$row_gene_set_name} = $field_value;
                    }
                    else {
                        $field_value = $transposed_matrix_values{$row_gene_set_name}{$col_gene_set_name};
                    }
                }
                # diagnonal GSx == GSy
                else {
                    $field_value = $output_matrix_type eq 'num_overlap'
                        # num overlap == number of genes in gene set
                        ? scalar(keys %{$gene_set_data{$row_gene_set_name}})
                        # percentage (%) overlap == 100
                        : 100;
                }
                push @line_parts, $field_value;
            }
            print $output_fh join("\t", @line_parts), "\n";
        }
        close($output_fh);
    }
    # input errors
    else {
        my $error_report_str = "Input Errors:\n* " . join("\n* ", @input_errors);
        $self->_append_to_report_file($output_file_path, $error_report_str, 0) if defined $output_file_path;
        croak($error_report_str);
    }
}

sub extract_contrast_data_subset {
    my $self = shift;
    # arguments
    # required: [input contrast dataset file path] OR [extract Confero contrast dataset ID], [output contrast data subset file path],
    #           [extract contrast names arrayref] OR [extract contrast indexes arrayref]
    # optional: [original contrast dataset file name], [debug file path]
    my ($input_file_path, $orig_input_file_name, $output_file_path, $extract_contrast_names_arrayref,
        $extract_contrast_idxs_arrayref, $contrast_dataset_id, $debug_file_path);
    if (@_) {
        ($input_file_path, $orig_input_file_name, $output_file_path, $extract_contrast_names_arrayref,
         $extract_contrast_idxs_arrayref, $contrast_dataset_id, $debug_file_path) = @_;
    }
    else {
        my ($extract_contrast_names_csv_str, $extract_contrast_idxs_csv_str);
        Getopt::Long::Configure('no_pass_through');
        GetOptions(
            'input-file=s'            => \$input_file_path,
            'orig-filename=s'         => \$orig_input_file_name,
            'output-file=s'           => \$output_file_path,
            'contrast-name=s@'        => \$extract_contrast_names_arrayref,
            'contrast-names=s'        => \$extract_contrast_names_csv_str,
            'contrast-idx=i@'         => \$extract_contrast_idxs_arrayref,
            'contrast-idxs=s'         => \$extract_contrast_idxs_csv_str,
            'contrast-dataset-id=s'   => \$contrast_dataset_id,
            'debug-file=s'            => \$debug_file_path,
        ) || pod2usage(-verbose => 0);
        if (!defined $extract_contrast_names_arrayref and !defined $extract_contrast_names_csv_str and 
            !defined $extract_contrast_idxs_arrayref and !$extract_contrast_idxs_csv_str and 
            !defined $contrast_dataset_id) {
            pod2usage(
                -message => 'Missing required parameter: one of (--contrast-name (multi) or --contrast-names (csv str)), ' .
                            '(--contrast-idx (multi) or -contrast-idxs (csv str)) or --contrast-dataset-id', 
                -verbose => 0,
            );
        }
        if (((defined $extract_contrast_names_arrayref or defined $extract_contrast_names_csv_str) and 
             (defined $extract_contrast_idxs_arrayref or defined $extract_contrast_idxs_csv_str))) {
            pod2usage(
                -message => 'Bad parameters: only one of (--contrast-name (multi) or --contrast-names (csv str)), ' .
                            'or (--contrast-idx (multi) or -contrast-idxs (csv str))', 
                -verbose => 0,
            );
        }
        if (!defined $input_file_path and !defined $contrast_dataset_id) {
            pod2usage(-message => 'Missing required parameter --input-file', -verbose => 0);
        }
        #if (!defined $output_file_path) {
        #    pod2usage(-message => 'Missing required parameter --output-file', -verbose => 0);
        #}
        if (defined $extract_contrast_names_csv_str) {
            push @{$extract_contrast_names_arrayref}, 
                map { s/^\s+//; s/\s+$//; $_ } 
                split /,/, $extract_contrast_names_csv_str;
        }
        if (defined $extract_contrast_idxs_csv_str) {
            push @{$extract_contrast_idxs_arrayref}, 
                map { s/^\s+//; s/\s+$//; $_ } 
                split /,/, $extract_contrast_idxs_csv_str;
        }
    }
    my @input_errors;
    if (defined $contrast_dataset_id) {
        my ($dataset_name) = deconstruct_id($contrast_dataset_id);
        eval {
            my $cfo_db = Confero::DB->new();
            $cfo_db->txn_do(sub {
                if (my $dataset = $cfo_db->resultset('ContrastDataSet')->find({
                    name => $dataset_name,
                })) {
                    # set input file path to scalar reference of in-memory data and open() will do the right thing
                    $input_file_path = \$dataset->source_data_file->data;
                    $orig_input_file_name = $dataset->source_data_file_name;
                }
                else {
                    push @input_errors, "Cannot find dataset '$dataset_name' in Confero DB";
                }
            });
        };
        if ($@) {
           my $message = "Confero DB transaction failed";
           $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
           confess("$message, please contact $CTK_ADMIN_EMAIL_ADDRESS: $@");
        }
    }
    $orig_input_file_name = fix_galaxy_replaced_chars($orig_input_file_name, 1) if defined $orig_input_file_name;
    my $input_data_file = Confero::DataFile->new($input_file_path, 'IdMAPS', $orig_input_file_name, (undef) x 7, 1);
    if (!@{$input_data_file->data_errors}) {
        my (%extract_contrast_names, %extract_contrast_idxs);
        if (defined $extract_contrast_names_arrayref) {
            %extract_contrast_names = map { fix_galaxy_replaced_chars($_, 1) => 1 } @{$extract_contrast_names_arrayref};
        }
        elsif (defined $extract_contrast_idxs_arrayref) {
            s/\s+//g for @{$extract_contrast_idxs_arrayref};
            %extract_contrast_idxs = map { $_ => 1 } @{$extract_contrast_idxs_arrayref};
        }
        my %file_contrast_data = map {
            $input_data_file->metadata->{contrast_names}->[$_] => $_ 
        } 0 .. $#{$input_data_file->metadata->{contrast_names}};
        for my $extract_contrast_idx (nsort keys %extract_contrast_idxs) {
            if ($extract_contrast_idx < 0 and $extract_contrast_idx > $#{$input_data_file->metadata->{contrast_names}}) {
                push @input_errors, "Contrast index $extract_contrast_idx not found in input contrast dataset";
            }
        }
        for my $extract_contrast_name (natsort keys %extract_contrast_names) {
            if (defined $file_contrast_data{$extract_contrast_name}) {
                $extract_contrast_idxs{$file_contrast_data{$extract_contrast_name}}++;
            }
            else {
                push @input_errors, "Contrast name '$extract_contrast_name' not found in input contrast dataset";
            }
        }
        if (!@input_errors) {
            $input_data_file->write_subset_file($output_file_path, \%extract_contrast_idxs);
            $input_data_file->write_debug_file($debug_file_path) if defined $debug_file_path;
        }
        # input errors
        else {
            my $error_report_str = "Input Errors:\n* " . join("\n* ", @input_errors);
            $self->_append_to_report_file($output_file_path, $error_report_str, 0) if defined $output_file_path;
            croak($error_report_str);
        }
    }
    # input data file errors
    else {
        # write output error report
        my $error_report_str = $input_data_file->data_type_common_name . " Data Errors:\n* " . join("\n* ", @{$input_data_file->data_errors});
        $self->_append_to_report_file($output_file_path, $error_report_str, 0) if defined $output_file_path;
        $input_data_file->write_debug_file($debug_file_path) if defined $debug_file_path;
        croak($error_report_str);
    }
}

sub _write_report_file {
    my ($self, $report_file_path, $report_str, $do_html) = @_;
    confess('No report file path specified') unless defined $report_file_path;
    confess('No report text specified') unless defined $report_str;
    open(my $output_fh, '>', $report_file_path) or confess("Could not open output report file $report_file_path: $!");
    print $output_fh '<pre>' if $do_html;
    print $output_fh $report_str;
    print $output_fh '</pre>' if $do_html;
    close($output_fh);
}

sub _append_to_report_file {
    my ($self, $report_file_path, $report_str, $do_html) = @_;
    confess('No report file path specified') unless defined $report_file_path;
    confess('No report text specified') unless defined $report_str;
    my $report_file_str = '';
    if (-e $report_file_path) {
        local $/;
        # 3-arg form of open because file path could be a scalar reference in-memory file
        open(my $input_fh, '<', $report_file_path) or confess("Could not open output report file $report_file_path: $!");
        $report_file_str = <$input_fh>;
        close($input_fh);
    }
    if ($do_html) {
        $report_file_str =~ s/^\s*<pre>//i;
        $report_file_str =~ s/<\/pre>\s*$//i;
    }
    open(my $output_fh, '>', $report_file_path) or confess("Could not open output report file $report_file_path: $!");
    print $output_fh '<pre>' if $do_html;
    print $output_fh $report_file_str, $report_str;
    print $output_fh '</pre>' if $do_html;
    close($output_fh);
}

sub _prepend_to_report_file {
    my ($self, $report_file_path, $report_str, $do_html) = @_;
    confess('No report file path specified') unless defined $report_file_path;
    confess('No report text specified') unless defined $report_str;
    my $report_file_str = '';
    if (-e $report_file_path) {
        local $/;
        # 3-arg form of open because file path could be a scalar reference in-memory file
        open(my $input_fh, '<', $report_file_path) or confess("Could not open output report file $report_file_path: $!");
        $report_file_str = <$input_fh>;
        close($input_fh);
    }
    if ($do_html) {
        $report_file_str =~ s/^\s*<pre>//i;
        $report_file_str =~ s/<\/pre>\s*$//i;
    }
    open(my $output_fh, '>', $report_file_path) or confess("Could not open output report file $report_file_path: $!");
    print $output_fh '<pre>' if $do_html;
    print $output_fh $report_str, $report_file_str;
    print $output_fh '</pre>' if $do_html;
    close($output_fh);
}

sub _modify_gsea_results_summary_html_file {
    my ($self, $html_file_path) = @_;
    confess('No GSEA results summary HTML file path specified') unless defined $html_file_path;
    confess("$html_file_path not valid") unless -f $html_file_path;
    my $tree = HTML::TreeBuilder->new();
    $tree->parse_file($html_file_path);
    my ($h4_up, $h4_dn) = $tree->look_down('_tag', 'h4');
    $h4_up->detach_content();
    $h4_up->push_content('Enrichment of gene sets in upregulated part of ranked list profile:');
    $h4_dn->detach_content();
    $h4_dn->push_content('Enrichment of gene sets in downregulated part of ranked list profile:');
    my ($ul_up, $ul_dn) = $tree->look_down('_tag', 'ul');
    my $li_up_1 = ($ul_up->content_list)[0];
    ($li_up_1->content_list)[1]->delete();
    my $li_up_1_content = $li_up_1->detach_content();
    $li_up_1_content =~ s/are upregulated in phenotype\s*$/enriched in upregulated part of ranked list profile/;
    $li_up_1->push_content($li_up_1_content);
    my $li_dn_1 = ($ul_dn->content_list)[0];
    ($li_dn_1->content_list)[1]->delete();
    my $li_dn_1_content = $li_dn_1->detach_content();
    $li_dn_1_content =~ s/are upregulated in phenotype\s*$/enriched in downregulated part of ranked list profile/;
    $li_dn_1->push_content($li_dn_1_content);
    # output HTML
    open(my $html_fh, '>', $html_file_path) or confess("Could not create file $html_file_path: $!");
    print $html_fh $tree->as_HTML();
    close($html_fh);
    # clean up memory
    $tree->delete();
}

sub _modify_gsea_enrich_results_html_file {
    my ($self, $html_file_path) = @_;
    confess('No GSEA enrichment results HTML file path specified') unless defined $html_file_path;
    confess("$html_file_path not valid") unless -f $html_file_path;
    my $tree = HTML::TreeBuilder->new();
    $tree->parse_file($html_file_path);
    # modify table header cell above links
    my $th_links = $tree->look_down(
        '_tag', 'th',
        sub {
            $_[0]->as_text =~ /GS follow link to MSigDB/i
        }
    );
    if ($th_links) {
        $th_links->detach_content();
        $th_links->push_content('GS follow link to MSigDB or Confero DB');
    }
    else {
        confess('No <th> table header tag for links found');
    }
    # don't need to do this anymore as I set URLs in GSEA gmt files above
    ## modify internal GS links
    #my @a_links = $tree->look_down(
    #    '_tag', 'a',
    #    sub {
    #        $_[0]->as_text =~ /$CTK_DISPLAY_ID_GENE_SET_REGEXP/io;
    #    }
    #);
    #if (@a_links) {
    #    for my $a_link (@a_links) {
    #        $a_link->attr('href', "http://$CTK_WEB_SERVER_HOST:$CTK_WEB_SERVER_PORT/view/contrast_gene_set/" . $a_link->as_text);
    #    }
    #}
    #else {
    #    # sometimes if CTK GS links have low enrichment then they will be low in GSEA output list and won't have any links
    #    #confess('No <a> link tags found');
    #}
    # add extract table header/footer and checkbox cells
    my @trs = $tree->look_down('_tag', 'tr');
    if (@trs) {
        for my $i (0 .. $#trs) {
            if ($i == 0) {
                # organism ID th header
                #my $th_organism_tax_id = HTML::Element->new('th', 'class' => 'richTable');
                #$th_organism_tax_id->push_content('Organism Tax ID');
                #($trs[$i]->content_list())[0]->postinsert($th_organism_tax_id);
                # extract th header
                my $th_extract = HTML::Element->new('th', 'class' => 'richTable');
                $th_extract->push_content('Extract');
                ($trs[$i]->content_list())[0]->postinsert($th_extract);
            }
            else {
                # organism td cell
                #my $td_organism_tax_id = HTML::Element->new('td',
                #    style => 'text-align: center'
                #);
                #($trs[$i]->content_list())[0]->postinsert($td_organism_tax_id);
                # extract td cell
                my $td_extract = HTML::Element->new('td', style => 'text-align: center');
                ($trs[$i]->content_list())[0]->postinsert($td_extract);
                if (($trs[$i]->content_list())[2]->as_text =~ /$CTK_DISPLAY_ID_GENE_SET_REGEXP/io) {
                    my $input_checkbox = HTML::Element->new('input', 
                        'type'  => 'checkbox',
                        'name'  => 'contrasts',
                        # contrast ID for value instead of gene set ID
                        'value' => $1,
                        #'value' => ($trs[$i]->content_list())[2]->as_text,
                    );
                    #$td_organism_tax_id->push_content('id here');
                    $td_extract->push_content($input_checkbox);
                }
                else {
                    #$td_organism_tax_id->push_content(HTML::Element->new('~literal',
                    #    'text' => '&nbsp;'
                    #));
                    $td_extract->push_content(HTML::Element->new('~literal',
                        'text' => '&nbsp;'
                    ));
                }
            }
        }
    }
    else {
        confess('No <tr> table row tags found');
    }
    # make wrapper form container, submit buttons and text
    my $div_container = $tree->look_down('_tag', 'div');
    if ($div_container) {
        my $orig_div_content = $div_container->detach_content();
        my $form = HTML::Element->new('form', 'method' => 'POST', 'action' => "http://$CTK_WEB_SERVER_HOST:$CTK_WEB_SERVER_PORT/view");
        $div_container->push_content($form);
        $form->push_content(HTML::Element->new('input', 'type' => 'submit', 'value' => 'EXTRACT'));
        $form->push_content(HTML::Element->new('~literal',
            'text' => '&nbsp;&larr;&nbsp;click here to extract contrast data from gene sets selected below'
        ));
        $form->push_content(HTML::Element->new('br'));
        $form->push_content($orig_div_content);
        $form->push_content(HTML::Element->new('br'));
        $form->push_content(HTML::Element->new('input', 'type' => 'submit', 'value' => 'EXTRACT'));
        $form->push_content(HTML::Element->new('~literal',
            'text' => '&nbsp;&larr;&nbsp;click here to extract contrast data from gene sets selected below'
        ));
    }
    else {
        confess('No <div> container tag found');
    }
    # output HTML
    open(my $html_fh, '>', $html_file_path) or confess("Could not create file $html_file_path: $!");
    print $html_fh $tree->as_HTML();
    close($html_fh);
    # clean up memory
    $tree->delete();
}

1;
