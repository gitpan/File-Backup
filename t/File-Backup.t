BEGIN {
    use strict;
    use Test::More 'no_plan';#tests => 1;
    use_ok 'File::Backup';
    use_ok 'File::Which';
}

my ($keep, $from_dir, $to_dir) = (2, 'from_dir', 'to_dir');

my $arch_prog = which('tar');
my $comp_prog = which('gzip');

unless (-d $to_dir) {
    mkdir $to_dir, 0755 or die "Can't mkdir $to_dir: $!\n";
}

SKIP: {
    skip "Can't find your tar program", 1 unless $arch_prog;

    # Just archive
    my $backed = backup(
#        debug => 1,
        compress => 0,
        from => $from_dir,
        to   => $to_dir,
        keep => 0,
    );
    is((keys %$backed)[0], $from_dir, 'from_dir backed up');
    like((values %$backed)[0], qr/to_dir\/.*?\.tar/,
        'to_dir backup file');
    is scalar files($to_dir), 0, "don't keep the backup";

    sleep 1;
}

SKIP: {
    skip "Can't find your gzip program", 1 unless $comp_prog && $arch_prog;

    $backed = backup(
#        debug => 1,
        from => $from_dir,
        to   => $to_dir,
        keep => $keep,
    );
    is((keys %$backed)[0], $from_dir, 'from_dir backed up');
    like((values %$backed)[0], qr/to_dir\/.*?\.tar\.gz/,
        'to_dir backup file');
    is scalar files($to_dir), 1, 'keep the backup';

    sleep 1;

    $backed = backup(
#        debug => 1,
        from => $from_dir,
        to   => $to_dir,
        keep => $keep,
    );
    is((keys %$backed)[0], $from_dir, 'from_dir backed up');
    like((values %$backed)[0], qr/to_dir\/.*?\.tar\.gz/,
        'to_dir backup file');
    is scalar files($to_dir), $keep, "keep $keep";

    sleep 1;

    # Keep all backups.
    $backed = backup(
#        debug => 1,
        from => $from_dir,
        to   => $to_dir,
        keep => -1,
    );
    is((keys %$backed)[0], $from_dir, 'from_dir backed up');
    like((values %$backed)[0], qr/to_dir\/.*?\.tar\.gz/,
        'to_dir backup file');
    is scalar files($to_dir), $keep + 1, 'keep all';

    sleep 1;

    # No keep: Why anyone would want to do this, I'm not sure.
    $backed = backup(
#        debug => 1,
        from => $from_dir,
        to   => $to_dir,
        keep => 0,
    );
    is((keys %$backed)[0], $from_dir, 'from_dir backed up');
    like((values %$backed)[0], qr/to_dir\/.*?\.tar\.gz/,
        'to_dir backup file');
    is scalar files($to_dir), 0, 'kept zero';
}

# TODO Test every edge case parameter permutation!

# Return the list of files in a given directory.
sub files {
    my $dir = shift;
    opendir DIR, $dir or die "Can't opendir $dir: $!\n";
    my @files = grep { !/^\.$|^\.\.$|^CVS$/ } readdir DIR;
    closedir DIR or die "Can't closedir $dir: $!\n";
    return @files;
}
