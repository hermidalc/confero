use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Confero::Web',
    AUTHOR              => q{Leandro Hermida <DL.ConferoSupport@pmi.com>},
    VERSION_FROM        => 'lib/Confero/Web.pm',
    ABSTRACT            => 'An Integrated Contrast and Gene Set Platform for Computational Analysis and Biological Interpretation of High-Throughput Experimental Data',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'YAML'       => 0,
        'Dancer'     => 1.3060,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Confero-Web-*' },
);
