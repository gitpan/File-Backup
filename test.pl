# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..7\n"; }
END {print "not ok 1\n" unless $loaded;}
use File::Backup('backup');
$loaded = 1;
&report(1);

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

my $testdir = "testdir";
my $bdir = "backupdir";

system("rm -rf $testdir");
mkdir $testdir, 0777 or die "Can't create $testdir: $!";
foreach (1..3) {
	open F, ">$testdir/$_" or die "$testdir/$_: $!";
	print F $_ x 20;
	close F;
}

system("rm -rf $bdir");
mkdir $bdir, 0777 or die "Can't create $bdir: $!";
my $keep = 5;
foreach (1..$keep) {
    backup(
        from => $testdir,
        to   => $bdir,
        keep => $keep,
    );
    my @backups = `ls $bdir`;
    &report(@backups == $_);
    sleep 1;
}

backup(
        from => $testdir,
        to   => $bdir,
        keep => $keep,
);
my @backups = `ls $bdir`;
&report(@backups == $keep);

system("rm -rf $testdir");
system("rm -rf $bdir");

#################################################################
sub report {
    my $ok = shift;
    $TEST_NUM++;
    print "not "x(!$ok), "ok $TEST_NUM\n";
    print STDERR $_[0] if (!$ok and $ENV{'TEST_VERBOSE'});
}
