
qemu-system-x86_64 -bios ${ACRN_HOST_DIR}/out/${ACRN_UEFI_FW} -hda ${ACRN_HOST_DIR}/out/${ACRN_DISK_IMAGE} -m 4G -cpu Broadwell -smp cpus=4,cores=4,threads=1 -serial stdio -machine accel=kvm:tcg


qemu-system-x86_64 -machine q35,accel=kvm,kernel-irqchip=split -m 4G \
	-device intel-iommu,intremap=on \
	-device e1000,netdev=net0 \
	-netdev user,id=net0 \
	-bios ./OVMF-pure-efi.fd \
	-drive file=acrn_vdisk_clear24480.img,if=virtio 

