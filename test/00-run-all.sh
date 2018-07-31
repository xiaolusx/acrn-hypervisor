#!/bin/bash
#
# This script is to create a disk image with ACRN hypervisor and service
# OS. The final disk image can be used to "dd" to USB disk or hard disk,
# to run, or run in qemu/ovmf or simics emulator. At this time, Guest OS
# isn't included in the image. You can copy your guest os image into the
# 4th patition of ACRN_DISK_IMAGE.
#
# After service OS boots up, you can login into the system as root without
# password, and take a look at /root/nuc/launch_uos.sh, and learn about
# start guest OS.

# Since dd image to disk is too time-consumping, the scripts also create
# tarball of sos_rootfs.tgz, UEFI ESP partion, and individual binary in
# ${ACRN_HOST_DIR}/out dir.
#
# Make sure that system has the following commands before executing 
#     wget, curl, sha512sum, grep, sed, xz, basename, dirname,
#     guestmount/guestunmount, docker qemu-system_x86-64
#
#  package in ubuntu/centos: libguestfs,  libguestfs-tools
# 
[ $# -ne 0 ] && LOG_FILE=$1 || LOG_FILE=log.txt


# set this if UOS boots from realmode on virtual SBL; don't set it if UOS boot
# from protected mode.
# export ACRN_UOS_VSBL=1

# The release# of clearlinux in /usr/lib/os-release: like 23140, we will pull
# a KVM image from http://clearlinux.org and use it as base image for docker.
# By default, the latest KVM image by parsing the web page:
#               https://cdn.download.clearlinux.org/current/
# export ACRN_CLEAR_OS_VERSION=23940
export ACRN_CLEAR_OS_VERSION=""

# The folder will be mounted into docker as volume in docker's word, to the
# mounting point at ${ACRN_MNT_VOL}. It is used as work diretory (pwd) to git
# clone acrn code, build disk image(20GB). Make sure that it has enough space.
# The script will create the dir if it doens't exsit. Change layout as you like.
#
# export ACRN_HOST_DIR=/work/vdisk
export ACRN_HOST_DIR=/home/${USER}/vdisk

# Mounting point in docker for ACRN_HOST_DIR. Needn't touch it
export ACRN_MNT_VOL=/acrn-vol

# The final disk image layout for qemu/ovmf or dd to disk, change it as u like
# the name of the image will be ${ACRN_DISK_IMAGE}_clearnnnnn.img, which saying
# the ACRN disk image is created based on clearlinux_nnnnn version.
export ACRN_DISK_IMAGE=acrn_vdisk
export ACRN_DISK_SIZE=5000  # disk size (MB)
export ACRN_DISK_P1=200      # EFI ESP
export ACRN_DISK_P2=200      # Linux swap
export ACRN_DISK_P3=3000     # sos rootfs
export ACRN_DISK_P4=         # user partition uses the rest

# Tell us if we should use sparse file for ${ACRN_DISK_IMAGE}. Note that sparse
# image is fast to create but might cause fragmentation issue. If u care about
# fragmentation, you can remove "sparse" even after disk image has been created
# by    "cp sparse.img raw.img --sparse=never"
export ACRN_DISK_SPARSE_IMAGE=1

# Docker name created from ACRN_DOCKER_IMAGE as development environment to
# build ACRN source code and disk image.
export ACRN_DOCKER_NAME=acrn-dev

# The info is used to git config user.mail & user.name in docker;
# You can change it to yours if you want. We need to set it because we
# use "git am" to apply clearlinux-pk414 patches to linux stable tree.
export ACRN_GIT_USER_NAME="test"
export ACRN_GIT_USER_EMAIL="test@gmail.com"

# If you are in China, define this. we will try to use mirror of china.
# like,  www.kernel.org ==> mirror.tuna.tsinghua.edu.cn
export ACRN_I_AM_IN_CHINA=1

# Set mirrors for some code/repo if you are in China
if [ ${ACRN_I_AM_IN_CHINA} -eq 1 ]; then

 # The best way is to git clone this stable tree to your local file system;
 # and then, modify this macro to your local git.  For exmaple, we git clone
 # it to home dir, and then, modify this macro to: /home/$USER/linux-stable.
 #
 #   export ACRN_LINUX_STABLE_GIT=${ACRN_MNT_VOL}/linux-stable
    export ACRN_LINUX_STABLE_GIT=https://mirrors.tuna.tsinghua.edu.cn/git/linux-stable.git
     export ACRN_PIP_SOURCE=https://pypi.tuna.tsinghua.edu.cn/simple  # https is required

else
  unset ACRN_LINUX_STABLE_GIT
  unset ACRN_PIP_SOURCE
fi;

# =========================================================================
# Most likely, you needn't modify the script after this line
# =========================================================================

# set "ACRN_TRACE_SHELL_ENABLE" to tell all scripts to "set -x". unset it if
# you don't want to trace shell commands.
# export ACRN_TRACE_SHELL=1

# Download Clearlinux OS image by the URL. Don't change it unless u know the
# URL is changed
export ACRN_CLEAR_URL=https://cdn.download.clearlinux.org

# The name of the docker image that we will create. We will alos add a tag
# by clearlinux os-version
export ACRN_DOCKER_IMAGE=acrn-clear

# UEFI firmware which will be used for QEMU booting. It is the filename in UEFI
# rpm package from UEFI open source project. 
export ACRN_UEFI_FW=OVMF-pure-efi.fd

# Save environment between scripts. Needn't touch it.
export ACRN_ENV_VARS=acrn-env.txt


mkdir -p ${ACRN_HOST_DIR}/

# remove the env file in case it exists for an incompleted execution.
rm -f ${ACRN_HOST_DIR}/${ACRN_ENV_VARS}

# copy all scripts to ACRN_HOST_DIR to execute from there
if [ ! `pwd` = ${ACRN_HOST_DIR} ]; then
	cp -af *.sh ${ACRN_HOST_DIR} ||
	    { echo "check if the dir ${ACRN_HOST_DIR} is writable for \"${USER}\"";
	    exit 1; }
	[ -z ${ACRN_UOS_VSBL} ] ||
		[ ${ACRN_UOS_VSBL} -eq 1 ] && cp uos-boot-realmode.patch ${ACRN_HOST_DIR}/
fi;

cd ${ACRN_HOST_DIR}/
truncate -s 0 ${LOG_FILE}

set -o pipefail

# Check if build environment is ok
{ echo -n "==== Runing script 01-build-env-check.sh  ====@ "; date; } >> ${LOG_FILE}
./01-build-env-check.sh 2>&1 | tee -a ${LOG_FILE}
[ $? -ne 0 ] && exit 1

echo "======================================================================"
echo -ne "It will take \033[31m hours \033[0m to download clearlinux image and"
echo -ne " bundles if you are downloading a new version; check it tomorrow if"
echo -e " you run this script at night"
echo "======================================================================"

# Pull KVM image of clearlinux, and build a docker image as dev environment
{ echo -n "==== Runing script 02-docker-from-clear.sh  ====@ "; date; } >> ${LOG_FILE}
./02-docker-from-clear.sh 2>&1 | tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to build clearlinux docker image"; exit -1; }

# Create and run ClearLinux Docker
{ echo -n "==== Runing script 03-setup-clearlinux-docker.sh ====@ "; date; } >> ${LOG_FILE}
./03-setup-clearlinux-docker.sh 2>&1 | tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to run clearlinux docker"; exit -1; }

# prepare SOS kernel source code
{ echo -n "==== Runing script 04-prepare-sos-source.sh  ====@ "; date; } >> ${LOG_FILE}
docker exec ${ACRN_DOCKER_NAME}  ${ACRN_MNT_VOL}/04-prepare-sos-source.sh 2>&1 \
	| tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to get SOS kernel source"; exit 1; }

# prepare HV/DM source code
{ echo -n "==== Runing script 05-clone-hv-dm.sh  ====@ "; date; } >> ${LOG_FILE}
docker exec ${ACRN_DOCKER_NAME}  ${ACRN_MNT_VOL}/05-clone-hv-dm.sh 2>&1 | \
       	tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to get ACRN hypervisor source"; exit 1; }

# build source to binary
{ echo -n "==== Runing script 06-build-uefi-acrn.sh  ====@ "; date; }  >> ${LOG_FILE}
docker exec ${ACRN_DOCKER_NAME} ${ACRN_MNT_VOL}/06-build-uefi-acrn.sh 2>&1 \
	| tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to build SOS"; exit; }

# Create a disk image
{ echo -n "==== Runing script 07-mk-disk-image.sh  ====@ "; date; } >> ${LOG_FILE}
docker exec ${ACRN_DOCKER_NAME} ${ACRN_MNT_VOL}/07-mk-disk-image.sh  2>&1 \
	| tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to create disk image"; exit; }

# extract sos rootfs from disk image
{ echo -n "==== Runing script 08-extract-rootfs.sh  ====@ "; date; } >> ${LOG_FILE}
./08-extract-rootfs.sh  2>&1 | tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to extract rootfs from acrn disk image"; exit; }

# download OVMF efi firmware
{ echo -n "==== Runing script 09-download-ovmf.sh  ====@ "; date; } >> ${LOG_FILE}
docker exec ${ACRN_DOCKER_NAME} ${ACRN_MNT_VOL}/09-download-ovmf.sh 2>&1 \
	| tee -a ${LOG_FILE}

# change ownership
docker exec ${ACRN_DOCKER_NAME} chmod 777 ${ACRN_MNT_VOL}/${ACRN_UEFI_FW}
docker exec ${ACRN_DOCKER_NAME} chmod 777 "${ACRN_MNT_VOL}/${ACRN_DISK_IMAGE}*"
docker exec ${ACRN_DOCKER_NAME} chmod 777 ${ACRN_MNT_VOL}/${ACRN_ENV_VARS}
docker exec ${ACRN_DOCKER_NAME} sh -c "mv ${ACRN_MNT_VOL}/${ACRN_DISK_IMAGE}* ${ACRN_MNT_VOL}/out/"
docker stop  ${ACRN_DOCKER_NAME}

# Comment this if you want to keep the docker as a build environment
# docker rm  ${ACRN_DOCKER_NAME}

# run qemu/ovmf in local host
sed -i 's/^ACRN_/export ACRN_/g' ${ACRN_HOST_DIR}/${ACRN_ENV_VARS}
source ${ACRN_HOST_DIR}/${ACRN_ENV_VARS}

# remove it, otherwise, conflict when run it in the same dir next time
rm -f ${ACRN_HOST_DIR}/${ACRN_ENV_VARS}


echo "If failed, trying manually starting qemu by: qemu-system-x86_64 -bios " \
	${ACRN_HOST_DIR}/${ACRN_UEFI_FW} \
	-hda "${ACRN_HOST_DIR}/${ACRN_DISK_IMAGE}"

qemu-system-x86_64 -bios ${ACRN_HOST_DIR}/${ACRN_UEFI_FW} -hda ${ACRN_HOST_DIR}/${ACRN_DISK_IMAGE} -m 4G -cpu Broadwell -smp cpus=4,cores=4,threads=1 -serial stdio

