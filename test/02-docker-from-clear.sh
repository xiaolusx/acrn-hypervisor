#!/bin/bash

#
# This script is to download clearlinux kvm image and use it as a base to
# create docker image for ACRN dev environment.
#
# Set env vars in case we are called by 0-all script
[ -z ${ACRN_ENV_VARS} ] && ACRN_ENV_VARS=acrn-env.txt
[ -f ${ACRN_ENV_VARS} ] && \
	{ for line in `cat ${ACRN_ENV_VARS}`; do export $line; done; }

[ -z ${ACRN_MNT_VOL} ] && ACRN_MNT_VOL=/acrn-vol
[ -z ${ACRN_HOST_DIR} ] && ACRN_HOST_DIR=/home/${USER}/vdisk

[ -z ${ACRN_DOCKER_NAME} ] && ACRN_DOCKER_NAME=acrn-dev
[ -z ${ACRN_DOCKER_IMAGE} ] && ACRN_DOCKER_IMAGE=acrn-clear

# clearlinux OS version and URL. Use latest version if not specified
[ -z ${ACRN_CLEAR_OS_VERSION} ] && ACRN_CLEAR_OS_VERSION=""
[ -z ${ACRN_CLEAR_URL} ] && ACRN_CLEAR_URL=https://cdn.download.clearlinux.org

# Respect the shell environment https_proxy in Docker
[ -z ${https_proxy} ] || PROXY_CONF="-e https_proxy="${https_proxy}

PEM_SUPD='Swupd_Root.pem'
PEM_CLEAR='ClearLinuxRoot.pem'

name_conflict()
{
	RET=`docker ps -a -q --format='{{.Names}}' | grep ${ACRN_DOCKER_NAME}`
	if [ "${RET}X" == "${ACRN_DOCKER_NAME}X" ]; then
		echo -n -e  "The Docker \"${ACRN_DOCKER_NAME}\" exists; "
		return 1
	fi;
	return 0;
}

# $1 - clear_os_version.
# it sets the ${CLEAR_IMAGE_FNAME} to the name of clearlinux kvm image
function get_url()
{
	### CLEAR_IMAGE_FNAME=clear-xxxxx-kvm.img.xz
	if [ "$1X" != "X" ]; then
		CLEAR_IMAGE_FNAME=clear-${ACRN_CLEAR_OS_VERSION}-kvm.img.xz
		IMAGE_BASE=${ACRN_CLEAR_URL}/releases/$1/clear/
	else
		# https://cdn.download.clearlinux.org/README.html the "current" folder
		# includes the latest version distribution
		IMAGE_BASE=${ACRN_CLEAR_URL}/current

		# Pattern: <a href="clear-xxxxx-kvm.img.xz">clear-xxxxx-kvm.img.xz</a>
		HREF=`curl -sSL ${IMAGE_BASE} | \
		    grep -Pioe "<a +href *= *\"?clear-[0-9]*-kvm.img.xz[^\-].*?</a>" | \
		    grep -Pioe \"clear-[0-9]*-kvm.img.xz\"`
		CLEAR_IMAGE_FNAME=`echo ${HREF} | sed 's/\"//g'`
		[ -z "${CLEAR_IMAGE_FNAME}" ] && \
		       	{ echo "Failed to get ClearLinux image URL"; exit 1; }
	fi;

	curl -sSL ${IMAGE_BASE}/${PEM_SUPD} -o ${PEM_SUPD}
	curl -sSL ${IMAGE_BASE}/${PEM_CLEAR} -o ${PEM_CLEAR}
}

# S1: URL base of clearlinux image
# S2: image name
function download_image() 
{
	local raw_image=${2::-3}  # without .xz suffix
	[ -r $raw_image ] && { echo $raw_image " exists, just use it"; return 0; }

	[ -r $2 ] && xz -kd $2 && { echo $2 " exists, just use it"; return 0; }

	echo -n "Starting to download image : " $1/$2 "@ "; date 
	wget -q -c $1/$2 && xz -kd $2 || exit -1
	echo -n "Completed downloading image : " $1/$2 "@ "; date 
}

