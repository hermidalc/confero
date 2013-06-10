package Confero::Config;

use strict;
use warnings;
use Const::Fast;
use Confero::LocalConfig qw(
    $CTK_BASE_DIR
    $CTK_AFFY_ANNOT_NETAFFX_VERSION
);
require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    $CTK_DATA_DIR
    $CTK_DATA_ID_MAPPING_FILE_DIR
    $CTK_DATA_ID_MAPPING_GENE_SYMBOL_SUFFIX
    %CTK_DATA_FILE_METADATA_FIELDS
    @CTK_DATA_CONTRAST_GENE_SET_TYPE_SUFFIXES
    $CTK_AFFY_ANNOT_DATA_DIR
    %CTK_AFFY_ARRAY_DATA
    $CTK_AGILENT_ANNOT_DATA_DIR
    %CTK_AGILENT_ARRAY_DATA
    $CTK_GEO_ANNOT_DATA_DIR
    %CTK_GEO_ARRAY_DATA
    $CTK_ILLUMINA_ANNOT_DATA_DIR
    %CTK_ILLUMINA_ARRAY_DATA
    $CTK_ENTREZ_GENE_DATA_DIR
    %CTK_ENTREZ_GENE_DATA
    %CTK_ENTREZ_GENE_ORGANISM_DATA
    %CTK_ENTREZ_GENE_REFSEQ_STATUS_DATA
    $CTK_GSEA_HOME
    $CTK_GSEA_JAR_PATH
    $CTK_GSEA_GENE_SET_DB_DIR
    $CTK_GSEA_MAPPING_FILE_DIR
    $CTK_GSEA_REPORTS_CACHE_DIR
    $CTK_GSEA_GENESIGDB_VERSION
    $CTK_GSEA_GENESIGDB_FILE_URI
    $CTK_GSEA_GSDB_ID_TYPE
    %CTK_GSEA_GSDBS
    $CTK_GSEA_REPORT_FILE_NAME_REGEXP
    $CTK_GSEA_DETAILS_FILE_NAME_REGEXP
    %CTK_GSEA_RESULTS_COLUMN_NAMES
    $CTK_WEB_EXTRACT_ROWS_PER_PAGE
    $CTK_GALAXY_ANNOT_NV_SEPARATOR
);
    #$CTK_DATA_FILE_REPOSITORY_DIR
our %EXPORT_TAGS = ( 
    all => \@EXPORT_OK,
    data => [qw(
        $CTK_DATA_DIR
        $CTK_DATA_ID_MAPPING_FILE_DIR
        $CTK_DATA_ID_MAPPING_GENE_SYMBOL_SUFFIX
        %CTK_DATA_FILE_METADATA_FIELDS 
        @CTK_DATA_CONTRAST_GENE_SET_TYPE_SUFFIXES
    )],
        #$CTK_DATA_FILE_REPOSITORY_DIR
    affy => [qw(
        $CTK_AFFY_ANNOT_DATA_DIR
        %CTK_AFFY_ARRAY_DATA
    )],
    agilent => [qw(
        $CTK_AGILENT_ANNOT_DATA_DIR
        %CTK_AGILENT_ARRAY_DATA
    )],
    geo => [qw(
        $CTK_GEO_ANNOT_DATA_DIR
        %CTK_GEO_ARRAY_DATA
    )],
    illumina => [qw(
        $CTK_ILLUMINA_ANNOT_DATA_DIR
        %CTK_ILLUMINA_ARRAY_DATA
    )],
    entrez => [qw(
        $CTK_ENTREZ_GENE_DATA_DIR
        %CTK_ENTREZ_GENE_DATA
        %CTK_ENTREZ_GENE_ORGANISM_DATA
        %CTK_ENTREZ_GENE_REFSEQ_STATUS_DATA
    )],
    gsea => [qw(
        $CTK_GSEA_HOME
        $CTK_GSEA_JAR_PATH
        $CTK_GSEA_GENE_SET_DB_DIR
        $CTK_GSEA_MAPPING_FILE_DIR
        $CTK_GSEA_REPORTS_CACHE_DIR
        $CTK_GSEA_GENESIGDB_VERSION
        $CTK_GSEA_GENESIGDB_FILE_URI
        $CTK_GSEA_GSDB_ID_TYPE
        %CTK_GSEA_GSDBS
        $CTK_GSEA_REPORT_FILE_NAME_REGEXP
        $CTK_GSEA_DETAILS_FILE_NAME_REGEXP
        %CTK_GSEA_RESULTS_COLUMN_NAMES
    )],
    web => [qw(
        $CTK_WEB_EXTRACT_ROWS_PER_PAGE
    )],
    galaxy => [qw(
        $CTK_GALAXY_ANNOT_NV_SEPARATOR
    )],
);
our $VERSION = '0.1';

