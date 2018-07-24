
  The scripts in this directory are to create a disk image to run acrn
hypervisor and service OS. It pulls opensourced code from github.com,
projectacrn and clearlinux git, build the code, and then create a disk
image.

  Just run the first script (0-run-all.sh) to get an image, which can
be used in qemu/ovmf or simics. The image also can be "dd" to USB disk
or hard disk to demo ACRN. Currently, final disk image doesn't include
UOS. You can manually copy the rootfs of UOS into the 4rd partition of
the image. 

   In most cases, you just need to modify one or two environment variables
defined at the beginning of the script 0-run-all.sh

   ACRN_CLEAR_OS_VERSION=23550   # version# of clearlinux, or "" for latest

   ACRN_HOST_DIR=/home/${USER}/vdisk    # the folder for saving the disk image

   # The final disk image file name and layout
   ACRN_DISK_IMAGE=acrn_vdisk_all.img
   ACRN_DISK_SIZE=13240  # disk size (MB), adjust it as u like
   ACRN_DISK_P1=200      # EFI ESP
   ACRN_DISK_P2=200      # Linux swap
   ACRN_DISK_P3=4096     # sos rootfs
   ACRN_DISK_P4=         # user partition uses the rest

   When build failed or completed, the partial/completely build environment
will be preserved so that we can use the docker as build system or check if
any errors occur. By default, the docker name is "acrn-dev", if code building
failed, you can :

   $ cd ${ACRN_HOST_DIR} to take a look at the log file "log.txt"

   $ docker start acrn-dev
   $ docker attach acrn-dev
   # cd /acrn-vol/acrn-hypervisor; make  # to check hypervisor building
   # cd /acrn-vol/linux-4.14.X; make bzImage        # check kernel building


About the scripts
-----------------
  a)  0-run-all.sh
      it calls the all the other scripts; the environment variables defined
      in this script will be passed to other scripts. At last, it tries to
      start ACRN hypervisor and SOS in OVMF (might fail if OVMF changes)
 
  b) 1-build-env-check.sh
      check if necessary commands are installed on host system;

  c) 2-docker-from-clear.sh
      Pull clearlinux kvm image to build an docker image as dev environment

  d) 3-setup-clearlinux-docker.sh
      Use the docker image built by 2-docker-from-clear.sh to start a docker

  e) 4-prepare-sos-source.sh
       Pull code from github.com and www.kernel.org to build SOS source code

  f) 5-clone-hv-dm.sh
       Clone ACRN hypervisor and device model code into /acrn-vol in docker

  g) 6-build-uefi-acrn.sh
       Build(compile) ACRN related code, including hypervisor and SOS

  h) 7-mk-disk-image.sh
       Create a disk image including ACRN hyperviosr and SOS

  i) 8-download-ovmf.sh
       Download OVMF binary from https://www.kraxel.org/repos/jenkins/edk2

  j) 9-unpack-rpm.sh
       ultility to unpack/install a RPM package for clearlinux doesn't use RPM



QA:
---
 1. Occasionally, an error message will be printed by curl, like,
       curl: (23) Failed writing body (0 != 1412)

    It should be fine since in piped shell commands, say curl | grep, the grep
    command got what he wants and closed pipe before curl completed writing. 
  

