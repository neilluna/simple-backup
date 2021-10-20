#!/usr/bin/env bash

script_version=1.0.0

script_name=$(basename ${BASH_SOURCE[0]})
script_dir=$(dirname ${BASH_SOURCE[0]})
script_path=${BASH_SOURCE[0]}

function echo_usage()
{ 
	echo_info "${script_name} - Version ${script_version}"
	echo_info ""
	echo_info "This script will backup key files."
	echo_info ""
	echo_info "Usage: ${script_name} [options] configuration-file"
	echo_info ""
	echo_info "                      Options:"
	echo_info "  -h, --help          Output this help information and exit."
	echo_info "      --version       Output the version and exit."
	echo_info ""
	echo_info "  configuration-file  Path to the configuration file."
} 

# ANSI color escape sequences for use in echo_color().
black='\e[30m'
red='\e[31m'
green='\e[32m'
yellow='\e[33m'
blue='\e[34m'
magenta='\e[35m'
cyan='\e[36m'
white='\e[37m'
reset='\e[0m'

# Back up a directory.
# Usage: backup_directory directory
function backup_directory()
{
	dir=${1}
	source=$(realpath ${directory})
	destination=${archive_dir}${dir}

	echo "ls -alFR ${source}" >> ${manifest_file}
	sudo ls -alFR ${source} >> ${manifest_file}

	destination_dir=$(dirname ${destination})
	if [ ! -d ${destination_dir} ]; then
		[ ${verbose} == true ] && echo_info "Creating directory ${destination_dir} ..."
		mkdir -p ${destination_dir}
		if [ ${?} -ne 0 ]; then
			echo_error "Error creating directory ${destination_dir}"
			echo_error "Could not backup directory ${source}"
			return
		fi
	fi

	[ ${verbose} == true ] && echo_info "Copying directory ${source} to ${destination} ..."
	sudo cp -rL ${source} ${destination}
	if [ ${?} -ne 0 ]; then
		echo_error "Error copying directory ${source} to ${destination}"
		return
	fi
}

# Back up a file.
# Usage: backup_file file
function backup_file()
{
	file=${1}
	source=$(realpath ${file})
	destination=${archive_dir}${file}

	echo "ls -alF ${source}" >> ${manifest_file}
	sudo ls -alF ${source} >> ${manifest_file}

	destination_dir=$(dirname ${destination})
	if [ ! -d ${destination_dir} ]; then
		[ ${verbose} == true ] && echo_info "Creating directory ${destination_dir} ..."
		mkdir -p ${destination_dir}
		if [ ${?} -ne 0 ]; then
			echo_error "Error creating directory ${destination_dir}"
			echo_error "Could not backup file ${source}"
			return
		fi
	fi

	[ ${verbose} == true ] && echo_info "Copying file ${source} to ${destination} ..."
	sudo cp -L ${source} ${destination}
	if [ ${?} -ne 0 ]; then
		echo_error "Error copying file ${source} to ${destination}"
		return
	fi
}

# Echo an error message.
# Usage: echo_error message
function echo_error()
{
	message=${1}
	echo_message "${message}" red true
}

# Echo an error message and exit.
# Usage: echo_error_and_exit message
function echo_error_and_exit()
{
	message=${1}
	echo_error "${message}"
	exit 1
}

# Echo an informational message.
# Usage: echo_info message
function echo_info()
{
	message=${1}
	echo_message "${message}" cyan false
}

# Echo a message.
# Usage: echo_message message color send_to_stderr
function echo_message()
{
	message=${1}
	color=${2}
	send_to_stderr=${3}

	if [ ${send_to_syslog} == true ]; then
		logger -i -t ${script_name} "${message}"
		return
	fi
	if [ ${send_in_color} == true ]; then
		# Echoing ANSI escape codes for color works, yet tput does not.
		# This may be caused by tput not being able to determine the terminal type.
		message="$(eval echo \$$color)${message}${reset}"
	fi
	if [ ${send_to_stderr} == true ]; then
		echo -e "${message}" >&2
	else
		echo -e "${message}"
	fi
}

# Echo a warning message.
# Usage: echo_warning message
function echo_warning()
{
	message=${1}
	echo_message "${message}" yellow true
}

# Temporary defaults. In use until overriden by the configuration file.
send_in_color=false
send_to_syslog=false
verbose=false

# NOTE: This requires GNU getopt. On Mac OS X and FreeBSD, you have to install this separately.
ARGS=$(getopt -o h -l help,version -n ${script_name} -- "${@}")
if [ ${?} != 0 ]; then
	exit 1
fi

# The quotes around "${ARGS}" are necessary.
eval set -- "${ARGS}"

# Parse the command line arguments.
while true; do
	case "${1}" in
		-h | --help)
			echo_usage
			exit 0
			;;
		--version)
			echo "${script_version}"
			exit 0
			;;
		--)
			shift
			break
			;;
	esac
