# debian-autoinstall-vagrant

Generate customized Debian ISO images for automatic deployments and Vagrant base boxes. 

### Dependencies

This repo uses Vagrant and Virtualbox so I would recommend to use those. However if you are on a Debian based machine and are only trying to build an automatic installing ISO then you can skip them and just run the build script.

Clone the repo
```bash
git clone https://github.com/alexgQQ/debian-autoinstall.git
cd debian-autoinstall
```

### Build ISO

On a Debian based machine just install the dependencies and run the build script. 

```bash
sudo apt-get update
sudo apt-get install curl git gnupg pwgen whois xorriso
./build.sh -u 'vagrant' -p 'vagrant' -xza -o dist/debian.iso
```

Otherwise on other machines use vagrant. This will run the above through a debian based vagrant vm. Build args can be changed in the root Vagrantfile.

```powershell
vagrant up
```

By default the ISO file will be in the `dist` dir.

Customize the installation however you would like with the flags below.
```
./build.sh [-u username] [-p password] [-n hostname] [-d domain] [-i version] [-o path] [-x] [-z] [-a] [-s] [-v] [-h]
Options:
  -u <username>    Admin username
  -p <password>    Admin password
  -n <hostname>    Machine hostname
  -d <domain>      Machine domain
  -i <version>     Debian version to build
  -o <out_file>    ISO output file
  -x               Power off after install
  -z               Sudo without password
  -a               Install Virtualbox Guest Additions
  -s               Skip ISO download verification
  -v               Enable verbose mode
  -h               Display this help message
```

#### Debian Config

This uses the preseed process for configuring an installation. Change it however you'd like. For an extended example, check:
https://www.debian.org/releases/trixie/example-preseed.txt

To include SSH keys for remote access, add them to the `configs/authorized_keys` file. By default this has the vagrant default user public keys.
```bash
curl -fsSLo configs/authorized_keys https://github.com/hashicorp/vagrant/raw/refs/heads/main/keys/vagrant.pub
```

The grub configuration in `configs/grub` can be adjusted for various boot options.

Any specific shell commands or scripts can be added to `installer/late.sh` to run after provisioning.

### Package Vagrant Box

With the ISO from the previous step provision a Virtualbox VM to boot from it. Vagrant uses this VM to export a baseline config so it will serve as that. With the default commands just run:
```powershell
./package.ps1
```

Then in `dist` dir there will be an exported vagrant box `.box` file with the OS and the VM config.

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
```bash
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

#### virtualbox guest additions issues

Check the modules and versions are identified. Startup the vm with guest additions and access it to run:
```bash
lsmod | grep vboxguest
```
There hsould be a `vboxguest` kernel module loaded. Then on the host machine check that Virtualbox can identify the version.
```powershell
VBoxManage guestproperty get "vagrant-packager" /VirtualBox/GuestAdd/Version
```
