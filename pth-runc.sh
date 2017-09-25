#!/bin/bash

# About runc specs
# https://github.com/opencontainers/runtime-spec/blob/master/specs-go/config.go

DOCKER_SOCK=${DOCKER_SOCK:=/var/run/docker.sock}
DOCKER_API_VERSION=${DOCKER_API_VERSION:=v1.23}
DOCKER_URL=${DOCKER_URL:=http://localhost/${DOCKER_API_VERSION}}
CURL="curl -s --unix-socket ${DOCKER_SOCK}"

CONTAINER_ID="$1"
HOSTNAME="$2"
basedir="/tmp/pth"

response=$($CURL ${DOCKER_URL}/info)
if [[ -z "$response" ]]; then
	echo "no response"
	exit 1
fi
echo "$response" | jq . > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
	echo "$response"
	exit 1
fi

response=$($CURL ${DOCKER_URL}/containers/${CONTAINER_ID}/json)
if [[ -z "$response" ]]; then
	echo "no response"
	exit 1
fi
echo "$response" | jq . > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
	echo "$response"
	exit 1
fi

function get_container_rootfs {
	local json="$1"

	case "$(echo "$json" | jq -r .GraphDriver.Name)" in
	    overlay)
			mount_option=$(echo "$json" | jq -r '.GraphDriver.Data | "lowerdir=\(.LowerDir),upperdir=\(.UpperDir),workdir=\(.WorkDir)"')
			echo -n "overlay / overlay "
			echo "$json" | jq -r '.GraphDriver.Data | "lowerdir=\(.LowerDir),upperdir=\(.UpperDir),workdir=\(.WorkDir)"'
			;;
		devicemapper)
			devicename=$(echo "$json" | jq -r .GraphDriver.Data.DeviceName)
			while read line
			do
				set -- $line
				if [[ "$1" == "$devicename" ]]; then
					echo "${devicename} / bind bind"
					break
				fi
			done < /proc/mounts
			;;
		*)
			echo "rootfs type not suported"
			exit 1
			;;
	esac
}

function get_mountinfo {
	local json="$response"

	get_container_rootfs "$response"
	echo "$json" | jq -r '.Mounts[] | select(.Destination != "/dev/termination-log" and (.Type == "bind" or .Type == null )) | "\(.Source) \(.Destination) bind bind"'
	echo "$json" | jq -r '"\(.ResolvConfPath) /etc/resolv.conf bind bind\n\(.HostnamePath) /etc/hostname bind bind"'

	echo ${HOSTNAME} > ${basedir}/hostname
	echo "$json" | jq -r '"\(.ResolvConfPath) __POD__/etc/resolv.conf bind bind"'
	echo "${basedir}/hostname __POD__/etc/hostname bind bind"
}

function format_mountinfo {
	comma=""
	if [[ -d "${basedir}/node_root" ]]; then
		node_root="${basedir}/node_root/"
	fi

	echo '['
	while read line
	do
		set -- $line
		if [[ "$2" =~ ^/ ]]; then
			dest="/container${2}"
		elif [[ "$2" =~ ^__POD__(.*) ]]; then
			node_root=""
			dest=${BASH_REMATCH[1]}
		fi
		cat << __EOT__
	$comma
	{
		"destination": "$dest",
		"type": "$3",
		"source": "${node_root}$1",
		"options": ["$4"]
	}
__EOT__
		comma=","
	done
	echo ']'
}

function set_capabilities {
	local json="$1"

	capabilities="{}"
	cap=$(cat ${basedir}/config.json | jq '.process.capabilities.bounding + ["CAP_SYS_ADMIN", "CAP_NET_ADMIN", "CAP_NET_RAW", "CAP_SETGID", "CAP_SETUID", "CAP_SYS_PTRACE", "CAP_SYS_CHROOT", "CAP_MKNOD", "CAP_DAC_READ_SEARCH"]')

	for key in $(cat ${basedir}/config.json | jq -r '.process.capabilities | keys[]')
	do
		tmp=$(cat << __EOT__
	{
		"$key": ${cap}
	}
__EOT__
		)
		capabilities=$(echo ${capabilities} | jq ". + ${tmp}")
	done

	config=$(cat ${basedir}/config.json | jq ".process.capabilities = $capabilities")
	echo "$config" > ${basedir}/config.json
} 

function set_namespace {
	local json="$1"
	pid=$(echo "$json" | jq -r .State.Pid)

    ns=$(cat <<__EOT__
[
	{
		"type": "pid",
		"path": "/proc/${pid}/ns/pid"
	},
	{
		"type": "network",
		"path": "/proc/${pid}/ns/net"
	},
	{
		"type": "ipc",
		"path": "/proc/${pid}/ns/ipc"
	},
	{
		"type": "uts"
	},
	{
		"type": "mount"
	}
]
__EOT__
)
	config=$(cat ${basedir}/config.json | jq ".linux.namespaces = $ns")
	echo "$config" > ${basedir}/config.json
}

function set_environ {
	local json="$1"
	environ=$(echo "$json" | jq '.Config.Env + ["TERM=xterm"]')

	config=$(cat ${basedir}/config.json | jq ".process.env = $environ")
	echo "$config" > ${basedir}/config.json
}

function set_readonlypaths {
	config=$(cat ${basedir}/config.json | jq '.linux.readonlyPaths |= .- ["/proc/sys"]')
	for dir in /proc/sys/*
	do
		[[ "$dir" == "/proc/sys/vm" ]] && continue
		config=$(echo "$config" | jq ".linux.readonlyPaths |= .+ [\"$dir\"]")
	done
	echo "$config" > ${basedir}/config.json
}

function set_args {
	args=$(cat <<__EOT__
[
  "/bin/bash"
]
__EOT__
)
	config=$(cat ${basedir}/config.json | jq ".process.args = $args")
	echo "$config" > ${basedir}/config.json
}


rootdir=${basedir}/rootfs

mkdir -p ${rootdir}
rm -f /tmp/config.json

mount --bind / ${rootdir}
mkdir -p ${rootdir}/container

runc spec -b /tmp
cat /tmp/config.json | jq ".hostname = \"${HOSTNAME}\"" | jq ".mounts |= . + $(get_mountinfo "$response" | format_mountinfo)" | jq '.root.readonly = false' > ${basedir}/config.json
rm -f /tmp/config.json

set_capabilities "$response"
set_namespace "$response"
set_environ "$response"
set_readonlypaths
set_args

runc run -b ${basedir} pth-${CONTAINER_ID}

umount ${rootdir}