# $1: ACRN_CLEAR_OS_VERSION
# $2: raw image file
function build_docker_image()
{
	local mnt_pt=/tmp/cl_$1_$$
	mkdir -p ${mnt_pt}

	# The 3rd partition(/dev/sda3) is the rootfs of clearlinux kvm image.
	# Change it only if clearlinux changed the layout in the future
	guestmount -a $2 -m /dev/sda3 ${mnt_pt} || exit 1

	# Use the rootfs of clear-xxx-kvm.img.xz as a docker base image
	tar -C ${mnt_pt} -c . | docker import - ${ACRN_DOCKER_IMAGE}:"t"$1

	docker create --name=${ACRN_DOCKER_NAME} --net=host  ${PROXY_CONF} \
		-v /dev:/dev/ --privileged \
		-v ${ACRN_HOST_DIR}:${ACRN_MNT_VOL} \
		-it ${ACRN_DOCKER_IMAGE}:"t"$1 "/bin/bash"

	docker start ${ACRN_DOCKER_NAME}
#	docker exec ${ACRN_DOCKER_NAME} sh -c "mkdir -p /etc/ssl/certs/"
	docker exec ${ACRN_DOCKER_NAME} sh -c \
		"cp ${ACRN_MNT_VOL}/${PEM_SUPD} /usr/share/clar/update-ca/ && \
		cp ${ACRN_MNT_VOL}/${PEM_CLEAR} /usr/share/clar/update-ca/" || \
		{ skip_cert="-n"; echo "Failed to copy PEM certs into clearlinux"; }

#	docker exec ${ACRN_DOCKER_NAME} swupd update
	echo -n "swupd bundle-add start @"; date
	docker exec ${ACRN_DOCKER_NAME} sh -c "swupd bundle-add $skip_cert \
		--skip-diskspace-check \
		c-basic storage-utils-dev  dev-utils-dev user-basic-dev > /dev/null" \
		|| { guestunmount ${mnt_pt}; exit -1; }

	echo -n "swupd bundle-add end @"; date
	if [ -n ${ACRN_PIP_SOURCE} ]; then
		base=`echo ${ACRN_PIP_SOURCE} | grep -Pioe "https://.*?/" -`
		host=${base:8:-1}
		src_args=" -i ${ACRN_PIP_SOURCE} --trusted-host ${host}"
	else
		unset ACRN_PIP_SOURCE
	fi;

	docker exec ${ACRN_DOCKER_NAME} sh -c \
		"pip3 install --timeout=180 ${src_args} kconfiglib" \
		|| { guestunmount ${mnt_pt}; exit -1; }

	docker exec ${ACRN_DOCKER_NAME} sh -c "mkdir -p ${ACRN_MNT_VOL}/firmware" || exit 1;
	for pkg in `ls linux-firmware-*`; do
	   docker exec ${ACRN_DOCKER_NAME} sh -c \
		   "${ACRN_MNT_VOL}/10-unpack-rpm.sh ${ACRN_MNT_VOL}/${pkg} ${ACRN_MNT_VOL}/firmware" || exit 1;
	done;
	docker exec ${ACRN_DOCKER_NAME} sh -c "cp -fr ${ACRN_MNT_VOL}/firmware/* /"  || exit 1;

	docker exec ${ACRN_DOCKER_NAME} sh -c "git config --global user.name ${ACRN_GIT_USER_NAME}" || exit 1;
	docker exec ${ACRN_DOCKER_NAME} sh -c "git config --global user.email ${ACRN_GIT_USER_EMAIL}" || exit 1;

	docker stop ${ACRN_DOCKER_NAME}
	docker commit ${ACRN_DOCKER_NAME} ${ACRN_DOCKER_IMAGE}:$1
	docker rm ${ACRN_DOCKER_NAME}
	docker rmi  ${ACRN_DOCKER_IMAGE}:"t"$1

	guestunmount ${mnt_pt}
}

# $1 -- the version# of clearlinux
function download_firmware() {
	local URL="https://download.clearlinux.org/releases/$1/clear/x86_64/os/Packages/"

	echo "Download the page: ${URL} ..."

	export ACRN_CLEAR_RPM_PAGE="clear_package_$$.html"
	export ACRN_CLEAR_RPM_URL=${URL}
        curl -sSL ${URL} -o ${ACRN_CLEAR_RPM_PAGE} || { echo "Failed to get page: $URL"; exit 1; }

	echo -n "begin to download firmware from clearlinux-"$1 "@"; date;
        for pkg in `cat ${ACRN_CLEAR_RPM_PAGE} | grep -Pioe "<a href=\"linux-firmware-.*\.rpm\">" \
		| grep -Pioe linux-firmware-.*\.rpm`;  do
		[ -f ${pkg} ] && { echo "${pkg} exists in current dir"; continue; }
		echo "downloading ${URL}/$pkg"
		wget -qcL ${URL}/$pkg;
	done;
	echo -n "end download firmware from clearlinux-"$1 "@"; date;
}

[ -z ${ACRN_TRACE_SHELL_ENABLE} ] || set -x

# Create the dir if does not exsit
mkdir -p ${ACRN_HOST_DIR}

name_conflict
[ $? -ne 0 ] && 
	{ echo -n "Use \"docker stop/rm ${ACRN_DOCKER_NAME}\" to remove the old";
	  echo " or define ACRN_DOCKER_NAME to other value"; exit 1; }

# Get URL and set ACRN_CLEAR_OS_VERSION if it is ""
get_url ${ACRN_CLEAR_OS_VERSION}

download_image  ${IMAGE_BASE} ${CLEAR_IMAGE_FNAME}

ACRN_CLEAR_OS_VERSION=`echo ${CLEAR_IMAGE_FNAME} | grep -ioe "[0-9]*"`

download_firmware ${ACRN_CLEAR_OS_VERSION}

IMAGE=${ACRN_DOCKER_IMAGE}:${ACRN_CLEAR_OS_VERSION}

DOCKER_TAG=`docker images -q ${IMAGE} --format={{.Repository}}:{{.Tag}}`

[ ${DOCKER_TAG}X != "${IMAGE}"X ] && \
	build_docker_image ${ACRN_CLEAR_OS_VERSION} ${CLEAR_IMAGE_FNAME::-3}

export ACRN_DOCKER_IMAGE=${IMAGE}

env | grep ACRN_  > ${ACRN_HOST_DIR}/${ACRN_ENV_VARS}
chmod 0666 ${ACRN_HOST_DIR}/${ACRN_ENV_VARS}

exit 0;
