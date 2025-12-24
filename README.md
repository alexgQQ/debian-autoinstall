# debian-autoinstall

Generate customized Debian ISO images for automatic deployments.

## Usage

Run `build.sh` to generate a hands-free ISO image.

```
./build.sh [-u username] [-p password] [-n hostname] [-d domain] [-a package] [-i iso_url] [-s sign_key] [-o path] [-x] [-z] [-v] [-h]
```

### Dependencies

Start a [devbox](https://www.jetify.com/devbox) [shell](https://www.jetify.com/devbox/docs/quickstart/#launch-your-development-environment) with:

```sh
devbox shell --pure
```

Or install all dependencies on a Debian system:

```sh
sudo apt update
sudo apt install curl git gnupg pwgen whois xorriso
```

### Clone repo

Clone this repository and `cd` into it.

```sh
git clone https://github.com/nothub/debian-autoinstall.git
cd debian-autoinstall
```

### SSH keys

To include SSH keys for remote access, add them to the `configs/authorized_keys` file.

```sh
curl -fsSLo configs/authorized_keys https://github.com/nothub.keys
echo "ssh-ed25519 AAAA... foo" >> configs/authorized_keys
echo "ssh-ed25519 AAAA... bar" >> configs/authorized_keys
```

### Build ISO

```sh
# set user and password
./build.sh -u 'hub' -p 'changeme'
# set hostname and domain
./build.sh -n 'calculon' -d 'example.org'
# include additional apt packages
./build.sh -a 'strace' -a 'unattended-upgrades'
```

### Flags

```
-u <username>    Admin username
-p <password>    Admin password
-n <hostname>    Machine hostname
-d <domain>      Machine domain
-a <package>     Additional apt package
-i <iso_url>     ISO download URL
-s <sign_key>    ISO pgp sign key
-o <out_file>    ISO output file
-x               Power off after install
-z               Sudo without password
-v               Enable verbose mode
-h               Display this help message
```

### Password

If the `-p` flag is not set, a random admin password will be generated, printed to stdout and written to `<out_file>.auth`.

### Hostname

If the `-n` flag is not set, a hostname will be generated at installation.
The hostname will be based on the installed machines mac addresses.

### Restart

If the `-x` flag is not set, the machine will restart after the installation is finished.

## Preseed Config

For an extended example, check:
https://www.debian.org/releases/trixie/example-preseed.txt

## Debug in VM

While running the installer, press `ctrl`+`alt`+`f4` to show the installers log output.
To switch back to the installer's graphical interface, press `ctrl`+`alt`+`f1`.
Switch to any other TTY for an interactive shell.


### Troubleshooting

#### ssh fails to connect

The image is built with pubkey only ssh auth, any pubkey in `configs\authorized_keys` will be authorized for the user configured so make sure the right key is there

Vagrant will by default port forward from the host localhost on port 2222 to guest on port 22, make sure the ports are aligned as expected.

Test the ssh config using the vagrant public key and vagrant user. The iso build script will set the `vagrant` user by default.
```powershell
Invoke-WebRequest "https://github.com/hashicorp/vagrant/raw/refs/heads/main/keys/vagrant.pub" -OutFile configs\authorized_keys
```
Run the buld and package step.
```powershell
Invoke-WebRequest "https://github.com/hashicorp/vagrant/raw/refs/heads/main/keys/vagrant.key.ed25519" -OutFile vagrant.key.ed25519
ssh -o StrictHostKeyChecking=no -i vagrant.key.ed25519 -p 2222 vagrant@127.0.0.1
```

The network becomes undiscoverable when using the `net.ifnames=0` boot param so make sure that is not being used.

Vagrant can timeout it's initial ssh setup/connection when provisioning for the first time if the boot time is very slow. Make sure the machine you're connecting to is provisioned and running to verify ssh. Check the next section for troubleshooting slow boot times.

#### slow startup time

Make sure acceleration options are enabled for the virtualization provider. For virtualbox make sure Physical Address Extension (PAE) is enabled.

For virtualbox make sure the SATA controller is using a lower number of ports (1 is fine but more can be enabled) and is using the host io cache. By default it will use 30 ports and won't use host io cache and this will slow down startup times and impact disk throughput. 

Check the kernel boot params. Some of these can noticeably impact startup times. Some that I have encountered:
* `page_poison` will take a several extra seconds on startup
* `elevator=noop` and `scsi_mod.use_blk_mq=Y` will enable faster r/w at startup in a vm environment

Check the startup time to see what is slow in loading.
```bash
sudo systemd-analyse time
sudo systemd-analyse blame
```
Additionally check the startup logs for any errors, long running blocks or time blocking processes. 
```
sudo dmesg
```

#### the os installer fails

This is likeley failing on the `late_command` segment of the preseed config. This runs the custom post-provisioning script `installer/late.sh`.
On the installing machine you can just acknowledge and skip the error. Boot it back up and check the installer logs.
```bash
sudo less /var/log/installer/syslog
```
In the interface type `/late.sh` and enter to search for log output starting at the script execution. Check for errors and try to fix accordingly.

The script will execute `in-target` which means the linux installation will be mounted much like `chroot` and ran within it's installation. This generally makes the script behave how it would as a normal script however the `in-target` mount doesn't carry all the features. Specifically various kernel modules are not loaded at this time so anything using an unload kernel module will need to be explicitly loaded with `modprobe`.

This also means that any custom files present on the boot install used on the `in-target` installation will need to be available to it. Make sure configs or scripts are being copied to the `/target` dir before the `late.sh` script runs.

#### final vagrant vm doesn't match exported config

If you are seeing drift between the packaging vm and the final vagrant box then make sure the vagrant installation has it's cache cleared and that you aren't caching the box. This can happen especially if the box name is the same between provisioning. First try removing and readding the box by its name.
```bash
vagrant box list
vagrant box remove <yourboxname> --provider virtualbox
```
Then try removing the box from the global status.
```bash
vagrant global-status --prune
```
If those don;t work you can also just clear the file cache directly.
```bash
sudo rm -rf ~/.vagrant.d/boxes/<yourboxname>
```
