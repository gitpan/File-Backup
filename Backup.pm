package File::Backup;

use strict;
use vars qw($VERSION @ISA @EXPORT_OK);
use Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = ('backup');
$VERSION = '0.02';

sub backup {
    my %o = (
        'keep' => 7,
        'tar'  => '/bin/tar',
        'compress' => '/usr/bin/gzip',
        'tarflags' => '-cf',
        'compressflags' => '',
        'tarsuffix' => '.tar',
        @_,
    );
    
    # Build the destination filename
    $o{to} =~ s#/$##;
    my $dest = "$o{to}/$o{torootname}" . &time2str . "$o{tarsuffix}";
    
    # Package up the file
    my $tarcmd = "$o{tar} $o{tarflags} $dest $o{from}";
    unless (system($tarcmd) == 0) {
        die "$tarcmd: $!";
    }
    
    # Compress the file
    if ($o{compress}) {
        my $zipcmd = "$o{compress} $o{compressflags} $dest";
        unless (system($zipcmd) == 0) {
            die "$zipcmd: $!";
        }
    }
    
    # Rotate the backups
    local *DIR;
    opendir (DIR, $o{to}) or die $!;
    my ($bfile, @extant);
    while (defined ($bfile = readdir DIR)) {
        push @extant, $bfile if $bfile =~ 
            /^\Q$o{torootname}\E                # Root part
              \d\d\d\d-\d\d-\d\d_\d\d-\d\d-\d\d # Date part
              \Q$o{tarsuffix}\E                 # Suffix part
            /x;
    }
    
    if (@extant > $o{keep}  and  $o{keep} >= 0) {
        @extant = (reverse sort @extant)[$o{keep} .. $#extant];
        foreach (@extant) {
            unlink("$o{to}/$_") or warn "Couldn't remove $_: $!";
        }
    }
}

sub time2str {
    my ($sec, $min, $hr, $dy, $mo, $yr) = localtime();
    $mo++; $yr+=1900;
    foreach (\($sec,$min,$hr,$dy,$mo)) {
        $$_ = "0$$_" if length($$_) == 1;
    }
    return "$yr-$mo-${dy}_$hr-$min-$sec";
}


1;
__END__

=head1 NAME

File::Backup - For making rotating backups of directories

=head1 SYNOPSIS

  use File::Backup("backup");
  backup(
     from          => "/dir/to/back/up",
     to            => "/destination/of/backup/files",
     torootname    => root name of backup file (default is ""),
     keep          => number of backups to keep in todir (default is 7),
     tar           => path to archiving utility (default is "/usr/bin/tar"),
     compress      => path to compressing utility (default is "/usr/bin/gzip"),
     tarflags      => flags to pass to 'tar' (default is "-cf"),
     compressflags => flags to pass to 'cmpr' (default is ""),
     tarsuffix     => suffix to put on the tarfile (default is '.tar'),
  );

=head1 DESCRIPTION

This module implements a very simple backup scheme.  In its barest form, it takes
as input a source directory and a destination directory, and puts a backup of the
source directory in the destination directory.  You may specify a maximum number
of backups to keep in the directory (the 'keep' parameter).  By setting the 'keep'
parameter to n, you will keep the n most recent backups.  Specify -1 to keep all
backups.

The backup will include a date string (of the format YYYY-MM-DD_hh-mm-ss) that
will be used to figure out which files are the most recent.  You can also give
a string that will be used as the beginning of the backup's filename (before the
date string), which may be useful if you're keeping backups of several different
things in the same directory.

=head1 BUGS

You can't make two backups of the same stuff in one second, because they'll try to
have the same name.

=head1 AUTHOR

Ken Williams (ken@forum.swarthmore.edu)

=head1 COPYRIGHT

Copyright 1998 Ken Williams.  All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

perl(1).

=cut
