use ExtUtils::MakeMaker;
WriteMakefile(
    NAME         => 'File::Backup',
    VERSION_FROM => 'lib/File/Backup.pm',
    PREREQ_PM    => {
        'Test::More'  => 0,
        'Carp'        => 0,
        'Cwd'         => 0,
        'File::Which' => 0,
    },
    ($] >= 5.005
        ? (ABSTRACT_FROM => 'lib/File/Backup.pm',
           AUTHOR        => 'Gene Boggs <gene@cpan.org>')
        : ()
    ),
);
