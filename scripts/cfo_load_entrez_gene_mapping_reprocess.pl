#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib/perl5", "$FindBin::Bin/../extlib/lib/perl5";
use sigtrap qw(handler sig_handler normal-signals error-signals ALRM);
use Confero::Cmd;
use Confero::Config qw(:data :entrez :gsea :affy :agilent :geo :illumina);
use Confero::DataFile;
use Confero::DB;
use Confero::EntrezGene;
use Confero::LocalConfig qw(:general :gsea);
use Cwd qw(cwd);
use Confero::Utils qw(construct_id);
use Const::Fast;
use File::Basename qw(basename fileparse);
use File::Copy qw(copy move);
use File::Fetch;
use File::Temp ();  # () for OO-interface
use Getopt::Long qw(:config auto_help auto_version);
use List::Util qw(min);
use Storable qw(lock_nstore lock_retrieve);
use Hash::Util;
use Parallel::Forker;
use Pod::Usage qw(pod2usage);
use Sort::Key qw(nsort);
use Sort::Key::Natural qw(natsort rnatsort natkeysort);
use Unix::Processors;
use Utils qw(is_integer);
use Data::Dumper;

$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Terse = 1;
$Data::Dumper::Deepcopy = 1;

sub sig_handler {
    die "\n\n$0 program exited gracefully [", scalar localtime, "]\n\n";
}
our $VERSION = '0.0.1';
# unbuffer error and output streams (make sure STDOUT is last so that it remains the default filehandle)
select(STDERR); $| = 1;
select(STDOUT); $| = 1;

# constants
const my $AFFY_ANNOT_SEPARATOR => qr/\s*\/\/\/\s*/o;
const my $AFFY_FIELD_SEPARATOR => qr/\s*\/\/\s*/o;

# end program if already running
if (`ps -eo cmd | grep -v grep | grep -c "perl $0"` > 1) {
    print "$0 already running! Exiting...\n\n";
    exit;
}
# --no-interactive to turn off interactive mode (default false)
# --parallel specifies degree of parallelism for CTK reprocessing (default 0 which is off)
# --no-entrez-download skips downloading of latest Entrez Gene data and uses existing local files (default false)
# --no-entrez-processing skips processing of Entrez Gene data and uses existing local data structures (default false)
# --download-netaffx downloads new NetAffx annotation files (default false)
# --no-mapping-file-processing skips processing of mapping files using latest Entrez Gene data and uses existing files (default false)
# --no-db-reprocessing skips full reprocessing of all CTK database using latest Entrez Gene data and mapping files (default false)
my $no_interactive = 0;
my $num_parallel_procs = 0;
my $no_entrez_download = 0;
my $no_entrez_processing = 0;
my $download_netaffx = 0;
my $download_agilent = 0;
my $download_geo = 0;
my $download_illumina = 0;
my $no_mapping_file_processing = 0;
my $no_netaffx_processing = 0;
my $no_agilent_processing = 0;
my $no_geo_processing = 0;
my $no_illumina_processing = 0;
my $no_db_reprocessing = 0;
my $debug = 0;
my $verbose = 0;
#my $man = 0;
GetOptions(
    'no-interactive'             => \$no_interactive,
    'parallel:i'                 => \$num_parallel_procs,
    'no-entrez-download'         => \$no_entrez_download,
    'no-entrez-processing'       => \$no_entrez_processing,
    'download-netaffx'           => \$download_netaffx,
    'download-agilent'           => \$download_agilent,
    'download-geo'               => \$download_geo,
    'download-illumina'          => \$download_illumina,
    'no-mapping-file-processing' => \$no_mapping_file_processing,
    'no-netaffx-processing'      => \$no_netaffx_processing,
    'no-agilent-processing'      => \$no_agilent_processing,
    'no-geo-processing'          => \$no_geo_processing,
    'no-illumina-processing'     => \$no_illumina_processing,
    'no-db-reprocessing'         => \$no_db_reprocessing,
    'debug'                      => \$debug,
    'verbose'                    => \$verbose,
    #'man'                        => \$man,
) || pod2usage(-verbose => 0);
#pod2usage(-exitstatus => 0, -verbose => 2) if $man;
print "#", '-' x 120, "#\n",
      "# Confero Entrez Gene Data Loader, Mapping File Creator and Database Reprocessor [" . scalar localtime() . "]\n\n";
