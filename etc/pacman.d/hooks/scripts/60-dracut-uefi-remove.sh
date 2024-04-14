#!/usr/bin/env bash
###
# File: 60-dracut-uefi-remove.sh
# Author: Leopold Meinel (leo@meinel.dev)
# -----
# Copyright (c) 2023 Leopold Meinel & contributors
# SPDX ID: GPL-3.0-or-later
# URL: https://www.gnu.org/licenses/gpl-3.0-standalone.html
# -----
###

set -e
if /usr/bin/mountpoint -q /efi; then
    /usr/bin/umount -AR /efi
fi
/usr/bin/mount /efi
shopt -s nocaseglob
/usr/bin/rm -f /efi/EFI/Linux/*.efi
