BEGIN {
    use strict;
#    use warnings;
    use Test::More 'no_plan';#tests => 1;
use lib 'lib'; # XXX
    use_ok 'File::Backup';
    use_ok 'File::Which';
}
END {
    # Handle any evil remnants
    #rm -f from_dir/.lock;rm -f from_dir/*.lock;rm -rf to_dir  #in shell
    unlink 'from_dir/*.lock' or die "Can't unlink from_dir/*.lock: $!\n"
        if glob 'from_dir/*.lock';
    unlink glob 'to_dir/*' or die "Can't unlink to_dir/*: $!\n"
        if glob 'to_dir/*';
    rmdir 'to_dir' or die "Can't rmdir to_dir: $!\n";  # Clean up
}

# Return the list of a given directory (non cvs) contents.
sub files {  # {{{
    my $dir = shift;
    opendir DIR, $dir or die "Can't opendir $dir: $!\n";
    my @files = grep { !/^\.\.?$|^CVS$/ } readdir DIR;
    closedir DIR or die "Can't closedir $dir: $!\n";
    return @files;
}  # }}}

# Perform the backup and make sure it happened right.
sub back {  # {{{
    my %args = @_;
    # Return a (single valued) hash reference of {source => destination}.
    my $backed = backup(%args);
    my $file = (values %$backed)[0];
    like $file, qr/^$args{pattern}$/, $file;
    if ($args{keep} < 0) {
        ok scalar files($args{to}), 'keep all';
    }
    else {
        is scalar files($args{to}), $args{keep}, "keep $args{keep}";
    }
    sleep 1;
}  # }}}

my ($from_dir, $to_dir, $arch, $comp, $comp_ext) = qw(
     from_dir   to_dir   tar    gzip   gz
);  # We use Unix.
my ($arch_prog, $comp_prog) = (scalar which($arch), scalar which($comp));
my $backed_file = '';  # This is the file we check for.

ok $arch_prog, "found $arch";
ok $comp_prog, "found $comp";

unless (-d $to_dir) {
    mkdir $to_dir, 0755 or die "Can't mkdir $to_dir: $!\n";
}
ok -d $to_dir && -w $to_dir,
    "$to_dir exists and is writable";
ok -d $from_dir && -r $from_dir,
    "$from_dir exists and is readable";

my $pat  = "$to_dir\/.*?\.$arch";  # Archive only at first.
my $keep = 5;

SKIP: {
    skip "Can't find your archive program", 1 unless $arch_prog;

    # Just archive
    back(
#        debug => 1,
        from => $from_dir,
        to   => $to_dir,
        keep => 0,
        pattern => $pat,
        compress => 0,
    );

}  # End skip archive only 

SKIP: {
    skip "Can't find your archive+compression program", 1
        unless $comp_prog && $arch_prog;

    $pat = "$pat\.$comp_ext";  # Add the compression suffix.

    # Make 5 backups.
    for my $i (1 .. $keep) {
        back(
#            debug => 1,
            from => $from_dir,
            to   => $to_dir,
            keep => $i,
            pattern => $pat,
        );
    }

    # Make a 6th backup and test keep = -1.
    back(
#        debug => 1,
        from => $from_dir,
        to   => $to_dir,
        keep => -1,
        pattern => $pat,
    );

    # Make a 7th backup and then test the keep parameter wrt purging.
    back(
#        debug => 1,
        from => $from_dir,
        to   => $to_dir,
        keep => $keep,
        pattern => $pat,
    );

    $keep = 0;

    # Test with no file locking.
    back(
#        debug => 1,
        from => $from_dir,
        to   => $to_dir,
        keep => $keep,
        pattern => $pat,
        lock => 0,
    );

    # Only backup a single file.
    back(
#        debug => 1,
        from => "$from_dir/1",
        to   => $to_dir,
        keep => $keep,
        pattern => $pat,
    );

    # Only backup files with single character names.
    back(
#        debug => 1,
        from => "$from_dir/?",
        to   => $to_dir,
        keep => $keep,
        pattern => $pat,
    );
}  # End skip compress with archive