my $tmp_dir = File::Temp->newdir('X' x 10, DIR => $CTK_TEMP_DIR, CLEANUP => $debug ? 0 : 1);
mkdir "$tmp_dir/$_" or die "Could not create $tmp_dir/$_ directory: $!" for qw(entrez_gene affymetrix agilent geo illumina mappings gsea reprocessing);
# entrez gene
print "[Entrez Gene Data]\n";
my $entrez_data_tmp_dir = "$tmp_dir/entrez_gene";
$no_entrez_download = 1 if $no_entrez_processing;
$no_entrez_processing = 0 if !$no_entrez_download;
if (!$no_interactive and !$no_entrez_download) {
    print "Would you like to download the latest NCBI Entrez Gene data? (type 'no' to use existing local files) [yes] ";
    chomp(my $answer = <STDIN>);
    $answer = 'yes' if $answer eq '';
    $no_entrez_download = ($answer =~ /^y(es|)$/i) ? 0 : 1;
}
my $entrez_data_work_dir;
if (!$no_entrez_download) {
    # download and uncompress latest public master Entrez Gene data files
    $entrez_data_work_dir = $entrez_data_tmp_dir;
    for my $entrez_gene_file_key (rnatsort keys %CTK_ENTREZ_GENE_DATA) {
        my $file_uri = $CTK_ENTREZ_GENE_DATA{$entrez_gene_file_key}{file_uri};
        my $ff = File::Fetch->new(uri => $file_uri) or die "\n\nERROR: File::Fetch object constructor error\n\n";
        my ($gi_file_basename, undef, $gi_file_ext) = fileparse($file_uri, qr/\.[^.]*/);
        print "Fetching latest $gi_file_basename$gi_file_ext\n";
        $ff->fetch(to => $entrez_data_work_dir) or die "\n\nERROR: File::Fetch fetch error: ", $ff->error, "\n\n";
        print "Uncompressing $gi_file_basename$gi_file_ext\n";
        if ($gi_file_ext) { 
            my $uncompress_cmd = lc($gi_file_ext) eq '.gz'  ? "gzip -df $entrez_data_work_dir/$gi_file_basename$gi_file_ext"
                               : lc($gi_file_ext) eq '.zip' ? "unzip -oq $entrez_data_work_dir/$gi_file_basename$gi_file_ext -d $entrez_data_work_dir"
                               : die "\n\nERROR: unsupported compressed file extension '$gi_file_ext'\n\n";
            system($uncompress_cmd) == 0 or die "\nERROR: $uncompress_cmd system call error: ", $? >> 8, "\n\n";
        }
    }
    # download and uncompress organism-specific gene_info files or parse master gene_info file to create organism-specific if one doesn't exist at NCBI
    for my $organism_name (sort keys %CTK_ENTREZ_GENE_ORGANISM_DATA) {
        if (defined $CTK_ENTREZ_GENE_ORGANISM_DATA{$organism_name}{gene_info_file_uri}) {
            my $ff = File::Fetch->new(uri => $CTK_ENTREZ_GENE_ORGANISM_DATA{$organism_name}{gene_info_file_uri}) 
                or die "\n\nERROR: File::Fetch object constructor error\n\n";
            my ($gi_file_basename, undef, $gi_file_ext) = fileparse($CTK_ENTREZ_GENE_ORGANISM_DATA{$organism_name}{gene_info_file_uri}, qr/\.[^.]*/);
            print "Fetching latest $gi_file_basename$gi_file_ext\n";
            $ff->fetch(to => $entrez_data_work_dir) or die "\n\nERROR: File::Fetch fetch error: ", $ff->error, "\n\n";
            print "Uncompressing $gi_file_basename$gi_file_ext\n";
            if ($gi_file_ext) {
                my $uncompress_cmd = lc($gi_file_ext) eq '.gz'  ? "gzip -df $entrez_data_work_dir/$gi_file_basename$gi_file_ext"
                                   : lc($gi_file_ext) eq '.zip' ? "unzip -oq $entrez_data_work_dir/$gi_file_basename$gi_file_ext -d $entrez_data_work_dir" 
                                   : die "\n\nERROR: unsupported compressed file extension '$gi_file_ext'\n\n";
                system($uncompress_cmd) == 0 or die "\nERROR: $uncompress_cmd system call error: ", $? >> 8, "\n\n";
            }
        }
        elsif (defined $CTK_ENTREZ_GENE_ORGANISM_DATA{$organism_name}{parse_gene_info}) {
            (my $organism_file_basename = $organism_name) =~ s/\s+/_/g;
            print "Parsing master gene_info file to create $organism_file_basename.gene_info, ",
                  "using taxonomy IDs ", join(',', @{$CTK_ENTREZ_GENE_ORGANISM_DATA{$organism_name}{parse_tax_ids}}), ': ';
            my %tax_ids = map { $_ => 1 } @{$CTK_ENTREZ_GENE_ORGANISM_DATA{$organism_name}{parse_tax_ids}};
            open(my $gene_info_fh, '<', "$entrez_data_work_dir/gene_info") 
                or die "\n\nERROR: could not open $entrez_data_work_dir/gene_info: $!\n\n";
            open(my $output_fh, '>', "$entrez_data_work_dir/$organism_file_basename.gene_info") 
                or die "\n\nERROR: could not create $entrez_data_work_dir/$organism_file_basename.gene_info: $!\n\n";
            # skip column header for organism-specific gene_info file
            my $col_header = <$gene_info_fh>;
            # print OUTFILE $header;
            my $genes_added = 0;
            while (<$gene_info_fh>) {
                my ($tax_id) = split /\t/;
                if ($tax_ids{$tax_id}) {
                    print $output_fh $_;
                    $genes_added++;
                }
            }
            close($output_fh);
            close($gene_info_fh);
            print "$genes_added genes added\n";
            die "\n\nERROR: problem with parsing or tax IDs, 0 genes added!\n\n" if $genes_added == 0;
        }
        else {
            die "\n\nERROR: problem with $organism_name Entrez Gene configuration! Missing gene_info_file_uri hash key/value, please check the configuration file.\n\n";
        }
    }
}
else {
    $entrez_data_work_dir = $CTK_ENTREZ_GENE_DATA_DIR;
    print "Skipping download of latest Entrez Gene data, using existing local files\n";
}
# parse latest Entrez Gene data from organism-specific gene_info files, create data structures and gene symbol mappings
my $mapping_data_work_dir = "$tmp_dir/mappings";
my $gene_symbol2id_bestmap;
if (!$no_entrez_processing) {
    my (%all_tax_ids, $gene_info_hashref, $add_gene_info_hashref, $gene_history_hashref, $symbol2gene_ids_map, $uc_symbol2gene_ids_map,
        $gene_id2symbols_map, $accession2gene_ids_map, $ensembl2gene_ids_map, $unigene2gene_ids_map);
    my $total_genes_parsed = 0;
    for my $organism_name (sort keys %CTK_ENTREZ_GENE_ORGANISM_DATA) {
        my %organism_gene_symbols;
        my $genes_parsed = 0;
        (my $organism_file_basename = $organism_name) =~ s/\s+/_/g;
        print "Parsing $organism_file_basename.gene_info: ";
        open(my $gene_info_fh, '<', "$entrez_data_work_dir/$organism_file_basename.gene_info") 
            or die "\n\nERROR: could not open $entrez_data_work_dir/$organism_file_basename.gene_info: $!\n\n";
        while (<$gene_info_fh>) {
            m/^#/ && next;
            my ($tax_id, $gene_id, $gene_symbol, undef, $symbol_synonyms_str, undef, $chromosome, undef, $gene_desc) = split /\t/;
            s/\s+//g for $tax_id, $gene_id, $gene_symbol, $chromosome;
            $symbol_synonyms_str =~ s/^\s+//;
            $symbol_synonyms_str =~ s/\s+$//;
            die "\n\nERROR: Organism Tax ID $tax_id is not an integer\n\n" unless is_integer($tax_id);
            die "\n\nERROR: Gene ID $gene_id is not an integer\n\n" unless is_integer($gene_id);
            die "\n\nERROR: Gene ID $gene_id defined more than once (there is a problem with Entrez Gene gene_info file)\n\n" if exists $gene_info_hashref->{$gene_id};
            $all_tax_ids{$tax_id}++;
            $gene_info_hashref->{$gene_id}->{organism_tax_id} = $tax_id;
            $gene_info_hashref->{$gene_id}->{symbol} = $gene_symbol;
            $add_gene_info_hashref->{$gene_id}->{description} = ($gene_desc and $gene_desc ne '-') ? $gene_desc : undef;
            $add_gene_info_hashref->{$gene_id}->{synonyms} = ($symbol_synonyms_str and $symbol_synonyms_str ne '-') ? $symbol_synonyms_str : undef;
            # add gene symbols and maps for organism and only those from organism mitochondria which don't already exist for organism
            if ($tax_id == $CTK_ENTREZ_GENE_ORGANISM_DATA{$organism_name}{tax_id} or !exists $organism_gene_symbols{$gene_symbol}) {
                $organism_gene_symbols{$gene_symbol}++;
                $symbol2gene_ids_map->{$organism_name}->{$gene_symbol}->{$gene_id}++;
                $uc_symbol2gene_ids_map->{$organism_name}->{uc($gene_symbol)}->{$gene_id}++;
                $gene_id2symbols_map->{$organism_name}->{$gene_id}->{$gene_symbol}++;
            }
            $genes_parsed++;
        }
        close($gene_info_fh);
        # organism gene symbol synonyms need to be processed after loading all organism official gene symbols because 
        # I need to know all official gene symbols to determine which gene symbol synonyms are really valid or not
        for my $gene_id (keys %{$gene_id2symbols_map->{$organism_name}}) {
            next unless defined $add_gene_info_hashref->{$gene_id}->{synonyms};
            my @valid_symbol_synonyms;
            for my $symbol_synonym (split /\|/, $add_gene_info_hashref->{$gene_id}->{synonyms}) {
                $symbol_synonym =~ s/^\s+//;
                $symbol_synonym =~ s/\s+$//;
                # if gene symbol synonym is not the same as an official gene symbol for this organism then it is valid, otherwise invalid
                if (!exists $organism_gene_symbols{$symbol_synonym}) {
                    $symbol2gene_ids_map->{$organism_name}->{$symbol_synonym}->{$gene_id}++;
                    $uc_symbol2gene_ids_map->{$organism_name}->{uc($symbol_synonym)}->{$gene_id}++;
                    # reverse map of gene symbol synonyms doesn't really make sense but it's only for reference
                    $gene_id2symbols_map->{$organism_name}->{$gene_id}->{$symbol_synonym}++;
                    # to update $add_gene_info_hashref synonyms below
                    push @valid_symbol_synonyms, $symbol_synonym;
                }
            }
            $add_gene_info_hashref->{$gene_id}->{synonyms} = join '|', @valid_symbol_synonyms;
        }
        print "$genes_parsed genes\n";
        die "\n\nERROR: problem parsing, 0 genes parsed!\n\n" if $genes_parsed == 0;
        $total_genes_parsed += $genes_parsed;
    }
    print "--> $total_genes_parsed <-- total current genes\n";
    # parse latest Entrez Gene gene_history
    my $relevant_old_genes_processed = 0;
    print "Parsing gene_history: ";
    open(my $gene_history_fh, '<', "$entrez_data_work_dir/gene_history") or die "\n\nERROR: Could not open $entrez_data_work_dir/gene_history: $!\n\n";
    while (<$gene_history_fh>) {
        m/^#/ && next;
        my ($tax_id, $current_gene_id, $discontinued_gene_id) = split /\t/;
        s/\s+//g for $tax_id, $current_gene_id, $discontinued_gene_id;
        die "\n\nERROR: Organism Tax ID $tax_id is not an integer\n\n" unless is_integer($tax_id);
        die "\n\nERROR: Gene ID $current_gene_id is not an integer\n\n" unless $current_gene_id eq '-' or is_integer($current_gene_id);
        die "\n\nERROR: discontinued Gene ID $discontinued_gene_id is not an integer\n\n" unless is_integer($discontinued_gene_id);
        die "\n\nERROR: discontinued Gene ID $discontinued_gene_id defined in current Entrez Gene data (there is a problem with Entrez Gene)\n\n" 
            if exists $gene_info_hashref->{$discontinued_gene_id};
        # only load gene history data lines for organisms used in our installation
        if (exists $all_tax_ids{$tax_id}) {
            if (!exists $gene_history_hashref->{$discontinued_gene_id}) {
                $gene_history_hashref->{$discontinued_gene_id}->{organism_tax_id} = $tax_id;
                $gene_history_hashref->{$discontinued_gene_id}->{current_gene_id} = $current_gene_id if $current_gene_id and $current_gene_id ne '-';
            }
            else {
                print "ERROR: discontinued Gene ID $discontinued_gene_id defined more than once (there is a problem with Entrez Gene)\n";
            }
            $relevant_old_genes_processed++;
        }
    }
    close($gene_history_fh);
    print "$relevant_old_genes_processed relevant discontinued gene IDs processed\n";
    # parse latest Entrez Gene gene2refseq
    my $refseqs_processed = 0;
    print "Parsing gene2refseq: ";
    open(my $gene2refseq_fh, '<', "$entrez_data_work_dir/gene2refseq") or die "\n\nERROR: Could not open $entrez_data_work_dir/gene2refseq: $!\n\n";
    while (<$gene2refseq_fh>) {
        m/^#/ && next;
        my ($tax_id, $gene_id, $status) = split /\t/;
        s/\s+//g for $tax_id, $gene_id, $status;
        # skip data lines for organisms not used in our installation
        next unless exists $gene_info_hashref->{$gene_id};
        $status = uc $status;
        # skip empty status
        next if $status eq 'NA';
        die "\n\nERROR: Organism Tax ID $tax_id is not an integer\n\n" unless is_integer($tax_id);
        die "\n\nERROR: Gene ID $gene_id is not an integer\n\n" unless is_integer($gene_id);
        die "\n\nERROR: Unsupported status $status for Gene ID $gene_id\n\n" unless exists $CTK_ENTREZ_GENE_REFSEQ_STATUS_DATA{$status};
        $gene_info_hashref->{$gene_id}->{status} = $status
            if !exists $gene_info_hashref->{$gene_id}->{status} or 
               $CTK_ENTREZ_GENE_REFSEQ_STATUS_DATA{$status}{rank} < $CTK_ENTREZ_GENE_REFSEQ_STATUS_DATA{$gene_info_hashref->{$gene_id}->{status}}{rank};
        $refseqs_processed++;
    }
    close($gene2refseq_fh);
    print "$refseqs_processed relevant Refseq status entries processed\n";
    # parse latest Entrez Gene gene2accession
    my $accessions_processed = 0;
    print "Parsing gene2accession: ";
    open(my $gene2accession_fh, '<', "$entrez_data_work_dir/gene2accession") or die "\n\nERROR: Could not open $entrez_data_work_dir/gene2accession: $!\n\n";
    while (<$gene2accession_fh>) {
        m/^#/ && next;
        my ($tax_id, $gene_id, $status, $transcript_accession) = split /\t/;
        s/\s+//g for $tax_id, $gene_id, $status, $transcript_accession;
        # skip data lines for organisms not used in our installation
        next unless exists $gene_info_hashref->{$gene_id};
        # strip off accession version
        $transcript_accession =~ s/\.\d+$//;
        #$status = uc $status;
        die "\n\nERROR: Organism Tax ID $tax_id is not an integer\n\n" unless is_integer($tax_id);
        die "\n\nERROR: Gene ID $gene_id is not an integer\n\n" unless is_integer($gene_id);
        #die "\n\nERROR: Unsupported status $status for Gene ID $gene_id\n\n" unless exists $CTK_ENTREZ_GENE_REFSEQ_STATUS_DATA{$status};
        $accession2gene_ids_map->{$transcript_accession}->{$gene_id}++;
        $accessions_processed++;
    }
    close($gene2accession_fh);
    print "$accessions_processed relevant accession entries processed\n";
    # parse latest Entrez Gene gene2ensembl
    my $ensembl_ids_processed = 0;
    print "Parsing gene2ensembl: ";
    open(my $gene2ensembl_fh, '<', "$entrez_data_work_dir/gene2ensembl") or die "\n\nERROR: Could not open $entrez_data_work_dir/gene2ensembl: $!\n\n";
    while (<$gene2ensembl_fh>) {
        m/^#/ && next;
        my ($tax_id, $gene_id, $ensembl_gene_id) = split /\t/;
        s/\s+//g for $tax_id, $gene_id, $ensembl_gene_id;
        # skip data lines for organisms not used in our installation
        next unless exists $gene_info_hashref->{$gene_id};
        die "\n\nERROR: Organism Tax ID $tax_id is not an integer\n\n" unless is_integer($tax_id);
        die "\n\nERROR: Gene ID $gene_id is not an integer\n\n" unless is_integer($gene_id);
        $ensembl2gene_ids_map->{$ensembl_gene_id}->{$gene_id}++;
        $ensembl_ids_processed++;
    }
    close($gene2ensembl_fh);
    print "$ensembl_ids_processed relevant ensembl entries processed\n";
    # parse latest Entrez Gene gene2unigene
    my $unigene_ids_processed = 0;
    print "Parsing gene2unigene: ";
    open(my $gene2unigene_fh, '<', "$entrez_data_work_dir/gene2unigene") or die "\n\nERROR: Could not open $entrez_data_work_dir/gene2unigene: $!\n\n";
    while (<$gene2unigene_fh>) {
        m/^#/ && next;
        my ($gene_id, $unigene_id) = split /\t/;
        s/\s+//g for $gene_id, $unigene_id;
        # skip data lines for organisms not used in our installation
        next unless exists $gene_info_hashref->{$gene_id};
        die "\n\nERROR: Gene ID $gene_id is not an integer\n\n" unless is_integer($gene_id);
        die "\n\nERROR: Unigene ID $unigene_id is not valid\n\n" unless $unigene_id =~ /^[A-Za-z]+\.\d+$/;
        $unigene2gene_ids_map->{$unigene_id}->{$gene_id}++;
        $unigene_ids_processed++;
    }
    close($gene2unigene_fh);
    print "$unigene_ids_processed relevant unigene entries processed\n";
    # lock data structures
    Hash::Util::lock_hashref_recurse($gene_info_hashref);
    Hash::Util::lock_hashref_recurse($gene_history_hashref);
    Hash::Util::lock_hashref_recurse($add_gene_info_hashref);
    Hash::Util::lock_hashref_recurse($symbol2gene_ids_map);
    Hash::Util::lock_hashref_recurse($uc_symbol2gene_ids_map);
    Hash::Util::lock_hashref_recurse($gene_id2symbols_map);
    Hash::Util::lock_hashref_recurse($accession2gene_ids_map);
    Hash::Util::lock_hashref_recurse($ensembl2gene_ids_map);
    Hash::Util::lock_hashref_recurse($unigene2gene_ids_map);
    # initialize EntrezGene singleton object
    Confero::EntrezGene->instance(
        gene_info => $gene_info_hashref,
        gene_history => $gene_history_hashref,
        add_gene_info => $add_gene_info_hashref,
        symbol2gene_ids => $symbol2gene_ids_map,
        uc_symbol2gene_ids => $uc_symbol2gene_ids_map,
        accession2gene_ids => $accession2gene_ids_map,
        ensembl2gene_ids => $ensembl2gene_ids_map,
        unigene2gene_ids => $unigene2gene_ids_map,
    );
    # serialize and store data structures
    print "Serializing and storing gene_info.pls\n";
    lock_nstore($gene_info_hashref, "$entrez_data_tmp_dir/gene_info.pls") 
        or die "\n\nERROR: could not serialize and store to $entrez_data_tmp_dir/gene_info.pls: $!\n\n";
    print "Serializing and storing add_gene_info.pls\n";
    lock_nstore($add_gene_info_hashref, "$entrez_data_tmp_dir/add_gene_info.pls") 
        or die "\n\nERROR: could not serialize and store to $entrez_data_tmp_dir/add_gene_info.pls: $!\n\n";
    print "Serializing and storing gene_history.pls\n";
    lock_nstore($gene_history_hashref, "$entrez_data_tmp_dir/gene_history.pls") 
        or die "\n\nERROR: could not serialize and store to $entrez_data_tmp_dir/gene_history.pls: $!\n\n";
    print "Serializing and storing symbol2gene_ids.pls\n";
    lock_nstore($symbol2gene_ids_map, "$entrez_data_tmp_dir/symbol2gene_ids.pls") 
        or die "\n\nERROR: could not serialize and store to $entrez_data_tmp_dir/symbol2gene_ids.pls: $!\n\n";
    print "Serializing and storing uc_symbol2gene_ids.pls\n";
    lock_nstore($uc_symbol2gene_ids_map, "$entrez_data_tmp_dir/uc_symbol2gene_ids.pls") 
        or die "\n\nERROR: could not serialize and store to $entrez_data_tmp_dir/uc_symbol2gene_ids.pls: $!\n\n";
    print "Serializing and storing accession2gene_ids.pls\n";
    lock_nstore($accession2gene_ids_map, "$entrez_data_tmp_dir/accession2gene_ids.pls") 
        or die "\n\nERROR: could not serialize and store to $entrez_data_tmp_dir/accession2gene_ids.pls: $!\n\n";
    print "Serializing and storing ensembl2gene_ids.pls\n";
    lock_nstore($ensembl2gene_ids_map, "$entrez_data_tmp_dir/ensembl2gene_ids.pls")
        or die "\n\nERROR: could not serialize and store to $entrez_data_tmp_dir/ensembl2gene_ids.pls: $!\n\n";
    print "Serializing and storing unigene2gene_ids.pls\n";
    lock_nstore($unigene2gene_ids_map, "$entrez_data_tmp_dir/unigene2gene_ids.pls")
        or die "\n\nERROR: could not serialize and store to $entrez_data_tmp_dir/unigene2gene_ids.pls: $!\n\n";
    # generate organism gene symbol mapping files
    print "\n[Gene Symbol Mapping Files]\n";
    for my $organism_name (sort keys %CTK_ENTREZ_GENE_ORGANISM_DATA) {
        (my $organism_file_basename = $organism_name) =~ s/\s+/_/g;
        my $map_file_basename = "${organism_file_basename}${CTK_DATA_ID_MAPPING_GENE_SYMBOL_SUFFIX}";
        my $num_maps_written = 0;
        print "Generating ${map_file_basename}.map: ";
        open(my $map_fh, '>', "$mapping_data_work_dir/${map_file_basename}.map") 
            or die "Could not create mapping file $mapping_data_work_dir/${map_file_basename}.map: $!";
        print $map_fh "Gene Symbol\tEntrez Gene IDs\n";
        for my $gene_symbol (natkeysort { lc } keys %{$symbol2gene_ids_map->{$organism_name}}) {
            my @gene_ids = nsort keys %{$symbol2gene_ids_map->{$organism_name}->{$gene_symbol}};
            print $map_fh "$gene_symbol\t", join("\t", @gene_ids), "\n";
            if (scalar(@gene_ids) == 1) {
                $gene_symbol2id_bestmap->{$organism_name}->{$gene_symbol}->{gene_id} = $gene_ids[0];
            }
            else {
                $gene_symbol2id_bestmap->{$organism_name}->{$gene_symbol}->{gene_id} = undef;
                $gene_symbol2id_bestmap->{$organism_name}->{$gene_symbol}->{ambig_gene_map}++;
            }
            $num_maps_written++;
        }
        close($map_fh);
        print "$num_maps_written maps\n";
        # lock data structure
        Hash::Util::lock_hashref_recurse($gene_symbol2id_bestmap->{$organism_name});
        $num_maps_written = 0;
        print "Generating ${map_file_basename}.ucmap: ";
        open(my $ucmap_fh, '>', "$mapping_data_work_dir/${map_file_basename}.ucmap") 
            or die "Could not create mapping file $mapping_data_work_dir/${map_file_basename}.ucmap: $!";
        print $ucmap_fh "Gene Symbol\tEntrez Gene IDs\n";
        for my $uc_gene_symbol (natsort keys %{$uc_symbol2gene_ids_map->{$organism_name}}) {
            my @gene_ids = nsort keys %{$uc_symbol2gene_ids_map->{$organism_name}->{$uc_gene_symbol}};
            print $ucmap_fh "$uc_gene_symbol\t", join("\t", @gene_ids), "\n";
            $num_maps_written++;
        }
        close($ucmap_fh);
        print "$num_maps_written maps\n";
        # write out reverse map file (not used by Confero only for human reference)
        $num_maps_written = 0;
        print "Generating ${map_file_basename}.revmap: ";
        open(my $revmap_fh, '>', "$mapping_data_work_dir/${map_file_basename}.revmap") 
            or die "Could not create mapping file $mapping_data_work_dir/${map_file_basename}.revmap: $!";
        print $revmap_fh "Entrez Gene ID\tGene Symbols (first in list is official symbol)\n";
        for my $gene_id (nsort keys %{$gene_id2symbols_map->{$organism_name}}) {
            # first gene symbol is official symbol, followed by symbol synonyms
            print $revmap_fh "$gene_id\t", join("\t", 
                $gene_info_hashref->{$gene_id}->{symbol}, 
                natkeysort { lc } grep { $_ ne $gene_info_hashref->{$gene_id}->{symbol} } keys %{$gene_id2symbols_map->{$organism_name}->{$gene_id}}
            ), "\n";
            $num_maps_written++;
        }
        close($revmap_fh);
        print "$num_maps_written maps\n";
        # write out best map file
        $num_maps_written = 0;
        print "Generating ${map_file_basename}.bestmap: ";
        open(my $bestmap_fh, '>', "$mapping_data_work_dir/${map_file_basename}.bestmap") 
            or die "Could not create mapping file $mapping_data_work_dir/${map_file_basename}.bestmap: $!";
        print $bestmap_fh "Gene Symbol\tEntrez Gene ID\n";
        for my $gene_symbol (natkeysort { lc } keys %{$gene_symbol2id_bestmap->{$organism_name}}) {
            print $bestmap_fh "$gene_symbol\t", defined $gene_symbol2id_bestmap->{$organism_name}->{$gene_symbol}->{gene_id} 
                ? $gene_symbol2id_bestmap->{$organism_name}->{$gene_symbol}->{gene_id} 
                : '', 
                "\n";
            $num_maps_written++;
        }
        close($bestmap_fh);
        print "$num_maps_written maps\n";
        # serialize and store data structures
        #print "Serializing and storing ${map_file_basename}.map.pls\n";
        #lock_nstore($symbol2gene_ids_map->{$organism_name}, "$mapping_data_work_dir/${map_file_basename}.map.pls") 
        #    or die "\n\nERROR: could not serialize and store to $mapping_data_work_dir/${map_file_basename}.map.pls: $!\n\n";
        print "Serializing and storing ${map_file_basename}.ucmap.pls\n";
        lock_nstore($uc_symbol2gene_ids_map->{$organism_name}, "$mapping_data_work_dir/${map_file_basename}.ucmap.pls") 
            or die "\n\nERROR: could not serialize and store to $mapping_data_work_dir/${map_file_basename}.ucmap.pls: $!\n\n";
        #print "Serializing and storing ${map_file_basename}.revmap.pls\n";
        #lock_nstore($gene_id2symbols_map->{$organism_name}, "$mapping_data_work_dir/${map_file_basename}.revmap.pls") 
        #    or die "\n\nERROR: could not serialize and store to $mapping_data_work_dir/${map_file_basename}.revmap.pls: $!\n\n";
        print "Serializing and storing ${map_file_basename}.bestmap.pls\n";
        lock_nstore($gene_symbol2id_bestmap->{$organism_name}, "$mapping_data_work_dir/${map_file_basename}.bestmap.pls") 
            or die "\n\nERROR: could not serialize and store to $mapping_data_work_dir/${map_file_basename}.bestmap.pls: $!\n\n";
    }
}
else {
    print "Skipping processing of Entrez Gene data, using existing local data structures\n";
    # don't do any more now that have Confero::EntrezGene singleton object
    #$gene_info_hashref = lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/gene_info.pls") 
    #    or die "\n\nERROR: could not deserialize and retrieve $CTK_ENTREZ_GENE_DATA_DIR/gene_info.pls: $!\n\n";
    #$add_gene_info_hashref = lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/add_gene_info.pls") 
    #    or die "\n\nERROR: could not deserialize and retrieve $CTK_ENTREZ_GENE_DATA_DIR/add_gene_info.pls: $!\n\n";
    #$gene_history_hashref = lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/gene_history.pls") 
    #    or die "\n\nERROR: could not deserialize and retrieve $CTK_ENTREZ_GENE_DATA_DIR/gene_history.pls: $!\n\n";
    #$symbol2gene_ids_map = lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/symbol2gene_ids.pls") 
    #    or die "\n\nERROR: could not deserialize and retrieve $CTK_ENTREZ_GENE_DATA_DIR/symbol2gene_ids.pls: $!\n\n";
    #$uc_symbol2gene_ids_map = lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/uc_symbol2gene_ids.pls") 
    #    or die "\n\nERROR: could not deserialize and retrieve $CTK_ENTREZ_GENE_DATA_DIR/uc_symbol2gene_ids.pls: $!\n\n";
    #$accession2gene_ids_map = lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/accession2gene_ids.pls") 
    #    or die "\n\nERROR: could not deserialize and retrieve $CTK_ENTREZ_GENE_DATA_DIR/accession2gene_ids.pls: $!\n\n";
    #$ensembl2gene_ids_map = lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/ensembl2gene_ids.pls") 
    #    or die "\n\nERROR: could not deserialize and retrieve $CTK_ENTREZ_GENE_DATA_DIR/ensembl2gene_ids.pls: $!\n\n";
    #$unigene2gene_ids_map = lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/unigene2gene_ids.pls") 
    #    or die "\n\nERROR: could not deserialize and retrieve $CTK_ENTREZ_GENE_DATA_DIR/unigene2gene_ids.pls: $!\n\n";
    for my $organism_name (sort keys %CTK_ENTREZ_GENE_ORGANISM_DATA) {
        (my $organism_file_basename = $organism_name) =~ s/\s+/_/g;
        my $map_file_basename = "${organism_file_basename}${CTK_DATA_ID_MAPPING_GENE_SYMBOL_SUFFIX}";
        $gene_symbol2id_bestmap->{$organism_name} = lock_retrieve("$CTK_DATA_ID_MAPPING_FILE_DIR/${map_file_basename}.bestmap.pls") 
            or die "\n\nERROR: could not deserialize and retrieve $CTK_DATA_ID_MAPPING_FILE_DIR/${map_file_basename}.bestmap.pls: $!\n\n";
    }
}
# get EntrezGene data structures
my $gene_info_hashref = Confero::EntrezGene->instance()->gene_info;
my $add_gene_info_hashref = Confero::EntrezGene->instance()->add_gene_info;
my $gene_history_hashref = Confero::EntrezGene->instance()->gene_history;
my $symbol2gene_ids_map = Confero::EntrezGene->instance()->symbol2gene_ids;
my $accession2gene_ids_map = Confero::EntrezGene->instance()->accession2gene_ids;
my $ensembl2gene_ids_map = Confero::EntrezGene->instance()->ensembl2gene_ids;
my $unigene2gene_ids_map = Confero::EntrezGene->instance()->unigene2gene_ids;
# platform mapping file processing
if (!$no_entrez_download) {
    $no_mapping_file_processing = 0;
    $no_netaffx_processing = 0;
    $no_agilent_processing = 0;
    $no_geo_processing = 0;
    $no_illumina_processing = 0;
}
$download_netaffx = 0 if $no_netaffx_processing;
$no_netaffx_processing = 0 if $download_netaffx;
$download_agilent = 0 if $no_agilent_processing;
$no_agilent_processing = 0 if $download_agilent;
$download_geo = 0 if $no_geo_processing;
$no_geo_processing = 0 if $download_geo;
$download_illumina = 0 if $no_illumina_processing;
$no_illumina_processing = 0 if $download_illumina;
print "\n[Platform Mapping Files]\n";
my ($src2gene_id_bestmap, $netaffx_data_work_dir, $agilent_data_work_dir, $geo_data_work_dir, $illumina_data_work_dir);
if (!$no_mapping_file_processing) {
    # Affymetrix
    if (!$no_netaffx_processing) {
        if (!$no_interactive and !$download_netaffx) {
            print "Would you like to download NetAffx annotation files? (type 'no' to use existing local files) [yes] ";
            chomp(my $answer = <STDIN>);
            $answer = 'yes' if $answer eq '';
            $download_netaffx = ($answer =~ /^y(es|)$/i) ? 1 : 0;
        }
        if ($download_netaffx) {
            $netaffx_data_work_dir = "$tmp_dir/affymetrix";
            for my $array_symbol (sort keys %CTK_AFFY_ARRAY_DATA) {
                die "\n\nERROR: problem with $array_symbol Affymetrix configuration! Missing annot_file_uri hash key/value, please check the configuration file.\n\n"
                    unless defined $CTK_AFFY_ARRAY_DATA{$array_symbol}{annot_file_uri};
                # download annotation file
                my ($annot_zip_file_basename, undef, $annot_zip_file_ext) = fileparse($CTK_AFFY_ARRAY_DATA{$array_symbol}{annot_file_uri}, qr/\.[^.]*/);
                my $ff = File::Fetch->new(uri => $CTK_AFFY_ARRAY_DATA{$array_symbol}{annot_file_uri}) or die "\n\nERROR: File::Fetch object constructor error\n\n";
                print "Fetching $annot_zip_file_basename$annot_zip_file_ext\n";
                $ff->fetch(to => $netaffx_data_work_dir) or die "\n\nERROR: File::Fetch fetch error: ", $ff->error, "\n\n";
            }
        }
        else {
            $netaffx_data_work_dir = $CTK_AFFY_ANNOT_DATA_DIR;
            print "Skipping download of NetAffx annotation files, using existing local files\n";
        }
        for my $array_symbol (sort keys %CTK_AFFY_ARRAY_DATA) {
            die "\n\nERROR: problem with $array_symbol Affymetrix configuration! Missing annot_file_uri hash key/value, please check the CTK configuration file.\n\n"
                unless defined $CTK_AFFY_ARRAY_DATA{$array_symbol}{annot_file_uri};
            # uncompress annotation file
            my ($annot_zip_file_basename, undef, $annot_zip_file_ext) = fileparse($CTK_AFFY_ARRAY_DATA{$array_symbol}{annot_file_uri}, qr/\.[^.]*/);
            my $annot_zip_file_path = "$netaffx_data_work_dir/$annot_zip_file_basename$annot_zip_file_ext";
            print "Uncompressing $annot_zip_file_basename$annot_zip_file_ext\n";
            if ($annot_zip_file_ext) {
                my $uncompress_cmd = lc($annot_zip_file_ext) eq '.zip' ? "unzip -oq $annot_zip_file_path -d $netaffx_data_work_dir"
                                   : lc($annot_zip_file_ext) eq '.gz'  ? "gzip -df $annot_zip_file_path"
                                   : die "\n\nERROR: unsupported compressed file extension '$annot_zip_file_ext'\n\n";
                system($uncompress_cmd) == 0 or die "\nERROR: $uncompress_cmd system call error: ", $? >> 8, "\n\n";
            }
            # parse annotation file and create map file
            my $annot_csv_file_name = $annot_zip_file_basename;
            print "Parsing $annot_csv_file_name and generating ${array_symbol}.map\n";
            my ($process_field_names, %field_pos, $probesets_processed, $netaffx_annot_tab_format_version);
            open(my $annot_csv_fh, '<', "$netaffx_data_work_dir/$annot_csv_file_name") 
                or die "\n\nERROR: could not open input annotation file $netaffx_data_work_dir/$annot_csv_file_name: $!\n\n";
            open(my $map_fh, '>', "$mapping_data_work_dir/$array_symbol.map") 
                or die "\n\nERROR: could not create output mapping file $mapping_data_work_dir/$array_symbol.map: $!\n\n";
            print $map_fh "Probeset ID\tEntrez Gene IDs\n";
            while(<$annot_csv_fh>) {
                s/^\s+//;
                s/\s+$//;
                m/^##/ && next;
                m/^\s*$/ && next;
                # header
                if (m/^#%/) {
                    s/^#%//;
                    my ($field, $value) = split /=/, $_, 2;
                    # header field processing
                    if ($field eq 'netaffx-annotation-tabular-format-version') {
                        $netaffx_annot_tab_format_version = $value;
                        if ($netaffx_annot_tab_format_version ne '1.0' and 
                            $netaffx_annot_tab_format_version ne '1.1' and 
                            $netaffx_annot_tab_format_version ne '1.11') {
                            die "\nERROR: unsupported NetAffx annotation tabular format version $netaffx_annot_tab_format_version\n\n";
                        }
                    }
                    $process_field_names++ unless $process_field_names;
                    next;
                }
                # field names
                elsif ($process_field_names) {
                    my @field_names = m/"(.+?)"/g;
                    for my $i (0 .. $#field_names) {
                        $field_pos{lc($field_names[$i])} = $i;
                    }
                    $process_field_names = undef;
                    next;
                }
                # field data
                my @field_data = m/"(.*?)"/g;
                for (@field_data) {
                    s/^\s+//;
                    s/\s+$//;
                    s/^---$//
                }
                my %entrez_gene_ids;
                if (defined $netaffx_annot_tab_format_version and $netaffx_annot_tab_format_version eq '1.0') {
                    print $map_fh $field_data[$field_pos{lc('Probe Set ID')}], "\t";
                    if ($field_data[$field_pos{lc('Entrez Gene')}]) {
                        my @entrez_gene_ids = split /$AFFY_ANNOT_SEPARATOR/o, $field_data[$field_pos{lc('Entrez Gene')}];
                        for my $entrez_gene_id (@entrez_gene_ids) {
                            die "\n\nERROR: Entrez Gene ID '$entrez_gene_id' is not an integer\n\n" unless is_integer($entrez_gene_id);
                            $entrez_gene_ids{$entrez_gene_id}++;
                        }
                    }
                }
                # for some reason sometimes they don't put the version in the metadata header for 1.1 and 1.11
                #elsif ($netaffx_annot_tab_format_version eq '1.1' or 
                #       $netaffx_annot_tab_format_version eq '1.11') {
                else {
                    print $map_fh "$field_data[$field_pos{'probeset_id'}]\t";
                    if ($field_data[$field_pos{'gene_assignment'}]) {
                        my @gene_data = split /$AFFY_ANNOT_SEPARATOR/o, $field_data[$field_pos{'gene_assignment'}];
                        for my $gene_info (@gene_data) {
                            my ($accession, $gene_symbol, $gene_title, $cytoband, $entrez_gene_id) = split /\s*\/\/\s*/, $gene_info;
                            # sometimes Entrez Gene info fields can be truncated so have to check if ID is defined
                            if (defined $entrez_gene_id) {
                                die "\n\nERROR: Entrez Gene ID '$entrez_gene_id' is not an integer\n\n" unless is_integer($entrez_gene_id);
                                $entrez_gene_ids{$entrez_gene_id}++;
                            }
                        }
                    }
                }
                my $current_entrez_gene_ids_tsv = join("\t", update_platform_gene_ids(keys %entrez_gene_ids));
                print $map_fh $current_entrez_gene_ids_tsv ? $current_entrez_gene_ids_tsv : '', "\n";
                #print "$probesets_processed probesets processed\n" if ++$probesets_processed % 100000 == 0;
                $probesets_processed++;
            }
            close($annot_csv_fh);
            close($map_fh);
            print "$probesets_processed probesets processed\n";
            $src2gene_id_bestmap->{$array_symbol} = process_platform_mapping_files($array_symbol);
            # we delete unzipped annotation file and keep only zipped one
            unlink("$netaffx_data_work_dir/$annot_csv_file_name") or warn "WARNING: could not remove temporary $netaffx_data_work_dir/$annot_csv_file_name: $!\n";
        }
    }
    else {
        print "Skipping NetAffx annotation file processing, using existing local mapping data structures\n";
        for my $array_symbol (sort keys %CTK_AFFY_ARRAY_DATA) {
            $src2gene_id_bestmap->{$array_symbol} = lock_retrieve("$CTK_DATA_ID_MAPPING_FILE_DIR/${array_symbol}.bestmap.pls")
                or die "\n\nERROR: could not deserialize and retrieve $CTK_DATA_ID_MAPPING_FILE_DIR/${array_symbol}.bestmap.pls: $!\n\n";
        }
    }
    # Agilent
    if (!$no_agilent_processing) {
        if (!$no_interactive and !$download_agilent) {
            print "Would you like to download Agilent annotation files? (type 'no' to use existing local files) [yes] ";
            chomp(my $answer = <STDIN>);
            $answer = 'yes' if $answer eq '';
            $download_agilent = ($answer =~ /^y(es|)$/i) ? 1 : 0;
        }
        if ($download_agilent) {
            $agilent_data_work_dir = "$tmp_dir/agilent";
            #for my $array_symbol (sort keys %CTK_AGILENT_ARRAY_DATA) {
            #    die "\n\nERROR: problem with $array_symbol Agilent configuration! Missing annot_file_uri hash key/value, please check the configuration file.\n\n"
            #        unless defined $CTK_AGILENT_ARRAY_DATA{$array_symbol}{annot_file_uri};
            #    # download annotation file
            #    my ($annot_zip_file_basename, undef, $annot_zip_file_ext) = fileparse($CTK_AGILENT_ARRAY_DATA{$array_symbol}{annot_file_uri}, qr/\.[^.]*/);
            #    my $ff = File::Fetch->new(uri => $CTK_AGILENT_ARRAY_DATA{$array_symbol}{annot_file_uri}) or die "\n\nERROR: File::Fetch object constructor error\n\n";
            #    print "Fetching $annot_zip_file_basename$annot_zip_file_ext\n";
            #    $ff->fetch(to => $agilent_data_work_dir) or die "\n\nERROR: File::Fetch fetch error: ", $ff->error, "\n\n";
            #}
        }
        else {
            $agilent_data_work_dir = $CTK_AGILENT_ANNOT_DATA_DIR;
            print "Skipping download of Agilent annotation files, using existing local files\n";
        }
        for my $array_name (sort keys %CTK_AGILENT_ARRAY_DATA) {
            # get annotation file
            my $annot_csv_file_name;
            for my $annot_file_path (<$agilent_data_work_dir/*>) {
                my $file_name = fileparse($annot_file_path);
                if ($file_name =~ /^$CTK_AGILENT_ARRAY_DATA{$array_name}{design_id}/) {
                    $annot_csv_file_name = $file_name;
                    last;
                }
            }
            die "\n\nERROR: could not find Agilent annotation file for '$array_name' [design id: $CTK_AGILENT_ARRAY_DATA{$array_name}{design_id}]\n\n" unless $annot_csv_file_name;
            # put underscores into array name for file
            (my $array_name_for_file = $array_name) =~ s/\s/_/g;
            # parse annotation file and create map file
            print "Parsing $annot_csv_file_name and generating ${array_name_for_file}.map\n";
            my $probesets_processed = 0;
            open(my $annot_csv_fh, '<', "$agilent_data_work_dir/$annot_csv_file_name") 
                or die "\n\nERROR: could not open input annotation file $agilent_data_work_dir/$annot_csv_file_name: $!\n\n";
            open(my $map_fh, '>', "$mapping_data_work_dir/$array_name_for_file.map") 
                or die "\n\nERROR: could not create output mapping file $mapping_data_work_dir/$array_name_for_file.map: $!\n\n";
            print $map_fh "Probeset ID\tEntrez Gene IDs\n";
            while (<$annot_csv_fh>) {
                m/^(?:#|\s*Probe\s*ID)/i && next;
                my ($probeset_id, undef, undef, undef, undef, $entrez_gene_id) = split /\t/;
                s/\s+//g for $probeset_id, $entrez_gene_id;
                my $current_entrez_gene_ids_tsv;
                if ($entrez_gene_id) {
                    die "\n\nERROR: Entrez Gene ID '$entrez_gene_id' is not an integer\n\n" unless is_integer($entrez_gene_id);
                    $current_entrez_gene_ids_tsv = join("\t", update_platform_gene_ids($entrez_gene_id));
                }
                print $map_fh "$probeset_id\t", $current_entrez_gene_ids_tsv ? $current_entrez_gene_ids_tsv : '', "\n";
                $probesets_processed++;
            }
            close($annot_csv_fh);
            close($map_fh);
            print "$probesets_processed probesets processed\n";
            $src2gene_id_bestmap->{$array_name} = process_platform_mapping_files($array_name_for_file);
        }
    }
    else {
        print "Skipping Agilent annotation file processing, using existing local mapping data structures\n";
        for my $array_name (sort keys %CTK_AGILENT_ARRAY_DATA) {
            $src2gene_id_bestmap->{$array_name} = lock_retrieve("$CTK_DATA_ID_MAPPING_FILE_DIR/${array_name}.bestmap.pls")
                or die "\n\nERROR: could not deserialize and retrieve $CTK_DATA_ID_MAPPING_FILE_DIR/${array_name}.bestmap.pls: $!\n\n";
        }
    }
    # NCBI GEO
    if (!$no_geo_processing) {
        if (!$no_interactive and !$download_geo) {
            print "Would you like to download NCBI GEO annotation files? (type 'no' to use existing local files) [yes] ";
            chomp(my $answer = <STDIN>);
            $answer = 'yes' if $answer eq '';
            $download_geo = ($answer =~ /^y(es|)$/i) ? 1 : 0;
        }
        if ($download_geo) {
            $geo_data_work_dir = "$tmp_dir/geo";
            for my $array_symbol (sort keys %CTK_GEO_ARRAY_DATA) {
                die "\n\nERROR: problem with $array_symbol NCBI GEO configuration! Missing annot_file_uri hash key/value, please check the configuration file.\n\n"
                    unless defined $CTK_GEO_ARRAY_DATA{$array_symbol}{annot_file_uri};
                # download annotation file
                #my ($annot_zip_file_basename, undef, $annot_zip_file_ext) = fileparse($CTK_GEO_ARRAY_DATA{$array_symbol}{annot_file_uri}, qr/\.[^.]*/);
                my $ff = File::Fetch->new(uri => $CTK_GEO_ARRAY_DATA{$array_symbol}{annot_file_uri}) or die "\n\nERROR: File::Fetch object constructor error\n\n";
                print "Fetching GEO ${array_symbol}.txt ($CTK_GEO_ARRAY_DATA{$array_symbol}{name})\n";
                $ff->fetch(to => \my $geo_annot_file_str) or die "\n\nERROR: File::Fetch fetch error: ", $ff->error, "\n\n";
                open(my $annot_fh, '>', "$geo_data_work_dir/${array_symbol}.txt") 
                    or die "\n\nERROR: could not create $geo_data_work_dir/${array_symbol}.txt: $!\n\n";
                print $annot_fh $geo_annot_file_str;
                close($annot_fh);
            }
        }
        else {
            $geo_data_work_dir = $CTK_GEO_ANNOT_DATA_DIR;
            print "Skipping download of NCBI GEO annotation files, using existing local files\n";
        }
        for my $array_symbol (sort keys %CTK_GEO_ARRAY_DATA) {
            die "\n\nERROR: problem with $array_symbol NCBI GEO configuration! Missing annot_file_uri hash key/value, please check the CTK configuration file.\n\n"
                unless defined $CTK_GEO_ARRAY_DATA{$array_symbol}{annot_file_uri};
            # parse annotation file and create map file
            my $annot_csv_file_name = "${array_symbol}.txt";
            print "Parsing $annot_csv_file_name and generating ${array_symbol}.map\n";
            my %col_idx;
            my $probesets_processed = 0;
            open(my $annot_csv_fh, '<', "$geo_data_work_dir/$annot_csv_file_name") 
                or die "\n\nERROR: could not open input annotation file $geo_data_work_dir/$annot_csv_file_name: $!\n\n";
            open(my $map_fh, '>', "$mapping_data_work_dir/$array_symbol.map") 
                or die "\n\nERROR: could not create output mapping file $mapping_data_work_dir/$array_symbol.map: $!\n\n";
            print $map_fh "Probeset ID\tEntrez Gene IDs\n";
            while(<$annot_csv_fh>) {
                s/^\s+//;
                s/\s+$//;   
                # column header
                if (m/^!platform_table_begin/i) {
                    my @col_names = split /\t/, <$annot_csv_fh>;
                    for my $i (0 .. $#col_names) {
                        $col_names[$i] =~ s/\s+//g;
                        if ($col_names[$i] =~ /^id$/i) {
                            $col_idx{id} = $i;
                        }
                        elsif ($col_names[$i] =~ /^(entrez|)(_| |)gene(_| |)id$/i) {
                            $col_idx{gene_id} = $i;
                        }
                        elsif ($col_names[$i] =~ /^(gene|)(_| |)symbol$/i) {
                            $col_idx{gene_symbol} = $i;
                        }
                        elsif ($col_names[$i] =~ /^refseq(_id| id|)$/i) {
                            $col_idx{refseq_id} = $i;
                        }
                        elsif ($col_names[$i] =~ /^(accession|gb_acc)$/i) {
                            $col_idx{accession} = $i;
                        }
                        elsif ($col_names[$i] =~ /^gb(_| |)list$/i) {
                            $col_idx{accession_list} = $i;
                        }         
                        elsif ($col_names[$i] =~ /^unigene(_| |)id$/i) {
                            $col_idx{unigene_id} = $i;
                        }
                        elsif ($col_names[$i] =~ /^spot(_id| id|)$/i) {
                            $col_idx{spot_id} = $i;
                        }
                    }
                }
                # file header
                elsif (m/^(\^|#|!)/) {
                    next;
                }
                # column data
                else {
                    my @entrez_gene_ids;
                    my @col_data = split /\t/;
                    s/\s+//g for @col_data;
                    if (defined $col_idx{gene_id} and $col_data[$col_idx{gene_id}]) {
                        push @entrez_gene_ids, $col_data[$col_idx{gene_id}];
                    }
                    elsif (defined $col_idx{gene_symbol} and $col_data[$col_idx{gene_symbol}] and 
                        defined $CTK_GEO_ARRAY_DATA{$array_symbol}{organism} and 
                        exists $symbol2gene_ids_map->{$CTK_GEO_ARRAY_DATA{$array_symbol}{organism}} and 
                        exists $symbol2gene_ids_map->{$CTK_GEO_ARRAY_DATA{$array_symbol}{organism}}->{$col_data[$col_idx{gene_symbol}]}) {
                        push @entrez_gene_ids, keys %{$symbol2gene_ids_map->{$CTK_GEO_ARRAY_DATA{$array_symbol}{organism}}->{$col_data[$col_idx{gene_symbol}]}};
                    }
                    elsif (defined $col_idx{unigene_id} and $col_data[$col_idx{unigene_id}] and exists $unigene2gene_ids_map->{$col_data[$col_idx{unigene_id}]}) {
                        push @entrez_gene_ids, keys %{$unigene2gene_ids_map->{$col_data[$col_idx{unigene_id}]}};
                    }
                    elsif (defined $col_idx{refseq_id} and $col_data[$col_idx{refseq_id}]) {
                        # strip off accession version
                        (my $accession = $col_data[$col_idx{refseq_id}]) =~ s/\.\d+$//;
                        if (exists $accession2gene_ids_map->{$accession}) {
                            push @entrez_gene_ids, keys %{$accession2gene_ids_map->{$accession}};
                        }
                        
                    }
                    elsif (defined $col_idx{accession} and $col_data[$col_idx{accession}]) {
                        # strip off accession version
                        (my $accession = $col_data[$col_idx{accession}]) =~ s/\.\d+$//;
                        if (exists $accession2gene_ids_map->{$accession}) {
                            push @entrez_gene_ids, keys %{$accession2gene_ids_map->{$accession}};
                        }
                    }
                    elsif (defined $col_idx{accession_list} and $col_data[$col_idx{accession_list}]) {
                        for my $accession (split /,/, $col_data[$col_idx{accession_list}]) {
                            # strip off accession version
                            $accession =~ s/\.\d+$//;
                            if (exists $accession2gene_ids_map->{$accession}) {
                                push @entrez_gene_ids, keys %{$accession2gene_ids_map->{$accession}};
                            }
                        }
                    }
                    elsif (defined $col_idx{spot_id} and $col_data[$col_idx{spot_id}]) {
                        if (my ($ensembl_id) = $col_data[$col_idx{spot_id}] =~ /^ensemble?:(\S+)$/i) {
                            if (exists $ensembl2gene_ids_map->{$ensembl_id}) {
                                push @entrez_gene_ids, keys %{$ensembl2gene_ids_map->{$ensembl_id}};
                            }
                        }
                        elsif (my ($id) = $col_data[$col_idx{spot_id}] =~ /^rosettageneid?:(\S+)$/i) {
                            if (exists $accession2gene_ids_map->{$id}) {
                                push @entrez_gene_ids, keys %{$accession2gene_ids_map->{$id}};
                            }
                            elsif (exists $ensembl2gene_ids_map->{$id}) {
                                push @entrez_gene_ids, keys %{$ensembl2gene_ids_map->{$id}};
                            }
                        }
                    }
                    my (%entrez_gene_ids, $current_entrez_gene_ids_tsv);
                    if (@entrez_gene_ids) {
                        for my $entrez_gene_id (@entrez_gene_ids) {
                            die "\n\nERROR: Entrez Gene ID '$entrez_gene_id' is not an integer\n\n" unless is_integer($entrez_gene_id);
                            $entrez_gene_ids{$entrez_gene_id}++;
                        }
                        $current_entrez_gene_ids_tsv = join("\t", update_platform_gene_ids(keys %entrez_gene_ids));
                    }
                    print $map_fh "$col_data[$col_idx{id}]\t", $current_entrez_gene_ids_tsv ? $current_entrez_gene_ids_tsv : '', "\n";
                    $probesets_processed++;
                }
            }
            close($annot_csv_fh);
            close($map_fh);
            print "$probesets_processed probesets processed\n";
            $src2gene_id_bestmap->{$array_symbol} = process_platform_mapping_files($array_symbol);
        }
    }
    else {
        print "Skipping NCBI GEO annotation file processing, using existing local mapping data structures\n";
        for my $array_symbol (sort keys %CTK_GEO_ARRAY_DATA) {
            $src2gene_id_bestmap->{$array_symbol} = lock_retrieve("$CTK_DATA_ID_MAPPING_FILE_DIR/${array_symbol}.bestmap.pls")
                or die "\n\nERROR: could not deserialize and retrieve $CTK_DATA_ID_MAPPING_FILE_DIR/${array_symbol}.bestmap.pls: $!\n\n";
        }
    }
    # Illumina
    if (!$no_illumina_processing) {
        if (!$no_interactive and !$download_illumina) {
            print "Would you like to download Illumina annotation files? (type 'no' to use existing local files) [yes] ";
            chomp(my $answer = <STDIN>);
            $answer = 'yes' if $answer eq '';
            $download_illumina = ($answer =~ /^y(es|)$/i) ? 1 : 0;
        }
        if ($download_illumina) {
            $illumina_data_work_dir = "$tmp_dir/illumina";
            #for my $array_symbol (sort keys %CTK_ILLUMINA_ARRAY_DATA) {
            #    die "\n\nERROR: problem with $array_symbol Illumina configuration! Missing annot_file_uri hash key/value, please check the configuration file.\n\n"
            #        unless defined $CTK_ILLUMINA_ARRAY_DATA{$array_symbol}{annot_file_uri};
            #    # download annotation file
            #    my ($annot_zip_file_basename, undef, $annot_zip_file_ext) = fileparse($CTK_ILLUMINA_ARRAY_DATA{$array_symbol}{annot_file_uri}, qr/\.[^.]*/);
            #    my $ff = File::Fetch->new(uri => $CTK_ILLUMINA_ARRAY_DATA{$array_symbol}{annot_file_uri}) or die "\n\nERROR: File::Fetch object constructor error\n\n";
            #    print "Fetching $annot_zip_file_basename$annot_zip_file_ext\n";
            #    $ff->fetch(to => $agilent_data_work_dir) or die "\n\nERROR: File::Fetch fetch error: ", $ff->error, "\n\n";
            #}
        }
        else {
            $illumina_data_work_dir = $CTK_ILLUMINA_ANNOT_DATA_DIR;
            print "Skipping download of Illumina annotation files, using existing local files\n";
        }
    }
    else {
        print "Skipping Illumina annotation file processing, using existing local mapping data structures\n";
        for my $array_symbol (sort keys %CTK_ILLUMINA_ARRAY_DATA) {
            $src2gene_id_bestmap->{$array_symbol} = lock_retrieve("$CTK_DATA_ID_MAPPING_FILE_DIR/${array_symbol}.bestmap.pls")
                or die "\n\nERROR: could not deserialize and retrieve $CTK_DATA_ID_MAPPING_FILE_DIR/${array_symbol}.bestmap.pls: $!\n\n";
        }
    }
}
else {
    print "Skipping mapping file processing, using existing local mapping data structures\n";
    for my $array_symbol ((sort keys %CTK_AFFY_ARRAY_DATA), (sort keys %CTK_AGILENT_ARRAY_DATA), (sort keys %CTK_GEO_ARRAY_DATA), (sort keys %CTK_ILLUMINA_ARRAY_DATA)) {
        $src2gene_id_bestmap->{$array_symbol} = lock_retrieve("$CTK_DATA_ID_MAPPING_FILE_DIR/${array_symbol}.bestmap.pls")
            or die "\n\nERROR: could not deserialize and retrieve $CTK_DATA_ID_MAPPING_FILE_DIR/${array_symbol}.bestmap.pls: $!\n\n";
    }
}
# auxiliary files processing
my $aux_files_exist = -f "$CTK_GSEA_MAPPING_FILE_DIR/EntrezGene.chip" and -f "$CTK_GSEA_MAPPING_FILE_DIR/GeneSymbol.chip" ? 1 : 0;
my $gsea_data_work_dir = "$tmp_dir/gsea";
if (!$no_entrez_processing or !$aux_files_exist) {
    print "\n[Auxiliary Files]\n";
    # create or replace EntrezGene.chip and GeneSymbol.chip GSEA files
    print "Generating GSEA EntrezGene.chip: ";
    open(my $entrez_gene_chip_fh, '>', "$gsea_data_work_dir/EntrezGene.chip") or die "Could not create $gsea_data_work_dir/EntrezGene.chip: $!";
    print $entrez_gene_chip_fh "Probe Set ID\tGene Symbol\tGene Title\n";
    for my $gene_id (nsort keys %{$gene_info_hashref}) {
        print $entrez_gene_chip_fh "$gene_id\t", uc($gene_info_hashref->{$gene_id}->{symbol}), "\t", $add_gene_info_hashref->{$gene_id}->{description} || '', "\n";
    }
    close($entrez_gene_chip_fh);
    print scalar(keys %{$gene_info_hashref}), " genes written\n";
    print "Generating GSEA GeneSymbol.chip: ";
    open(my $gene_symbol_chip_fh, '>', "$gsea_data_work_dir/GeneSymbol.chip") or die "Could not create $gsea_data_work_dir/GeneSymbol.chip: $!";
    print $gene_symbol_chip_fh "Probe Set ID\tGene Symbol\tGene Title\tAliases\n";
    for my $gene_id (nsort keys %{$gene_info_hashref}) {
        # GSEA .chip files have weird character chr(28) for spacing synonyms
        my $symbol_synonyms_str = defined $add_gene_info_hashref->{$gene_id}->{synonyms} ? join(chr(28), split(/\|/, $add_gene_info_hashref->{$gene_id}->{synonyms})) : '';
        print $gene_symbol_chip_fh uc($gene_info_hashref->{$gene_id}->{symbol}), "\t", uc($gene_info_hashref->{$gene_id}->{symbol}), "\t", 
            $add_gene_info_hashref->{$gene_id}->{description} || 'NA', "\t", uc($symbol_synonyms_str) || '', "\n";
    }
    close($gene_symbol_chip_fh);
    print scalar(keys %{$gene_info_hashref}), " symbols written\n";
}
# database load, update, reprocessing
eval {
    my $ctk_db = Confero::DB->new();
    $ctk_db->txn_do(sub {
        # not needed anymore
        #my @genes;
        # existing database
        if ($ctk_db->resultset('Gene')->count() > 0) {
            print "\n", ($num_parallel_procs > 1 ? "[Reprocess]\n" : "[Reprocess & Database Reload]\n");
            if (!$no_interactive and !$no_db_reprocessing) {
                print "Would you like to fully reprocess all CTK database data? (type 'no' to do an incremental database update) [yes] ";
                chomp(my $answer = <STDIN>);
                $answer = 'yes' if $answer eq '';
                $no_db_reprocessing = ($answer =~ /^y(es|)$/i) ? 0 : 1;
            }
            if (!$no_db_reprocessing) {
                my $reprocessing_data_dir = "$tmp_dir/reprocessing";
                my @contrast_datasets = $ctk_db->resultset('ContrastDataSet')->search(undef, {
                    prefetch => 'organism',
                })->all();
                my @gene_sets = $ctk_db->resultset('GeneSet')->search(undef, {
                    prefetch => 'organism',
                })->all();
                # parallel
                if ($num_parallel_procs > 1) {
                    my $fork_manager = Parallel::Forker->new(use_sig_child => 1, max_proc => min($num_parallel_procs, Unix::Processors->new()->max_physical));
                    $SIG{CHLD} = sub { Parallel::Forker::sig_child($fork_manager) };
                    $SIG{TERM} = sub { $fork_manager->kill_tree_all('TERM') if $fork_manager and $fork_manager->in_parent; die "Exiting child process\n" };
                    for my $dataset (@contrast_datasets) {
                        $fork_manager->schedule(run_on_start => sub {
                            my $dataset_id = construct_id($dataset->name);
                            print "Reprocessing $dataset_id [PID $$]\n";
                            my $log_file_name = "$dataset_id.log";
                            my $log_file_path = "$reprocessing_data_dir/$log_file_name";
                            my $src2gene_id_bestmap = $dataset->source_data_file_id_type ne 'GeneSymbol'
                                                    ? $src2gene_id_bestmap->{$dataset->source_data_file_id_type}
                                                    : $gene_symbol2id_bestmap->{$dataset->organism->name};
                            my ($input_idmap, undef, undef, $gene_sets_arrayref) = 
                            Confero::Cmd->process_data_file(
                                \$dataset->source_data_file->data, 'IdMAPS', $log_file_path, $dataset->source_data_file_name, 
                                $dataset->source_data_file_id_type, $dataset->collapsing_method, undef, $dataset->name, 
                                $dataset->description, $src2gene_id_bestmap, 1, undef, undef, 1,
                            );
                            lock_nstore([$input_idmap, $gene_sets_arrayref], "$reprocessing_data_dir/reprocessed_data_set_data_${dataset_id}.pls")
                                or die "Could not serialize and store to $reprocessing_data_dir/reprocessed_data_set_data_${dataset_id}.pls: $!";
                            #print "Finished     $dataset_id [PID $$], see $log_file_name for report\n";
                            print "Finished     $dataset_id [PID $$]\n";
                        })->ready();
                    }
                    for my $gene_set (@gene_sets) {
                        $fork_manager->schedule(run_on_start => sub {
                            my $gene_set_id = construct_id($gene_set->name, $gene_set->contrast_name, $gene_set->type);
                            print "Reprocessing $gene_set_id [PID $$]\n";
                            my $log_file_name = "$gene_set_id.log";
                            my $log_file_path = "$reprocessing_data_dir/$log_file_name";
                            my $src2gene_id_bestmap = $gene_set->source_data_file_id_type ne 'GeneSymbol'
                                                    ? $src2gene_id_bestmap->{$gene_set->source_data_file_id_type}
                                                    : $gene_symbol2id_bestmap->{$gene_set->organism->name};
                            my ($input_idlist, undef, undef, $gene_sets_arrayref) = 
                            Confero::Cmd->process_data_file(
                                \$gene_set->source_data_file->data, 'IdList', $log_file_path, $gene_set->source_data_file_name, 
                                $gene_set->source_data_file_id_type, undef, undef, $gene_set->name, 
                                $gene_set->description, $src2gene_id_bestmap, 1, undef, undef, 1,
                            );
                            lock_nstore([$input_idlist, $gene_sets_arrayref], "$reprocessing_data_dir/reprocessed_gene_set_data_${gene_set_id}.pls")
                                or die "Could not serialize and store to $reprocessing_data_dir/reprocessed_gene_set_data_${gene_set_id}.pls: $!";
                            #print "Finished     $gene_set_id [PID $$], see $log_file_name for report\n";
                            print "Finished     $gene_set_id [PID $$]\n";
                        })->ready();
                    }
                    # wait for all child processes to finish
                    $fork_manager->wait_all();
                    print "\n[Database Reload]\n";
                }
                # delete all existing genes in DB
                print "Removing old genes from database: ";
                my $genes_deleted = $ctk_db->resultset('Gene')->delete();
                print "$genes_deleted genes removed\n";
                # load latest genes in DB
                print "Loading latest genes into database: ";
                # load latest genes (convert data to correct form for DBIx::Class::Schema::populate)
                my @latest_gene_data = map { [
                    $_,
                    $gene_info_hashref->{$_}->{symbol}, 
                    exists $gene_info_hashref->{$_}->{status} ? $gene_info_hashref->{$_}->{status} : undef,
                    @{$add_gene_info_hashref->{$_}}{qw(synonyms description)} 
                ] } nsort keys %{$gene_info_hashref};
                $ctk_db->populate('Gene', [
                    [qw( id symbol status synonyms description )],
                    @latest_gene_data
                ]);
                print $ctk_db->resultset('Gene')->count(), " genes loaded\n";
                # not needed anymore
                #my $genes_rs = $ctk_db->resultset('Gene');
                #$genes_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
                #@genes = $genes_rs->all();
                # not needed anymore, %genes was need in submit_data_file() when using direct DBI commands for (contrast)gene_set_gene tables, still defining empty %genes though for now
                #my %genes = map { $_->{id} => $_ } @genes;
                my %genes;
                # load all reprocessed CTK data into database
                print +($num_parallel_procs > 1 ? "Reloading " : "Reprocessing and loading "), scalar(@contrast_datasets), " contrast datasets:\n";
                for my $dataset (@contrast_datasets) {
                    my $dataset_id = construct_id($dataset->name);
                    my $log_file_name = "$dataset_id.log";
                    my $log_file_path = "$reprocessing_data_dir/$log_file_name";
                    if ($num_parallel_procs > 1) {
                        #print "Loading $dataset_id: ";
                        print "Loading $dataset_id";
                        my ($input_idmap, $gene_sets_arrayref) = @{lock_retrieve("$reprocessing_data_dir/reprocessed_data_set_data_${dataset_id}.pls")
                            or die "Could not retrieve and unserialize $reprocessing_data_dir/reprocessed_data_set_data_${dataset_id}.pls: $!"};
                        Confero::Cmd->submit_data_file(
                            $input_idmap, $log_file_path, undef, $gene_sets_arrayref, $ctk_db, $dataset, \%genes,
                        );
                    }
                    else {
                        my $src2gene_id_bestmap = $dataset->source_data_file_id_type ne 'GeneSymbol'
                                                ? $src2gene_id_bestmap->{$dataset->source_data_file_id_type}
                                                : $gene_symbol2id_bestmap->{$dataset->organism->name};
                        #print "Reprocessing and loading $dataset_id: ";
                        print "Reprocessing and loading $dataset_id";
                        Confero::Cmd->process_submit_data_file(
                            \$dataset->source_data_file->data, 'IdMAPS', $log_file_path, $dataset->source_data_file_name, 
                            $dataset->source_data_file_id_type, $dataset->collapsing_method, undef, $dataset->name, 
                            $dataset->description, $src2gene_id_bestmap, $ctk_db, $dataset, \%genes, 1, undef, undef, undef, 1,
                        );
                    }
                    #print "success, see $log_file_name for report\n";
                    print "\n";
                }
                print +($num_parallel_procs > 1 ? "Reloading " : "Reprocessing and loading "), scalar(@gene_sets), " gene sets:\n";
                for my $gene_set (@gene_sets) {
                    my $gene_set_id = construct_id($gene_set->name, $gene_set->contrast_name, $gene_set->type);
                    my $log_file_name = "$gene_set_id.log";
                    my $log_file_path = "$reprocessing_data_dir/$log_file_name";
                    if ($num_parallel_procs > 1) {
                        #print "Loading $gene_set_id: ";
                        print "Loading $gene_set_id";
                        my ($input_idlist, $gene_sets_arrayref) = @{lock_retrieve("$reprocessing_data_dir/reprocessed_gene_set_data_${gene_set_id}.pls")
                            or die "Could not retrieve and unserialize $reprocessing_data_dir/reprocessed_gene_set_data_${gene_set_id}.pls: $!"};
                        Confero::Cmd->submit_data_file(
                            $input_idlist, $log_file_path, undef, $gene_sets_arrayref, $ctk_db, $gene_set, \%genes,
                        );
                    }
                    else {
                        my $src2gene_id_bestmap = $gene_set->source_data_file_id_type ne 'GeneSymbol'
                                                ? $src2gene_id_bestmap->{$gene_set->source_data_file_id_type}
                                                : $gene_symbol2id_bestmap->{$gene_set->organism->name};
                        #print "Reprocessing and loading $gene_set_id: ";
                        print "Reprocessing and loading $gene_set_id";
                        Confero::Cmd->process_submit_data_file(
                            \$gene_set->source_data_file->data, 'IdList', $log_file_path, $gene_set->source_data_file_name, 
                            $gene_set->source_data_file_id_type, undef, undef, $gene_set->name, 
                            $gene_set->description, $src2gene_id_bestmap, $ctk_db, $gene_set, \%genes, 1, undef, undef, undef, 1,
                        );
                    }
                    #print "success, see $log_file_name for report\n";
                    print "\n";
                }
            }
            # skip CTK full database reprocessing
            else {
                if ($no_entrez_download) {
                    print "Skipping reprocessing of all CTK data, assuming since Entrez Gene public files were not updated then database is still valid\n";
                }
                else {
                    print "Skipping reprocessing of all CTK data, doing incremental database update\n";
                    die "\nIncremental update feature not implemented yet\n";
                }
                ## delete only those genes (and link to gene sets) which don't exist in Entrez Gene anymore
                ## update genes (and link to gene sets) which are discontinued but have a current equivalent
                #print "Removing fully discontinued genes and updating those with current equivalents in database ";
                #@genes = $ctk_db->resultset('Gene')->all();
                #for my $gene (@genes) {
                #    if (defined $gene_history_hashref->{$gene->id}) {
                #        # discontinued with current equivalent
                #        if (defined $gene_history_hashref->{$gene->id}->{current_gene_id}) {
                #            # if current equivalent is new (doesn't exist in DB) turn old gene into new 
                #            # by updating the ID and gene set link (symbol updated later)
                #            if () {
                #                $gene->id($gene_history_hashref->{$gene->id}->{current_gene_id});
                #                $gene->update();
                #            }
                #            # 
                #            else {
                #                
                #            }
                #        }
                #        # fully discontinued
                #        else {
                #            $gene->delete();
                #       }
                #    }
                #}
                #
                ## load new and update existing genes
                #print "Loading new and updating existing genes in database (can take a little while)\n";
                #my $genes_loaded;
                #for my $gene_id (nsort keys %{$gene_info_hashref}) {
                #    $ctk_db->resultset('Gene')->update_or_create(
                #        {
                #          id     => $gene_id,
                #          symbol => $gene_info_hashref->{$gene_id}->{symbol}
                #        },
                #        { key => 'primary' }
                #    );
                #    print "$genes_loaded genes loaded or updated\n" if (++$genes_loaded) % 100000 == 0;
                #}
                #print "$genes_loaded genes loaded or updated\n\n";
            }
        }
        # new empty database
        else {
            print "\n[Database Load]\n";
            # load latest genes (convert data to correct form for DBIx::Class::Schema::populate)
            my @latest_gene_data = map { [
                    $_,
                    $gene_info_hashref->{$_}->{symbol}, 
                    exists $gene_info_hashref->{$_}->{status} ? $gene_info_hashref->{$_}->{status} : undef,
                    @{$add_gene_info_hashref->{$_}}{qw(synonyms description)} 
                ] } nsort keys %{$gene_info_hashref};
            $ctk_db->populate('Gene', [
                [qw( id symbol status synonyms description )],
                @latest_gene_data
            ]);
            print $ctk_db->resultset('Gene')->count(), " genes loaded\n";
            # not needed anymore
            #my $genes_rs = $ctk_db->resultset('Gene');
            #$genes_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
            #@genes = $genes_rs->all();
        }
        # move files to final location
        print "\n[Move Files]\nMoving all files to permanent location and setting permissions\n";
        if (!$no_entrez_processing) {
            for my $file_path (glob("$entrez_data_tmp_dir/*")) {
                print "$file_path\n" if $verbose;
                chmod(0640, $file_path);
                copy($file_path, "$CTK_ENTREZ_GENE_DATA_DIR/" . basename($file_path)) or die "Could not move $file_path: $!";
            }
        }
        if ($download_netaffx) {
            for my $file_path (glob("$netaffx_data_work_dir/*")) {
                print "$file_path\n" if $verbose;
                copy($file_path, "$CTK_AFFY_ANNOT_DATA_DIR/" . basename($file_path)) or die "Could not copy $file_path: $!";
            }
        }
        if ($download_agilent) {
            for my $file_path (glob("$agilent_data_work_dir/*")) {
                print "$file_path\n" if $verbose;
                copy($file_path, "$CTK_AGILENT_ANNOT_DATA_DIR/" . basename($file_path)) or die "Could not copy $file_path: $!";
            }
        }
        if ($download_geo) {
            for my $file_path (glob("$geo_data_work_dir/*")) {
                print "$file_path\n" if $verbose;
                copy($file_path, "$CTK_GEO_ANNOT_DATA_DIR/" . basename($file_path)) or die "Could not copy $file_path: $!";
            }
        }
        if ($download_illumina) {
            for my $file_path (glob("$illumina_data_work_dir/*")) {
                print "$file_path\n" if $verbose;
                copy($file_path, "$CTK_ILLUMINA_ANNOT_DATA_DIR/" . basename($file_path)) or die "Could not copy $file_path: $!";
            }
        }
        for my $file_path (glob("$mapping_data_work_dir/*")) {
            print "$file_path\n" if $verbose;
            chmod(0640, $file_path);
            copy($file_path, "$CTK_DATA_ID_MAPPING_FILE_DIR/" . basename($file_path)) or die "Could not copy $file_path: $!";
        }
        for my $file_path (glob("$gsea_data_work_dir/*")) {
            chmod(0640, $file_path);
            copy($file_path, "$CTK_GSEA_MAPPING_FILE_DIR/" . basename($file_path)) or die "Could not copy $file_path: $!";
        }
        my $old_cwd = cwd();
        chdir($CTK_GSEA_MAPPING_FILE_DIR) or die "Could not chdir to $CTK_GSEA_MAPPING_FILE_DIR: $!";
        if (-e 'GENE_SYMBOL.chip' and !-l 'GENE_SYMBOL.chip' and !-e 'GENE_SYMBOL.chip.DIST') {
            move('GENE_SYMBOL.chip', 'GENE_SYMBOL.chip.DIST') or die "Could not move GENE_SYMBOL.chip: $!";
        }
        if (!-l 'GENE_SYMBOL.chip') {
            symlink('GeneSymbol.chip', 'GENE_SYMBOL.chip') or die "Could not symlink GENE_SYMBOL.chip: $!";
        }
        chdir($old_cwd) or warn "Could not chdir to $old_cwd: $!";
        print "\n";
    });
};
if ($@) {
    my $message = "ERROR: Confero database transaction failed";
    $message .= " and ROLLBACK FAILED" if $@ =~ /rollback failed/i;
    die "\n\n$message: $@\n";
}
print "Confero Entrez Gene Data Loader, Mapping File Creator and Database Reprocessor complete [", scalar localtime, "]\n\n";
exit;

