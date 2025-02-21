#!/bin/bash

# This script does the following:
# zramswap start:
#  Space is assigned to the zram device, then swap is initialized and enabled.
# zramswap stop:
#  Somewhat potentially dangerous, removes zram module at the end

# https://github.com/torvalds/linux/blob/master/Documentation/blockdev/zram.txt

readonly CONFIG="/etc/default/zramswap"

if command -v logger >/dev/null; then
    function elog {
        logger -s "Error: $*"
        exit 1
    }

    function wlog {
        logger -s "$*"
    }
else
    function elog {
        echo "Error: $*"
        exit 1
    }

    function wlog {
        echo "$*"
    }
fi

function start {
    wlog "Starting Zram"

    # Load config
    test -r "${CONFIG}" || wlog "Cannot read config from ${CONFIG} continuing with defaults."
    source "${CONFIG}" 2>/dev/null

    # Set defaults if not specified
    : "${ALGO:=lz4}" "${SIZE:=256}" "${PRIORITY:=100}"

    SIZE=$((SIZE * 1024 * 1024)) # convert amount from MiB to bytes

    # Prefer percent if it is set
    if [ -n "${PERCENT}" ]; then
        readonly TOTAL_MEMORY=$(awk '/MemTotal/{print $2}' /proc/meminfo) # in KiB
        readonly SIZE="$((TOTAL_MEMORY * 1024 * PERCENT / 100))"
    fi

    # Check Zram Class created
    if [ ! -d "/sys/class/zram-control" ]; then
        modprobe zram || elog "inserting the zram kernel module"
        SWAP_DEV='zram0'
    elif [ -b "$(lsblk --noheadings -o name,mountpoints /dev/zram*|awk '$2 == "[SWAP]" {print $1}')" ]; then
        SWAP_DEV="$(lsblk --noheadings -o name,mountpoints /dev/zram*|awk '$2 == "[SWAP]" {print $1}')"
    else
        SWAP_DEV="zram$(cat /sys/class/zram-control/hot_add)"
    fi
    #modprobe zram || elog "inserting the zram kernel module"
    echo -n "${ALGO}" > /sys/block/${SWAP_DEV}/comp_algorithm || elog "setting compression algo to ${ALGO}"
    echo -n "${SIZE}" > /sys/block/${SWAP_DEV}/disksize || elog "setting zram device size to ${SIZE}"
    mkswap "/dev/${SWAP_DEV}" || elog "initialising swap device"
    swapon -p "${PRIORITY}" "/dev/${SWAP_DEV}" || elog "enabling swap device"
}

function status {
    test -x "$(which zramctl)" || elog "install zramctl for this feature"
    SWAP_DEV="/dev/$(lsblk -o name,mountpoints|awk '$2 == "[SWAP]" {print $1}')"
    test -b "${SWAP_DEV}" || elog "${SWAP_DEV} doesn't exist"
    # old zramctl doesn't have --output-all
    #zramctl --output-all
    zramctl "${SWAP_DEV}"
}

function stop {
    wlog "Stopping Zram"
    SWAP_DEV="/dev/$(lsblk -o name,mountpoints|awk '$2 == "[SWAP]" {print $1}')"
    test -b "${SWAP_DEV}" || wlog "${SWAP_DEV} doesn't exist"
    swapoff "${SWAP_DEV}" 2>/dev/null || wlog "disabling swap device: ${SWAP_DEV}"
    echo ${SWAP_DEV} | grep -o -E '[0-9]+' > /sys/class/zram-control/hot_remove
}

function usage {
    cat << EOF

Usage:
    zramswap (start|stop|restart|status)

EOF
}

case "$1" in
    start)      start;;
    stop)       stop;;
    restart)    stop && start;;
    status)     status;;
    "")         usage;;
    *)          elog "Unknown option $1";;
esac
