#!/usr/bin/env bash
###
# File: 51-pkglists.sh
# Author: Leopold Meinel (leo@meinel.dev)
# -----
# Copyright (c) 2023 Leopold Meinel & contributors
# SPDX ID: GPL-3.0-or-later
# URL: https://www.gnu.org/licenses/gpl-3.0-standalone.html
# -----
###

print_header() {
    /usr/bin/echo ''
    /usr/bin/echo '########################'
    /usr/bin/date -u +"#%Y-%m-%dT%H:%M:%S %Z"
    /usr/bin/echo '########################'
}
{
    print_header
    /usr/bin/pacman -Qen
} >>/var/log/pkglist-explicit.pacman.log
{
    print_header
    /usr/bin/pacman -Qem
} >>/var/log/pkglist-foreign.pacman.log
{
    print_header
    /usr/bin/pacman -Qd
} >>/var/log/pkglist-deps.pacman.log
/usr/bin/chmod 644 /var/log/pkglist-*.log
