#!/bin/bash

# GPLv2.
# (C) 2009 Philipp Kern
# (C) 2009 Marc Brockschmidt

set -e

if [ "$USER" != "buildd" ]
then
    echo "You need to run this as user buildd!" >&2
    exit 1
fi

usage() {
    message=$1
    if [ ! -z "$message" ]
    then
        echo "E: $message" >&2
    fi
    echo "Usage: $0 http://some.debian.mirror/debian suite [vgname lvsize]" >&2
    echo "Valid suites: oldstable, stable, testing, unstable," >&2
    echo "              oldstable-security, stable-security," >&2
    echo "              testing-security, oldstable-backports," >&2
    echo "              stable-backports, oldstable-edu," >&2
    echo "              stable-edu, stable-volatile," >&2
    echo "              testing-volatile, experimental" >&2
    echo "If vgname is given, the script will setup schroot" >&2
    echo "to use snapshots based on a source lv." >&2
    exit 1
}

error() {
    message=$1
    echo "E: ${message}" >&2
    exit 1
}

MIRROR="$1"
SUITE="$2"
VGNAME="$3"
LVSIZE="$4"
# This might need an adjustment if you are creating chroots different
# from the host architecture.  (Not tested.)
ARCH="$(dpkg --print-architecture)"

if [ -z "$MIRROR" ]
then
    usage "No mirror specified!"
fi

if [ -z "$SUITE" ]
then
    usage "No suite specified!"
fi

if ! [ -z "$VGNAME" ] && [ -z "$LVSIZE" ]
then
    usage "You need to specifiy a source lv size!"
fi

BASE="$SUITE"
OLDSTABLE="etch"
STABLE="lenny"
TESTING="squeeze"
case "$SUITE" in
    oldstable) BASE=$OLDSTABLE ;;
    oldstable-security) BASE=$OLDSTABLE; VARIANT="security" ;;
    oldstable-backports) BASE=$OLDSTABLE; VARIANT="backports" ;;
    oldstable-volatile) BASE=$OLDSTABLE; VARIANT="volatile" ;;
    oldstable-edu) BASE=$OLDSTABLE; VARIANT="edu" ;;
    stable) BASE=$STABLE ;;
    stable-security) BASE=$STABLE; VARIANT="security" ;;
    stable-backports) BASE=$STABLE; VARIANT="backports" ;;
    stable-volatile) BASE=$STABLE; VARIANT="volatile" ;;
    stable-edu) BASE=$STABLE; VARIANT="edu" ;;
    testing) BASE=$TESTING ;;
    testing-security) BASE=$TESTING; VARIANT="security" ;;
    unstable) BASE="sid" ;;
    experimental) BASE="sid"; VARIANT="experimental";;
    *) usage "Invalid suite specified (must be symbolic, e.g. 'stable')!" ;;
esac

echo "I: Building environment for $SUITE"
echo "I: Mirror: $MIRROR"
echo "I: Base suite: $BASE"
if [ ! -z "$VARIANT" ]
then
    echo "I: Variant: $VARIANT"
    IDENTIFIER="$BASE-$VARIANT"
else
    IDENTIFIER="$BASE"
fi

TARGET=~buildd/chroots/$IDENTIFIER
echo "I: Chroot target: $TARGET"

check_prerequisites() {
    echo "I: Checking prerequisites..."
    [ -d /etc/schroot/chroot.d ] || \
        error "/etc/schroot/chroot.d not found, schroot not installed?"
    [ ! -d $TARGET ] || error "Target $TARGET already exists."
}

do_debootstrap() {
    ensure_target_mounted
    echo "I: Running debootstrap..."
    echo
    sudo debootstrap \
        --arch=$ARCH \
        --variant=buildd \
        --include=sudo,fakeroot,build-essential,debfoster,apt \
        $BASE \
        $TARGET \
        $MIRROR
    echo
    echo "I: Creating a policy-rc.d to prevent daemon startups..."
    TEMPFILE="$(mktemp)"
    cat > "${TEMPFILE}" <<EOT
#!/bin/sh                                                                                                                                                      
echo "All runlevel operations denied by policy" >&2                                                                                                            
exit 101
EOT
    sudo mv "${TEMPFILE}" "${TARGET}/usr/sbin/policy-rc.d"
    sudo chown root: "${TARGET}/usr/sbin/policy-rc.d"
    sudo chmod 0755 "${TARGET}/usr/sbin/policy-rc.d"
    ensure_target_unmounted
}

