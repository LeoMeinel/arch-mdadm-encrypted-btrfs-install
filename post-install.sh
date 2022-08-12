#!/bin/sh

set -e
sudo timedatectl set-ntp true
sudo hwclock --systohc
paru -S --needed librewolf-bin ungoogled-chromium chromium-extension-web-store snap-pac-grub pacman-log-orphans-hook snapper-gui-git sweet-theme-full-git
paru -Scc
paru -Syu
