#!/usr/bin/env bash
###
# File: rescue-mount.sh
# Author: Leopold Meinel (leo@meinel.dev)
# -----
# Copyright (c) 2024 Leopold Meinel & contributors
# SPDX ID: GPL-3.0-or-later
# URL: https://www.gnu.org/licenses/gpl-3.0-standalone.html
# -----
###

# Source config
SCRIPT_DIR="$(dirname -- "$(readlink -f -- "$0")")"
source "$SCRIPT_DIR/install.conf"

# Fail on error
set -e

# Define functions
sed_exit() {
    echo "ERROR: 'sed' didn't replace, report this @"
    echo "       https://github.com/leomeinel/arch-install/issues"
    exit 1
}

# Unmount everything from /mnt
mountpoint -q /mnt &&
    umount -AR /mnt

# Prompt user for RAID
read -rp "Use RAID? (Type 'yes' in capital letters): " choice
case "$choice" in
YES)
    ## Detect disks
    readarray -t DISKS < <(lsblk -drnpo NAME -I 259,8,254 | tr -d "[:blank:]")
    DISKS_LENGTH="${#DISKS[@]}"
    for ((i = 0; i < DISKS_LENGTH; i++)); do
        udevadm info -q property --property=ID_BUS --value "${DISKS[$i]}" | grep -q "usb" &&
            {
                unset 'DISKS[$i]'
                continue
            }
        DISKS=("${DISKS[@]}")
    done
    [[ "${#DISKS[@]}" -lt 2 ]] &&
        {
            echo "ERROR: There are less than 2 disks attached!"
            exit 1
        }
    [[ "${#DISKS[@]}" -gt 2 ]] &&
        {
            echo "WARNING: There are more than 2 disks attached!"
            lsblk -drnpo SIZE,NAME,MODEL,LABEL -I 259,8,254
            ### Prompt user to select 2 RAID members
            read -rp "Which disk is the first RAID member? (Type '/dev/sdX' fex.): " choice0
            read -rp "Which disk is the second RAID member? (Type '/dev/sdY' fex.): " choice1
            if [[ "$(tr -d "[:space:]" <<<"$choice0")" != "$(tr -d "[:space:]" <<<"$choice1")" ]] && lsblk -drnpo SIZE,NAME,MODEL,LABEL -I 259,8,254 "$choice0" "$choice1"; then
                echo "Using $choice0 and $choice1 for rescue-system."
                DISKS=("$choice0" "$choice1")
            else
                echo "ERROR: Drives not suitable for rescue-system!"
                exit 1
            fi
        }
    ## Set disks
    DISK1="${DISKS[0]}"
    DISK2="${DISKS[1]}"
    ## Prompt user to confirm selection
    read -rp "Use $DISK1 and $DISK2? (Type 'yes' in capital letters): " choice
    case "$choice" in
    YES)
        echo "Using $DISK1 and $DISK2..."
        ;;
    *)
        echo "ERROR: User aborted using ${DISK1} and ${DISK2}!"
        exit 1
        ;;
    esac
    ;;
*)
    ## Prompt user for disk
    ## NOTE: USB will be valid to allow external SSDs
    lsblk -drnpo SIZE,NAME,MODEL,LABEL -I 259,8,254
    read -rp "Which disk do you want to use? (Type '/dev/sdX' fex.): " choice
    if lsblk -drnpo SIZE,NAME,MODEL,LABEL -I 259,8,254 "$choice"; then
        echo "Using $choice..."
        DISK1="$choice"
    else
        echo "ERROR: Drive not suitable for rescue-system!"
        exit 1
    fi
    ;;
esac