setup_symlink() {
    echo "I: Setting up symlink..."
    ln -sv "$(basename $TARGET)" $SUITE
}

setup_schroot() {
    echo "I: Setting up schroot configuration..."
    TEMPFILE="$(mktemp)"
    cat > "${TEMPFILE}" <<EOT
[${IDENTIFIER}-${ARCH}-sbuild]
description=Debian ${IDENTIFIER} buildd chroot
users=buildd
root-users=buildd
aliases=${SUITE}-${ARCH}-sbuild
run-setup-scripts=true
run-exec-scripts=true
EOT
    if [ -z "$VGNAME" ]; then
        echo "type=directory" >> "${TEMPFILE}"
        echo "location=${TARGET}" >> "${TEMPFILE}"
        SCHROOT="schroot -c ${IDENTIFIER}-${ARCH}-sbuild -u root -d /root --"
    else
        cat >>"${TEMPFILE}" <<EOT
type=lvm-snapshot
device=/dev/${VGNAME}/buildd-${IDENTIFIER}-${ARCH}
lvm-snapshot-options=--size ${LVSIZE}
source-users=buildd
source-root-users=buildd
script-config=script-defaults.buildd
EOT
        SCHROOT="schroot -c ${IDENTIFIER}-${ARCH}-sbuild-source -u root -d /root --"
    fi
    sudo mv "${TEMPFILE}" "/etc/schroot/chroot.d/buildd-${IDENTIFIER}-${ARCH}"
    sudo chown root: "/etc/schroot/chroot.d/buildd-${IDENTIFIER}-${ARCH}"
    sudo chmod 0644 "/etc/schroot/chroot.d/buildd-${IDENTIFIER}-${ARCH}"
}

setup_sources() {
    echo "I: Setting up sources..."
    TEMPFILE="$(mktemp)"
    cat > "${TEMPFILE}" <<EOT
# local mirror
deb ${MIRROR} ${BASE} main contrib
deb-src ${MIRROR} ${BASE} main contrib
EOT

    if [ "$VARIANT" = "edu" ]; then
        echo "I: Adding edu entries to sources.list..."
        cat >> "${TEMPFILE}" <<EOT
deb http://ftp.skolelinux.no/skolelinux/ ${BASE}-test local
deb-src http://ftp.skolelinux.no/skolelinux/ ${BASE}-test local
EOT
    fi

    if [ "$VARIANT" = "backports" ]; then     
        echo "I: Adding backports entries to sources.list..."
        cat >> "${TEMPFILE}" <<EOT
deb http://www.backports.org/buildd/ ${BASE}-backports main contrib non-free
deb-src http://www.backports.org/buildd/ ${BASE}-backports main contrib non-free
EOT
    fi

    if [ "$VARIANT" = "volatile" ]; then     
        echo "I: Adding volatile entries to sources.list..."
        cat >> "${TEMPFILE}" <<EOT
deb     http://volatile.debian.net/debian-volatile      ${BASE}-proposed-updates/volatile main contrib non-free
deb-src http://volatile.debian.net/debian-volatile      ${BASE}-proposed-updates/volatile main contrib non-free
EOT
    fi

	if [ -z "$VARIANT" ] && [ "$BASE" != "sid" ]; then
        echo "I: Adding proposed-updates entries to sources.list..."
        cat >> "${TEMPFILE}" <<EOT
deb http://incoming.debian.org/debian ${BASE}-proposed-updates main contrib
deb-src http://incoming.debian.org/debian ${BASE}-proposed-updates main contrib
EOT
	fi

    if [ "$BASE" = "sid" ]; then     
        echo "I: Adding unstable incoming entries to sources.list..."
        cat >> "${TEMPFILE}" <<EOT
deb     http://incoming.debian.org/debian sid main contrib
deb-src http://incoming.debian.org/debian sid main contrib
deb     http://incoming.debian.org/buildd-unstable /
deb-src http://incoming.debian.org/buildd-unstable /
EOT
    fi

    if [ "$VARIANT" = "experimental" ]; then     
        echo "I: Adding experimental entries to sources.list..."
        cat >> "${TEMPFILE}" <<EOT
deb ${MIRROR} experimental main contrib
deb-src ${MIRROR} experimental main contrib
deb     http://incoming.debian.org/buildd-experimental /
deb-src http://incoming.debian.org/buildd-experimental /
EOT
    fi

    if [ "$VARIANT" = "security" ]; then
        echo "I: Adding security entries to sources.list..."
        cat >> "${TEMPFILE}" <<EOT
deb http://security-master.debian.org/debian-security ${BASE}/updates main contrib
deb-src http://security-master.debian.org/debian-security ${BASE}/updates main contrib
deb http://security-master.debian.org/buildd ${BASE}/
deb-src http://security-master.debian.org/buildd ${BASE}/
EOT
    fi

    ensure_target_mounted
    sudo mv "${TEMPFILE}" "${TARGET}/etc/apt/sources.list"
    sudo chown root: "${TARGET}/etc/apt/sources.list"
    sudo chmod 0644 "${TARGET}/etc/apt/sources.list"
    
    echo "I: Telling apt to not pull in recommends..."
    TEMPFILE="$(mktemp)"
    cat > "${TEMPFILE}" <<EOT
APT::Install-Recommends "False";
EOT
    sudo mv "${TEMPFILE}" "${TARGET}/etc/apt/apt.conf.d/no-install-recommends"
    sudo chown root: "${TARGET}/etc/apt/apt.conf.d/no-install-recommends"
    sudo chmod 0644 "${TARGET}/etc/apt/apt.conf.d/no-install-recommends"
    ensure_target_unmounted

    update_apt_cache
}

