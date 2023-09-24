# arch-install

My personal Arch Linux install script using LUKS2 encryption, LVM and btrfs.

RAID can also be used.

Meant for servers that are mainly hosting docker.

## Info

:information_source: | Expect errors to occur during the installation. They only matter if any of the scripts don't finish successfully.

:information_source: | I recommend disks with at least 512GB (change $DISK_ALLOCATION in install.conf otherwise).

:warning: | All data on selected disks will be wiped!

:exclamation: | Follow [these instructions](https://github.com/leomeinel/arch-install/blob/server/virt-manager.md) for virt-manager.

## Pre-installation

:information_source: | Follow the `Pre-installation` section of this [guide](https://wiki.archlinux.org/title/Installation_guide#Pre-installation) until (including) the `Connect to the internet` section.

## Installation

```sh
pacman -Sy
pacman -S git
git clone -b server https://github.com/leomeinel/arch-install.git
chmod +x /root/arch-install/prepare.sh
/root/arch-install/prepare.sh
arch-chroot /mnt
/git/arch-install/setup.sh
exit
umount -AR /mnt
reboot
```

:information_source: | Use `<...>.sh |& tee <logfile>.log` to create a log file.

:information_source: | Configure installation using `vim /root/arch-install/install.conf`.

## Post-installation (tty)

:warning: | If using virt-manager skip ¹.

:information_source: | ¹Enable `Secure Boot` [`Setup Mode`](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#Putting_firmware_in_"Setup_Mode") in [`UEFI Firmware Settings`](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#Before_booting_the_OS).

:information_source: | ¹Set your UEFI password(s) and reboot.

:information_source: | Log into $SYSUSER account and run:

```sh
~/post.sh
reboot
```

:information_source: | ¹Enable `Secure Boot` in [`UEFI Firmware Settings`](https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#Before_booting_the_OS).
