#!/usr/bin/env bash

set -euo pipefail

GIT_ROOT=$(git rev-parse --show-toplevel)
BASE_IMG_DIR="$GIT_ROOT/images/base"
WORK_IMG_DIR="$GIT_ROOT/images/workdir"
CONFIG_DIR="$GIT_ROOT/config"

declare -A IMAGES=(
    ["ubuntu-jammy"]="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img 0b88d22f32e3f076b0884d60dfa4753f"
    ["amazonlinux2"]="https://cdn.amazonlinux.com/al2023/os-images/2023.4.20240513.0/kvm/al2023-kvm-2023.4.20240513.0-kernel-6.1-x86_64.xfs.gpt.qcow2 ba335f9d4d9c1638a78301f90ef514a3"
)

declare -A WORKLOADS=(
    ["apache"]="80:8080"
    ["nginx"]="80:8080"
    ["mysql"]="3306:3306"
    ["postgres"]="5432:5432"
    ["redis"]="6379:6379"
    ["memcached"]="11211:11211"
    ["all"]="80:8080"
)

declare -a ACTIONS=(
    "setup"
    "first"
    "test"
    "trace"
    "all"
)

usage() {
    echo "Usage: $0 <image_name> <workload> <action>"
    echo "Supported images: ${!IMAGES[@]}"
    echo "Supported workloads: ${!WORKLOADS[@]}"
    echo "Supported actions: ${ACTIONS[@]}"
    exit 1
}

parse_args() {
    if [ $# -lt 3 ]; then
        usage
    fi

    image_name=$1
    workload_name=$2
    action=$3

    if [ -z "${IMAGES[$image_name]}" ]; then
        echo "Unsupported image $image_name"
        usage
    fi

    if [ -z "${WORKLOADS[$workload_name]}" ]; then
        echo "Unsupported workload $workload_name"
        usage
    fi

    if [[ ! "${ACTIONS[@]}" =~ "$action" ]]; then
        echo "Unsupported action $action"
        usage
    fi

    image_info=${IMAGES[$image_name]}
    workload_info=${WORKLOADS[$workload_name]}
    action=$3
}

# download base image
download_image() {
    local image_url=$1
    local image_file=$2

    mkdir -p "$BASE_IMG_DIR"
    if [ ! -f "$image_file" ]; then
        echo "Downloading $image_name"
        curl -L -o "$image_file" "$image_url"
        # make image read-only to prevent accidental modification
        chmod a-w "$image_file"
    else
        echo "Image $image_file already exists"
    fi
}

# verify base image checksum
verify_checksum() {
    local image_path=$1
    local checksum=$2

    echo "Verifying checksum for $image_path"
    echo "$checksum $image_path" | md5sum -c -
}

# copy base image to workdir
copy_to_workdir() {
    local base_image_file=$1
    local work_image_file=$2

    mkdir -p "$WORK_IMG_DIR"
    # if [ -f "$work_image_file" ]; then
    #     echo "Workload image $work_image_file already exists, use -f to overwrite"
    #     return
    # fi

    echo "Copying $base_image_file to $work_image_file"
    cp "$base_image_file" "$work_image_file"
    # make image writable
    chmod a+w "$work_image_file"
}

# resize work image
resize_image() {
    local image_file=$1
    local size=$2

    echo "Resizing $image_file to $size"
    qemu-img resize --shrink "$image_file" "$size"
}

# start imds server
start_imds_server() {
    local config_dir=$1
    local workload_name=$2
    ## FIXME: doesn't work, need to debug
    # echo "Starting IMDS server in $config_dir"
    # python3 -m http.server 8000 --directory "$config_dir" &
    echo "Start the IMDS server using: python3 -m http.server 8000 --directory $config_dir"
    # echo "Press any key to continue"
    # read -n 1 -s
}

# get ssh port, start from 2222 and increment by 1 if not available
get_ssh_port() {
    local port=2222
    while netstat -tuln | grep -q $port; do
        port=$((port + 1))
    done
    echo $port
}

# first run for setting up the workload
first_run() {
    local image_file=$1
    local guest_port=$2
    local host_port=$3
    local ssh_port=$(get_ssh_port)

    echo "Setting up $image_file"
    qemu-system-x86_64 \
        -device virtio-net-pci,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::$ssh_port-:22,hostfwd=tcp::$host_port-:$guest_port \
        -machine accel=kvm,type=q35 \
        -cpu host \
        -m 2G \
        -nographic \
        -no-reboot \
        -hda "$image_file" \
        -smbios type=1,serial=ds="nocloud;s=http://10.0.2.2:8000/"
}

# test run for running the workload
test_run() {
    local image_file=$1
    local workload_name=$2
    local guest_port=$3
    local host_port=$4
    local ssh_port=$(get_ssh_port)

    echo "Running $image_file with $workload_name, access the service at localhost:$host_port"
    qemu-system-x86_64 \
        -device virtio-net-pci,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::$ssh_port-:22,hostfwd=tcp::$host_port-:$guest_port \
        -machine accel=kvm,type=q35 \
        -cpu host \
        -smp 8 \
        -m 8G \
        -nographic \
        -no-reboot \
        -hda "$image_file"
}

# trace run for tracing the workload
trace_run() {
    local image_file=$1
    local workload_name=$2
    local guest_port=$3
    local host_port=$4
    local ssh_port=$(get_ssh_port)

    echo "Tracing $image_file with $workload_name, access the service at localhost:$host_port"
    qemu-system-x86_64 \
        -device virtio-net-pci,netdev=net0 \
        -netdev user,id=net0,hostfwd=tcp::$ssh_port-:22,hostfwd=tcp::$host_port-:$guest_port \
        -machine accel=tcg,type=q35 \
        -cpu host \
        -m 2G \
        -nographic \
        -no-reboot \
        -hda "$image_file" \
        -trace events=events.txt
}

parse_args "$@"

image_url=$(echo "$image_info" | awk '{print $1}')
checksum=$(echo "$image_info" | awk '{print $2}')

base_image_file=$BASE_IMG_DIR/$image_name.img
work_image_file=$WORK_IMG_DIR/$image_name-$workload_name.img
guest_port=$(echo "$workload_info" | awk -F: '{print $1}')
host_port=$(echo "$workload_info" | awk -F: '{print $2}')

if [ "$action" == "setup" ] || [ "$action" == "all" ]; then
    download_image "$image_url" "$base_image_file"
    verify_checksum "$base_image_file" "$checksum"
    copy_to_workdir "$base_image_file" "$work_image_file"
    resize_image "$work_image_file" 10G
fi

if [ "$action" == "first" ] || [ "$action" == "all" ]; then
    start_imds_server "$CONFIG_DIR" "$workload_name"
    first_run "$work_image_file" "$guest_port" "$host_port"
    # create_checkpoint "$work_image_file" #todo
fi

if [ "$action" == "test" ] || [ "$action" == "all" ]; then
    test_run "$work_image_file" "$workload_name" "$guest_port" "$host_port"
fi

if [ "$action" == "trace" ] || [ "$action" == "all" ]; then
    trace_run "$work_image_file" "$workload_name" "$guest_port" "$host_port"
fi