# Configure raid and encryption
DISK1P1="$(lsblk -rnpo TYPE,NAME "$DISK1" | grep "part" | sed 's/part//' | sed -n '1p' | tr -d "[:space:]")"
DISK1P2="$(lsblk -rnpo TYPE,NAME "$DISK1" | grep "part" | sed 's/part//' | sed -n '2p' | tr -d "[:space:]")"
if [[ -n "$DISK2" ]]; then
    DISK2P1="$(lsblk -rnpo TYPE,NAME "$DISK2" | grep "part" | sed 's/part//' | sed -n '1p' | tr -d "[:space:]")"
    DISK2P2="$(lsblk -rnpo TYPE,NAME "$DISK2" | grep "part" | sed 's/part//' | sed -n '2p' | tr -d "[:space:]")"
    ## Configure raid1
    RAID_DEVICE=/dev/md/md0
    ## Configure encryption
    cryptsetup open "$RAID_DEVICE" md0_crypt
else
    ## Configure encryption
    cryptsetup open "$DISK1P2" md0_crypt
fi

## Mount subvolumes
SUBVOLUMES_LENGTH="${#SUBVOLUMES[@]}"
LV0="/dev/mapper/vg0-lv0"
LV1="/dev/mapper/vg0-lv1"
LV2="/dev/mapper/vg0-lv2"
LV3="/dev/mapper/vg0-lv3"
OPTIONS0="noatime,space_cache=v2,compress=zstd,ssd,discard=async,subvol=/@"
OPTIONS1="nodev,noatime,space_cache=v2,compress=zstd,ssd,discard=async,subvol=/@"
OPTIONS2="nodev,nosuid,noatime,space_cache=v2,compress=zstd,ssd,discard=async,subvol=/@"
OPTIONS3="noexec,nodev,nosuid,noatime,space_cache=v2,compress=zstd,ssd,discard=async,subvol=/@"
mount_subs0() {
    mount --mkdir -o "$3$2" "$4" "/mnt$1"
    mount --mkdir -o "$OPTIONS3${2}_snapshots" "$4" "/mnt$1.snapshots"
    mount_subs1 "$1" "$3" "$4"
}
mount_subs1() {
    for ((a = 0; a < SUBVOLUMES_LENGTH; a++)); do
        if [[ "${SUBVOLUMES[$a]}" != "$1" ]] && grep -nq "^$1" <<<"${SUBVOLUMES[$a]}"; then
            if grep -nq "^${1}lib/" <<<"${SUBVOLUMES[$a]}" && ! grep -nq "^${1}lib/flatpak/" <<<"${SUBVOLUMES[$a]}"; then
                mount --mkdir -o "$OPTIONS3${CONFIGS[$a]}" "$3" "/mnt${SUBVOLUMES[$a]}"
            else
                mount --mkdir -o "$2${CONFIGS[$a]}" "$3" "/mnt${SUBVOLUMES[$a]}"
            fi
            mount --mkdir -o "$OPTIONS3${CONFIGS[$a]}_snapshots" "$3" "/mnt${SUBVOLUMES[$a]}.snapshots"
        fi
    done
}
for ((i = 0; i < SUBVOLUMES_LENGTH; i++)); do
    case "${SUBVOLUMES[$i]}" in
    "/")
        mount -o "$OPTIONS0" "$LV0" "/mnt${SUBVOLUMES[$i]}"
        mount --mkdir -o "${OPTIONS3}snapshots" "$LV0" "/mnt${SUBVOLUMES[$i]}.snapshots"
        ;;
    "/usr/")
        mount_subs0 "${SUBVOLUMES[$i]}" "${CONFIGS[$i]}" "$OPTIONS1" "$LV1"
        ;;
    "/var/")
        mount_subs0 "${SUBVOLUMES[$i]}" "${CONFIGS[$i]}" "$OPTIONS2" "$LV2"
        ;;
    "/home/")
        mount_subs0 "${SUBVOLUMES[$i]}" "${CONFIGS[$i]}" "$OPTIONS2" "$LV3"
        ;;
    esac
done
## /efi
OPTIONS4="noexec,nodev,nosuid,noatime,fmask=0077,dmask=0077"
mount --mkdir -o "$OPTIONS4" "$DISK1P1" /mnt/efi
[[ -n "$DISK2" ]] &&
    mount --mkdir -o "$OPTIONS4" "$DISK2P1" /mnt/.efi.bak

# Inform user how to use arch-chroot
echo "INFO: To enter the rescue-system, execute the following:"
echo "          > arch-chroot /mnt"