done
while [ ${#} -gt 0 ]; do
	if [ -z "${configuration_file}" ]; then
		configuration_file=${1}
	else
		echo_error "Invalid argument: ${1}"
		echo_usage
		exit 1
	fi
	shift
done
if [ -z "${configuration_file}" ]; then
	echo_error "configuration-file not specified."
	echo_usage
	exit 1
fi

# Smoke test of configuration file.
if [ ! -f ${configuration_file} ]; then
	echo_error_and_exit "Missing configuration file."
fi
jq -er '.' ${configuration_file} > /dev/null
if [ ${?} -ne 0 ]; then
	echo_error_and_exit "Errors in configuration file."
fi
configuration_file=$(realpath ${configuration_file})

send_in_color=$(jq -er '.messages.send_in_color' ${configuration_file})
send_to_syslog=$(jq -er '.messages.send_to_syslog' ${configuration_file})
verbose=$(jq -er '.messages.verbose' ${configuration_file})

owner_user=$(jq -er '.archive.ownership.user' ${configuration_file})
owner_group=$(jq -er '.archive.ownership.group' ${configuration_file})
dir_permissions=$(jq -er '.archive.permissions.directory' ${configuration_file})
file_permissions=$(jq -er '.archive.permissions.file' ${configuration_file})

[ ${verbose} == true ] && echo_info "Starting backup ..."

archive_base_dir=$(jq -er '.archive.directory' ${configuration_file})
[ ${verbose} == true ] && echo_info "Changing to directory ${archive_base_dir} ..."
cd ${archive_base_dir}
if [ ${?} -ne 0 ]; then
	echo_error_and_exit "Error changing to directory ${archive_base_dir}"
fi

archive_name=$(date +%FT%H-%M-%S%z)
archive_dir=${archive_name}
[ ${verbose} == true ] && echo_info "Creating directory ${archive_dir} ..."
mkdir ${archive_dir}
if [ ${?} -ne 0 ]; then
	echo_error_and_exit "Error creating directory ${archive_dir}"
fi

manifest_file=${archive_dir}/manifest.txt
[ ${verbose} == true ] && echo_info "Creating file ${manifest_file} ..."
echo "Manifest for backup ${archive_name}" > ${manifest_file}

# For each file to backup ...
file_count=$(jq -er '.backup.files | length' ${configuration_file})
for file_index in $(seq 0 $(expr ${file_count} - 1)); do
	file=$(jq -er '.backup.files['${file_index}']' ${configuration_file})
	backup_file ${file}
done

# For each directory to backup ...
directory_count=$(jq -er '.backup.directories | length' ${configuration_file})
for directory_index in $(seq 0 $(expr ${directory_count} - 1)); do
	directory=$(jq -er '.backup.directories['${directory_index}']' ${configuration_file})
	backup_directory ${directory}
done

[ ${verbose} == true ] && echo_info "Changing ownership of directory ${archive_dir} ..."
sudo chown -R ${owner_user}:${owner_group} ${archive_dir}
if [ ${?} -ne 0 ]; then
	echo_error_and_exit "Error changing ownership of directory ${archive_dir}"
fi

[ ${verbose} == true ] && echo_info "Changing permissions of directories in ${archive_dir} ..."
sudo find ${archive_dir} -type d -exec chmod ${dir_permissions} '{}' \;
if [ ${?} -ne 0 ]; then
	echo_error_and_exit "Error changing permissions of directories in ${archive_dir}"
fi

[ ${verbose} == true ] && echo_info "Changing permissions of files in ${archive_dir} ..."
sudo find ${archive_dir} -type f -exec chmod ${file_permissions} '{}' \;
if [ ${?} -ne 0 ]; then
	echo_error_and_exit "Error changing permissions of files in ${archive_dir}"
fi

tar_file=${archive_dir}.tar.gz
[ ${verbose} == true ] && echo_info "Archiving ${archive_dir} to ${tar_file} ..."
tar -zcf ${tar_file} ${archive_dir}
if [ ${?} -ne 0 ]; then
	echo_error_and_exit "Error creating file ${tar_file}"
fi

[ ${verbose} == true ] && echo_info "Changing permissions of file ${tar_file} ..."
chmod ${file_permissions} ${tar_file}
if [ ${?} -ne 0 ]; then
	echo_error_and_exit "Error changing permissions of file ${tar_file}"
fi

[ ${verbose} == true ] && echo_info "Removing directory ${archive_dir} ..."
rm -rf ${archive_dir}
if [ ${?} -ne 0 ]; then
	echo_error_and_exit "Error removing directory ${archive_dir}"
fi

[ ${verbose} == true ] && echo_info "Backup complete."

exit 0
