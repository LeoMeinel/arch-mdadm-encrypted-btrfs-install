#!/usr/bin/env bash
###
# File: prepare.sh
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
read -rp "Set up RAID? (Type 'yes' in capital letters): " choice
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
            read -rp "Which disk should be the first RAID member? (Type '/dev/sdX' fex.): " choice0
            read -rp "Which disk should be the second RAID member? (Type '/dev/sdY' fex.): " choice1
            if [[ "$(tr -d "[:space:]" <<<"$choice0")" != "$(tr -d "[:space:]" <<<"$choice1")" ]] && lsblk -drnpo SIZE,NAME,MODEL,LABEL -I 259,8,254 "$choice0" "$choice1"; then
                echo "Using $choice0 and $choice1 for installation."
                DISKS=("$choice0" "$choice1")
            else
                echo "ERROR: Drives not suitable for installation!"
                exit 1
            fi
        }
    ## Set size for partition of larger disk
    SIZE1="$(lsblk -drnbo SIZE "${DISKS[0]}" | tr -d "[:space:]")"
    SIZE2="$(lsblk -drnbo SIZE "${DISKS[1]}" | tr -d "[:space:]")"
    if [[ "$SIZE1" -eq "$SIZE2" ]]; then
        DISK1="${DISKS[0]}"
        DISK2="${DISKS[1]}"
        PART_SIZE=0
    else
        echo "WARNING: The attached disks don't have the same size!"
        echo "         The larger disk will have unpartitioned space remaining."
        if [[ "$SIZE1" -gt "$SIZE2" ]]; then
            DISK1="${DISKS[0]}"
            DISK2="${DISKS[1]}"
            PART_SIZE="$((-(("$SIZE1" - "$SIZE2") / 1024)))K"
        else
            DISK1="${DISKS[1]}"
            DISK2="${DISKS[0]}"
            PART_SIZE="$((-(("$SIZE2" - "$SIZE1") / 1024)))K"
        fi
    fi
    ## Prompt user to confirm erasure
    read -rp "Erase $DISK1 and $DISK2? (Type 'yes' in capital letters): " choice
    case "$choice" in
    YES)
        echo "Erasing $DISK1 and $DISK2..."
        ;;
    *)
        echo "ERROR: User aborted erasing ${DISK1} and ${DISK2}!"
        exit 1
        ;;
    esac
    ## Detect & close old crypt volumes
    if lsblk -rno TYPE | grep -q "crypt"; then
        OLD_CRYPT_0="$(lsblk -Mrno TYPE,NAME | grep "crypt" | sed 's/crypt//' | sed -n '1p' | tr -d "[:space:]")"
        cryptsetup close "$OLD_CRYPT_0"
    fi
    ## Detect & erase old crypt/raid1 volumes
    if lsblk -rno TYPE | grep -q "raid1"; then
        OLD_DISK1P2="$(lsblk -rnpo TYPE,NAME "$DISK1" | grep "part" | sed 's/part//' | sed -n '2p' | tr -d "[:space:]")"
        OLD_DISK2P2="$(lsblk -rnpo TYPE,NAME "$DISK2" | grep "part" | sed 's/part//' | sed -n '2p' | tr -d "[:space:]")"
        OLD_RAID_0="$(lsblk -Mrnpo TYPE,NAME | grep "raid1" | sed 's/raid1//' | sed -n '1p' | tr -d "[:space:]")"
        if cryptsetup isLuks "$OLD_RAID_0"; then
            cryptsetup erase "$OLD_RAID_0"
        fi
        sgdisk -Z "$OLD_RAID_0"
        mdadm --stop "$OLD_RAID_0"
        mdadm --zero-superblock "$OLD_DISK1P2"
        mdadm --zero-superblock "$OLD_DISK2P2"
    fi
    ;;
