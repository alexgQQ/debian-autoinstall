# This powershell script is to be used with the vagrant packaging process.
# It builds a virtualbox vm from the created iso for vagrant to clone.
# Any configuration setup here with virtualbox will be the default on the packaged vagrant box.

$vmname = "vagrant-packager"
$isopath = "dist\vagrantbox.iso"
$vmdir = ".vbox"
$disk_size = 1024 * 15  # 10 Gb
$cpu_count = 2
$mem_size = 1024 * 2  # 2 Gb
$box_file = "dist\vagrantbox.box"

function Create-VM {
    param (
        $name,
        $cpu,
        $memory,
        $disk_path,
        $disk_size,
        $iso_path
    )
    VBoxManage createvm --name $name --ostype Debian_64 --register
    VBoxManage modifyvm $name --memory $memory --cpus $cpu --sata on --boot1 dvd --boot2 disk --pae on --graphicscontroller VMSVGA
    VBoxManage createmedium disk --filename $disk_path --size $disk_size --format VDI --variant Fixed
    # TODO: Sometimes this is registered as "SATA Controller" by default and that name needs to be used
    # but usually this command isn't even needed so figure what to do with it
    # VBoxManage storagectl $name --name "SATA" --add sata --controller IntelAhci
    VBoxManage storageattach $name --storagectl "SATA" --port 0 --device 0 --type hdd --medium $disk_path
    VBoxManage storagectl $name --name "SATA" --portcount 1 --hostiocache on
    VBoxManage storagectl $name --name "IDE" --add ide --controller PIIX4
    VBoxManage storageattach $name --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium $iso_path
    VBoxManage modifyvm $name --natpf1 "ssh,tcp,127.0.0.1,2222,,22"
}

function Wait-VMStopped {
    param([string]$VMName)

    Write-Host "Waiting for VM '$VMName' to power off..."
    $vmState = ""
    while ($vmState -ne 'poweroff') {
        $info = & VBoxManage showvminfo --machinereadable $VMName

        $stateLine = $info | Select-String "^VMState="
        if ($stateLine) {
            $vmState = $stateLine.ToString().Split('=')[1].Trim("""")
        } else {
            Write-Error "Could not retrieve state for VM '$VMName'. Exiting loop."
            break
        }

        if ($vmState -ne 'poweroff') {
            Start-Sleep -Seconds 2
        }
    }

    Write-Host "VM '$VMName' is now powered off."
}

# This returns an exit code if the vm doesn't exist
VBoxManage showvminfo $vmname *> $null
if ($LASTEXITCODE -eq 0) {
    Write-Error "VM $vmname already exists."
    # VBoxManage unregistervm $vmname --delete-all
    exit 1
}

if (-not (Test-Path -Path $isopath -PathType Leaf)) {
    Write-Error "Boot image not found: $isopath"
    exit 1
}
elseif (Test-Path -Path $box_file -PathType Leaf) {
    Write-Error "Box file already exists: $box_file"
    exit 1
}

if (-not (Test-Path -Path $vmdir -PathType Container)) {
    New-Item -ItemType Directory -Path $vmdir -Force
}
elseif (Test-Path -Path "$vmdir\$vmname.vdi" -PathType Leaf) {
    Write-Error "The disk file: $vmdir\$vmname.vdi already exists."
    exit 1
}

Create-VM -name $vmname -cpu $cpu_count -memory $mem_size -disk_path "$vmdir\$vmname.vdi" -disk_size $disk_size -iso_path $isopath
VBoxManage startvm $vmname
Wait-VMStopped -VMName $vmname
vagrant package --base $vmname --output $box_file
