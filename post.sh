#!/bin/bash
###
# File: post.sh
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

# Configure $KEYMAP
doas localectl --no-convert set-keymap "$KEYMAP"
doas localectl --no-convert set-x11-keymap "$KEYLAYOUT"

# Initialize Firefox
## Don't fail on error
set +e
## Initialization
timeout 5 firefox --headless
doas su -c 'timeout 5 firefox --headless' "$HOMEUSER"
doas su -c 'timeout 5 firefox --headless' "$GUESTUSER"
## Fail on error
set -e

# Configure dot-files (setup)
/dot-files.sh setup
doas su -lc '/dot-files.sh setup' "$HOMEUSER"
doas su -lc '/dot-files.sh setup' "$GUESTUSER"
doas su -lc '/dot-files.sh setup-min' root

# Configure clock
doas timedatectl set-ntp true

# Set default java
doas archlinux-java set java-17-openjdk

# Configure iptables
# FIXME: Replace with nftables
# References
#
# https://networklessons.com/uncategorized/iptables-example-configuration
# https://linoxide.com/block-common-attacks-iptables/
# https://serverfault.com/questions/199421/how-to-prevent-ip-spoofing-within-iptables
# https://www.cyberciti.biz/tips/linux-iptables-10-how-to-block-common-attack.html
# https://javapipe.com/blog/iptables-ddos-protection/
# https://danielmiessler.com/study/iptables/
# https://inai.de/documents/Perfect_Ruleset.pdf
# https://unix.stackexchange.com/questions/108169/what-is-the-difference-between-m-conntrack-ctstate-and-m-state-state
# https://gist.github.com/jirutka/3742890
# https://www.ripe.net/publications/docs/ripe-431
# https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/security_guide/sect-security_guide-firewalls-malicious_software_and_spoofed_ip_addresses
#
## ipv4
### Flush & delete all chains
doas iptables -F
doas iptables -X
### Set up new chains
doas iptables -L | grep -q "Chain INPUT" ||
    doas iptables -N INPUT
doas iptables -L | grep -q "Chain FORWARD" ||
    doas iptables -N FORWARD
doas iptables -L | grep -q "Chain OUTPUT" ||
    doas iptables -N OUTPUT
### Allow all connections on all chains to start
doas iptables -P INPUT ACCEPT
doas iptables -P FORWARD ACCEPT
doas iptables -P OUTPUT ACCEPT
### Accept loopback
doas iptables -A INPUT -i lo -j ACCEPT
### First packet has to be TCP SYN
doas iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
### Drop all invalid packets
doas iptables -A INPUT -m state --state INVALID -j DROP
doas iptables -A FORWARD -m state --state INVALID -j DROP
doas iptables -A OUTPUT -m state --state INVALID -j DROP
### Block packets with bogus TCP flags
doas iptables -A INPUT -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
doas iptables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
doas iptables -A INPUT -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
doas iptables -A INPUT -p tcp --tcp-flags FIN,ACK FIN -j DROP
doas iptables -A INPUT -p tcp --tcp-flags ACK,URG URG -j DROP
doas iptables -A INPUT -p tcp --tcp-flags ACK,PSH PSH -j DROP
### Drop NULL packets
doas iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
### Drop XMAS packets
doas iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
### Drop excessive TCP RST packets
doas iptables -A INPUT -p tcp --tcp-flags RST RST -m limit --limit 2/s --limit-burst 2 -j ACCEPT
doas iptables -A INPUT -p tcp --tcp-flags RST RST -j DROP
### Drop SYN-FLOOD packets
doas iptables -A INPUT -p tcp -m state --state NEW -m limit --limit 2/second --limit-burst 2 -j ACCEPT
doas iptables -A INPUT -p tcp -m state --state NEW -j DROP
### Drop fragments
doas iptables -A INPUT -f -j DROP
doas iptables -A FORWARD -f -j DROP
doas iptables -A OUTPUT -f -j DROP
### Drop SYN packets with suspicious MSS value
doas iptables -A INPUT -p tcp -m state --state NEW -m tcpmss ! --mss 536:65535 -j DROP
### Block spoofed packets
doas iptables -A INPUT -s 127.0.0.0/8 ! -i lo -j DROP
### Drop ICMP
doas iptables -A INPUT -p icmp -j DROP
### Allow SMTP
doas iptables -A INPUT -p tcp --dport 25 -j ACCEPT
doas iptables -A INPUT -p tcp --dport 587 -j ACCEPT
### Allow POP & POPS
doas iptables -A INPUT -p tcp --dport 110 -j ACCEPT
doas iptables -A INPUT -p tcp --dport 995 -j ACCEPT
### Allow IMAP & IMAPS
doas iptables -A INPUT -p tcp --dport 143 -j ACCEPT
doas iptables -A INPUT -p tcp --dport 993 -j ACCEPT
### Allow mDNS
doas iptables -A INPUT -p udp --dport 5353 -j ACCEPT
### Allow http & https (for wget)
doas iptables -A INPUT -p tcp --dport 80 -j ACCEPT
doas iptables -A INPUT -p tcp --dport 443 -j ACCEPT
### Allow Transmission
doas iptables -A INPUT -p udp --dport 51413 -j ACCEPT
### Allow established connections
doas iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
### Set default policies for chains
doas iptables -P INPUT DROP
doas iptables -P FORWARD ACCEPT
doas iptables -P OUTPUT ACCEPT
## ipv6
### Flush & delete all chains
doas ip6tables -F
doas ip6tables -X
### Set up new chains
doas ip6tables -L | grep -q "Chain INPUT" ||
    doas ip6tables -N INPUT