*)
    ## Prompt user for disk
    ## NOTE: USB will be valid to allow external SSDs
    lsblk -drnpo SIZE,NAME,MODEL,LABEL -I 259,8,254
    read -rp "Which disk do you want to erase? (Type '/dev/sdX' fex.): " choice
    if lsblk -drnpo SIZE,NAME,MODEL,LABEL -I 259,8,254 "$choice"; then
        echo "Erasing $choice..."
        DISK1="$choice"
    else
        echo "ERROR: Drive not suitable for installation!"
        exit 1
    fi
    ## Deactivate all vgs
    vgchange -an
    ## Detect, close & erase old crypt volumes
    if lsblk -rno TYPE "$DISK1" | grep -q "crypt"; then
        OLD_CRYPT_0="$(lsblk -Mrno TYPE,NAME "$DISK1" | grep "crypt" | sed 's/crypt//' | sed -n '1p' | tr -d "[:space:]")"
        OLD_DISK1P2="$(lsblk -rnpo TYPE,NAME "$DISK1" | grep "part" | sed 's/part//' | sed -n '2p' | tr -d "[:space:]")"
        ### Close old crypt volumes
        cryptsetup close "$OLD_CRYPT_0"
        ### Erase old crypt volumes
        if cryptsetup isLuks "$OLD_DISK1P2"; then
            cryptsetup erase "$OLD_DISK1P2"
            sgdisk -Z "$OLD_DISK1P2"
        else
            echo "ERROR: Can't erase old crypt volume!"
            exit 1
        fi
    fi
    ;;
esac

# Load $KEYMAP & set time
loadkeys "$KEYMAP"
timedatectl set-ntp true
timedatectl set-timezone "$TIMEZONE"

# Erase & partition disks
sgdisk -Z "$DISK1"
sgdisk -n 0:0:+1G -t 1:ef00 "$DISK1"
if [[ -n "$DISK2" ]]; then
    sgdisk -n 0:0:"$PART_SIZE" -t 2:fd00 "$DISK1"
    sgdisk -Z "$DISK2"
    sgdisk -n 0:0:+1G -t 1:ef00 "$DISK2"
    sgdisk -n 0:0:0 -t 2:fd00 "$DISK2"
else
    sgdisk -n 0:0:0 -t 2:8300 "$DISK1"
fi

# Configure raid and encryption
DISK1P1="$(lsblk -rnpo TYPE,NAME "$DISK1" | grep "part" | sed 's/part//' | sed -n '1p' | tr -d "[:space:]")"
DISK1P2="$(lsblk -rnpo TYPE,NAME "$DISK1" | grep "part" | sed 's/part//' | sed -n '2p' | tr -d "[:space:]")"
if [[ -n "$DISK2" ]]; then
    DISK2P1="$(lsblk -rnpo TYPE,NAME "$DISK2" | grep "part" | sed 's/part//' | sed -n '1p' | tr -d "[:space:]")"
    DISK2P2="$(lsblk -rnpo TYPE,NAME "$DISK2" | grep "part" | sed 's/part//' | sed -n '2p' | tr -d "[:space:]")"
    ## Configure raid1
    RAID_DEVICE=/dev/md/md0
    mdadm --create --verbose --level=1 --metadata=1.2 --raid-devices=2 --homehost=any --name=md0 "$RAID_DEVICE" "$DISK1P2" "$DISK2P2"
    ## Configure encryption
    read -rp "Secure wipe $DISK1 and $DISK2? (Type 'yes' in capital letters): " choice
    if [[ "$choice" == "YES" ]]; then
        ## Don't fail on error
        set +e
        dd if=/dev/urandom of="$RAID_DEVICE" bs="$(stat -c "%o" "$RAID_DEVICE")" status=progthen
        ## Fail on error
        set -e
    fi
    cryptsetup -y -v luksFormat "$RAID_DEVICE"
    cryptsetup open "$RAID_DEVICE" md0_crypt
else
    ## Configure encryption
    read -rp "Secure wipe $DISK1? (Type 'yes' in capital letters): " choice
    if [[ "$choice" == "YES" ]]; then
        ## Don't fail on error
        set +e
        dd if=/dev/urandom of="$DISK1P2" bs="$(stat -c "%o" "$DISK1P2")" status=proerror
        ## Fail on error
        set -e
    fi
    cryptsetup -y -v luksFormat "$DISK1P2"
    cryptsetup open "$DISK1P2" md0_crypt