# Data
const our $CTK_DATA_DIR                              => "$CTK_BASE_DIR/data";
const our $CTK_DATA_ID_MAPPING_FILE_DIR              => "$CTK_DATA_DIR/mappings";
const our $CTK_DATA_ID_MAPPING_GENE_SYMBOL_SUFFIX    => '_gene_symbols';
# we don't store data files in file system anymore
#const our $CTK_DATA_FILE_REPOSITORY_DIR              => "$CTK_BASE_DIR/tmp";
const our %CTK_DATA_FILE_METADATA_FIELDS             => (
    contrast_names => {
        is_multi => 1,
    },
    gs_min_size => {
        is_uint => 1,
    },
    gs_max_size => {
        is_uint => 1,
    },
    gs_m_val_thres => {
        is_multi => 1,
        is_unum => 1,
    },
    gs_a_val_thres => {
        is_multi => 1,
        is_unum => 1,
    },
    gs_p_val_thres => {
        is_multi => 1,
        is_unum => 1,
    },
    gs_up_sizes => {
        is_multi => 1,
        is_uint => 1,
    },
    gs_dn_sizes => {
        is_multi => 1,
        is_uint => 1,
    },
    gs_data_split_meths => {
        is_multi => 1,
        valid_values => [qw(
            zero
            median_m
        )],
    },
    gs_is_ranked => {
    },
    gs_all_default => {
    },
    collapsing_alg => {
    },
    organism => {
        order_in_display_id => 2,
    },
    id_type => {
    },
    source_id_type => {
    },
    dataset_name => {
    },
    dataset_desc => {
    },
    gene_set_name => {
    },
    gene_set_desc => {
    },
    rank_column => {
    },
    system => {
        is_annot => 1,
        order_in_display_id => 4,
    },
    study_no => {
        is_annot => 1,
        order_in_display_id => 1,
    },
    cell_tissue => {
        is_annot => 1,
        order_in_display_id => 3,
    },
    stimulus => {
        is_annot => 1,
        order_in_display_id => 5,
    },
);
# contrast gene set type suffixes
const our @CTK_DATA_CONTRAST_GENE_SET_TYPE_SUFFIXES  => qw( UP UPr DN DNr AR ARr );
# Affymetrix
# local, not exported
const my  $AFFY_ANNOT_DATA_BASE_URI                  => 'http://media.affymetrix.com/analysis/downloads';
const my  $AFFY_ANNOT_FILE_BASE_URI                  => "$AFFY_ANNOT_DATA_BASE_URI/$CTK_AFFY_ANNOT_NETAFFX_VERSION";
const our $CTK_AFFY_ANNOT_DATA_DIR                   => "$CTK_DATA_DIR/affymetrix";
const our %CTK_AFFY_ARRAY_DATA                       => (
    #'ATH1-121501' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/ATH1-121501.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    #'Celegans' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/Celegans.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    #'DrosGenome1' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/DrosGenome1.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    #'Drosophila_2' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/Drosophila_2.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    #'HG-Focus' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/HG-Focus.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    #'HG_U95A' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/HG_U95A.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    'HG_U95Av2' => {
       annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/HG_U95Av2.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    },
    #'HG-U133A' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/HG-U133A.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    #'HG-U133B' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/HG-U133B.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    'HG-U133A_2' => {
       annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/HG-U133A_2.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    },
    'HG-U133_Plus_2' => {
       annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/HG-U133_Plus_2.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    },
    'HuEx-1_0-st-v2' => {
       annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/wtexon/HuEx-1_0-st-v2.$CTK_AFFY_ANNOT_NETAFFX_VERSION.1.hg19.transcript.csv.zip",
    },
    'HuGene-1_0-st-v1' => {
       annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/wtgene-32_2/HuGene-1_0-st-v1.$CTK_AFFY_ANNOT_NETAFFX_VERSION.2.hg19.transcript.csv.zip",
    },
    'HT_HG-U133_Plus_PM' => {
        annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/HT_HG-U133_Plus_PM.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    },
    'HT_MG-430_PM' => {
        annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/HT_MG-430_PM.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    },
    'HT_Rat230_PM' => {
        annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/HT_Rat230_PM.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    },
    #'MG_U74Av2' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/MG_U74Av2.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    #'MG_U74Bv2' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/MG_U74Bv2.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    #'MG_U74Cv2' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/MG_U74Cv2.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    #'MOE430A' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/MOE430A.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    #'MOE430B' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/MOE430B.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    'Mouse430A_2' => {
       annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/Mouse430A_2.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    },
    'Mouse430_2' => {
       annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/Mouse430_2.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    },
    'MoEx-1_0-st-v1' => {
       annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/wtexon/MoEx-1_0-st-v1.$CTK_AFFY_ANNOT_NETAFFX_VERSION.1.mm9.transcript.csv.zip",
    },
    'MoGene-1_0-st-v1' => {
       annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/wtgene-32_2/MoGene-1_0-st-v1.$CTK_AFFY_ANNOT_NETAFFX_VERSION.2.mm9.transcript.csv.zip",
    },
    #'Plasmodium_Anopheles' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/Plasmodium_Anopheles.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    #'RAE230A' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/RAE230A.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    #'RAE230B' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/RAE230B.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    'Rat230_2' => {
       annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/Rat230_2.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    },
    'RaEx-1_0-st-v1' => {
       annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/wtexon/RaEx-1_0-st-v1.$CTK_AFFY_ANNOT_NETAFFX_VERSION.1.rn4.transcript.csv.zip",
    },
    'RaGene-1_0-st-v1' => {
       annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/wtgene-32_2/RaGene-1_0-st-v1.$CTK_AFFY_ANNOT_NETAFFX_VERSION.2.rn4.transcript.csv.zip",
    },
    #'Rhesus' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/Rhesus.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    #'Rice' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/Rice.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    #'Yeast_2' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/Yeast_2.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
    #'YG_S98' => {
    #   annot_file_uri => "$AFFY_ANNOT_FILE_BASE_URI/ivt/YG_S98.$CTK_AFFY_ANNOT_NETAFFX_VERSION.annot.csv.zip",
    #},
);
# Agilent
const our $CTK_AGILENT_ANNOT_DATA_DIR                => "$CTK_DATA_DIR/agilent";
const our %CTK_AGILENT_ARRAY_DATA                    => (
    #'Whole_Human_Genome_Microarray_4x44K_v2' => {
    #   design_id => '026652',
    #},
    #'Whole_Mouse_Genome_Microarray_4x44K_v2' => {
    #   design_id => '026655',
    #},
    #'Whole_Rat_Genome_Microarray_4x44K_v3' => {
    #   design_id => '028282',
    #},
);
# GEO
const my  $GEO_ANNOT_DATA_BASE_URI                   => 'http://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?targ=platform&form=text&view=data&acc=';
const our $CTK_GEO_ANNOT_DATA_DIR                    => "$CTK_DATA_DIR/geo";
const our %CTK_GEO_ARRAY_DATA                        => (
    'GPL334' => {
        annot_file_uri => "${GEO_ANNOT_DATA_BASE_URI}GPL334",
        name => 'Human 10K - Wellcome Trust Sanger Institute',
        organism => 'Homo sapiens',
    },
    'GPL1708' => {
        annot_file_uri => "${GEO_ANNOT_DATA_BASE_URI}GPL1708",
        name => 'Agilent-012391 Whole Human Genome Oligo Microarray G4112A',
        organism => 'Homo sapiens',
    },
    'GPL2507' => {
        annot_file_uri => "${GEO_ANNOT_DATA_BASE_URI}GPL2507",
        name => 'Sentrix Human-6 Expression Beadchip',
        organism => 'Homo sapiens',
    },
    'GPL3730' => {
        annot_file_uri => "${GEO_ANNOT_DATA_BASE_URI}GPL3730",
        name => 'NTU_CGM_MCF Human 672 Metachip',
        organism => 'Homo sapiens',
    },
    'GPL3877' => {
        annot_file_uri => "${GEO_ANNOT_DATA_BASE_URI}GPL3877",
        name => 'PRHU05-S1-0006 (PC Human Operon v2 21k) ',
        organism => 'Homo sapiens',
    },
    'GPL6104' => {
        annot_file_uri => "${GEO_ANNOT_DATA_BASE_URI}GPL6104",
        name => 'Illumina HumanRef-8 v2.0 Expression Beadchip',
        organism => 'Homo sapiens',
    },
    'GPL6883' => {
        annot_file_uri => "${GEO_ANNOT_DATA_BASE_URI}GPL6883",
        name => 'Illumina HumanRef-8 v3.0 Expression Beadchip',
        organism => 'Homo sapiens',
    },
    'GPL6885' => {
        annot_file_uri => "${GEO_ANNOT_DATA_BASE_URI}GPL6885",
        name => 'Illumina MouseRef-8 v2.0 Expression Beadchip',
        organism => 'Mus musculus',
    },
    'GPL6947' => {
        annot_file_uri => "${GEO_ANNOT_DATA_BASE_URI}GPL6947",
        name => 'Illumina HumanHT-12 V3.0 Expression Beadchip',
        organism => 'Homo sapiens',
    },
    'GPL8389' => {
        annot_file_uri => "${GEO_ANNOT_DATA_BASE_URI}GPL8389",
        name => 'Illumina Mouse-8 Expression Beadchip',
        organism => 'Mus musculus',
    },
    'GPL7015' => {
        annot_file_uri => "${GEO_ANNOT_DATA_BASE_URI}GPL7015",
        name => 'Agilent Homo sapiens 21.6K Custom Array',
        organism => 'Homo sapiens',
    },
    'GPL10687' => {
        annot_file_uri => "${GEO_ANNOT_DATA_BASE_URI}GPL10687",
        name => 'Rosetta/Merck Human RSTA Affymetrix 1.0 Microarray, Custom CDF',
        organism => 'Homo sapiens',
    },
);
# Illumina
const our $CTK_ILLUMINA_ANNOT_DATA_DIR               => "$CTK_DATA_DIR/illumina";
const our %CTK_ILLUMINA_ARRAY_DATA                   => (
    #'MouseRef-8_v2_0' => {
    #    name => 'MouseRef-8 v2.0 Expression BeadChip',
    #},
);
# Entrez Gene
# local, not exported
const my  $NCBI_FTP_BASE_URI                         => 'ftp://ftp.ncbi.nih.gov';
const my  $ENTREZ_GENE_DATA_BASE_URI                 => "$NCBI_FTP_BASE_URI/gene/DATA";
const our $CTK_ENTREZ_GENE_DATA_DIR                  => "$CTK_DATA_DIR/entrez_gene";
const our %CTK_ENTREZ_GENE_DATA                      => (
    'gene_info' => {
        file_uri => "$ENTREZ_GENE_DATA_BASE_URI/gene_info.gz",
    },
    'gene_history' => {
        file_uri => "$ENTREZ_GENE_DATA_BASE_URI/gene_history.gz",
    },
    'gene2refseq' => {
        file_uri => "$ENTREZ_GENE_DATA_BASE_URI/gene2refseq.gz",
    },
    'gene2accession' => {
        file_uri => "$ENTREZ_GENE_DATA_BASE_URI/gene2accession.gz",
    },
    'gene2ensembl' => {
        file_uri => "$ENTREZ_GENE_DATA_BASE_URI/gene2ensembl.gz",
    },
    'gene2unigene' => {
        # NCBI doesn't gzip gene2unigene because file is small
        file_uri => "$ENTREZ_GENE_DATA_BASE_URI/gene2unigene",
    },
);
const our %CTK_ENTREZ_GENE_ORGANISM_DATA             => (
    'Anopheles gambiae' => {
        gene_info_file_uri => "$ENTREZ_GENE_DATA_BASE_URI/GENE_INFO/Invertebrates/Anopheles_gambiae.gene_info.gz",
        tax_id => '7165',
    },
    'Arabidopsis thaliana' => {
        gene_info_file_uri => "$ENTREZ_GENE_DATA_BASE_URI/GENE_INFO/Plants/Arabidopsis_thaliana.gene_info.gz",
        tax_id => '3702',
    },
    'Caenorhabditis elegans' => {
        gene_info_file_uri => "$ENTREZ_GENE_DATA_BASE_URI/GENE_INFO/Invertebrates/Caenorhabditis_elegans.gene_info.gz",
        tax_id => '6239',
    },
    'Drosophila melanogaster' => {
        gene_info_file_uri => "$ENTREZ_GENE_DATA_BASE_URI/GENE_INFO/Invertebrates/Drosophila_melanogaster.gene_info.gz",
        tax_id => '7227',
    },
    'Homo sapiens' => {
        gene_info_file_uri => "$ENTREZ_GENE_DATA_BASE_URI/GENE_INFO/Mammalia/Homo_sapiens.gene_info.gz",
        tax_id => '9606',
    },
    'Mus musculus' => {
        gene_info_file_uri => "$ENTREZ_GENE_DATA_BASE_URI/GENE_INFO/Mammalia/Mus_musculus.gene_info.gz",
        tax_id => '10090',
    },
    'Oryza sativa' => {
        gene_info_file_uri => "$ENTREZ_GENE_DATA_BASE_URI/GENE_INFO/Plants/Oryza_sativa.gene_info.gz",
        tax_id => '4530',
    },
    'Rattus norvegicus' => {
        gene_info_file_uri => "$ENTREZ_GENE_DATA_BASE_URI/GENE_INFO/Mammalia/Rattus_norvegicus.gene_info.gz",
        tax_id => '10116',
    },
    'Saccharomyces cerevisiae' => {
        gene_info_file_uri => "$ENTREZ_GENE_DATA_BASE_URI/GENE_INFO/Fungi/Saccharomyces_cerevisiae.gene_info.gz",
        tax_id => '4932',
    },
    'Schizosaccharomyces pombe' => {
        tax_id => '284812',
        gene_info_tax_ids => [qw( 4896 284812 )],
    },
);
const our %CTK_ENTREZ_GENE_REFSEQ_STATUS_DATA => (
    REVIEWED    => { rank => 1 },
    VALIDATED   => { rank => 2 },
    PROVISIONAL => { rank => 3 },
    PREDICTED   => { rank => 4 },
    MODEL       => { rank => 5 },
    INFERRED    => { rank => 6 },
    SUPPRESSED  => { rank => 7 },
);
# GSEA
const our $CTK_GSEA_HOME                             => "$CTK_BASE_DIR/opt/gsea";
const our $CTK_GSEA_JAR_PATH                         => "$CTK_GSEA_HOME/gsea.jar";
const our $CTK_GSEA_GENE_SET_DB_DIR                  => "$CTK_GSEA_HOME/data/databases";
const our $CTK_GSEA_MAPPING_FILE_DIR                 => "$CTK_GSEA_HOME/data/mappings";
const our $CTK_GSEA_REPORTS_CACHE_DIR                => "$ENV{HOME}/gsea_home/reports_cache_foo";
const our $CTK_GSEA_GENESIGDB_VERSION                => '4.0';
const our $CTK_GSEA_GENESIGDB_FILE_URI               => 'http://compbio.dfci.harvard.edu/genesigdb/download/ALL_SIGSv4.gmt';
# local, not exported
const my $CTK_GSEA_MSIGDB_VERSION                    => '3.1';
# 'entrez' or 'symbols'
const our $CTK_GSEA_GSDB_ID_TYPE                     => 'symbols';
const our %CTK_GSEA_GSDBS                            => (
    'msigdb'                => "msigdb.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c1'             => "c1.all.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c2'             => "c2.all.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c2.ar'          => "c2.all.ar.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c2.cgp'         => "c2.cgp.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c2.cgp.ar'      => "c2.cgp.ar.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c2.cp'          => "c2.cp.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c2.cp.biocarta' => "c2.cp.biocarta.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c2.cp.kegg'     => "c2.cp.kegg.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c2.cp.reactome' => "c2.cp.reactome.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c3'             => "c3.all.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c3.mir'         => "c3.mir.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c3.tft'         => "c3.tft.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c4'             => "c4.all.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c4.cgn'         => "c4.cgn.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c4.cm'          => "c4.cm.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c5'             => "c5.all.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c5.bp'          => "c5.bp.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c5.cc'          => "c5.cc.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c5.mf'          => "c5.mf.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'msigdb.c6'             => "c6.all.v$CTK_GSEA_MSIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
    'genesigdb'             => "genesigdb.v$CTK_GSEA_GENESIGDB_VERSION.$CTK_GSEA_GSDB_ID_TYPE.gmt",
);
const our $CTK_GSEA_REPORT_FILE_NAME_REGEXP          => qr/^gsea_report_for_na_(pos|neg)_\d+\.xls$/o;
const our $CTK_GSEA_DETAILS_FILE_NAME_REGEXP         => qr/^[A-Z0-9].*?\.xls$/o;
const our %CTK_GSEA_RESULTS_COLUMN_NAMES             => map { uc($_) => 1 } (
    'SIZE',
    'ES',
    'NES',
    'NOM p-val',
    'FDR q-val',
    'FWER p-val',
    'RANK AT MAX',
    'LEADING EDGE',
);
# Confero Web
const our $CTK_WEB_EXTRACT_ROWS_PER_PAGE             => 2000;
# Galaxy
const our $CTK_GALAXY_ANNOT_NV_SEPARATOR             => '<->';

1;
