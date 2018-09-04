
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
# Make sure that CONFIG_RELOC for ACRN hypervisor is enabled during compiling.
# Otherwise, acrn.efi will try to allocate memory for hypervisor at fixed addr,
# which might be unavailable, and in turn, hyperviosr will fail to start.
#

DISK_IMAGE=out/acrn_vdisk_clear24620.img

nested=`cat /sys/module/kvm_intel/parameters/nested`
[ "${nested}X" == "NX"  ] && { echo "Please pass \"nested=y\" for linux kvm-intel.ko module"; exit 1; }

modprobe kvm-intel -r
modprobe kvm-intel nested=y enable_apicv=y

qemu-system-x86_64 -machine q35,accel=kvm,kernel-irqchip=split -m 4G \
	-device intel-iommu,intremap=on,x-aw-bits=48,caching-mode=on,device-iotlb=on \
	-device e1000,netdev=net0 \
	-netdev user,id=net0 \
	-bios ./out/OVMF-pure-efi.fd \
	-drive file=${DISK_IMAGE},if=virtio \
	-serial stdio \
	-append "uart=port@0x3f8" -kernel out/acrn.efi \
	-smp cpus=2,cores=2,threads=1 \
	--enable-kvm \
	-cpu kvm64,+fpu,+vme,+de,+pse,+tsc,+msr,+pae,+mce,+cx8,+apic,+sep,+mtrr,+pge,+mca,+cmov,+pat,+pse36,+clflush,+acpi,+mmx,+fxsr,+sse,+sse2,+ss,+ht,+tm,+pbe,+syscall,+nx,+pdpe1gb,+rdtscp,+lm,+pni,+pclmulqdq,+dtes64,+monitor,+ds_cpl,+vmx,+smx,+est,+tm2,+ssse3,+fma,+cx16,+xtpr,+pdcm,+pcid,+sse4_1,+sse4_2,+x2apic,+movbe,+popcnt,+tsc-adjust,+tsc-deadline,+aes,+xsave,+avx,+f16c,+rdrand,+lahf_lm,+abm,+3dnowprefetch,+ssbd,+xtpr,+fsgsbase,+tsc_adjust,+bmi1,+hle,+avx2,+smep,+bmi2,+erms,+invpcid,+rtm,+mpx,+rdseed,+adx,+smap,+clflushopt,+xsaveopt,+xsavec,+xgetbv1,+xsaves,+arat,level=21,pmu=true




