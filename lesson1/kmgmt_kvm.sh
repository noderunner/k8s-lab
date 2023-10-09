IGNITION_CONFIG="/home/mstevenson/git/k8s-lab/scripts/kmgmt.ign"
IMAGE="$1"
VM_NAME="kmgmt"
VCPUS="4"
RAM_MB="8192"
STREAM="stable"
DISK_GB="20"
NETWORK="bridge=vbr0"
IGNITION_DEVICE_ARG=(--qemu-commandline="-fw_cfg name=opt/com.coreos/config,file=${IGNITION_CONFIG}")

# Setup the correct SELinux label to allow access to the config
chcon --verbose --type svirt_home_t ${IGNITION_CONFIG}

virt-install --connect="qemu:///session" --name="${VM_NAME}" --vcpus="${VCPUS}" --memory="${RAM_MB}" \
        --os-variant="fedora-coreos-$STREAM" --import --graphics=none \
        --disk="size=${DISK_GB},backing_store=${IMAGE}" \
        --network "${NETWORK}" "${IGNITION_DEVICE_ARG[@]}"
