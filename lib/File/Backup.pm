package File::Backup;

use vars qw($VERSION);
$VERSION = '0.07';

use strict;
use Carp;
use base qw(Exporter);  # XXX Yuck. Exported is bloated.
use vars qw(@EXPORT_OK @EXPORT);
@EXPORT = @EXPORT_OK = qw(backup);
use Cwd;
use File::Which;
use LockFile::Simple qw(lock unlock);

sub backup {  # {{{
    # Function parameters  {{{
    # Default options
    my %o = (
        debug => 0,  # Debugging: It does a body good.

        # Source and destination directory defaults.
        from => cwd(),
        to   => cwd(),

        keep => 7,  # Number of backup files to keep.  Legacy code of a week.

        timeformat => 'YYYY-MM-DD_hh-mm-ss',  # Format string.
        use_gmtime => 0,  # Use the system localtime not gmtime.

        archive => 1,  # Archive toggle
        archiver => scalar which('tar'),  # The achiving program.
        archive_flags => '-cf',  # Archive switches.
        archive_prefix => '',      # Archive prefix.
        archive_suffix => 'tar',  # Archive suffix.

        compress => 1,  # Compression on or off.
        compressor => scalar which('gzip'),  # The compression program.
        compress_flags => '',  # Compression switches.
        compress_suffix => 'gz',  # Compression suffix.

        lock => 1,  # Turn locking on or off.
        purge_first => 0,  # Purge the backups after the backup.

        # Idiomatic "catch-all" for passing alternate parameters or
        # redefining default ones.
        @_,
    );

    # If the compress arg is not numeric, it is probably the name of
    # the compression program that the caller wants to use.
    if ($o{compress} !~ /^\d$/) {
        $o{compressor} = $o{compress};
        $o{compress} = 1;  # Assume that the user wants compression.
    }

    # NOTE I changed the names of the *fix parameters and need to be
    # backwards compatible with myself now.  Grrrr!
    $o{archive_prefix} = $o{prefix} if $o{prefix};
    $o{archive_suffix} = $o{suffix} if $o{suffix};

    # Now for the legacy API compatibility.
    @o{qw(tar      tarflags      torootname     tarsuffix      compressflags)} = 
    @o{qw(archiver archive_flags archive_prefix archive_suffix compress_flags)};
    # }}}

    croak "Archiver executable not found. Ouch.\n"
        if $o{archive} && !$o{archiver};
    croak "Compressor executable not found. Ouch.\n"
        if $o{compress} && !$o{compressor};

#    _debug("Parameters:\n", map { "$_: $o{$_}\n" } keys %o) if $o{debug};
    _debug('Source ',(-d $o{from}|| glob join' ',$o{from}?'does':'does not').' exist') if $o{debug};
    _debug('Destination path ',(-d $o{to}?'does':'does not').' exist') if $o{debug};

    # The files that have been backed up.
    my %backed = ();

    # Strip any trailing file separator off the destination directory.
    $o{to} =~ s#/$##;

    # Stitch together the name of the archive file.
    my $dest = "$o{to}/";
    $dest .= $o{archive_prefix} if $o{archive_prefix};
    $dest .= _time_to_string(
        format => $o{timeformat},
        use_gmtime => $o{use_gmtime},
    );
    $dest .= '.' . $o{archive_suffix} if $o{archive_suffix};
#    _debug("Archive file to make: $dest") if $o{debug};

    if ($o{archive} && $dest) {  # {{{
        purge_backups(\%o) if $o{purge_first};

        # Lock each file in the from directory.
        if ($o{lock}) {  # {{{
            if (-d $o{from}) {
                opendir FROM, $o{from} or
                    croak "Can't open directory $o{from}: $!\n";
                _debug("Locking files in $o{from}") if $o{debug};

                for my $file (grep { !-d } readdir FROM) {
                    $file = "$o{from}/$file";
                    _debug("Locking $file") if $o{debug};
                    lock($file);
                }

                closedir FROM or
                    croak "Can't close directory $o{from}: $!\n";
            }
            else {
                for my $file (grep { !-d } glob join ' ', $o{from}) {
                    _debug("Locking glob $file") if $o{debug};
                    lock($file);
                }
            }
        }  # }}}

        # Build and execute the archive command.
        my @command = ($o{archiver}, $o{archive_flags}, $dest, $o{from});
        _debug('Archive command: ', join ' ', @command) if $o{debug};
        croak "Error executing archive command: $!"
            unless system(join ' ', @command) == 0 && -e $dest;
        _debug("Made archive file: $dest") if $o{debug};

        # Lock each file in the from directory.
        if ($o{lock}) {  # {{{
            if (-d $o{from}){
                opendir FROM, $o{from} or
                    croak "Can't open directory $o{from}: $!\n";

                # unlock each non-lock file in the from directory.
                for (grep { !-d && !/\.lock$/ } readdir FROM) {
                    my $file = "$o{from}/$_";
                    _debug("Unlocking $file") if $o{debug};
                    unlock($file);
                }

                _debug("Unlocked files in $o{from}.") if $o{debug};
                closedir FROM or croak "Can't close directory $o{from}: $!\n";
            }
            else {
                for my $file (grep { !-d } glob join ' ', $o{from}) {
                    _debug("Unlocking glob $file") if $o{debug};
                    unlock($file);
                }
            }
        }  # }}}

        # Compress the archive
        if ($o{compressor} and $o{compress}) {  # {{{
            @command = ($o{compressor}, $o{compress_flags}, $dest);
            $dest .= '.' . $o{compress_suffix};
            _debug('Compression command: ', join ' ', @command) if $o{debug};
            croak "Error executing compression command: $!"
                unless system(join ' ', @command) == 0 && -e $dest;
            _debug("Made compressed file: $dest") if $o{debug};
        }  # }}}

        # Log the archive name.
        $backed{ $o{from} } = $dest;
#_debug("Backed files:\n",map{"$_: $backed{$_}\n"}keys%backed) if $o{debug}; 

        purge_backups(\%o) unless $o{purge_first};
    }  # }}}

    return \%backed;
}  # }}}

