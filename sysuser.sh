#!/bin/bash
###
# File: sysuser.sh
# Author: Leopold Meinel (leo@meinel.dev)
# -----
# Copyright (c) 2023 Leopold Meinel & contributors
# SPDX ID: GPL-3.0-or-later
# URL: https://www.gnu.org/licenses/gpl-3.0-standalone.html
# -----
###

# Fail on error
set -eu

# Set variables
SCRIPT_DIR="$(dirname -- "$(readlink -f -- "$0")")"

# Set up post.sh
cp "$SCRIPT_DIR/pkgs-post.txt" ~/
cp "$SCRIPT_DIR/post.sh" ~/
cp "$SCRIPT_DIR/install.conf" ~/
chmod +x ~/post.sh
cp "$SCRIPT_DIR/post-gui.sh" ~/

# Create backup directory
mkdir -p ~/backup
