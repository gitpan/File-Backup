# $Id: Backup.pm,v 1.22 2003/09/22 01:49:00 gene Exp $

package File::Backup;
use strict;
use Carp;
use vars qw($VERSION); $VERSION = '0.06.1';
use base qw(Exporter);
use vars qw(@EXPORT_OK @EXPORT);
@EXPORT = @EXPORT_OK = qw(backup);

use Cwd;
use File::Which;
use LockFile::Simple qw(lock unlock);

sub backup {  # {{{
    # Function parameters:   {{{
    # Default options:
    my %o = (
        debug => 0,  # Debugging: It does a body good.

        # Source and destination directory defaults.
        from => cwd(),
        to   => cwd(),

# TODO Implement these:
#        files => [],    # List of files to backup.
#        include => '',  # Regular expression of filenames to match.
#        exclude => '',  # Regular expression of filenames to match.
#        flatten => 0,   # Do not preserve the source directory tree.
#        unique_names => 1,  # Source files must have unique names.

        keep => 7,  # Backup files to keep in the destination dir.

        timeformat => 'YYYY-MM-DD_hh-mm-ss',  # Format string.
        use_gmtime => 0,  # Use the system localtime not gmtime.

        archive => 1,  # We want to tar/gz/zip our backups.
        archiver => scalar which('tar'),  # The achiving program.
        archive_flags => '-cf',  # Archive switches.
        prefix => '',      # Archive prefix.
        suffix => '.tar',  # Archive suffix.

        compressor => scalar which('gzip'),  # Local gzip location.
        compress_flags => '',  # Compression switches.
        compress => 1,  # Compression on or off.

        # Idiomatic "catch-all" for passing alternate parameters or
        # redefining default ones.
        @_,
    );

    # And now for the legacy API backward compatibility:
    # If the compress arg is not numeric, it is probably the name of
    # the compression program that the caller wants to use.
    if ($o{compress} !~ /^\d$/) {
        $o{compressor} = $o{compress};
        $o{compress} = 1;
    }
    @o{qw(tar      tarflags      torootname tarsuffix compressflags)} = 
    @o{qw(archiver archive_flags prefix     suffix    compress_flags)};
    # }}}

    croak "Archiver executable not found. Ouch.\n"
        if $o{archive} && !$o{archiver};
    croak "Compressor executable not found. Ouch.\n"
        if $o{compress} && !$o{compressor};

#    _debug("Parameters:\n", map { "$_: $o{$_}\n" } keys %o) if $o{debug};
    _debug('From directory ', -d $o{from} ? 'exists' : 'does not exist') if $o{debug};
    _debug('To directory ',   -d $o{to}   ? 'exists' : 'does not exist') if $o{debug};

    # The files that have been backed up.
    my %backed_files = ();

    # Strip any trailing file separator off the destination directory.
    # XXX Oof. OS dependency.
    $o{to} =~ s#/$##;

    # Stitch together the name of the archive file.
    my $dest = "$o{to}/";
    $dest .= $o{prefix} if $o{prefix};
    $dest .= _time_to_string(
        format => $o{timeformat},
        use_gmtime => $o{use_gmtime},
    );
    $dest .= "$o{suffix}" if $o{suffix};
#    _debug("Archive file to make: $dest") if $o{debug};

    if ($o{archive} && $dest) {  # {{{
        # Package up the file
        my @command = ($o{archiver}, $o{archive_flags}, $dest, $o{from});
        _debug('Archive command: ', join ' ', @command) if $o{debug};

        # Lock each file in the from directory.
        opendir FROM, $o{from} or
            croak "Can't open directory $o{from}: $!\n";
        _debug("Locking files in $o{from}") if $o{debug};
        for (grep { !-d } readdir FROM) {
            my $file = "$o{from}/$_";
            _debug("Locking $file") if $o{debug};
            lock("$file") or croak "Can't lock $file\n";
        }
        closedir FROM or croak "Can't close directory $o{from}: $!\n";

        # Execute the archive command.
        croak "Error executing archive command: $!"
            unless system(@command) == 0 && -e $dest;
        _debug("Made archive file: $dest") if $o{debug};

        opendir FROM, $o{from} or
            croak "Can't open directory $o{from}: $!\n";
        # unlock each non-lock file in the from directory.
        for (grep { !-d && !/\.lock$/ } readdir FROM) {
            my $file = "$o{from}/$_";
            unlock($file) or croak "Can't unlock $file\n";
            _debug("Unlocked $file") if $o{debug};
        }
        _debug("Unlocked files in $o{from}.") if $o{debug};
        closedir FROM or croak "Can't close directory $o{from}: $!\n";

        # Compress the file
        if ($o{compressor} and $o{compress}) {
            @command = ($o{compressor}, $o{compress_flags}, $dest);
            $dest .= '.gz';
            _debug('Compression command: ', join ' ', @command) if $o{debug};
            croak "Error executing compression command: $!"
                unless system(join ' ', @command) == 0 && -e $dest;
            _debug("Made compressed file: $dest") if $o{debug};
        }

        # Log the archive name.
        $backed_files{$o{from}} = $dest;
#_debug("Backed files:\n", map { "$_: $backed_files{$_}\n" } keys %backed_files) if $o{debug}; 

        # Rotate ("only keep the latest") backups if keep is not
        # negative.
        if ($o{keep} >= 0) {  # {{{
            _debug("Proceed to rotate with $o{keep} max in '$o{timeformat}' format.") if $o{debug};
            # Open the destination directory.
            local *DIR;
            opendir (DIR, $o{to}) or croak "Can't open $o{to}: $!\n";

            # Convert the YMDhms format string to a \d regular expression.
            my $regexp = _format_to_re($o{timeformat});

            # Grab the names of all the existing backup files.
            my @files;
            while (my $file = readdir DIR) {
#                _debug("Saw $file") if $o{debug};
                if ($file =~
                    /^               # Start
                     \Q$o{prefix}\E  # Prefix
                     $regexp         # Date RE
                     \Q$o{suffix}\E  # Suffix
                    /x
                ) {
                    _debug("Existing backup file: $file") if $o{debug};
                    push @files, $file;
                }
            }

            # Close the from directory.
            closedir DIR or croak "Can't close $o{to}: $!\n";

            # Keep a finite number of backup files unless the keep flag
            # is set to a negative number.
            if ((@files > $o{keep}) and ($o{keep} >= 0)) {
                _debug(scalar @files . " > $o{keep} and $o{keep} >= 0") if $o{debug};
                @files = (reverse sort @files)[$o{keep} .. $#files];
                for my $file (@files) {
                    _debug("Unlinking $o{to}/$file") if $o{debug};
                    unlink("$o{to}/$file") or
                        carp "Couldn't unlink $file: $!";
                }
            }
        }  # }}}
    }  # }}}

    return \%backed_files;
}  # }}}

sub _time_to_string {  # {{{
    my %args = @_;
    my $stamp = '';

    # No format provided.  Return an empty string.
    if (!$args{format}) {
        $stamp = '';
    }
    # Use epoch time if format is given as the word 'epoch'.
    elsif ($args{format} eq 'epoch') {
        $stamp = time;
    }
    # Convert a YMDhms format string to %0d sprintf style.
    elsif (my $printf_format = _format_to_printf($args{format})) {
        croak "Unrecognized format: $args{format}.\n"
            unless $printf_format;

        my ($sec, $min, $hr, $dy, $mo, $yr) =
            $args{use_gmtime} ? gmtime : localtime;

        $stamp = sprintf $printf_format,
            1900 + $yr, ++$mo, $dy, $hr, $min, $sec;
    }

    return $stamp;
}

sub _format_to_re {
    my $format = shift;
    # Convert YMDhms to \d.
    $format =~ s/[dhmsy]/\\d/ig;
    return $format;
}

sub _format_to_printf {
    my $format = shift;

    my $n = 0;

    for my $char (qw(Y M D h m s)) {
        $n++ while $format =~ /$char/g;
        $n = '%0'. $n .'d';
        $format =~ s/$char+/$n/;
        $n = 0;
    }

    return $format;
}  # }}}

sub _debug { print @_, "\n"; }

1;
__END__

=head1 NAME

File::Backup - Easy file backup & rotation automation

=head1 SYNOPSIS

  use File::Backup;

  backup(
      from => '/source/path/to/backup/from',
      to   => '/destination/path/to/backup/to',
      keep => 5,
      timeformat => 'YYMMDD_hhmmss',
  );

=head1 DESCRIPTION

This module implements archival and compression (A.K.A "backup") 
schemes with automatic source file locking.

* Currently, this is only tar and gzip with Unix path strings.  Maybe 
your computer is okay with that... Cross platform file backing is
going to be implemented soon.

A really nice feature of this new version is the use of C<File::Which> 
to find your local version of tar and gzip.  Additionally, automatic
file locking ala C<LockFile::Simple> is implemented now.

One very cool thing is that you can now supply the C<backup> function 
with an arbitrary timestamp format string.

Also, you can specify whether to apply compression to your tar.

All these options are detailed in the arguments section of the 
C<backup> function documentation, below.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<backup> %ARGUMENTS

  $backed_files = backup(%arguments);

In its barest form, this function takes as input a source directory 
and a destination directory, and puts a compressed archive file of the
source directory files into the destination directory.

Return a hash reference with the path of the source as key and the 
name of the archive file as the value or the files that were backed-up 
individually as the keys and the new, timestamped path names as their 
values, respectively.

The function arguments are described below.

=over 4

=item * debug => 0 | 1

Turn on verbose processing.  Defaults to zero (off).

=item * from => $PATH

The source directory of files to backup.  If not given, the current 
directory is used.

=item * to => $PATH

The optional destination directory where the archive is placed.  If
not given, the current directory is used.

=item * keep => $NUMBER

The maximum number of backups to keep in the directory.

By setting this to some non-negative number C<n>, the C<n> most 
recent backups will be kept.  Set this to a negative number to keep 
all backups.  The default is set to the magical number 7 (a weeks 
worth of backups).

=item * timeformat => $STRING

The date-time format string to use in stamping backup files.

This parameter can take either nothing for no timestamp, the word 
'epoch' to use C<time> as the stamp, or a string containing a 
combination of the following in order:

  Y => year
  M => month
  D => day
  h => hour
  m => minute
  s => second

How about some examples:

'YYYY-MM-DD_hh-mm-ss' is seen by C<sprintf> as
'%4d-%02d-%02d_%02d-%02d-%02d'.  For Janurary 2, 2003 at 3:04 and 
5 seconds AM, that would be '2003-01-02_03-04-05'.

You can leave off ending format characters.  'YYYYMMDD' would be 
'%04d%02d%02d' producing '20030102'.

Note that this module always uses a four digit numeral for the year,
so 'Y-MMDD' will produce '2003-0102'. 

This "reverse date" scheme is used to unambiguously sort the backup 
files chronologially.  That is, the stamp must be in order of largest 
timescale maginitude.  Of course, you can produce an ambiguous stamp
with 'YMDhms' which would produce '200312345'.  Is this December 3rd,
2003?  Who knows?

=item * archive => 0 | 1

Flag to archive the backed-up files.  Default 1.

* This is not useful yet, but in a future version files will be able 
to be stamped and copied to a backup directory without any bundled 
archiving.

=item * archiver => $PATH_TO_PROGRAM

The achiving program.  Default is your local tar.

=item * archive_flags => $COMMAND_SWITCHES

The optional archive switches.  Default C<'-cf'>.

=item * prefix => $STRING

An optional prefix string to be used as the beginning of the archive 
filename (before the timestamp string).

This is useful if backups of several different things are being kept
in the same directory.

=item * suffix => $STRING

The optional, but important archive extension.  This defaults to 
C<'.tar'>.

=item * compressor => $PATH_TO_PROGRAM

The compression program.  Default is your local gzip.

=item * compress_flags => $COMMAND_SWITCHES

The optional compression switches.

=item * compress => 0 | 1

Flag to turn archive compression off or on.

* Currently, this only makes sense if the C<archive> flag is turned on.

=item * files => \@FILENAMES

The optional list of files to backup.

B<XXX Not yet implemented>

=item * include => $REGEXP

An optional regular expression of filenames to match for inclusion.

B<XXX Not yet implemented>

=item * exclude => $REGEXP

An optional regular expression of filenames to match for exclusion.

B<XXX Not yet implemented>

=item * flatten => 0 | 1

Flag to preserve the source directory tree structure or not.  Default 
set to 0.

B<XXX Not yet implemented>

=item * unique_names => 0 | 1

Flag to force source files to have unique names in the archive.
Default 0.

B<XXX Not yet implemented>

=back

The following legacy parameters are still around, but are now aliases 
to the corresponding parameters:

  tar           => archiver
  tarflags      => archive_flags
  torootname    => prefix
  tarsuffix     => suffix
  compress      => compressor
  compressflags => compress_flags

=back

=head1 PRIVATE FUNCTIONS

=over 4

=item B<_time2str> [%ARGUMENTS]

  $timestamp = _time2str(
      format     => $YMDhms_format,
      use_gmtime => $boolean,
  );

Return a date-time string to use in a file name.

See the documentation for the C<timeformat> parameter for a 
description of what a YMDhms format string is.

The system C<localtime> is used unless the C<use_gmtime> flag is set
in the C<backup> function call.

If a format string is not provided, an empty string will be returned 
for the stamp.  If it is set to the string, 'epoch', then the perl 
C<time> function will be used for the returned stamp.  Otherwise, the
YMDhms format string is used.

=item B<_format_to_regexp> $FORMAT

  $re = _format_to_regexp($YMDhms_format);

Convert a 'YMDhms format string' into a simple regular expression.

This function simply replaces the format characters with a \d (digit 
metacharacter).

=item B<_format_to_printf> $FORMAT

  $printf_format = _format_to_printf($YMDhms_format);

This function replaces the YMDhms format characters with a %0B<n>d 
printf format string, where B<n> is the number of identical, 
contiguous YMDhms format characters.

=back

=head1 BUGS

You can't make two backups of the same stuff in one second, because 
they'll try to have the same name.  Is this really a bug?

=head1 TO DO

Test every edge case parameter permutation!

Restrict processing to a provided list of filenames and wildcards.

Support file include and exclude regexps.

Make a friendly commandline function using a C<Getopt::*> module.

Use C<File::Spec> or C<Class::Path> to build OS aware backup strings.

Use C<Archive::Any/File/Tar/Zip> instead of Unix system calls.

Use other archivers and compressiors not covered by perl modules.

Do the same for compression, of course (e.g. C<Compress::Zlib>, etc).

Backup to database with record locking.

Descend into directories with C<File::Find>.

Use standard ISO formats for the C<time2str> function.

Allow various backup file naming conventions (also with a string 
format).

Make the C<keep> option time sensitive as well as "numerically 
naive".   Consider the C<ctime> and C<mtime> file attributes.

Allow the source files to be backed up without the file system 
directory tree structure.  That is, "flatten" the archive.

Allow the user to make sure unique filenames are being used in the
backup.

Make a C<File::Backup::Base> superclass for implementing focused 
back-up tasks.  (With cvs or scp, nfs or to a legacy device, for 
instance.)

Okay.  Support scp with C<Net::SCP>.  Should this be 
C<File::Backup::SCP> or C<File::Backup qw(scp)>.  Hmmm.

Make the code magically look for system archival programs, if asked 
nicely.

=head1 SEE ALSO

L<Cwd>

L<File::Which>

L<LockFile::Simple>

=head1 THANK YOU

Help, insight, suggestions and comments came from Ken Williams
(A.K.A. DrMath) and Joshua Keroes (A.K.A. ua).

=head1 AUTHORS

Original: Ken Williams, E<lt>kwilliams@cpan.orgE<gt>

Current: Gene Boggs, E<lt>gene@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 1998-2003 Ken Williams.  All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
