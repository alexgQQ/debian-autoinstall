#!/usr/bin/env sh

set -eu

admin="@USERNAME@"
hostname="@HOSTNAME@"
domain="@DOMAIN@"
sudonopw="@SUDONOPW@"
vboxguest="@VBOXGUEST@"

echo "${hostname}" >"/etc/hostname"
cat <<EOF >"/etc/hosts"
127.0.0.1	localhost
127.0.1.1	${hostname}.${domain}	${hostname}

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# custom configs
cp -a "/var/configs/sshd_config" "/etc/ssh/sshd_config"

# allow sudo without password
if test "${sudonopw}" = "true"; then
    echo "${admin} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${admin}"
fi

# authorize ssh keys for admin user
mkdir -p  "/home/${admin}/.ssh"
chmod 700 "/home/${admin}/.ssh"
cp -a "/var/configs/authorized_keys" "/home/${admin}/.ssh/authorized_keys"
chmod 600 "/home/${admin}/.ssh/authorized_keys"

# reset user homedir owner
chown -R "${admin}:${admin}" "/home/${admin}"

# Configure grub to boot directly to default
cat /var/configs/grub > /etc/default/grub
rm /etc/default/grub.d/*
update-grub

if test "${vboxguest}" = "true"; then
    # permissions for shared file mount
    groupadd vboxsf
    adduser "${admin}" vboxsf

    # install guest additions
    # https://developer.hashicorp.com/vagrant/docs/providers/virtualbox/boxes#virtualbox-guest-additions
    # TODO: hwdetect seems to handle this automatically
    VBOX_VERSION=7.1.14
    apt-get install -yqq linux-headers-$(uname -r) build-essential dkms gcc make perl wget
    wget -q -O "/tmp/VBoxGuestAdditions_${VBOX_VERSION}.iso" \
        "https://download.virtualbox.org/virtualbox/${VBOX_VERSION}/VBoxGuestAdditions_${VBOX_VERSION}.iso"
    mkdir "/media/VBoxGuestAdditions"
    modprobe loop
    mount -o loop,ro "/tmp/VBoxGuestAdditions_${VBOX_VERSION}.iso" "/media/VBoxGuestAdditions"
    sh /media/VBoxGuestAdditions/VBoxLinuxAdditions.run
    umount "/media/VBoxGuestAdditions"
    rmdir "/media/VBoxGuestAdditions"
fi