sub process_multi_gene_map {
    my ($source_id, $src2gene_id_map, $gene2src_id_map, @gene_ids) = @_;
    #print STDERR "START: $source_id ", join(' ', @gene_ids), "\nREPRE: $gene_id\nALTER: ", join(' ', @alt_source_ids);
    #<STDIN>;
    my $gene_id = scalar(@gene_ids) > 1 ? get_best_gene_id(@gene_ids) 
                :                         $gene_ids[0];
    # check if best Gene ID maps to any other source ID(s)
    my @alt_source_ids = grep { $_ ne $source_id } keys %{$gene2src_id_map->{$gene_id}};
    if (@alt_source_ids) {
        my $better_alt_source_id_found;
        for my $alt_source_id (natsort @alt_source_ids) {
            if (scalar(keys %{$src2gene_id_map->{$alt_source_id}}) == 1) {
                $better_alt_source_id_found++;
                last;
            }
        }
        # if a better alternate source ID was found
        if ($better_alt_source_id_found) {
            @gene_ids = grep { $_ != $gene_id } @gene_ids;
            #print STDERR "UNIQ : $gene_id\nNEXT : ", join(' ', @gene_ids);
            #<STDIN>;
            $gene_id = @gene_ids ? process_multi_gene_map($source_id, $src2gene_id_map, $gene2src_id_map, @gene_ids)
                     :             undef;
        }
    }
    return $gene_id;
}