doas ip6tables -L | grep -q "Chain INPUT" ||
    doas ip6tables -N FORWARD
doas ip6tables -L | grep -q "Chain INPUT" ||
    doas ip6tables -N OUTPUT
### Allow all connections on all chains to start
doas ip6tables -P INPUT ACCEPT
doas ip6tables -P FORWARD ACCEPT
doas ip6tables -P OUTPUT ACCEPT
### Accept loopback
doas ip6tables -A INPUT -i lo -j ACCEPT
### First packet has to be TCP SYN
doas ip6tables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
### Drop all invalid packets
doas ip6tables -A INPUT -m state --state INVALID -j DROP
doas ip6tables -A FORWARD -m state --state INVALID -j DROP
doas ip6tables -A OUTPUT -m state --state INVALID -j DROP
### Block packets with bogus TCP flags
doas ip6tables -A INPUT -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
doas ip6tables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
doas ip6tables -A INPUT -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
doas ip6tables -A INPUT -p tcp --tcp-flags FIN,ACK FIN -j DROP
doas ip6tables -A INPUT -p tcp --tcp-flags ACK,URG URG -j DROP
doas ip6tables -A INPUT -p tcp --tcp-flags ACK,PSH PSH -j DROP
### Drop NULL packets
doas ip6tables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
### Drop XMAS packets
doas ip6tables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
### Drop excessive TCP RST packets
doas ip6tables -A INPUT -p tcp --tcp-flags RST RST -m limit --limit 2/s --limit-burst 2 -j ACCEPT
doas ip6tables -A INPUT -p tcp --tcp-flags RST RST -j DROP
### Drop SYN-FLOOD packets
doas ip6tables -A INPUT -p tcp -m state --state NEW -m limit --limit 2/second --limit-burst 2 -j ACCEPT
doas ip6tables -A INPUT -p tcp -m state --state NEW -j DROP
### Drop fragments
doas ip6tables -A INPUT -m frag -j DROP
doas ip6tables -A FORWARD -m frag -j DROP
doas ip6tables -A OUTPUT -m frag -j DROP
### Drop SYN packets with suspicious MSS value
doas ip6tables -A INPUT -p tcp -m state --state NEW -m tcpmss ! --mss 536:65535 -j DROP
### Block spoofed packets
doas ip6tables -A INPUT -s ::1/128 ! -i lo -j DROP
### Drop ICMP
doas ip6tables -A INPUT -p icmp -j DROP
### Allow SMTP
doas ip6tables -A INPUT -p tcp --dport 25 -j ACCEPT
doas ip6tables -A INPUT -p tcp --dport 587 -j ACCEPT
### Allow POP & POPS
doas ip6tables -A INPUT -p tcp --dport 110 -j ACCEPT
doas ip6tables -A INPUT -p tcp --dport 995 -j ACCEPT
### Allow IMAP & IMAPS
doas ip6tables -A INPUT -p tcp --dport 143 -j ACCEPT
doas ip6tables -A INPUT -p tcp --dport 993 -j ACCEPT
### Allow mDNS
doas ip6tables -A INPUT -p udp --dport 5353 -j ACCEPT
### Allow http & https (for wget)
doas ip6tables -A INPUT -p tcp --dport 80 -j ACCEPT
doas ip6tables -A INPUT -p tcp --dport 443 -j ACCEPT
### Allow Transmission
doas ip6tables -A INPUT -p udp --dport 51413 -j ACCEPT
### Allow established connections
doas ip6tables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
### Set default policies for chains
doas ip6tables -P INPUT DROP
doas ip6tables -P FORWARD ACCEPT
doas ip6tables -P OUTPUT ACCEPT
### Save rules to /etc/iptables
doas sh -c 'iptables-save > /etc/iptables/iptables.rules'
doas sh -c 'ip6tables-save > /etc/iptables/ip6tables.rules'
doas chmod 644 /etc/iptables/*.rules

# Configure secureboot
# Prompt user
# This prompt prevents unwanted overrides of already enrolled keys
echo "INFO: To deploy your own keys, don't confirm the next prompt"
source "/etc/cryptboot.conf"
read -rp "Overwrite secureboot keys? (Type 'yes' in capital letters): " choice
case "$choice" in
YES)
    if mountpoint -q /efi; then
        doas umount -AR /efi
    fi
    doas mount /efi
    doas cryptboot-efikeys create
    doas cryptboot-efikeys enroll
    doas cryptboot systemd-boot-sign
    doas sh -c "{
        echo "uefi_secureboot_cert=\""$EFI_KEYS_DIR"/db.crt\""
        echo "uefi_secureboot_key=\""$EFI_KEYS_DIR"/db.key\""
    } >/etc/dracut.conf.d/secureboot.conf"
    ;;
*)
    {
        echo '#!/bin/bash'
        echo ''
        echo 'source "/etc/cryptboot.conf"'
        echo 'read -rp "Have you transferred your keys to $EFI_KEYS_DIR? (Type '"'"'yes'"'"' in capital letters): " choice'
        echo 'case "$choice" in'
        echo 'YES)'
        echo '    doas chmod 000 "$EFI_KEYS_DIR"/*'
        echo '    if mountpoint -q /efi; then'
        echo '        doas umount -AR /efi'
        echo '    fi'
        echo '    doas mount /efi'
        echo '    doas cryptboot-efikeys enroll'
        echo '    doas cryptboot systemd-boot-sign'
        echo '    doas sh -c "{'
        echo '        echo "uefi_secureboot_cert=\""$EFI_KEYS_DIR"/db.crt\""'
        echo '        echo "uefi_secureboot_key=\""$EFI_KEYS_DIR"/db.key\""'
        echo '    } >/etc/dracut.conf.d/secureboot.conf"'
        echo '    ;;'
        echo '*)'
        echo '    echo "ERROR: User has not transferred keys to ${EFI_KEYS_DIR}!"'
        echo '    exit 1'
        echo '    ;;'
        echo 'esac'
    } >~/secureboot.sh
    doas mkdir -p "$EFI_KEYS_DIR"
    doas chmod 700 "$EFI_KEYS_DIR"
    chmod 700 ~/secureboot.sh
    echo "WARNING: User aborted enrolling secureboot keys"
    echo "         Deploy your own keys in $EFI_KEYS_DIR and run ~/secureboot.sh to sign your bootloader"
    ;;
esac

# Install paru-bin
source ~/.bash_profile
git clone https://aur.archlinux.org/paru-bin.git ~/git/paru-bin
cd ~/git/paru-bin
makepkg -sri --noprogressbar --noconfirm --needed

# Configure paru.conf
## START sed
FILE=/etc/paru.conf
STRING="^#RemoveMake"
grep -q "$STRING" "$FILE" || sed_exit
doas sed -i "s/$STRING/RemoveMake/" "$FILE"
STRING="^#CleanAfter"
grep -q "$STRING" "$FILE" || sed_exit
doas sed -i "s/$STRING/CleanAfter/" "$FILE"
STRING="^#SudoLoop.*"
grep -q "$STRING" "$FILE" || sed_exit
doas sed -i "s/$STRING/SudoLoop = true/" "$FILE"
STRING="^#\[bin\]"
grep -q "$STRING" "$FILE" || sed_exit
doas sed -i "s/$STRING/\[bin\]/" "$FILE"
STRING="^#FileManager =.*"
grep -q "$STRING" "$FILE" || sed_exit
doas sed -i "s/$STRING/FileManager = nvim/" "$FILE"
STRING="^FileManager = nvim"
grep -q "$STRING" "$FILE" || sed_exit
doas sed -i "/$STRING/a FileManagerFlags = -cNvimTreeFocus" "$FILE"
STRING="^#Sudo =.*"
grep -q "$STRING" "$FILE" || sed_exit
doas sed -i "s/$STRING/Sudo = doas/" "$FILE"
STRING="^#CombinedUpgrade"
grep -q "$STRING" "$FILE" || sed_exit
doas sed -i "/$STRING/a BatchInstall" "$FILE"
## END sed

# Install packages
paru -S --noprogressbar --noconfirm --needed - <"$SCRIPT_DIR/pkgs-post.txt"
paru -Syu --noprogressbar --noconfirm
paru -Scc

# Clean firecfg
doas firecfg --clean

# Configure dot-files (vscodium)
/dot-files.sh vscodium
doas su -lc '/dot-files.sh vscodium' "$HOMEUSER"
doas su -lc '/dot-files.sh vscodium' "$GUESTUSER"

# Configure firejail
## START sed
FILE=/etc/firejail/firecfg.config
STRINGS=("code-oss" "code" "codium" "dnsmasq" "lollypop" "nextcloud-desktop" "nextcloud" "shotwell" "signal-desktop" "transmission-cli" "transmission-create" "transmission-daemon" "transmission-edit" "transmission-gtk" "transmission-remote" "transmission-show" "vscodium")
for string in "${STRINGS[@]}"; do
    grep -q "$string" "$FILE" || sed_exit
    doas sed -i "s/^$string$/#$string #arch-install/" "$FILE"
done
## END sed
doas firecfg --add-users root "$SYSUSER" "$HOMEUSER" "$GUESTUSER"
doas apparmor_parser -r /etc/apparmor.d/firejail-default
doas firecfg
rm -rf ~/.local/share/applications/*
doas su -c 'rm -rf ~/.local/share/applications/*' "$HOMEUSER"
doas su -c 'rm -rf ~/.local/share/applications/*' "$GUESTUSER"

# Enable systemd services
pacman -Qq "iptables" >/dev/null 2>&1 &&
    {
        doas systemctl enable ip6tables
        doas systemctl enable iptables
    }

# Enable systemd user services
pacman -Qq "usbguard-notifier" >/dev/null 2>&1 &&
    systemctl enable --user usbguard-notifier.service

# Remove repo
rm -rf ~/git

# Remove scripts
doas rm -f /dot-files.sh
doas rm -f /root/.bash_history
rm -f ~/.bash_history
rm -f "$SCRIPT_DIR/pkgs-post.txt"
rm -f "$SCRIPT_DIR/post.sh"
rm -f "$SCRIPT_DIR/install.conf"
