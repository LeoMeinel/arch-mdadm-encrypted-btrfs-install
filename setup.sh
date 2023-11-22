#!/bin/bash
###
# File: setup.sh
# Author: Leopold Meinel (leo@meinel.dev)
# -----
# Copyright (c) 2023 Leopold Meinel & contributors
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

# Add groups & users
## Configure passwords
{
    echo "# passwd defaults from arch-install"
    echo "password required pam_pwquality.so shadowretry=3 minlen=12 difok=6 dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1 enforce_for_root"
    echo "password required pam_unix.so use_authtok shadow"
} >/etc/pam.d/passwd
## FIXME: Add below after support has been implemented
##{
##    echo ""
##    echo "# Custom"
##    echo "YESCRYPT_COST_FACTOR 11"
##} >>/etc/login.defs
## START sed
FILE=/etc/default/useradd
STRING="^SHELL=.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/SHELL=\/bin\/bash/" "$FILE"
## END sed
groupadd -r audit
groupadd -r usbguard
useradd -ms /bin/bash -G adm,audit,log,rfkill,sys,systemd-journal,usbguard,wheel,video "$SYSUSER"
useradd -ms /bin/bash -G docker,video "$DOCKUSER"
useradd -ms /bin/bash -G video "$HOMEUSER"
echo "#################################################################"
echo "#                      _    _           _   _                   #"
echo "#                     / \  | | ___ _ __| |_| |                  #"
echo "#                    / _ \ | |/ _ \ '__| __| |                  #"
echo "#                   / ___ \| |  __/ |  | |_|_|                  #"
echo "#                  /_/   \_\_|\___|_|   \__(_)                  #"
echo "#                                                               #"
echo "#       It is mandatory to choose a password matching the       #"
echo "#                       following specs:                        #"
echo "#                    At least 12 characters,                    #"
echo "#           at least 1 digit, 1 uppercase character,            #"
echo "#         1 lowercace character and 1 other character.          #"
echo "#################################################################"
echo "Enter password for root"
passwd root
echo "Enter password for $SYSUSER"
passwd "$SYSUSER"
echo "Enter password for $DOCKUSER"
passwd "$DOCKUSER"
echo "Enter password for $HOMEUSER"
passwd "$HOMEUSER"

# Setup /etc
rsync -rq "$SCRIPT_DIR/etc/" /etc
## Configure locale in /etc/locale.gen /etc/locale.conf
### START sed
FILE=/etc/locale.gen
for string in "${LANGUAGES[@]}"; do
    grep -q "^#$string" "$FILE" || sed_exit
    sed -i "s/^#$string/$string/" "$FILE"
done
### END sed
chmod 644 /etc/locale.conf
locale-gen
## Configure /etc/doas.conf
chown root:root /etc/doas.conf
chmod 0400 /etc/doas.conf
## Configure pacman hooks in /etc/pacman.d/hooks
{
    echo '#!/bin/sh'
    echo ''
    echo '/usr/bin/firecfg >/dev/null 2>&1'
    echo "/usr/bin/su -c '/usr/bin/rm -rf ~/.local/share/applications/*' $SYSUSER"
    echo "/usr/bin/su -c '/usr/bin/rm -rf ~/.local/share/applications/*' $DOCKUSER"
    echo "/usr/bin/su -c '/usr/bin/rm -rf ~/.local/share/applications/*' $HOMEUSER"
} >/etc/pacman.d/hooks/scripts/70-firejail.sh
DISK1="$(lsblk -npo PKNAME "$(findmnt -no SOURCE --target /efi)" | tr -d "[:space:]")"
DISK1P2="$(lsblk -rnpo TYPE,NAME "$DISK1" | grep "part" | sed 's/part//' | sed -n '2p' | tr -d "[:space:]")"
lsblk -rno TYPE "$DISK1P2" | grep -q "raid1" &&
    {
        {
            echo '[Trigger]'
            echo 'Operation = Install'
            echo 'Operation = Upgrade'
            echo 'Operation = Remove'
            echo 'Type = Path'
            echo 'Target = usr/lib/modules/*/vmlinuz'
            echo ''
            echo '[Action]'
            echo 'Depends = rsync'
            echo 'Description = Backing up /efi...'
            echo 'When = PostTransaction'
            echo "Exec = /bin/sh -c '/etc/pacman.d/hooks/scripts/99-efibackup.sh'"
        } >/etc/pacman.d/hooks/99-efibackup.hook
        {
            echo '#!/bin/sh'
            echo ''
            echo 'set -e'
            echo 'if /usr/bin/mountpoint -q /efi; then'
            echo '    /usr/bin/umount -AR /efi'
            echo 'fi'
            echo 'if /usr/bin/mountpoint -q /.efi.bak; then'
            echo '    /usr/bin/umount -AR /.efi.bak'
            echo 'fi'
            echo '/usr/bin/mount /efi'
            echo '/usr/bin/mount /.efi.bak'
            echo '/usr/bin/rsync -aq --delete --mkpath /.efi.bak/ /.efi.bak.old'
            echo '/usr/bin/rsync -aq --delete --mkpath /efi/ /.efi.bak'
            echo '/usr/bin/umount /.efi.bak'
        } >/etc/pacman.d/hooks/scripts/99-efibackup.sh
    }
