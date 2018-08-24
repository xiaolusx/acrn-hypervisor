#!/bin/bash
#
# This script is expected to run in ClearLinux host or docker developement
# environment. Make sure system has the following commands before executing
#      git
#
URL_ACRN=https://github.com/projectacrn/


# This is the volume on host system, and will be mounted as volume into
# docker -v ${HOST_DIR_VOL}:${ACRN_MNT_VOL}. We "git clone" all ACRN repos,
# and then build disk image there in docker. Make sure that it has 30GB
# space since we create disk image there.
[ -z ${ACRN_MNT_VOL} ] && ACRN_MNT_VOL=/acrn-vol
cd ${ACRN_MNT_VOL} || { echo "Failed to cd "${ACRN_MNT_VOL}; exit -1; }

[ -z ${ACRN_ENV_VARS} ] && ACRN_ENV_VARS=acrn-env.txt
[ -f ${ACRN_ENV_VARS} ] && \
     { for line in `cat ${ACRN_ENV_VARS}`; do export $line; done; }

[ -z ${ACRN_HV_DIR} ] && ACRN_HV_DIR=acrn-hypervisor

[ -z ${ACRN_TRACE_SHELL_ENABLE} ] || set -x

if [ ! -d ${ACRN_HV_DIR} ]; then
	git clone ${URL_ACRN}/${ACRN_HV_DIR} || 
		{ echo "Failed to git-clone ${URL_ACRN}${ACRN_HV_DIR}"; exit 1; }

        echo "Completed git-clone ACRN hypervisor and device model"

	if [ ! -z ${ACRN_UOS_VSBL} ] && [ ${ACRN_UOS_VSBL} -eq 1 ]; then
		cd ${ACRN_HV_DIR};
		for i in `ls ../hv*.patch`; do
			echo "Patch ${i} to acrn-hypervisor";
			git am  $i; 
		       [ $? -ne 0 ] && { echo "Failed to apply $i to hypervisor"; exit 1; }
		done;
	fi;

fi;

export ACRN_HV_DIR=${ACRN_HV_DIR}


env | grep ACRN > ${ACRN_MNT_VOL}/${ACRN_ENV_VARS}

exit 0;
