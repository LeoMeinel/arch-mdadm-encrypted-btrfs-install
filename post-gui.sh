#!/usr/bin/env bash
###
# File: post-gui.sh
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

# Configure dot-files (vscodium)
~/dot-files/exts-code.sh
doas su -lc '~/dot-files/exts-code.sh' "$VIRTUSER"
doas su -lc '~/dot-files/exts-code.sh' "$HOMEUSER"
doas su -lc '~/dot-files/exts-code.sh' "$GUESTUSER"

# Remove scripts
rm -f ~/.bash_history
rm -f "$SCRIPT_DIR/install.conf"
rm -f "$SCRIPT_DIR/post-gui.sh"
