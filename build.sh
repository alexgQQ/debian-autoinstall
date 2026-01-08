#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

usage() {
    echo "Usage: $0 [-u username] [-p password] [-n hostname] [-d domain] [-i version] [-o path] [-x] [-z] [-a] [-s] [-v] [-h]"
    echo "Options:"
    echo "  -u <username>    Admin username"
    echo "  -p <password>    Admin password"
    echo "  -n <hostname>    Machine hostname"
    echo "  -d <domain>      Machine domain"
    echo "  -i <version>     Debian version to build"
    echo "  -o <out_file>    ISO output file"
    echo "  -x               Power off after install"
    echo "  -z               Sudo without password"
    echo "  -a               Install Virtualbox Guest Additions"
    echo "  -s               Skip ISO download verification"
    echo "  -v               Enable verbose mode"
    echo "  -h               Display this help message"
}

username="vagrant"
password="vagrant"
hostname="vagrantbox"
domain="local"
debian_version="13.2.0"
out_file="vagrantbox.iso"
poweroff="false"
sudonopw="false"
vboxguest="false"
noverify="false"

while getopts u:p:n:d:i:o:xzasvh opt; do
    case $opt in
    u) username="$OPTARG" ;;
    p) password="$OPTARG" ;;
    n) hostname="$OPTARG" ;;
    d) domain="$OPTARG" ;;
    i) debian_version="$OPTARG" ;;
    o) out_file="$OPTARG" ;;
    x) poweroff="true" ;;
    z) sudonopw="true" ;;
    a) vboxguest="true" ;;
    s) noverify="true" ;;
    v) set -o xtrace ;;
    h) usage ; exit 0 ;;
    *) usage ; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

iso_url="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-${debian_version}-amd64-netinst.iso"

# go to project root
cd "$(realpath "$(dirname "$(readlink -f "$0")")")"

# download
iso_file=$(basename "${iso_url}")
if [[ ! -f ${iso_file} ]]; then
    echo >&2 "Downloading iso image: ${iso_file}"
    curl -sLo "${iso_file}" "${iso_url}"
fi

if test "${noverify}" = "false"; then
    curl -sLO "$(dirname "${iso_url}")/SHA256SUMS"
    curl -sLO "$(dirname "${iso_url}")/SHA256SUMS.sign"

    # Make sure to load keys listed here https://www.debian.org/CD/verify
    gpg --keyserver keyring.debian.org --recv "988021A964E6EA7D"
    gpg --keyserver keyring.debian.org --recv "DA87E80D6294BE9B"
    gpg --keyserver keyring.debian.org --recv "42468F4009EA8AC3"

    gpg --verify SHA256SUMS.sign SHA256SUMS
    if ! sha256sum -c <<<"$(grep "${iso_file}" SHA256SUMS)"; then
        echo >&2 "Error: Checksum not matching for: ${iso_file}"
        exit 1
    fi
fi

workdir="$(mktemp --directory)"

# unpack iso
xorriso \
    -osirrox on \
    -dev "${iso_file}" \
    -extract "/isolinux/isolinux.cfg" "${workdir}/isolinux.cfg" \
    -extract "/isolinux/adtxt.cfg" "${workdir}/adtxt.cfg"

# set default boot entry and parameters
sed -i "s#default vesamenu.c32#default auto#" "${workdir}/isolinux.cfg"
sed -i "s#auto=true#auto=true file=/cdrom/preseed.cfg#" "${workdir}/adtxt.cfg"

# copy files to include
cp -a configs/*   "${workdir}"
cp -a installer/* "${workdir}"

# generate password hash
salt="$(pwgen -ns 16 1)"
passhash="$(mkpasswd -m sha-512 -S "${salt}" "${password}")"

# replace tokens
replace_token() {
    find "${workdir}" -type f -exec sed -i "s#${1}#${2}#" {} \;
}
replace_token "@USERNAME@" "${username}"
replace_token "@PASSHASH@" "${passhash}"
replace_token "@HOSTNAME@" "${hostname}"
replace_token "@DOMAIN@"   "${domain}"

# add poweroff option
if test "${poweroff}" = "true"; then
    replace_token "@POWEROFF@" "true"
else
    replace_token "@POWEROFF@" "false"
fi

# add sudo no-password option
if test "${sudonopw}" = "true"; then
    replace_token "@SUDONOPW@" "true"
else
    replace_token "@SUDONOPW@" "false"
fi

if test "${vboxguest}" = "true"; then
    replace_token "@VBOXGUEST@" "true"
else
    replace_token "@VBOXGUEST@" "false"
fi

# clear existing output iso file
if test -f "${out_file}"; then
    rm -f "${out_file}"
fi

# with no authorized keys, create dummy file
if test ! -f "${workdir}/authorized_keys"; then
    echo -n >"${workdir}/authorized_keys"
fi

# repack iso
rm -f "${iso_file//.iso/-auto.iso}"
xorriso -indev "${iso_file}" \
    -map "${workdir}/adtxt.cfg"       "/isolinux/adtxt.cfg" \
    -map "${workdir}/isolinux.cfg"    "/isolinux/isolinux.cfg" \
    -map "${workdir}/late.sh"         "/late.sh" \
    -map "${workdir}/preseed.cfg"     "/preseed.cfg" \
    -map "${workdir}/authorized_keys" "/configs/authorized_keys" \
    -map "${workdir}/grub"            "/configs/grub" \
    -map "${workdir}/sshd_config"     "/configs/sshd_config" \
    -boot_image isolinux dir=/isolinux \
    -outdev "${out_file}"

rm -rf "${workdir}"

sha256sum "${out_file}" >"${out_file}.sum"