chmod 755 /etc/pacman.d/hooks
chmod 755 /etc/pacman.d/hooks/scripts
chmod 644 /etc/pacman.d/hooks/*.hook
chmod 744 /etc/pacman.d/hooks/scripts/*.sh
## Configure /etc/systemd/zram-generator.conf
chmod 644 /etc/systemd/zram-generator.conf
## Configure /etc/sysctl.d
chmod 755 /etc/sysctl.d
chmod 644 /etc/sysctl.d/*
## Configure /etc/systemd/system/snapper-cleanup.timer.d/override.conf
chmod 644 /etc/systemd/system/snapper-cleanup.timer.d/override.conf
## Configure /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf
chmod 644 /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf
## Configure /etc/systemd/network/10-en.network
chmod 644 /etc/systemd/network/10-en.network
## Configure /etc/pacman.conf , /etc/makepkg.conf & /etc/xdg/reflector/reflector.conf
## Configure /etc/pacman.conf /etc/makepkg.conf /etc/xdg/reflector/reflector.conf
{
    echo "--save /etc/pacman.d/mirrorlist"
    echo "--country $MIRRORCOUNTRIES"
    echo "--protocol https"
    echo "--latest 20"
    echo "--sort rate"
} >/etc/xdg/reflector/reflector.conf
chmod 644 /etc/xdg/reflector/reflector.conf
### START sed
FILE=/etc/makepkg.conf
STRING="^#PACMAN_AUTH=.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/PACMAN_AUTH=(doas)/" "$FILE"
###
FILE=/etc/pacman.conf
STRING="^#Color"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/Color/" "$FILE"
STRING="^#ParallelDownloads =.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/ParallelDownloads = 10/" "$FILE"
STRING="^#CacheDir"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/CacheDir/" "$FILE"
### END sed
pacman-key --init
## Update mirrors
reflector --save /etc/pacman.d/mirrorlist --country "$MIRRORCOUNTRIES" --protocol https --latest 20 --sort rate

# Install packages
pacman -Syu --noprogressbar --noconfirm --needed - <"$SCRIPT_DIR/pkgs-setup.txt"
## Install optional dependencies
DEPENDENCIES=""
pacman -Qq "apparmor" >/dev/null 2>&1 &&
    DEPENDENCIES+=$'\npython-notify2'
pacman -Qq "docker" >/dev/null 2>&1 &&
    DEPENDENCIES+=$'\ndocker-scan'
pacman -Qq "libvirt" >/dev/null 2>&1 &&
    DEPENDENCIES+=$'\ndnsmasq'
pacman -Qq "lollypop" >/dev/null 2>&1 &&
    DEPENDENCIES+=$'\ngst-plugins-base\ngst-plugins-good\ngst-libav\neasytag\nkid3-qt'
pacman -Qq "mpv" >/dev/null 2>&1 &&
    DEPENDENCIES+=$'\nyt-dlp'
pacman -Qq "r" >/dev/null 2>&1 &&
    DEPENDENCIES+=$'\ngcc-fortran\ntk'
pacman -Qq "system-config-printer" >/dev/null 2>&1 &&
    DEPENDENCIES+=$'\ncups-pk-helper'
pacman -Qq "thunar" >/dev/null 2>&1 &&
    DEPENDENCIES+=$'\ngvfs\nthunar-archive-plugin\nthunar-media-tags-plugin\nthunar-volman\ntumbler'
pacman -Qq "tlp" >/dev/null 2>&1 &&
    DEPENDENCIES+=$'\nsmartmontools'
pacman -Qq "transmission-gtk" >/dev/null 2>&1 &&
    DEPENDENCIES+=$'\ntransmission-cli'
pacman -Qq "wl-clipboard" >/dev/null 2>&1 &&
    DEPENDENCIES+=$'\nmailcap'
pacman -Qq "wlroots" >/dev/null 2>&1 &&
    DEPENDENCIES+=$'\nxorg-xwayland'
pacman -S --noprogressbar --noconfirm --needed --asdeps - <<<"$DEPENDENCIES"
## Reinstall pipewire plugins as dependencies
DEPENDENCIES=""
pacman -Qq "pipewire" >/dev/null 2>&1 &&
    DEPENDENCIES+=$'\npipewire-alsa\npipewire-jack\npipewire-pulse'
pacman -Qq "r" >/dev/null 2>&1 &&
    DEPENDENCIES+=$'\nblas-openblas'
pacman -S --noprogressbar --noconfirm --asdeps - <<<"$DEPENDENCIES"

# Configure $SYSUSER
## Run sysuser.sh
chmod +x "$SCRIPT_DIR/sysuser.sh"
su -c "$SCRIPT_DIR/sysuser.sh" "$SYSUSER"
cp "$SCRIPT_DIR/dot-files.sh" /
chmod 777 /dot-files.sh

# Configure /etc
## Configure /etc/crypttab
if lsblk -rno TYPE "$DISK1P2" | grep -q "raid1"; then
    MD0UUID="$(blkid -s UUID -o value /dev/md/md0)"
else
    MD0UUID="$(blkid -s UUID -o value $DISK1P2)"
fi
{
    echo "md0_crypt UUID=$MD0UUID none luks,discard,key-slot=0"
} >/etc/crypttab
## Create /etc/encryption/keys directory
mkdir -p /etc/encryption/keys
chmod 700 /etc/encryption/keys
## Create /etc/access/keys directory
mkdir -p /etc/access/keys
chmod 700 /etc/access/keys
## Configure /etc/localtime /etc/vconsole.conf /etc/hostname /etc/hosts
ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
hwclock --systohc
echo "KEYMAP=$KEYMAP" >/etc/vconsole.conf
echo "$HOSTNAME" >/etc/hostname
{
    echo "127.0.0.1  localhost"
    echo "127.0.1.1  $HOSTNAME.$DOMAIN	$HOSTNAME"
    echo "::1  ip6-localhost ip6-loopback"
    echo "ff02::1  ip6-allnodes"
    echo "ff02::2  ip6-allrouters"
} >/etc/hosts
## Configure /etc/fwupd/uefi_capsule.conf
{
    echo ""
    echo "# Custom"
    echo "## Set /efi as mountpoint"
    echo "OverrideESPMountPoint=/efi"
} >>/etc/fwupd/uefi_capsule.conf
## Configure /etc/cryptboot.conf
git clone -b server https://github.com/leomeinel/cryptboot.git /git/cryptboot
cp /git/cryptboot/cryptboot.conf /etc/
chmod 644 /etc/cryptboot.conf
## Configure /etc/ssh/sshd_config
{
    echo ""
    echo "# Override"
    echo "PasswordAuthentication no"
    echo "AuthenticationMethods publickey"
    echo "PermitRootLogin no"
    echo "AllowTcpForwarding no"
    echo "ClientAliveCountMax 2"
    echo "LogLevel VERBOSE"
    echo "MaxAuthTries 3"
    echo "MaxSessions 2"
    echo "Port 9122"
    echo "TCPKeepAlive no"
    echo "AllowAgentForwarding no"
    echo "Banner /etc/issue.net"
} >>/etc/ssh/sshd_config
## Configure /etc/mdadm.conf
lsblk -rno TYPE "$DISK1P2" | grep -q "raid1" &&
    mdadm --detail --scan >>/etc/mdadm.conf
## Configure /etc/usbguard/usbguard-daemon.conf /etc/usbguard/rules.conf
usbguard generate-policy >/etc/usbguard/rules.conf
usbguard add-user -g usbguard --devices=modify,list,listen --policy=list --exceptions=listen
## Configure /etc/pam.d/system-login /etc/security/faillock.conf /etc/pam.d/su /etc/pam.d/su-l
echo "auth optional pam_faildelay.so delay=8000000" >>/etc/pam.d/system-login
### START sed
FILE=/etc/security/faillock.conf
STRING="^#.*dir.*=.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s|$STRING|dir = /var/lib/faillock|" "$FILE"
### END sed
echo "auth required pam_wheel.so use_uid" >>/etc/pam.d/su
echo "auth required pam_wheel.so use_uid" >>/etc/pam.d/su-l
## Configure /etc/audit/auditd.conf
### START sed
FILE=/etc/audit/auditd.conf
STRING="^log_group.*=.*"
grep -q "$STRING" "$FILE" || sed_exit
sed -i "s/$STRING/log_group = audit/" "$FILE"
### END sed
## Configure /etc/snap-pac.ini
{
    echo ""
    echo "# Custom"
    echo "[root]"
    echo "snapshot = True"
    echo 'important_packages = ["dracut", "linux", "linux-lts", "linux-zen"]'
    echo ""
    echo "[usr]"
    echo "snapshot = True"
    echo 'important_packages = ["dracut", "linux", "linux-lts", "linux-zen"]'
    echo ""
    echo "[var]"
    echo "snapshot = True"
    echo 'important_packages = ["dracut", "linux", "linux-lts", "linux-zen"]'
    echo ""
    echo "[var_lib]"
    echo "snapshot = True"
    echo 'important_packages = ["dracut", "linux", "linux-lts", "linux-zen"]'
    echo ""
    echo "[var_lib_docker]"
    echo "snapshot = True"
    echo 'important_packages = ["dracut", "linux", "linux-lts", "linux-zen"]'
    echo ""
    echo "[var_lib_flatpak]"
    echo "snapshot = True"
    echo 'important_packages = ["dracut", "linux", "linux-lts", "linux-zen"]'
    echo ""
    echo "[var_lib_libvirt]"
    echo "snapshot = True"
    echo 'important_packages = ["dracut", "linux", "linux-lts", "linux-zen"]'
    echo ""
    echo "[var_lib_mysql]"
    echo "snapshot = True"
    echo 'important_packages = ["dracut", "linux", "linux-lts", "linux-zen"]'
} >>/etc/snap-pac.ini
## Configure /etc/dracut.conf.d/modules.conf
{
    echo "filesystems+=\" btrfs \""
} >/etc/dracut.conf.d/modules.conf
## Configure /etc/dracut.conf.d/cmdline.conf
DISK1P2UUID="$(blkid -s UUID -o value "$DISK1P2")"
PARAMETERS="rd.luks.uuid=luks-$MD0UUID rd.lvm.lv=vg0/lv0 rd.md.uuid=$DISK1P2UUID root=/dev/mapper/vg0-lv0 rootfstype=btrfs rootflags=rw,noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvolid=256,subvol=/@ rd.lvm.lv=vg0/lv1 rd.lvm.lv=vg0/lv2 rd.lvm.lv=vg0/lv3 rd.luks.allow-discards=$DISK1P2UUID rd.vconsole.unicode rd.vconsole.keymap=$KEYMAP loglevel=3 bgrt_disable audit=1 lsm=landlock,lockdown,yama,integrity,apparmor,bpf iommu=pt zswap.enabled=0 lockdown=integrity module.sig_enforce=1"
#### If on intel set kernel parameter intel_iommu=on
pacman -Qq "intel-ucode" >/dev/null 2>&1 &&
    PARAMETERS="${PARAMETERS} intel_iommu=on"
echo "kernel_cmdline=\"$PARAMETERS\"" >/etc/dracut.conf.d/cmdline.conf
chmod 644 /etc/dracut.conf.d/*.conf
## Harden system
### Disable coredump
{
    echo ""
    echo "# Custom"
    echo "* hard core 0"
} >>/etc/security/limits.conf
### Harden Postfix
postconf -e disable_vrfy_command=yes
postconf -e inet_interfaces=loopback-only
### chmod & touch files
FILES_600=("/etc/at.deny" "/etc/anacrontab" "/etc/cron.deny" "/etc/crontab" "/etc/ssh/sshd_config" "/root/.rhosts" "/root/.rlogin" "/root/.shosts" "/etc/audit/rules.d/custom.rules")
FILES_644=("/etc/hosts.allow" "/etc/hosts.deny" "/etc/hosts.equiv" "/etc/issue" "/etc/issue.net" "/etc/motd" "/etc/shosts.equiv")
DIRS_700=("/etc/cron.d" "/etc/cron.daily" "/etc/cron.hourly" "/etc/cron.monthly" "/etc/cron.weekly" "/etc/audit/rules.d")
for file in "${FILES_600[@]}"; do
    [[ ! -f "$file" ]] &&
        touch "$file"
    chmod 600 "$file"
done
for file in "${FILES_644[@]}"; do
    [[ ! -f "$file" ]] &&
        touch "$file"
    chmod 644 "$file"
done
for dir in "${DIRS_700[@]}"; do
    [[ ! -f "$dir" ]] &&
        mkdir -p "$dir"
    chmod 700 "$dir"
done

# Setup /usr
rsync -rq "$SCRIPT_DIR/usr/" /usr
cp /git/cryptboot/systemd-boot-sign /usr/local/bin/
cp /git/cryptboot/cryptboot /usr/local/bin/
cp /git/cryptboot/cryptboot-efikeys /usr/local/bin/
## Configure /usr/local/bin
chmod 755 /usr/local/bin/cryptboot
chmod 755 /usr/local/bin/cryptboot-efikeys
chmod 755 /usr/local/bin/systemd-boot-sign
ln -s "$(which nvim)" /usr/local/bin/edit
ln -s "$(which nvim)" /usr/local/bin/vedit
ln -s "$(which nvim)" /usr/local/bin/vi
ln -s "$(which nvim)" /usr/local/bin/vim
chmod 755 /usr/local/bin/edit
chmod 755 /usr/local/bin/ex
chmod 755 /usr/local/bin/sway-logout
chmod 755 /usr/local/bin/vedit
chmod 755 /usr/local/bin/vi
chmod 755 /usr/local/bin/view
chmod 755 /usr/local/bin/vim
chmod 755 /usr/local/bin/vimdiff

# Configure /usr
## Configure /usr/share/snapper/config-templates/default & configure snapper configs
### Setup configs
#### /usr/share/snapper/config-templates/default
##### START sed
STRING0="^ALLOW_GROUPS=.*"
STRING1="^SPACE_LIMIT=.*"
STRING2="^FREE_LIMIT=.*"
STRING3="^NUMBER_LIMIT=.*"
STRING4="^NUMBER_LIMIT_IMPORTANT=.*"
STRING5="^TIMELINE_CREATE=.*"
STRING6="^TIMELINE_CLEANUP=.*"
STRING7="^TIMELINE_LIMIT_MONTHLY=.*"
STRING8="^TIMELINE_LIMIT_YEARLY=.*"
#####
FILE0=/usr/share/snapper/config-templates/default
grep -q "$STRING0" "$FILE0" || sed_exit
sed -i "s/$STRING0/ALLOW_GROUPS=\"wheel\"/" "$FILE0"
grep -q "$STRING1" "$FILE0" || sed_exit
sed -i "s/$STRING1/SPACE_LIMIT=\"0.2\"/" "$FILE0"
grep -q "$STRING2" "$FILE0" || sed_exit
sed -i "s/$STRING2/FREE_LIMIT=\"0.4\"/" "$FILE0"
grep -q "$STRING3" "$FILE0" || sed_exit
sed -i "s/$STRING3/NUMBER_LIMIT=\"5\"/" "$FILE0"
grep -q "$STRING4" "$FILE0" || sed_exit
sed -i "s/$STRING4/NUMBER_LIMIT_IMPORTANT=\"5\"/" "$FILE0"
grep -q "$STRING5" "$FILE0" || sed_exit
sed -i "s/$STRING5/TIMELINE_CREATE=\"yes\"/" "$FILE0"
grep -q "$STRING6" "$FILE0" || sed_exit
sed -i "s/$STRING6/TIMELINE_CLEANUP=\"yes\"/" "$FILE0"
grep -q "$STRING7" "$FILE0" || sed_exit
sed -i "s/$STRING7/TIMELINE_LIMIT_MONTHLY=\"0\"/" "$FILE0"
grep -q "$STRING8" "$FILE0" || sed_exit
sed -i "s/$STRING8/TIMELINE_LIMIT_YEARLY=\"0\"/" "$FILE0"
##### END sed
### Remove & unmount snapshots (Prepare snapshot dirs 1)
for subvolume in "${SUBVOLUMES[@]}"; do
    umount "$subvolume".snapshots
    rm -rf "$subvolume".snapshots
done
####### START sed
STRING0="^TIMELINE_LIMIT_HOURLY=.*"
STRING1="^TIMELINE_LIMIT_DAILY=.*"
#######
SUBVOLUMES_LENGTH="${#SUBVOLUMES[@]}"
[[ "$SUBVOLUMES_LENGTH" -ne ${#CONFIGS[@]} ]] &&
    {
        echo "ERROR: SUBVOLUMES and CONFIGS aren't the same length!"
        exit 1
    }
for ((i = 0; i < SUBVOLUMES_LENGTH; i++)); do
    #### Copy template
    FILE1="/usr/share/snapper/config-templates/${CONFIGS[$i]}"
    cp "$FILE0" "$FILE1"
    chmod 644 "$FILE1"
    #### Set variables for configs
    case "${CONFIGS[$i]}" in
    "var_cache" | "var_games" | "var_log")
        HOURLY=1
        DAILY=1
        ;;
    "var" | "var_lib" | "var_lib_docker")
        HOURLY=2
        DAILY=2
        ;;
    "home")
        HOURLY=3
        DAILY=2
        ;;
    *)
        HOURLY=2
        DAILY=1
        ;;
    esac
    #######
    grep -q "$STRING0" "$FILE1" || sed_exit
    sed -i "s/$STRING0/TIMELINE_LIMIT_HOURLY=\"$HOURLY\"/" "$FILE1"
    grep -q "$STRING1" "$FILE1" || sed_exit
    sed -i "s/$STRING1/TIMELINE_LIMIT_DAILY=\"$DAILY\"/" "$FILE1"
    ####### END sed
    #### Create config
    snapper --no-dbus -c "${CONFIGS[$i]}" create-config -t "${CONFIGS[$i]}" "${SUBVOLUMES[$i]}"
done
### Replace subvolumes for snapshots (Prepare snapshot dirs 2)
for subvolume in "${SUBVOLUMES[@]}"; do
    btrfs subvolume delete "$subvolume".snapshots
    mkdir -p "$subvolume".snapshots
done
#### Mount /etc/fstab
mount -a
### Set correct permissions on snapshots (Prepare snapshot dirs 3)
for subvolume in "${SUBVOLUMES[@]}"; do
    chmod 755 "$subvolume".snapshots
    chown :wheel "$subvolume".snapshots
done

# Configure /var
## Configure /var/games
chown :games /var/games

# Setup /efi
rsync -rq "$SCRIPT_DIR/efi/" /efi
chmod 644 /efi/loader/loader.conf

# Enable systemd services
pacman -Qq "apparmor" >/dev/null 2>&1 &&
    {
        systemctl enable apparmor.service
        systemctl enable auditd.service
    }
pacman -Qq "containerd" >/dev/null 2>&1 &&
    systemctl enable containerd.service
pacman -Qq "docker" >/dev/null 2>&1 &&
    systemctl enable docker.service
pacman -Qq "logwatch" >/dev/null 2>&1 &&
    systemctl enable logwatch.timer
pacman -Qq "openssh" >/dev/null 2>&1 &&
    systemctl enable sshd.service
pacman -Qq "reflector" >/dev/null 2>&1 &&
    {
        systemctl enable reflector.service
        systemctl enable reflector.timer
    }
pacman -Qq "snapper" >/dev/null 2>&1 &&
    {
        systemctl enable snapper-cleanup.timer
        systemctl enable snapper-timeline.timer
    }
pacman -Qq "sysstat" >/dev/null 2>&1 &&
    systemctl enable sysstat.service
pacman -Qq "systemd" >/dev/null 2>&1 &&
    {
        systemctl enable systemd-resolved.service
        systemctl enable systemd-networkd.service
        systemctl enable systemd-boot-update.service
    }
pacman -Qq "usbguard" >/dev/null 2>&1 &&
    systemctl enable usbguard.service
pacman -Qq "util-linux" >/dev/null 2>&1 &&
    systemctl enable fstrim.timer

# Setup /boot & /efi
bootctl --esp-path=/efi --no-variables install
dracut --regenerate-all --force

# Remove repo
rm -rf /git
