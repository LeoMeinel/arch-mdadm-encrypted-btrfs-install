#!/bin/bash
###
# File: post-gui.sh
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

# Clean firecfg
doas firecfg --clean

# Configure dot-files (vscodium)
~/dot-files/exts-code.sh
doas su -lc '~/dot-files/exts-code.sh' "$VIRTUSER"
doas su -lc '~/dot-files/exts-code.sh' "$HOMEUSER"
doas su -lc '~/dot-files/exts-code.sh' "$GUESTUSER"

# Configure firejail
## START sed
FILE=/etc/firejail/firecfg.config
STRINGS=("code-oss" "code" "codium" "dnsmasq" "lollypop" "nextcloud-desktop" "nextcloud" "shotwell" "signal-desktop" "transmission-cli" "transmission-create" "transmission-daemon" "transmission-edit" "transmission-gtk" "transmission-remote" "transmission-show" "vscodium")
for string in "${STRINGS[@]}"; do
    grep -q "$string" "$FILE" || sed_exit
    doas sed -i "s/^$string$/#$string #arch-install/" "$FILE"
done
## END sed
doas firecfg --add-users root "$SYSUSER" "$VIRTUSER" "$HOMEUSER" "$GUESTUSER"
doas apparmor_parser -r /etc/apparmor.d/firejail-default
doas firecfg
rm -rf ~/.local/share/applications/*
doas su -c 'rm -rf ~/.local/share/applications/*' "$VIRTUSER"
doas su -c 'rm -rf ~/.local/share/applications/*' "$HOMEUSER"
doas su -c 'rm -rf ~/.local/share/applications/*' "$GUESTUSER"

# Remove scripts
rm -f "$SCRIPT_DIR/install.conf"
rm -f "$SCRIPT_DIR/post-gui.sh"
