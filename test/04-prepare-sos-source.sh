#!/bin/bash
#
# This script is expected to run in ClearLinux host or docker developement
# environment. Make sure system has the following commands before executing
#     wget, grep, tar, xz, basename, dirname,
#
# It does:
#   1. git clone https://github.com/clearlinux-pkgs/linux-pk414
#   2. wget -c https://www.kernel.org/pub/linux/kernel/v4.x/linux-4.14.xxx.tar.xz
#   3. tar xJf linux-4.14.xxx.tar.xz
#   4. cd linux-4.14.xxx
#   5. for i in `ls ../linux-pk414/*.patch`; do patch -p1 <$i; done;
#   6. cp ../linux-pk414/config-pk414-sos  .config
#
cd ${ACRN_MNT_VOL};

[ -z ${ACRN_ENV_VARS} ] && ACRN_ENV_VARS=acrn-env.txt
[ -f ${ACRN_ENV_VARS} ] && \
    { for line in `cat ${ACRN_ENV_VARS}`; do export $line; done; }

[ -z ${ACRN_TRACE_SHELL_ENABLE} ] || set -x

# All works will be done in this folder. We "git clone" all ACRN repositories,
# compile, and then build disk image there. Make sure that it has 30GB space

# The dirname of Linux kernel source for SOS.
# "auto" tells the script to use latest kernel based on clearlinux linux-pk414.
# The rpmbuild spec file in clearlinux linux-pkt414 repo indicates the kenrel 
# version. Bease that, we download a tarball from www.kernel.org, uncompress
# it. If u have a stable kernel git and checkout the right version, set this. 
# For exmaple, linux-4.14.39
SOS_DIR="auto"

# In linux-pk414 git, there is linux-pk414.spec file. Get kernel base
# from the "Source0: https://" in that file.
get_base_kernel_version() {
	cd linux-pk414
	RPM_SPEC=`ls *.spec`
        if ! [ -r ${RPM_SPEC} ]; then
           echo "Failed to find linux rpmbuild spec file in "`pwd`
           exit -1
        fi;
        SOURCE=`(grep -i "SOURCE0" ${RPM_SPEC})`
        INDEX=`(expr index "${SOURCE}" "https://")`
        URL_STABLE_KERNEL=${SOURCE:${INDEX}}
        cd ../
	KERNEL_XZ=`basename ${URL_STABLE_KERNEL}`
	SOS_DIR=`echo ${KERNEL_XZ/.tar.xz/}`
}

# wget is faster than git clone stable kernel if you are not in China. Still,
# Prefer git clone to wget tarball from www.kernel.org
wget_or_gitclone_kernel() {

	if [ ! -r ${KERNEL_XZ} ] && [ -n ${ACRN_LINUX_STABLE_GIT} ]; then
		LINUX_VERSION=${SOS_DIR:6}
		CUR_BRANCH=linux-v${LINUX_VERSION}
		git clone ${ACRN_LINUX_STABLE_GIT} ${SOS_DIR} ||
			{ echo "Failed to git clone ${ACRN_LINUX_STABLE_GIT}"; exit 1; }
		cd ${SOS_DIR};

		# checkout the tag specified in clearlinux RPM_SPEC
		git checkout "v${LINUX_VERSION}" ||
		    { echo -n "${ACRN_LINUX_STABLE_GIT} doesn't have v${LINUX_VERSION},";
		      echo -n "try update your git and then re-run the scripts"; exit 1; }

		# create a branch with this linux tag, say v4.14.56
		git branch ${CUR_BRANCH}  && git checkout ${CUR_BRANCH} && return 0;
	fi;

	# Delete the dir if git clone failed, and then try get xz tarball
	cd ${ACRN_MNT_VOL}; rm -fr ${SOS_DIR}

	if [ -r ${KERNEL_XZ} ]; then
		echo ${KERNEL_XZ}" exsits, will use it instead of download it again"
	else
		echo "Downloading(wget) kernel: "${URL_STABLE_KERNEL}
		wget -c -q ${URL_STABLE_KERNEL} || { echo "wget failed"; exit 1; }
	fi;

	tar xJf ${KERNEL_XZ} || { echo "Failed to uncompress ${KERNEL_XZ}"; exit 1; }
	cd ${SOS_DIR};
	git init . && git add * && git commit -a -m "linux stable kernel ${SOS_DIR}"
	[ $? -ne 0 ] && { echo "Failed to init git by ${KERNEL_XZ}"; exit 1; }



	return 0
}


# clone pkt414 kenrel, which hosts the SOS kernel patches. If it exists,
# we don't update it (git pull), instead assume that you want to use the
# old one.  You can update it before runnoing the script
if [ -d ./linux-pk414 ]; then
        echo "linux-pk414 exsits. Use the exsiting git"
else
        echo "git clone linx-pk414"
        git clone https://github.com/clearlinux-pkgs/linux-pk414
fi;


[ ${SOS_DIR}X == "auto"X ] && get_base_kernel_version

# use the existing SOS kernel base or donwload it
if [ -d ${SOS_DIR} ]; then
	echo "SOS source exsits, use the old";
else
       	wget_or_gitclone_kernel

	[ $? -ne 0 ] && { echo "Remove the ${SOS_DIR} before re-run scripts again"; exit 1; }

        cp ../linux-pk414/config-pk414-sos  .config || 
		{ echo "Failed to copy SOS kconfig from clear-pk414 git"; exit 1; }

	# apply the patches in pk414 repo to SOS kernel
	git am ../linux-pk414/*.patch || { echo "Failed to apply linux-pk414 patches to ${SOS_DIR}"; exit 1; }
	mkdir -p firmware
	cp -a /lib/firmware/intel-ucode firmware
	cp -a /lib/firmware/i915 firmware
fi;

for pt in `ls ../sos*.patch`; do
	git am $pt || { echo "Failed to apply patch $pt"; exit 1; }
done;

# export it in Docker and indicate that SOS source is Ok
export ACRN_SOS_DIR=${SOS_DIR}

echo "Stable kernel source in: "${ACRN_SOS_DIR}

env | grep ACRN_ > ${ACRN_MNT_VOL}/${ACRN_ENV_VARS}
