#!/bin/bash

RAM=2048
VCPUS=2
OS_VARIANT="ubuntu18.04"
CLOUD_IMAGE_FILENAME="bionic-server-cloudimg-amd64.img"
CLOUD_IMAGE_DIR="/mnt/vm-hdd/cloud-images"
VM_DISK_DIR="/mnt/vm-ssd"
TMP_DIR="/mnt/vm-hdd/tmp"

# Take one argument from the command line: <vm-name>
if ! [ $# -eq 1 ]; then
	echo "Usage: $0 <vm-name>"
	exit 1
fi

# Check to see whether or not the cloud image file exists
if ! [ -e $CLOUD_IMAGE_DIR/$CLOUD_IMAGE_FILENAME ]; then
	echo "ERROR: Cloud image: $CLOUD_IMAGE_DIR/$CLOUD_IMAGE_FILENAME does not exist"
	exit 1
fi

# Check to see whether or not the VM disk dir exists
if ! [ -e $VM_DISK_DIR ]; then
	echo "ERROR: VM disk directory: $VM_DISK_DIR does not exist"
	exit 1
fi

# Check to see whether or not a VM already exists with the name, <vm-name>
virsh dominfo $1 &> /dev/null
if [ $? -eq 0 ]; then
	echo "ERROR: $1 already exists. Quitting..."
	exit 1
fi

# Generate cloud-init CD image
echo "Generating cloud-init CD image..."
mkdir $TMP_DIR
cat << EOF > $TMP_DIR/meta-data
instance-id: $1; local-hostname: $1
EOF
cat << EOF > $TMP_DIR/user-data
#cloud-config
preserve_hostname: False
hostname: $1
fqdn: $1
users:
  - name: mboglesby
    groups: sudo
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh-authorized-keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC/psswHb+rKBc/OD1sHZlpKjPyt6Dlwn8braSMcPRi+L+9brxc4lnu0e5F3/7dRoMBKIC7TzLOJJ4MZzHJ+6x8pcDj1kN8OFfb+bgnRGF98d0kwf1pKhbJHidZYxqyL5/IP7BuBFFR/dfT5Qu+IzzrcoBCr44hlWJDzeF+zsM9oQyFaIiAoOpDcrgbT38MeifrUgRz/8Hmv8YWZovP83gn470C5rnxLDOnTbaA8280z0LJECskGCQp8hC8Pn9HV61b+qFg8wnbSOnG+7qRFhV6zGyC8I9DddLrGPDenrk8qDsktRH1Eqszs8Xf3Skrkwm6eOHvY95+fAPpIGunT6jT mboglesby@mbo-ubuntu-mate
packages: ['qemu-guest-agent']
EOF
genisoimage -output $CLOUD_IMAGE_DIR/$1-cloudinit.iso -volid cidata -joliet -r $TMP_DIR/user-data $TMP_DIR/meta-data
rm -rf $TMP_DIR
echo ""

# Copying cloud OS image
echo "Copying cloud OS image..."
cp $CLOUD_IMAGE_DIR/$CLOUD_IMAGE_FILENAME $VM_DISK_DIR/$1.img
echo ""

# Instantiate VM
echo "Instantiating VM..."
virt-install \
	--import \
	--name $1 \
	--ram=$RAM \
	--vcpus=$VCPUS \
	--disk $VM_DISK_DIR/$1.img,format=raw,bus=virtio \
	--disk $CLOUD_IMAGE_DIR/$1-cloudinit.iso,device=cdrom \
	--network type=bridge,source=ovsbr,model=virtio,virtualport_type=openvswitch \
	--os-type=linux --os-variant=$OS_VARIANT \
	--graphics spice \
	--noautoconsole
echo ""

# Eject cloud-init CD image after VM has booted
echo "Sleeping for 60 seconds..."
sleep 60
echo ""
echo "Ejecting cloud-init CD image from VM..."
virsh change-media $1 $CLOUD_IMAGE_DIR/$1-cloudinit.iso --eject
echo ""

# Remove cloud-init CD image
echo "Deleting cloud-init CD image..."
rm -f $CLOUD_IMAGE_DIR/$1-cloudinit.iso
echo ""


# Display VM network interfaces (pass through python json formatter if python is installed)
echo "VM Network Interfaces (look for IP address):"
which python > /dev/null
if [ $? -eq 0 ]; then
	virsh qemu-agent-command $1 '{"execute":"guest-network-get-interfaces"}' | python -mjson.tool
else
	virsh qemu-agent-command $1 '{"execute":"guest-network-get-interfaces"}'
fi
echo ""

echo "Done!"
