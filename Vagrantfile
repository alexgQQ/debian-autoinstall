$script = <<-'SCRIPT'
apt-get update -yqq
apt-get install -yqq curl git gnupg pwgen whois xorriso
# writes are slow on the default shared mount point so build the image in the home dir and copy it back
cp -r /vagrant /home/vagrant/debian-autoinstall
./debian-autoinstall/build.sh -u vagrant -p vagrant -xza 
cp debian-autoinstall/vagrantbox.iso /vagrant/dist
SCRIPT

Vagrant.configure("2") do |config|
    config.vm.box = "debian/bookworm64"
    config.vm.provider "virtualbox" do |v|
        v.name = "image-builder"
    end
    config.vm.provision "shell",
        inline: $script
    config.vm.provision "shell",
        inline: "shutdown now"
end