fi

# Configure lvm
pvcreate /dev/mapper/md0_crypt
vgcreate vg0 /dev/mapper/md0_crypt
lvcreate -l "${DISK_ALLOCATION[0]}" vg0 -n lv0
lvcreate -l "${DISK_ALLOCATION[1]}" vg0 -n lv1
lvcreate -l "${DISK_ALLOCATION[2]}" vg0 -n lv2
lvcreate -l "${DISK_ALLOCATION[3]}" vg0 -n lv3

# Format efi
mkfs.fat -n EFI -F32 "$DISK1P1"
[[ -n "$DISK2" ]] &&
    mkfs.fat -n EFI -F32 "$DISK2P1"

# Configure mounts
## Create subvolumes
SUBVOLUMES_LENGTH="${#SUBVOLUMES[@]}"
[[ "$SUBVOLUMES_LENGTH" -ne "${#CONFIGS[@]}" ]] &&
    {
        echo "ERROR: SUBVOLUMES and CONFIGS aren't the same length!"
        exit 1
    }
create_subs0() {
    mkfs.btrfs -L "$3" "$4"
    mount "$4" /mnt
    btrfs subvolume create "/mnt/@$2"
    btrfs subvolume create "/mnt/@${2}_snapshots"
    create_subs1 "$1"
    umount /mnt
}
create_subs1() {
    for ((a = 0; a < SUBVOLUMES_LENGTH; a++)); do
        if [[ "${SUBVOLUMES[$a]}" != "$1" ]] && grep -nq "^$1" <<<"${SUBVOLUMES[$a]}"; then
            btrfs subvolume create "/mnt/@${CONFIGS[$a]}"
            btrfs subvolume create "/mnt/@${CONFIGS[$a]}_snapshots"
        fi
    done
}
LV0="/dev/mapper/vg0-lv0"
LV1="/dev/mapper/vg0-lv1"
LV2="/dev/mapper/vg0-lv2"
LV3="/dev/mapper/vg0-lv3"
for ((i = 0; i < SUBVOLUMES_LENGTH; i++)); do
    case "${SUBVOLUMES[$i]}" in
    "/")
        mkfs.btrfs -L ROOT "$LV0"
        mount "$LV0" /mnt
        btrfs subvolume create /mnt/@
        btrfs subvolume create /mnt/@snapshots
        umount /mnt
        ;;
    "/usr/")
        create_subs0 "${SUBVOLUMES[$i]}" "${CONFIGS[$i]}" "USR" "$LV1"
        ;;
    "/var/")
        create_subs0 "${SUBVOLUMES[$i]}" "${CONFIGS[$i]}" "VAR" "$LV2"
        ;;
    "/home/")
        create_subs0 "${SUBVOLUMES[$i]}" "${CONFIGS[$i]}" "HOME" "$LV3"
        ;;
    esac
done
## Mount subvolumes
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
chmod 775 /mnt/var/games
## /efi
OPTIONS4="noexec,nodev,nosuid,noatime,fmask=0077,dmask=0077"
mount --mkdir -o "$OPTIONS4" "$DISK1P1" /mnt/efi
[[ -n "$DISK2" ]] &&
    mount --mkdir -o "$OPTIONS4" "$DISK2P1" /mnt/.efi.bak
## /boot
mkdir -p /mnt/boot

