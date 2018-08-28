
# Note that Q35 is the only platform for which qemu emulates VT-D feature.
# Since ACRN demonds VT-D feature, if you select other platform, please
# make sure that platform support VTD.
#

DISK_IMAGE=out/acrn_vdisk_clear24480.img

qemu-system-x86_64 -machine q35,accel=kvm,kernel-irqchip=split -m 4G \
	-device intel-iommu,intremap=on \
	-device e1000,netdev=net0 \
	-netdev user,id=net0 \
	-bios ./out/OVMF-pure-efi.fd \
	-drive file=${DISK_IMAGE},if=virtio \
	-cpu Broadwell -smp cpus=4,cores=4,threads=1 -serial stdio 

