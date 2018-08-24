#!/bin/bash
#
#
[ -z ${ACRN_ENV_VARS} ] && ACRN_ENV_VARS=acrn-env.txt
[ -z ${ACRN_MNT_VOL} ] && ACRN_MNT_VOL=/acrn-vol
cd ${ACRN_MNT_VOL} || { echo "Failed to cd "${ACRN_MNT_VOL}; exit -1; }
[ -f ${ACRN_ENV_VARS} ] && \
    { for line in `cat ${ACRN_ENV_VARS}`; do export $line; done; }


[ -z ${ACRN_HV_DIR} ] && ACRN_HV_DIR=acrn-hypervisor

[ -z ${ACRN_TRACE_SHELL_ENABLE} ] || set -x

#
# $1 -- the dir where SOS vmlinuz and modules are (set INSTALL_PATH  and
#       INSTALL_MOD_PATH to the dir when building Linux kernel)
# $2 -- the dir where ACRN HV build output are
# $3 -- the path to the script which is used to start UOS
#
if [ $# -eq 3 ]; then
        # comes from 0-run-all.sh or commandline
        PATH_SOS_OUT=$1
        PATH_HV_OUT=$2
	LAUNCH_UOS_SCRIPT=$3 
else
	# Assume that users used default output path for HV and SOS
        PATH_SOS_OUT=${ACRN_SOS_DIR}/out
        PATH_HV_OUT=${ACRN_HV_DIR}/build
	LAUNCH_UOS_SCRIPT=${ACRN_HV_DIR}/devicemodel/samples/*
	echo "Three args needed(assume): "
	echo -e "\tSOS_BUILD_OUT=\${ACRN_SOS_DIR}/out ==== " ${PATH_SOS_OUT}
	echo -e "\tHV_BUILD_OUT=\${ACRN_HV_DIR}/build ==== " ${PATH_HV_OUT}
	echo -e "\tLAUNCH_UOS_SCRIPT=\${ACRN_HV_DIR}/devicemodel/samples/* === " \
		${LAUNCH_UOS_SCRIPT}
	echo "Make sure the dirs are rigth"
fi;


# A list of the prefix of rpm package name. ClearLinux KVM image doesn't
# install those packages, so we install them by ourselves
extra_rpm_package=("e2fsprogs-extras-" "dosfstools-bin-")



# the name fo disk image which will be created at last. used to boot
# in UEFI OVMF
[ -z ${ACRN_DISK_IMAGE} ] && ACRN_DISK_IMAGE=acrn_vdisk_all.img
[ -z ${ACRN_DISK_SIZE} ] && ACRN_DISK_SIZE=20480
[ -z ${ACRN_DISK_P1} ] && ACRN_DISK_P1=200
[ -z ${ACRN_DISK_P2} ] && ACRN_DISK_P2=200
[ -z ${ACRN_DISK_P3} ] && ACRN_DISK_P3=4096

# Use Clearlinux KVM image as rootfs
OS_RELEASE=`cat /usr/lib/os-release | grep VERSION_ID`
VERSION_ID=${OS_RELEASE:11}
URL_BASE=https://download.clearlinux.org/releases/${VERSION_ID}/clear/
IMAGE_RAW=clear-${VERSION_ID}-kvm.img
IMAGE_XZ=clear-${VERSION_ID}-kvm.img.xz
FILE_SHA1=${IMAGE_XZ}-SHA512SUMS
FILE_SIG=${IMAGE_XZ}-SHA512SUMS.sig

export ACRN_DISK_IMAGE="${ACRN_DISK_IMAGE}_clear${VERSION_ID}.img"

# Fdisk a disk image to 4 partition(ESP, swap, rootfs, user)
#       $1 --- the name of disk image
fdisk_img() {
        GPT_PAR="g\nn\n1\n\n+"${ACRN_DISK_P1}"M\nt\n1\n" # xMB ESP parition
        SWAP_PAR="n\n2\n\n+"${ACRN_DISK_P2}"M\nt\n2\n19\n" # Linux SWAP
	SOS_PAR="n\n3\n\n+"${ACRN_DISK_P3}"M\nt\n3\n20\n" # SOS rootfs
        USR_PAR="n\n4\n\n\nt\n4\n20\n"   # user

        (echo -e ${GPT_PAR}${SWAP_PAR}${SOS_PAR}${USR_PAR}"w\n") | \
                fdisk $1 1>/dev/null

        return 0;
}

# Download KVM image from clearlinux.org, which will be used to create
# rootfs of service OS
download_image() {

	[ -f ${IMAGE_RAW} ] && { echo "Image file exists. Use the old"; return 0; }
        if [ -f ${IMAGE_XZ} ]; then
                echo "Compressed image file exists. Use the old"
	else
		echo "Downloading "${IMAGE_XZ}" from "${URL_BASE}
		wget -c $1/${IMAGE_XZ}
	       	echo "Downloading "${IMAGE_SHA1}" from "${URL_BASE}
		wget -c $1/${FILE_SHA1}
		echo "Downloading "${IMAGE_SIG}" from "${URL_BASE}
	       	wget -c $1/${FILE_SIG}

		sha512sum -c ${FILE_SHA1} || \
		    { echo "Checksum failed: sha512sum -c "${IMAGE_XZ}; exit $?; }
	fi;

        xz -kd ${IMAGE_XZ}
}


# If the disk image exsits, don't overwrite it. Or comment this to continue
[ -f ${ACRN_DISK_IMAGE} ] && \
        { echo "Disk image "${ACRN_DISK_IMAGE}" exits already."; \
	 echo "ACRN_DISK_IMAGE=${ACRN_DISK_IMAGE}" >> ${ACRN_MNT_VOL}/${ACRN_ENV_VARS}; \
	 exit 0; }

if [ -z ${ACRN_DISK_SPARSE_IMAGE} ] || [ ${ACRN_DISK_SPARSE_IMAGE} -ne 1 ]; then
	sparse=0
else
	sparse=1
	sparse_str="sparse"
fi;

echo "Using dd/fdisk to create an empty disk ${sparse_str} image of ${ACRN_DISK_SIZE}"

if [ ${sparse} -eq 1 ]; then
	dd if=/dev/zero of=${ACRN_DISK_IMAGE} bs=1M count=0  seek=${ACRN_DISK_SIZE}
else
	dd if=/dev/zero of=${ACRN_DISK_IMAGE} bs=1M count=${ACRN_DISK_SIZE}
fi;

[ $? -ne 0 ] && { echo "Failed to dd/create ${sparse_str} disk image"; exit 1; }

# Get SOS kernel bzImage and modules path
BZ_FPATH=`ls ${PATH_SOS_OUT}/* | grep -v "*.old" | grep vmlinuz`
[ ! -f ${BZ_FPATH} ] && { echo "Failed to get Linux bzImage file: vmlinuz-xxx-xxx"; exit 1; }

BZ_NAME=`basename ${BZ_FPATH}`
BZ_DIR=`dirname ${BZ_FPATH}`

let idx=`expr index ${BZ_NAME} "-"` 
MODS_NAME=${BZ_NAME:${idx}}
let len=`echo $MODS_NAME | wc -L`

MODS_FPATH=${BZ_DIR}/"lib/modules/"

if false; then
let found=0
for dir in `ls ${MODS_FPATH}`; do
	echo "dir=${dir}"
	echo "mods_name=${MODS_NAME}"
	echo "sub_str: ${dir:0:$len}"

        if [ "${dir}" == "${MODS_NAME}"* ]; then
		echo "equal"
	       	found=1
	fi;
	echo ${found}
done;
[ ${found} -eq 0 ] && { echo "Failed to get linux modules: "${MODS_FPATH}; exit 1; }
fi;

# download Clearlinux KVM image if not exits
download_image ${URL_BASE}

CLR_DEV_LOOP=`losetup -f -P --show ./${IMAGE_RAW}`
mkdir -p ./cl_p1 ./cl_p3
mount ${CLR_DEV_LOOP}p1 ./cl_p1
mount ${CLR_DEV_LOOP}p3 ./cl_p3

# Caculate the size of rootfs and make sure partition room is engouth to hold it
read -a SIZE <<< `du -s ./cl_p3`
COUNT=`expr ${SIZE} / 1000 + 1`
echo "ClearLinux rootfs size: "${COUNT}MB
[ ${COUNT} -gt `expr ${ACRN_DISK_P3} / 1` ] && ACRN_DISK_P3=${COUNT}


fdisk_img ${ACRN_DISK_IMAGE}

IMG_DEV_LOOP=`losetup -f -P --show ./${ACRN_DISK_IMAGE}`
mkdir -p ./img_p1 ./img_p3
mkfs.vfat ${IMG_DEV_LOOP}p1
mkfs.ext3 -U time ${IMG_DEV_LOOP}p3 
mkfs.ext3 -U time ${IMG_DEV_LOOP}p4
mount ${IMG_DEV_LOOP}p1 ./img_p1
mount ${IMG_DEV_LOOP}p3 ./img_p3

cp -a ./cl_p1/* ./img_p1/  # copy clearlinux ESP to our ESP partition
cp -a ./cl_p3/* ./img_p3/  # copy clearlinux rootfs to our rootfs partition
cp -a /lib/firmware/intel-ucode ./img_p3/lib/firmware/intel-ucode
cp -a /lib/firmware/i915 ./img_p3/lib/firmware/i915
cp -a /lib/firmware/intel ./img_p3/lib/firmware/intel

TMP_STR=`fdisk -l -o uuid,device ${IMG_DEV_LOOP} | grep ${IMG_DEV_LOOP}p3`
UUID_ROOT=${TMP_STR::36}

echo "sos bzImage, modules and HV into disk image ..."
cp ${PATH_HV_OUT}/hypervisor/acrn.efi ./img_p1/EFI/org.clearlinux/


# if you can set acrn.efi as the first one to boot from UEFI firmware
# you needn't change BOOTX64.EFI.
cp ./img_p1/EFI/BOOT/BOOTX64.EFI  ./img_p1/EFI/BOOT/BOOTX64-orig.EFI
cp ${PATH_HV_OUT}/hypervisor/acrn.efi ./img_p1/EFI/BOOT/BOOTX64.EFI

cp ${BZ_FPATH} ./img_p1/EFI/org.clearlinux/

cp -R ${MODS_FPATH}/*  ./img_p3/lib/modules/

cp ${PATH_HV_OUT}/devicemodel/acrn-dm  ./img_p3/usr/bin/
cp -r ${PATH_HV_OUT}/tools/*  ./img_p3/usr/bin/

cp /usr/lib64/libuuid.so.1      ./img_p3/usr/lib64/
cp /usr/lib64/libpciaccess.so.0 ./img_p3/usr/lib64/
cp /usr/lib64/libcrypto.so.1.0.0        ./img_p3/usr/lib64/


# copy launch_uos_script.sh which is used to start guest OS
mkdir -p ./img_p3/root/
cp -R ${LAUNCH_UOS_SCRIPT} ./img_p3/root/
cp ./${ACRN_HV_DIR}/devicemodel/bios/VSBL* ./img_p3/root/
cp ./12-create-network-for-uos.sh  ./img_p3/root/

# remove the colorful prompt and terminal, it blinks on uart shell
touch ./img_p3/root/.dircolors
cat <<EOF>./img_p3/etc/profile
export PS1="\u #"
EOF


# empty password for root account
cat <<EOF>./img_p3/etc/passwd
root::0:0:root:/root:/bin/bash
EOF


# permit root ssh without password
mkdir -p ./img_p3/etc/ssh/
cat <<EOF>./img_p3/etc/ssh/sshd_config
PermitRootLogin yes
PermitEmptyPasswords yes
EOF

# create loader.conf
cat <<EOF>./img_p1/loader/loader.conf
default acrn
echo "timeout 10"
EOF

# create acrn.conf
cat <<EOF>./img_p1/loader/entries/acrn.conf
title "ACRN Hypervisor"
linux  /EFI/org.clearlinux/${BZ_NAME}
options  console=tty0 console=ttyS0 root=PARTUUID=${UUID_ROOT} rw \
rootwait ignore_loglevel no_timer_check consoleblank=0 \
cma=2560M@0x100000000-0
EOF

for prefix in  ${extra_rpm_package[*]}; do
	for pkg in  `grep -Pioe "<a href=\"$prefix.*\.rpm\">" ${ACRN_CLEAR_RPM_PAGE} \
                | grep -Pioe $prefix.*\.rpm`; do

                [ -f ${pkg} ] && { echo "${pkg} exists in current dir"; continue; }
                echo "downloading ${ACRN_CLEAR_RPM_URL}/$pkg"
                wget -qcL ${ACRN_CLEAR_RPM_URL}/$pkg || { echo "Failed to download $pkg"; exit 1; }
		./10-unpack-rpm.sh $pkg ./img_p3
        done;
done;


sync;

cd ${ACRN_MNT_VOL}
umount ./img_p1
umount ./img_p3
umount ./cl_p1
umount ./cl_p3
losetup -d ${IMG_DEV_LOOP}
losetup -d ${CLR_DEV_LOOP}

rmdir ./cl_p1 ./cl_p3 ./img_p1 ./img_p3

echo -e "Boot \033[31m ${ACRN_DISK_IMAGE} \033[0m in qemu/kvm, or simics. Or dd it into hard/USB disk to boot"

chmod 666 ${ACRN_DISK_IMAGE}

env | grep ACRN > ${ACRN_MNT_VOL}/${ACRN_ENV_VARS}

exit 0;