update_apt_cache() {
    echo "I: Updating apt cache..."
    $SCHROOT apt-get update
}

do_dist_upgrade() {
    echo "I: Running dist-upgrade..."
    $SCHROOT apt-get dist-upgrade -y
}

do_debfoster() {
    echo "I: Running debfoster to clean up..."
    $SCHROOT debfoster -f
}

adjust_debconf() {
    echo "I: Adjusting debconf settings..."
    echo "debconf debconf/priority select critical" | $SCHROOT debconf-set-selections
    echo "debconf debconf/interface select noninteractive" | $SCHROOT debconf-set-selections
# TODO: not needed(?), will ask questions again
#    $SCHROOT dpkg-reconfigure debconf
}

setup_sbuild() {
    echo "I: Setting up sbuild..."
    ensure_target_mounted
    sudo mkdir -p "$TARGET/build"
    sudo chown root:sbuild "$TARGET/build"
    sudo chmod 02770 "$TARGET/build"
    sudo mkdir -p "$TARGET/var/lib/sbuild/srcdep-lock"
    sudo chown -R root:sbuild "$TARGET/var/lib/sbuild"
    sudo chmod -R 02775 "$TARGET/var/lib/sbuild"
    ensure_target_unmounted
}

old_sbuild_compat() {
    # TODO: remove once unified
    echo "I: Create apt.conf for old sbuild..."
    ensure_target_mounted
    sudo mkdir "$TARGET/var/debbuild"
    TEMPFILE="$(mktemp)"
    cat > "${TEMPFILE}" <<EOT
Dir "${TARGET}/";
APT::Get::AllowUnauthenticated "true";
APT::Install-Recommends 0;
Acquire::PDiffs "false";
EOT
    sudo mv "${TEMPFILE}" "${TARGET}/var/debbuild/apt.conf"
    sudo chown root: "${TARGET}/var/debbuild/apt.conf"
    sudo chmod 0644 "${TARGET}/var/debbuild/apt.conf"
    ensure_target_unmounted
}

add_arch_specific_debfoster_item() {
    file=$1
    arch=$2
    pkg=$3

    if [ "$ARCH" = "$arch" ]
    then
        echo "W: Adding architecture-specific package '$pkg' to debfoster, please review."
        echo $pkg >> "$file"
    fi
}

