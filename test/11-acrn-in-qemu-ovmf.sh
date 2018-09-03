
# Note that Q35 is the only platform for which qemu emulates VT-D feature.
# Since ACRN demonds VT-D feature, if you select other platform, please
# make sure that platform support VTD. Beside, to support VT-D 48-bit, the
# following commit in qemu is needed; in upstream qemu git, qemu:v2.12.0 or
# above include the patch;
#
#     commit 37f51384ae05bd50f83308339dbffa3e78404874
#     Author: Prasad Singamsetty <prasad.singamsetty@oracle.com>
#     Date:   Tue Nov 14 18:13:50 2017 -0500
#
#        intel-iommu: Extend address width to 48 bits
#
# Ubuntu bionic is shipped with qemu-v2.11.1, so it doesn't include the patch.
# You can compile qemu for yourself or download a binary from Canonical, or
# upgrade to Ubuntu 18.10 (Cosmic)
#
# Since KVM depends on host to emuate some CPU features, we pass "-cpu host"
# to qemu, that means your host CPUs should support VT-D features, also, cpuid
# level should no less than 0x16. Override it with the cpuid of your host system.
#
#       "cat /proc/cpuinfo | grep level"
#
# then, set -cpu host,your_level

# Make sure that CONFIG_RELOC for ACRN hypervisor is enabled during compiling.
# Otherwise, acrn.efi will try to allocate memory for hypervisor at fixed addr,
# which might be unavailable, and in turn, hyperviosr will fail to start.
#


DISK_IMAGE=out/acrn_vdisk_clear24620.img

qemu-system-x86_64 -machine q35,accel=kvm,kernel-irqchip=split -m 4G \
	-device intel-iommu,intremap=on,x-aw-bits=48,caching-mode=on,device-iotlb=on \
	-device e1000,netdev=net0 \
	-netdev user,id=net0 \
	-bios ./out/OVMF-pure-efi.fd \
	-drive file=${DISK_IMAGE},if=virtio \
	-smp cpus=4,cores=4,threads=1 -serial stdio \
	-append "uart=port@0x3f8" -kernel out/acrn.efi \
	-cpu host,level=22 -smp cpus=4,cores=4,threads=1 

#	-cpu Skylake-Client-IBRS \
#	-cpu host


