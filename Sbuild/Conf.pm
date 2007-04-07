#
# Conf.pm: configuration library for sbuild
# Copyright (C) 2005 Ryan Murray <rmurray@debian.org>
# Copyright (C) 2006 Roger Leigh <rleigh@debian.org>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
#
# $Id: Sbuild.pm,v 1.2 2006/03/07 16:58:12 rleigh Exp $
#

package Sbuild::Conf;

use strict;
use warnings;
use Cwd qw(cwd);

BEGIN {
    use Exporter ();
    our (@ISA, @EXPORT);

    @ISA = qw(Exporter);

    @EXPORT = qw($HOME %alternatives $apt_policy $check_watches $cwd
		 $username $verbose $nolog $mailprog $dpkg $su
		 $schroot $schroot_options $fakeroot $apt_get
		 $apt_cache $dpkg_source $md5sum $avg_time_db
		 $avg_space_db $build_env_cmnd $pgp_options $log_dir
		 $mailto $mailfrom $purge_build_directory
		 @toolchain_regex $stalled_pkg_timeout
		 $srcdep_lock_dir $srcdep_lock_wait
		 @ignore_watches_no_build_deps $build_dir $sbuild_mode
		 $debug $force_orig_source
		 %individual_stalled_pkg_timeout $path
		 $maintainer_name $uploader_name $key_id);
}

# Originally from the main namespace.
(our $HOME = $ENV{'HOME'})
	or die "HOME not defined in environment!\n";
our $username = (getpwuid($<))[0] || $ENV{'LOGNAME'} || $ENV{'USER'};
our $cwd = cwd();
our $verbose = 0;
our $nolog = 0;

# Defaults.
our $source_dependencies;
our $mailprog = "/usr/sbin/sendmail";
our $dpkg = "/usr/bin/dpkg";
our $sudo;
our $su = "/bin/su";
our $schroot = "/usr/bin/schroot";
our $schroot_options = "-q";
our $fakeroot = "/usr/bin/fakeroot";
our $apt_get = "/usr/bin/apt-get";
our $apt_cache = "/usr/bin/apt-cache";
our $dpkg_source = "/usr/bin/dpkg-source";
our $md5sum = "/usr/bin/md5sum";
our $avg_time_db;
our $avg_space_db;
our $build_env_cmnd = "";
our $pgp_options = "-us -uc";
our $log_dir = "$HOME/logs";
our $mailto = "";
our $mailfrom = "Source Builder <sbuild>";
our $purge_build_directory = "successful";
our @toolchain_regex = ( 'binutils$', 'gcc-[\d.]+$', 'g\+\+-[\d.]+$', 'libstdc\+\+', 'libc[\d.]+-dev$', 'linux-kernel-headers$' );
our $stalled_pkg_timeout = 90; # minutes
our $srcdep_lock_dir = "/var/lib/sbuild/srcdep-lock";
our $srcdep_lock_wait = 1; # minutes
our $chroot_only;
our $chroot_mode;
our $apt_policy = 1;
our $check_watches = 1;
our @ignore_watches_no_build_deps = qw();
our $build_dir = undef;
our $sbuild_mode = "buildd";
our $debug = 0;
our $force_orig_source = 0;
our %individual_stalled_pkg_timeout = ();
our $path = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/X11R6/bin:/usr/games";
our $maintainer_name;
our $uploader_name;
our $key_id;
our %alternatives;

# read conf files
require "/usr/share/sbuild/sbuild.conf";
require "/etc/sbuild/sbuild.conf" if -r "/etc/sbuild/sbuild.conf";
require "$HOME/.sbuildrc" if -r "$HOME/.sbuildrc";

sub init {
	# some checks
	die "mailprog binary $Sbuild::Conf::mailprog does not exist or isn't executable\n"
		if !-x $Sbuild::Conf::mailprog;
	die "schroot binary $Sbuild::Conf::schroot does not exist or isn't executable\n"
	    if !-x $Sbuild::Conf::schroot;
	die "apt-get binary $Sbuild::Conf::apt_get does not exist or isn't executable\n"
		if !-x $Sbuild::Conf::apt_get;
	die "apt-cache binary $Sbuild::Conf::apt_cache does not exist or isn't executable\n"
		if !-x $Sbuild::Conf::apt_cache;
	die "dpkg-source binary $Sbuild::Conf::dpkg_source does not exist or isn't executable\n"
		if !-x $Sbuild::Conf::dpkg_source;
	die "$Sbuild::Conf::srcdep_lock_dir is not a directory\n"
		if ! -d $Sbuild::Conf::srcdep_lock_dir;
	die "mailto not set\n" if !$Sbuild::Conf::mailto;

	if (!defined($Sbuild::Conf::build_dir)) {
	    $Sbuild::Conf::build_dir = $Sbuild::Conf::cwd;
	}
	if (! -d "$Sbuild::Conf::build_dir") {
	    die "Build directory $Sbuild::Conf::build_dir does not exist";
	}

	if (defined($chroot_mode)) {
	    die "chroot_mode is obsolete";
	}

	if (defined($chroot_only)) {
	    die "chroot_only is obsolete";
	}

	if (defined($sudo)) {
	    die "sudo is obsolete";
	}

	if (defined($source_dependencies)) {
	    die "Source dependencies are obsolete";
	}

}

1;
