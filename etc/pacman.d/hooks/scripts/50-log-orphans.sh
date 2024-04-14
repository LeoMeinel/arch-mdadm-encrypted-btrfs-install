#!/usr/bin/env bash
###
# File: 50-log-orphans.sh
# Author: Leopold Meinel (leo@meinel.dev)
# -----
# Copyright (c) 2023 Leopold Meinel & contributors
# SPDX ID: GPL-3.0-or-later
# URL: https://www.gnu.org/licenses/gpl-3.0-standalone.html
# -----
###

PKGS="$(/usr/bin/pacman -Qtdq)"
if [[ -n "$PKGS" ]]; then
    {
        /usr/bin/echo "The following packages are installed but not required (anymore): "
        /usr/bin/echo "$PKGS"
        /usr/bin/echo "You can remove them all using 'pacman -Qtdq | pacman -Rns -'"
    }
fi
