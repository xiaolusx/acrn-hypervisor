#!/bin/bash

declare -A commands
commands=(
	[xz]="xz commandline missed, install it please"
	[git]="git command missed, install it first"
	[sed]="Need to install sed command"
	[wget]="Need to install wget commands/package"
	[curl]="Please install curl command"
	[docker]="Need to install docker.io package"
	[guestmount]="Need to install libguestfs and libguestfs-tools package" 
	[qemu-system-x86_64]="Need to install qemu/x86, qemu-system-x86_64 missed"
)

# check if a group in group list: $1 group; $2 group list;
function group_in_list() {
	for g in $2; do
		[ $g == $1 ] && return 1;
	done
	return 0;
}

function has_docker_group() {
	local tmp=`grep -Pioe "^docker:" /etc/group` >> /dev/null
	[ ${tmp}X == "docker:"X ] && return 1;
	return 0
}

# ensure that all commandlines defined in commands[]
for cmd in $(echo ${!commands[*]}); do
	which ${cmd} >> /dev/null && echo ${cmd} "is ok" || { echo ${commands[${cmd}]}; exit -1; }
done;


CURR_USER=`whoami`
ret=`groups ${CURR_USER}`
group_list=${ret#*:}



# Ensure that host system has "docker" user group 
has_docker_group
if [ $? -eq 0 ]; then
	echo -n "Need to create a docker group by: \"groupadd docker\", "
	echo -n "and then add" ${CURR_USER} "into the group by:"
	echo -e "  \"usermod -a ${CURR_USER} -G docker\". "
	echo "You need to logout and then login to enable the group changes"
	exit 1
fi;

# ensure current user is in docker group
group_in_list "docker" "${group_list}"
if [ $? -eq 0 ]; then
	echo -n "Need to add" \"${CURR_USER}\" "into group" \"docker\" "by:"
	echo -e "  \"usermod -a ${CURR_USER} -G docker\""
	echo "You need to logout and then login to enable the group changes"
	exit 1
fi;

# ensure current user is in kvm group
[ -c /dev/kvm ] || { echo "Failed:  The kernel doesn't supports kvm or kvm modules are not loaded"; exit 1; }
kvm_group=`stat -c %G /dev/kvm`
group_in_list ${kvm_group} "${group_list}"
if [ $? -eq 0 ]; then
	echo -n "Need to add" \"${CURR_USER}\" "into group" \"${kvm_group}\" "by:"
	echo -e "  \"usermod -a ${CURR_USER} -G ${kvm_group}\""
	echo "You need to logout and then login to enable the group changes"
	exit 1
fi;

# kernel_readable_by_user
for vmlinuz in `ls /boot/vmlinuz*`; do
	[ -r $vmlinuz ] || { echo "\"$CURR_USER\" lack of read permission for $vmlinuz"; exit 1; }
done;
