BEGIN {
    use strict;
    use Test::More 'no_plan';#tests => 1;
    use_ok 'File::Backup';
}

my ($keep, $from_dir, $to_dir) = (2, 'from_dir', 'to_dir');
mkdir $to_dir;

my $backed = backup(
#    debug => 1,
    from => $from_dir,
    to   => $to_dir,
    keep => $keep,
);
# Did we actually back anything up?
is((keys %$backed)[0], $from_dir, 'backup files in from_dir');
like((values %$backed)[0], qr/to_dir\/.*?\.tar\.gz/, 'to_dir has backup file');
is scalar files($to_dir), 1, 'keep the backup around';

# Hold on a second!!
sleep 1;

# Thank you, Sir. May I have another, Sir?
$backed = backup(
#    debug => 1,
    from => $from_dir,
    to   => $to_dir,
    keep => $keep,
);
# Did we actually back anything up?
is((keys %$backed)[0], $from_dir, 'backup files in from_dir');
like((values %$backed)[0], qr/to_dir\/.*?\.tar\.gz/, 'to_dir has backup file');
is scalar files($to_dir), $keep, "keep $keep";

# Hold on a second!!
sleep 1;

# Keep all backups.
$backed = backup(
#    debug => 1,
    from => $from_dir,
    to   => $to_dir,
    keep => -1,
);
# Did we actually back anything up?
is((keys %$backed)[0], $from_dir, 'backup files in from_dir');
like((values %$backed)[0], qr/to_dir\/.*?\.tar\.gz/, 'to_dir has backup file');
is scalar files($to_dir), $keep + 1, 'keep all';

# Hold on a second!!
sleep 1;

# No keep: Why anyone would want to do this, I'm not sure.
$backed = backup(
#    debug => 1,
    from => $from_dir,
    to   => $to_dir,
    keep => 0,
);
# Did we actually back anything up?
is((keys %$backed)[0], $from_dir, 'backup files in from_dir');
like((values %$backed)[0], qr/to_dir\/.*?\.tar\.gz/, 'to_dir has backup file');
is scalar files($to_dir), 0, 'kept zero';

# TODO Test every edge case parameter permutation!

# Return the list of files in a given directory.
sub files {
    my $dir = shift;
    opendir DIR, $dir or die "Can't opendir $dir: $!\n";
    my @files = grep { !/^\.$|^\.\.$|^CVS$/ } readdir DIR;
    closedir DIR or die "Can't closedir $dir: $!\n";
    return @files;
}
