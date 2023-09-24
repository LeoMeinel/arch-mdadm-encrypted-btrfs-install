#!/bin/bash
###
# File: dot-files.sh
# Author: Leopold Meinel (leo@meinel.dev)
# -----
# Copyright (c) 2023 Leopold Meinel & contributors
# SPDX ID: GPL-3.0-or-later
# URL: https://www.gnu.org/licenses/gpl-3.0-standalone.html
# -----
###

# Fail on error
set -e

# Set up dot-files
git clone https://github.com/leomeinel/dot-files.git ~/dot-files
chmod +x ~/dot-files/setup-min.sh
~/dot-files/setup-min.sh