# Rotate ("only keep the latest") backups if keep is not negative.
sub purge_backups {  # {{{
    my $args = shift;

    # Okay, zero backup keeping is allowed too.
    if ($args->{keep} >= 0) {
        _debug("Rotate with $args->{keep} max in '$args->{timeformat}' format.") if $args->{debug};

        # Open the backup directory.
        opendir (DIR, $args->{to}) or
            croak "Can't open $args->{to}: $!\n";

        # Convert the YMDhms format string to a \d regular expression.
        my $regexp = _format_to_re($args->{timeformat});

        # Create the archive filename.
        my $stamp = '';
        $stamp .= $args->{archive_prefix}
            if $args->{archive} && $args->{archive_prefix};
        $stamp .= $regexp;
        $stamp .= '\\.' . $args->{archive_suffix}
            if $args->{archive}  && $args->{archive_suffix};
        $stamp .= '\\.' . $args->{compress_suffix}
            if $args->{compress} && $args->{compress_suffix};
        _debug("Looking for: $stamp") if $args->{debug};

        # Grab the names of all the files in the backup directory.
        my @files;
        while (my $file = readdir DIR) {
            _debug("Saw $file") if $args->{debug};
            if ($file =~ m/^$stamp$/) {
                _debug("Existing backup file: $file") if $args->{debug};
                push @files, $file;
            }
        }

        # Close the backup directory.
        closedir DIR or croak "Can't close $args->{to}: $!\n";

        # Keep a finite number of backup files unless the keep flag
        # is set to a negative number.
        if ((@files > $args->{keep}) and ($args->{keep} >= 0)) {
            _debug(scalar @files . " > $args->{keep} and $args->{keep} >= 0") if $args->{debug};
            @files = (reverse sort @files)[$args->{keep} .. $#files];
            for my $file (@files) {
                _debug("Unlinking $args->{to}/$file") if $args->{debug};
                unlink("$args->{to}/$file") or
                    carp "Couldn't unlink $file: $!";
            }
        }
    }
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

# Convert YMDhms to \d.
sub _format_to_re {
    my $format = shift;
    $format =~ s/[dhmsy]/\\d/ig;
    return $format;
}

# Convert YMDhms to printf format.
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

  backup( from => "/source/path", to => "/destination/path" );
  backup( from => "/kansas/*", to => "/oz" );

  purge_backups(
      to => "/destination/path",
      compress => 0,
      keep => 5,
      timeformat => "YYYYMMDD_hhmmss",
  );

=head1 DESCRIPTION

This legacy module implements archival and compression (A.K.A
"backup") and file rotation and is an implementation of C<tar> and
C<gzip> calls.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<backup> %ARGUMENTS

  $backed = backup(%arguments);

In its barest form, this function takes as input a source path or glob
and a destination directory, and puts an archive file of the source
directory files into the destination directory.

The backup() function returns a single valued source => destination
hash reference (AKA an array).

The function arguments are described below.

=over 4

=item * debug => 0 | 1

Turn on verbose processing.  Default is off.

=item * from => $PATH

The source directory or glob reference of files to backup.  If not
given, the current directory is used.

=item * to => $PATH

The optional destination directory where the archive is placed.  If
not given, the current directory is used.

=item * keep => $NUMBER

The maximum number of backups to keep in the directory.

By setting this to some non-negative number C<n>, the C<n> most 
recent backups will be kept.  Set this to a negative number to keep 
all backups.  The default is the magical number 7 (a weeks worth).
If C<keep> is set to zero, no backup files will be kept.

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

The default 'YYYY-MM-DD_hh-mm-ss' in C<printf> format is
'%4d-%02d-%02d_%02d-%02d-%02d'.  For Janurary 2, 2003 at 3:04 and 
5 seconds AM, that would be '2003-01-02_03-04-05'.

You can leave off ending format characters.  'YYYYMMDD' would produce
'20030102'.  This module always uses a four digit numeral for the
year, so 'Y-MMDD' would actually produce '2003-0102'. 

The "reverse date" scheme is used to unambiguously sort the backup 
files chronologically.  You can of course produce a stamp with
'YMDhms' which would make '200312345'.  Is that December 3rd or
January 23rd?  Who knows?  Don't do that.

=item * archive => 0 | 1

Flag to toggle file archiving.  Default is on.

=item * archiver => $PATH_TO_PROGRAM

The achiving program.  The default is the local C<tar> program.

=item * archive_flags => $COMMAND_SWITCHES

The optional archive switches.  Default is set to the C<tar> program's
C<-cf>.  That is, "create" and "filename".  See L<tar> of course.

=item * archive_prefix => $STRING

An optional archive_prefix string to be used as the beginning of the archive 
filename (before the timestamp string).  This is handy for
identifying your backup files and defaults to nothing (i.e. '').

=item * archive_suffix => $STRING

The optional, but important archive extension.  This defaults to 
the string C<tar>.

=item * compressor => $PATH_TO_PROGRAM

The compression program.  Default is the local C<gzip> program.

=item * compress_flags => $COMMAND_SWITCHES

The optional compression switches.  Default is nothing.

=item * compress => 0 | 1

Flag to toggle archive compression.  Default is on.  We like compression.

* Currently, this only makes sense if the C<archive> flag is turned on.

=item * compress_suffix => $STRING

The optional, but important archive extension.  This defaults to 
the string C<gz>.

=item * lock => 0 | 1

Flag to toggle file locking.  Default is on.

=item * purge_first => 0 | 1

Flag to toggle when file purging happens.  The default is off, which
means that old backup files are "rotated" after the backup process
happens.

=back

=item B<purge_backups> %ARGUMENTS

This function is handy for cleaning out backup directories.  It does
no archival but the arguments are the same as with the C<backup>
function.

=back

=head1 LEGACY

The following parameters are still around, but are now aliased to the
corresponding names:

  tar           => archiver
  tarflags      => archive_flags
  torootname    => archive_prefix and prefix
  tarsuffix     => archive_suffix and suffix
  compress      => compressor
  compressflags => compress_flags

=head1 BUGS

You can't make two backups of the same stuff in one second, because 
they'll try to have the same name.  Is this really a bug?

=head1 TO DO

Make the stuttering YYYYMMDDhhmmss stop.  Just use YMDhms or make
the string processing intelligent instead.  There's an idea...

Restrict processing to a provided list of filenames and look for them
with C<File::Find>.

Support file name include and exclude regexps.

Make a friendly commandline function using a C<Getopt::*> module.

Use C<Archive::Any/File/Tar/Zip/Whatever> instead of Unix system
calls.

Use standard ISO formats for the C<time2str> function.

Allow various backup file naming conventions (also with a string 
format).

Make the C<keep> option time sensitive as well as "numerically 
naive".   Consider the C<ctime> and C<mtime> file attributes.

Make the C<keep> option size sensitive.  Duuuh.

Allow the source files to be backed up without the file system 
directory tree structure.  That is, "flatten" the archive.

Make sure unique filenames are being used in the backup.

Make a C<File::Backup::Base> superclass for implementing focused 
back-up tasks with cvs or scp, nfs or to a legacy device, for 
instance.

=head1 SEE ALSO

C<Cwd>

C<File::Which>

C<LockFile::Simple>

Related modules:

C<File::Rotate::Backup> is a later, apparantly orphaned module that
appears to be mostly redundant.

C<Dir::Split> seems handy.

=head1 THANK YOU

Help, insight, suggestions and comments came from Ken Williams, Joshua
Keroes and John McDermott.

=head1 AUTHORS

Original: Ken Williams E<lt>kwilliams@cpan.orgE<gt>

Current: Gene Boggs E<lt>gene@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 1998-2004 Ken Williams and Gene Boggs.  All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 CVS

$Id: Backup.pm,v 1.28 2004/03/23 12:17:06 gene Exp $

=cut
