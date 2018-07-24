#!/bin/bash
#
# This script is expected to run in ClearLinux host or docker developement
# environment. Make sure system has the following commands before executing
#     grep, basename, dirname,
# 
[ -z ${ACRN_ENV_VARS} ] && ACRN_ENV_VARS=acrn-env.txt
[ -f ${ACRN_ENV_VARS} ] && \
    { for line in `cat ${ACRN_ENV_VARS}`; do export $line; done; }

[ -z ${ACRN_TRACE_SHELL_ENABLE} ] || set -x

IMG_P1=p1_$$
IMG_P3=p3_$$

mkdir -p out

mkdir ${IMG_P1} ${IMG_P3} || { echo "Failed to mkdir"; exit 1; }

guestmount -a ${ACRN_DISK_IMAGE} -m /dev/sda1 --ro ${IMG_P1} || \
  { echo "Failed to guestmount ESP"; exit 1; }

guestmount -a ${ACRN_DISK_IMAGE} -m /dev/sda3 --ro ${IMG_P3} || \
  { echo "Failed to guestmount rootfs"; exit 1; }

tar -zcf out/esp_partition.tgz -C ${IMG_P1} . || exit 1
tar -zcf out/sos_rootfs.tgz -C ${IMG_P3} . || exit 1
cp ${IMG_P1}/loader/entries/acrn.conf out/ || exit 1
cp ${IMG_P1}/loader/loader.conf out/ || exit 1
cp ${IMG_P1}/EFI/org.clearlinux/acrn.efi out/ || exit 1
cp ${IMG_P1}/EFI/org.clearlinux/*acrn out/ || exit 1

guestunmount ./${IMG_P1} 
guestunmount ./${IMG_P3}

rmdir  ${IMG_P1} ${IMG_P3}

