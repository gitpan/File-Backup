use ExtUtils::MakeMaker;
WriteMakefile(
    NAME         => 'File::Backup',
    VERSION_FROM => 'lib/File/Backup.pm',
    PREREQ_PM    => {
        'File::Which' => 0,
        'LockFile::Simple' => 0,
    },
    ($] >= 5.005
        ? (ABSTRACT_FROM => 'lib/File/Backup.pm',
           AUTHOR        => 'Gene Boggs <gene@cpan.org>')
        : ()
    ),
);
