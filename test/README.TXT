NOTE:
  1.  CLONE STABLE KERNEL TO LOCAL FILE SYSTEM 

      Please do this so as not to push too pressure on public & free linux
      kernel mirror, meanwhile, it spends up the execution of the scripts if
      you run the scripts more than one time.

      Manually,  "git clone" a stable kernel to local file system, and then
      modifiy ACRN_LINUX_STABLE_GIT definition in script 00 to this repo. For
      example,

         # cd ${ACRN_HOST_DIR}
         # git clone https://mirrors.tuna.tsinghua.edu.cn/git/linux-stable.git
         # modify script-00: export ACRN_LINUX_STABLE_GIT=${ACRN_MNT_VOL}/linux-stable.git

===============================================================================

  The scripts in this directory are to create a disk image to run acrn
hypervisor and service OS; and/or individual binary/tarball for SOS/ESP,
etc. It pulls opensourced code from github.com, projectacrn and clearlinux
pk414 git, build the code, and create a disk image. Since the image is few
gigabyte, it takes time to "dd" it to disk/USB, the script also extracts
ESP partition and SOS rootfs parition as respective tarball. so developers
can just copy the ESP and SOS_rootfs to corresponding partition, instead of
"dd" the whole image to disk.

  Run the first script (0-run-all.sh) to get an image, which can be used
also in qemu/ovmf or simics. Currently, the final disk image doesn't include
UOS. You can manually copy the rootfs of UOS into the 4rd partition of the
image. 

   After the scripts execution, the build results are in 

     # cd ${ACRN_HOST_DIR}
     # ls -lh out/
    
total 1.5G
-rwxr-xr-x 1 minskey minskey  251 Jul 30 18:31 acrn.conf
-rwxr-xr-x 1 minskey minskey 292K Jul 30 18:31 acrn.efi
-rwxrwxrwx 1 minskey minskey    4.9G Jul 31 08:13 acrn_vdisk_clear24030.img
-rw-r--r-- 1 minskey minskey  13M Jul 30 18:31 esp_partition.tgz
-rwxr-xr-x 1 minskey minskey   31 Jul 30 18:31 loader.conf
-rw-r--r-- 1 minskey minskey 319M Jul 30 18:31 sos_rootfs.tgz
-rwxr-xr-x 1 minskey minskey 7.8M Jul 30 18:31 vmlinuz-4.14.57-acrn

   a)  acrn_vdisk_clear24030.img  -- disk image
       
   b)  sos_rootfs.tgz  -- rootfs for SOS
       esp_partition.tgz (including acrn.efi, acrn.conf. loader.conf vmlinuz-4.14.xx-acrn)
       
   c)  acrn.conf
       acrn.efi
       loader.conf
       vmlinuz-4.14.xx-acrn

So, you have 3 options,

    1. dd acrn_vdisk_clear24030.img to USB or hardisk to run;
    2. create EFI partitioned a disk, and then untar esp_partition.tgz to ESP, 
       untar sos_rootfs.tgz to a partition for SOS root;
    3. create yourself ESP boot paritition, and copy files listed in C) ;

+++ NOTE: Double check the "root=PARTUUID" in acrn.conf for SOS root partition +++


   In most cases, you just need to modify one or two environment variables
defined at the beginning of the script 00-run-all.sh

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
  a)  00-run-all.sh
      it calls the all the other scripts; the environment variables defined
      in this script will be passed to other scripts. At last, it tries to
      start ACRN hypervisor and SOS in OVMF (might fail if OVMF changes)
 
  b) 01-build-env-check.sh
      check if necessary commands are installed on host system;

  c) 02-docker-from-clear.sh
      Pull clearlinux kvm image to build an docker image as dev environment

  d) 03-setup-clearlinux-docker.sh
      Use the docker image built by 2-docker-from-clear.sh to start a docker

  e) 04-prepare-sos-source.sh
       Pull code from github.com and www.kernel.org to build SOS source code

  f) 05-clone-hv-dm.sh
       Clone ACRN hypervisor and device model code into /acrn-vol in docker

  g) 06-build-uefi-acrn.sh
       Build(compile) ACRN related code, including hypervisor and SOS

  h) 07-mk-disk-image.sh
       Create a disk image including ACRN hyperviosr and SOS

  i) 08-extract-rootfs.sh
       extract ESP, SOS rootfs from the disk image created in script 07

  j) 09-download-ovmf.sh
       Download OVMF binary from https://www.kraxel.org/repos/jenkins/edk2

  k) 10-unpack-rpm.sh
       ultility to unpack/install a RPM package for clearlinux doesn't use RPM


QA
---
 1. Occasionally, an error message will be printed by curl, like,
       curl: (23) Failed writing body (0 != 1412)
    It should be fine since in piped shell commands, say curl | grep, the grep
    command got what he wants and closed pipe before curl completed writing. 
  
 2. For whatever reason, it is slow for guys in China to download some of those
    code from www.kernel.org, pip source, etc. Please use the mirror you know it
    is fast for you. Currently, we choose the Mirror from Tsinghua University.

 3. if you want to install some packages in the SOS rootfs, instead of whole
    bundle, you can go to:

      https://download.clearlinux.org/releases/24330/clear/x86_64/os/Packages/,

    here, 24330 is the verion ID of clearlinux, or "current", and check which
    rpm packages you want to install,  and then put the name of packages into
    the array extra_rpm_package[] in script-07.