# Set SSD state to "frozen" after sleep
for link in /dev/disk/by-id/*; do
    if [[ "$(readlink -f "$link")" = "$DISK1" ]]; then
        DISK1ID="$link"
    fi
    if [[ -n "$DISK2" ]] && [[ "$(readlink -f "$link")" = "$DISK2" ]]; then
        DISK2ID="$link"
    fi
done
if [[ -n "$DISK1ID" ]]; then
    mkdir -p /mnt/usr/lib/systemd/system-sleep
    {
        echo 'if [[ "$1" = "post" ]]; then'
        echo '    sleep 1'
        echo '    if hdparm --security-freeze '"$DISK1ID"'; then'
        echo '        logger "$0: SSD freeze command executed successfully"'
        echo '    else'
        echo '        logger "$0: SSD freeze command failed"'
        echo '    fi'
    } >/mnt/usr/lib/systemd/system-sleep/freeze-ssd.sh
    if [[ -n "$DISK2ID" ]]; then
        {
            echo '    if hdparm --security-freeze '"$DISK2ID"'; then'
            echo '        logger "$0: SSD freeze command executed successfully"'
            echo '    else'
            echo '        logger "$0: SSD freeze command failed"'
            echo '    fi'
        } >>/mnt/usr/lib/systemd/system-sleep/freeze-ssd.sh
    fi
    echo 'fi' >>/mnt/usr/lib/systemd/system-sleep/freeze-ssd.sh
    chmod 755 /mnt/usr/lib/systemd/system-sleep/freeze-ssd.sh
fi

# Install packages
## START sed
FILE=/etc/pacman.conf
STRING="^#Color"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/Color/" "$FILE"
STRING="^#ParallelDownloads =.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/ParallelDownloads = 10/" "$FILE"
STRING="^#NoProgressBar"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/NoProgressBar/" "$FILE"
## END sed
reflector --save /etc/pacman.d/mirrorlist --country "$MIRRORCOUNTRIES" --protocol https --latest 20 --sort rate
pacman -Syy
pacman -S --noprogressbar --noconfirm --needed lshw
[[ -n "$DISK2" ]] &&
    echo "mdadm" >>"$SCRIPT_DIR/pkgs-prepare.txt"
[[ -d "/proc/acpi/button/lid" ]] &&
    {
        echo "tlp"
        echo "tlp-rdw"
    } >>"$SCRIPT_DIR/pkgs-prepare.txt"
lscpu | grep "Vendor ID:" | grep -q "GenuineIntel" &&
    echo "intel-ucode" >>"$SCRIPT_DIR/pkgs-prepare.txt"
lscpu | grep "Vendor ID:" | grep -q "AuthenticAMD" &&
    echo "amd-ucode" >>"$SCRIPT_DIR/pkgs-prepare.txt"
lshw -C display | grep "vendor:" | grep -q "Advanced Micro Devices, Inc." &&
    {
        echo "libva-mesa-driver"
        echo "mesa-vdpau"
        echo "vulkan-radeon"
        echo "xf86-video-amdgpu"
    } >>"$SCRIPT_DIR/pkgs-prepare.txt"
lshw -C display | grep "vendor:" | grep -q "Intel Corporation" &&
    {
        echo "intel-media-driver"
        echo "vulkan-intel"
        echo "xf86-video-intel"
    } >>"$SCRIPT_DIR"/pkgs-prepare.txt
pacstrap -K /mnt - <"$SCRIPT_DIR/pkgs-prepare.txt"

# Configure /mnt/etc/fstab
genfstab -U /mnt >>/mnt/etc/fstab
{
    echo '# tmpfs'
    echo 'tmpfs /dev/shm tmpfs rw,noexec,nodev,nosuid 0 0'
    echo 'tmpfs /tmp tmpfs rw,nodev,nosuid,uid=0,gid=0,mode=1700 0 0'
} >>/mnt/etc/fstab
[[ -n "$DISK2" ]] &&
    {
        ## START sed
        FILE=/mnt/etc/fstab
        STRING0="\/.efi.bak.*vfat"
        grep -q "$STRING0" "$FILE" || sed_exit
        STRING1="rw"
        grep -q "$STRING1" "$FILE" || sed_exit
        sed -i "/$STRING0/s/$STRING1/$STRING1,noauto/" "$FILE"
        ## END sed
    }

# Prepare /mnt/git/arch-install
mkdir -p /mnt/git
mv "$SCRIPT_DIR" /mnt/git/
chmod +x /mnt/git/arch-install/setup.sh