setup_debfoster() {
    echo "I: Setting up debfoster's keepers file..."
    TEMPFILE="$(mktemp)"
    cat > "$TEMPFILE" <<EOT
build-essential
debfoster
fakeroot
sudo
EOT

# Semi consensus: packages should depend on gcc-multilib if they
# need those packages.  libc6-xen is quite required on Xen, though,
# but we do not support usage of Xen for a buildd and the admin could
# easily add it to the keepers file.
#    add_arch_specific_debfoster_item "$TEMPFILE" alpha libc6.1-alphaev67
#    add_arch_specific_debfoster_item "$TEMPFILE" i386 libc6-amd64
#    add_arch_specific_debfoster_item "$TEMPFILE" mipsel libc6-mips64
#    add_arch_specific_debfoster_item "$TEMPFILE" mipsel libc6-mipsn32
#    add_arch_specific_debfoster_item "$TEMPFILE" mips libc6-mips64
#    add_arch_specific_debfoster_item "$TEMPFILE" mips libc6-mipsn32
#    add_arch_specific_debfoster_item "$TEMPFILE" powerpc libc6-ppc64
#    add_arch_specific_debfoster_item "$TEMPFILE" s390 libc6-s390x
#    add_arch_specific_debfoster_item "$TEMPFILE" sparc libc6-sparc64
#    add_arch_specific_debfoster_item "$TEMPFILE" sparc libc6-sparcv9b

    ensure_target_mounted
    sudo mv "${TEMPFILE}" "${TARGET}/var/lib/debfoster/keepers"
    sudo chown root: "${TARGET}/var/lib/debfoster/keepers"
    sudo chmod 0644 "${TARGET}/var/lib/debfoster/keepers"
    ensure_target_unmounted
}

setup_security() {
    echo "I: Setting up security parts..."

    echo "I: Allowing unauthenticated repositories..."
    TEMPFILE="$(mktemp)"
    cat > "${TEMPFILE}" <<EOT
APT::Get::AllowUnauthenticated 1;
EOT
    ensure_target_mounted
    sudo mv "${TEMPFILE}" "${TARGET}/etc/apt/apt.conf.d/allow-unauthenticated"
    sudo chown root: "${TARGET}/etc/apt/apt.conf.d/allow-unauthenticated"
    sudo chmod 0644 "${TARGET}/etc/apt/apt.conf.d/allow-unauthenticated"

    ensure_target_unmounted
    update_apt_cache
}

setup_logical_volume() {
    LVPATH="/dev/${VGNAME}/buildd-${IDENTIFIER}-${ARCH}"
    echo "I: Setting up logical volume ${LVPATH}..."
    sudo lvcreate --name "buildd-${IDENTIFIER}-${ARCH}" --size "${LVSIZE}" "${VGNAME}"
    echo "I: Setting up file system on ${LVPATH}..."
    sudo mkfs.ext3 "${LVPATH}"
    TMPMOUNTDIR=$(mktemp -d)
}

ensure_target_mounted() {
    if ! [ -z "$TMPMOUNTDIR" ]; then
        echo "I: Mounting file system ${LVPATH} on ${TMPDIR}..."
        sudo mount "${LVPATH}" ${TMPMOUNTDIR}
    fi
}

ensure_target_unmounted() {
    if ! [ -z "$TMPMOUNTDIR" ]; then
        echo "I: Umounting file system ${LVPATH} on ${TMPDIR}..."
        sudo umount ${TMPMOUNTDIR}
    fi
}

cd ~buildd/chroots
check_prerequisites

if ! [ -z "$VGNAME" ]; then
    setup_logical_volume
    TARGET=$TMPMOUNTDIR
fi
do_debootstrap
# As chroots will be controlled by schroot anyway, the symlink should not be
# needed anymore.
#setup_symlink
setup_schroot
setup_sources
adjust_debconf
setup_sbuild
old_sbuild_compat
setup_debfoster

[ "$VARIANT" = "security" ] && setup_security

do_dist_upgrade

echo
echo "I: The last step is coming up, you can also abort on the apt prompt"
echo "I: caused by debfoster!"
echo
do_debfoster