sub get_best_gene_id {
    my (@gene_ids) = @_;
    # first determine which Gene IDs have best Refseq status
    my (@status_ranks, $best_status_rank);
    # debugging
    #print STDERR "G IDS : ", join(' ', @gene_ids), "\n";
    for my $gene_id (@gene_ids) {
        if (exists $gene_info_hashref->{$gene_id} and exists $gene_info_hashref->{$gene_id}->{status}) {
            push @status_ranks, $CTK_ENTREZ_GENE_REFSEQ_STATUS_DATA{$gene_info_hashref->{$gene_id}->{status}}{rank};
            if (!defined $best_status_rank or 
                $CTK_ENTREZ_GENE_REFSEQ_STATUS_DATA{$gene_info_hashref->{$gene_id}->{status}}{rank} < $best_status_rank) {
                $best_status_rank = $CTK_ENTREZ_GENE_REFSEQ_STATUS_DATA{$gene_info_hashref->{$gene_id}->{status}}{rank};
            }
        }
    }
    # debugging
    #print STDERR "RANKS : ", join(' ', @status_ranks), "\n";
    #print STDERR "BEST R: $best_status_rank\n";
    #print STDERR "B IDS : ", join(' ', nsort map { $gene_ids[$_] } grep { (defined $status_ranks[$_]) && ($status_ranks[$_] == $best_status_rank) } 0 .. $#status_ranks), "\n";
    # return Gene IDs with best RefSeq status rank and if there is more than one Gene ID with 
    # best status rank then currently just take the lowest Gene ID from those
    # if no best RefSeq status Gene IDs could be determined return lowest Gene ID
    return defined $best_status_rank
        ? (nsort map { $gene_ids[$_] } grep { (defined $status_ranks[$_]) && ($status_ranks[$_] == $best_status_rank) } 0 .. $#status_ranks)[0]
        : (nsort @gene_ids)[0];
}

sub update_platform_gene_ids {
    my @entrez_gene_ids = @_;
    my %current_entrez_gene_ids;
    # make sure to apply nsort is here, order important for consistent multi-gene bestmap evaluation step
    for my $gene_id (nsort @entrez_gene_ids) {
        # check if Gene ID is current
        if (exists $gene_info_hashref->{$gene_id}) {
            $current_entrez_gene_ids{$gene_id}++;
        }
        # check if Gene ID is historical and update with current Gene ID if exists, otherwise it's discontinued
        elsif (exists $gene_history_hashref->{$gene_id}) {
            if (exists $gene_history_hashref->{$gene_id}->{current_gene_id}) {
                $current_entrez_gene_ids{$gene_history_hashref->{$gene_id}->{current_gene_id}}++;
            }
            elsif ($debug and $verbose) {
                print "Discontinued Entrez Gene ID found: $gene_id\n";
            }
        }
        # invalid Gene ID
        elsif ($debug and $verbose) {
            print "Invalid Entrez Gene ID found: $gene_id\n";
        }
    }
    # make sure to apply nsort is here, order important for consistent multi-gene bestmap evaluation step
    return nsort keys %current_entrez_gene_ids;
}

sub process_platform_mapping_files {
    my ($array_symbol) = @_;
    # process map files and create data structures
    print "Generating mapping data structures\n";
    my ($src2gene_id_map, $gene2src_id_map);
    open(my $map_fh, '<', "$mapping_data_work_dir/${array_symbol}.map") or die "\n\nERROR: could not open mapping file $mapping_data_work_dir/${array_symbol}.map: $!\n\n";
    my $header = <$map_fh>;
    while (<$map_fh>) {
        s/\s+$//;
        my ($source_id, @entrez_gene_ids) = split /\t/;
        s/\s+//g for $source_id, @entrez_gene_ids;
        # even if we have no Entrez Gene IDs to map make sure to have an existing key for the source ID (in case we use keys for valid ID checks)
        $src2gene_id_map->{$source_id} = undef;
        for my $gene_id (@entrez_gene_ids) {
            $src2gene_id_map->{$source_id}->{$gene_id}++;
            $gene2src_id_map->{$gene_id}->{$source_id}++;
        }
    }
    close($map_fh);
    # lock data structure
    Hash::Util::lock_hashref_recurse($src2gene_id_map);
    Hash::Util::lock_hashref_recurse($gene2src_id_map);
    # generate best map file and data structure
    my $src2gene_id_bestmap;
    for my $source_id (natsort keys %{$src2gene_id_map}) {
        # even if we have no Entrez Gene IDs to map make sure to have an existing key for the source ID (in case we use keys for valid ID checks)
        $src2gene_id_bestmap->{$source_id} = undef;
        # check if source ID has a Gene ID map
        if (defined $src2gene_id_map->{$source_id}) {
            my @gene_ids = nsort keys %{$src2gene_id_map->{$source_id}};
            # check if source ID has multi Gene ID map
            if (scalar(@gene_ids) > 1) {
                $src2gene_id_bestmap->{$source_id}->{gene_id} 
                    = process_multi_gene_map($source_id, $src2gene_id_map, $gene2src_id_map, @gene_ids);
                if (defined $src2gene_id_bestmap->{$source_id}->{gene_id}) {
                    $src2gene_id_bestmap->{$source_id}->{multi_gene_map}++;
                }
                else {
                    $src2gene_id_bestmap->{$source_id}->{ambig_gene_map}++ 
                }
            }
            # single Gene ID map
            else {
                $src2gene_id_bestmap->{$source_id}->{gene_id} = $gene_ids[0];
            }
        }
        # no Gene ID map
        else {
            $src2gene_id_bestmap->{$source_id}->{gene_id} = undef;
            $src2gene_id_bestmap->{$source_id}->{no_gene_map}++;
        }
    }
    # write out reverse map and best map files (not used by CTK only for reference)
    open(my $revmap_fh, '>', "$mapping_data_work_dir/$array_symbol.revmap") 
        or die "\n\nERROR: could not create output mapping file $mapping_data_work_dir/$array_symbol.revmap: $!\n\n";
    print "Generating $array_symbol.revmap\n";
    print $revmap_fh "Entrez Gene ID\tProbeset IDs\n";
    for my $gene_id (nsort keys %{$gene2src_id_map}) {
        print $revmap_fh "$gene_id\t", defined $gene2src_id_map->{$gene_id} ? join("\t", natsort keys %{$gene2src_id_map->{$gene_id}}) : '', "\n";
    }
    close($revmap_fh);
    open(my $bestmap_fh, '>', "$mapping_data_work_dir/$array_symbol.bestmap") 
        or die "\n\nERROR: could not create output mapping file $mapping_data_work_dir/$array_symbol.bestmap: $!\n\n";
    print "Generating $array_symbol.bestmap\n";
    print $bestmap_fh "Probeset ID\tEntrez Gene ID\n";
    for my $source_id (natsort keys %{$src2gene_id_bestmap}) {
        print $bestmap_fh "$source_id\t", 
            defined $src2gene_id_bestmap->{$source_id}->{gene_id} ? $src2gene_id_bestmap->{$source_id}->{gene_id} : '', "\n";
    }
    close($bestmap_fh);
    # lock data structure
    Hash::Util::lock_hashref_recurse($src2gene_id_bestmap);
    # serialize and store data structures
    #print "Serializing and storing ${array_symbol}.map.pls\n";
    #lock_nstore($src2gene_id_map, "$mapping_data_work_dir/${array_symbol}.map.pls") 
    #    or die "\n\nERROR: could not serialize and store to $mapping_data_work_dir/${array_symbol}.map.pls: $!\n\n";
    #print "Serializing and storing ${array_symbol}.revmap.pls\n";
    #lock_nstore($gene2src_id_map, "$mapping_data_work_dir/${array_symbol}.revmap.pls") 
    #    or die "\n\nERROR: could not serialize and store to $mapping_data_work_dir/${array_symbol}.revmap.pls: $!\n\n";
    print "Serializing and storing ${array_symbol}.bestmap.pls\n";
    lock_nstore($src2gene_id_bestmap, "$mapping_data_work_dir/${array_symbol}.bestmap.pls") 
        or die "\n\nERROR: could not serialize and store to $mapping_data_work_dir/${array_symbol}.bestmap.pls: $!\n\n";
    return $src2gene_id_bestmap;
}

__END__

=head1 NAME 

cfo_load_entrez_gene_mapping_reprocess.pl - Confero Entrez Gene Data Loader, Mapping File Creator and Database Reprocessor

=head1 SYNOPSIS

 cfo_load_entrez_gene_mapping_reprocess.pl [options]

 Options:
    --no-interactive               Run in non-interactive mode (default false)
    --parallel=n                   Number of parallel processes to use for reprocessing of CTK repository data (default 0 which is off)
    --no-entrez-download           Skip download of latest Entrez Gene data files from NCBI and use existing files (default false)
    --no-entrez-processing         Skip processing and generation of Entrez Gene files and use existing data structures (default false)
    --download-netaffx             Download new NetAffx annotations files from Affymetrix (default false)
    --download-agilent             Download new Agilent annotations files from Agilent (default false)
    --download-geo                 Download new GEO annotations files from NCBI (default false)
    --download-illumina            Download new Illumina annotations files from Illumina (default false)
    --no-mapping-file-processing   Skip processing and generation of all mapping files and use existing data structures (default false)
    --no-netaffx-processing        Skip processing of NetAffx annotation files and use existing data structures (default false)
    --no-agilent-processing        Skip processing of Agilent annotation files and use existing data structures (default false)
    --no-geo-processing            Skip processing of NCBI GEO annotation files and use existing data structures (default false)
    --no-illumina-processing       Skip processing of Illumina annotation files and use existing data structures (default false)
    --no-db-reprocessing           Skip full reprocessing of CTK database from latest Entrez Gene data and mapping files (default false)
    --help                         Display usage message and exit
    --version                      Display program version and exit

=cut
