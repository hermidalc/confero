package Confero::EntrezGene;

use strict;
use warnings;
use base 'Class::Singleton';
use Confero::Config qw(:entrez);
use Storable qw(lock_retrieve);

our $VERSION = '0.1';

#sub _new_instance {
#    my $class = shift;
#    my %args  = @_ && ref $_[0] eq 'HASH' ? %{ $_[0] } : @_;
#    my $self = bless { %args }, $class;
#    $self->{gene_info} ||= lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/gene_info.pls");
#    $self->{gene_history} ||= lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/gene_history.pls");
#    return $self;
#}

sub gene_info {
    my $self = shift;
    $self->{gene_info} ||= lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/gene_info.pls");
    return $self->{gene_info};
}

sub gene_history {
    my $self = shift;
    $self->{gene_history} ||= lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/gene_history.pls");
    return $self->{gene_history};
}

sub add_gene_info {
    my $self = shift;
    $self->{add_gene_info} ||= lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/add_gene_info.pls");
    return $self->{add_gene_info};
}

sub symbol2gene_ids {
    my $self = shift;
    $self->{symbol2gene_ids} ||= lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/symbol2gene_ids.pls");
    return $self->{symbol2gene_ids};
}

sub uc_symbol2gene_ids {
    my $self = shift;
    $self->{uc_symbol2gene_ids} ||= lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/uc_symbol2gene_ids.pls");
    return $self->{uc_symbol2gene_ids};
}

sub accession2gene_ids {
    my $self = shift;
    $self->{accession2gene_ids} ||= lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/accession2gene_ids.pls");
    return $self->{accession2gene_ids};
}

sub ensembl2gene_ids {
    my $self = shift;
    $self->{ensembl2gene_ids} ||= lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/ensembl2gene_ids.pls");
    return $self->{ensembl2gene_ids};
}

sub unigene2gene_ids {
    my $self = shift;
    $self->{unigene2gene_ids} ||= lock_retrieve("$CTK_ENTREZ_GENE_DATA_DIR/unigene2gene_ids.pls");
    return $self->{unigene2gene_ids};
}

1;

