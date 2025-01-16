#!/usr/bin/env bash
###
# File: post.sh
# Author: Leopold Meinel (leo@meinel.dev)
# -----
# Copyright (c) 2025 Leopold Meinel & contributors
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
doas su -c 'timeout 5 firefox --headless' "$VIRTUSER"
doas su -c 'timeout 5 firefox --headless' "$HOMEUSER"
doas su -c 'timeout 5 firefox --headless' "$GUESTUSER"
## Fail on error
set -e

# Configure dot-files (setup)
/dot-files.sh setup
doas su -lc '/dot-files.sh setup' "$VIRTUSER"
doas su -lc '/dot-files.sh setup' "$HOMEUSER"
doas su -lc '/dot-files.sh setup' "$GUESTUSER"
doas su -lc '/dot-files.sh setup-min' root

# Configure clock
doas timedatectl set-ntp true

# Set default java
doas archlinux-java set java-21-openjdk

# Configure nftables
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
### Flush & delete all chains
doas nft 'flush ruleset'
## ipv4
### Set up new tables
doas nft 'add table ip filter'
### Set up new chains
doas nft 'add chain ip filter input { type filter hook input priority 0; policy drop; }'
# NOTE: We need to accept on the forward chain for libvirtd networking to work at all. There might be better methods, but this works and is safe if nothing else uses the forward chain
doas nft 'add chain ip filter forward { type filter hook forward priority 0; policy accept; }'
doas nft 'add chain ip filter output { type filter hook output priority 0; policy accept; }'
### Accept loopback
doas nft 'add rule ip filter input iifname "lo" counter accept'
### First packet has to be TCP SYN
doas nft 'add rule ip filter input tcp flags != syn / fin,syn,rst,ack ct state new counter drop'
### Drop all invalid packets
doas nft 'add rule ip filter input ct state invalid counter drop'
doas nft 'add rule ip filter forward ct state invalid counter drop'
doas nft 'add rule ip filter output ct state invalid counter drop'
### Block packets with bogus TCP flags
doas nft 'add rule ip filter input tcp flags fin,syn / fin,syn counter drop'
doas nft 'add rule ip filter input tcp flags syn,rst / syn,rst counter drop'
doas nft 'add rule ip filter input tcp flags fin,rst / fin,rst counter drop'
doas nft 'add rule ip filter input tcp flags fin / fin,ack counter drop'
doas nft 'add rule ip filter input tcp flags urg / ack,urg counter drop'
doas nft 'add rule ip filter input tcp flags psh / psh,ack counter drop'
### Drop NULL packets
doas nft 'add rule ip filter input tcp flags 0x0 / fin,syn,rst,psh,ack,urg counter drop'
### Drop XMAS packets
doas nft 'add rule ip filter input tcp flags fin,syn,rst,psh,ack,urg / fin,syn,rst,psh,ack,urg counter drop'
### Drop excessive TCP RST packets
doas nft 'add chain ip filter input_prerouting'
doas nft 'add rule ip filter input tcp flags rst limit rate 2/second burst 2 packets counter jump input_prerouting'
doas nft 'add rule ip filter input tcp flags rst counter drop'
### Drop SYN-FLOOD packets
doas nft 'add rule ip filter input ip protocol tcp ct state new limit rate 2/second burst 2 packets counter jump input_prerouting'
doas nft 'add rule ip filter input ip protocol tcp ct state new counter drop'
### Drop fragments
doas nft 'add rule ip filter input ip frag-off & 0x1fff != 0 counter drop'
doas nft 'add rule ip filter forward ip frag-off & 0x1fff != 0 counter drop'
doas nft 'add rule ip filter output ip frag-off & 0x1fff != 0 counter drop'
### Drop SYN packets with suspicious MSS value
doas nft 'add rule ip filter input ip protocol tcp ct state new tcp option maxseg size != 536-65535 counter drop'
### Block spoofed packets
doas nft 'add rule ip filter input iifname != "lo" ip saddr 127.0.0.0/8 counter drop'
### Drop ICMP
doas nft 'add rule ip filter input ip protocol icmp counter drop'
### Allow SMTP
doas nft 'add rule ip filter input_prerouting tcp dport 25 counter accept'
doas nft 'add rule ip filter input_prerouting tcp dport 587 counter accept'
### Allow POP & POPS
doas nft 'add rule ip filter input_prerouting tcp dport 110 counter accept'
doas nft 'add rule ip filter input_prerouting tcp dport 995 counter accept'
### Allow IMAP & IMAPS
doas nft 'add rule ip filter input_prerouting tcp dport 143 counter accept'
doas nft 'add rule ip filter input_prerouting tcp dport 993 counter accept'
### Allow mDNS
doas nft 'add rule ip filter input_prerouting udp dport 5353 counter accept'
### Allow http & https (for wget)
doas nft 'add rule ip filter input_prerouting tcp dport 80 counter accept'
doas nft 'add rule ip filter input_prerouting tcp dport 443 counter accept'
### Allow Transmission
doas nft 'add rule ip filter input_prerouting udp dport 51413 counter accept'
### Allow established connections
doas nft 'add rule ip filter input ct state related,established counter accept'
## ipv6
### Set up new tables
doas nft 'add table ip6 filter'
### Set up new chains
doas nft 'add chain ip6 filter input { type filter hook input priority 0; policy drop; }'
# NOTE: We need to accept on the forward chain for libvirtd networking to work at all. There might be better methods, but this works and is safe if nothing else uses the forward chain
doas nft 'add chain ip6 filter forward { type filter hook forward priority 0; policy accept; }'
doas nft 'add chain ip6 filter output { type filter hook output priority 0; policy accept; }'
### Accept loopback
doas nft 'add rule ip6 filter input iifname "lo" counter accept'
### First packet has to be TCP SYN
doas nft 'add rule ip6 filter input tcp flags != syn / fin,syn,rst,ack ct state new counter drop'
### Drop all invalid packets
doas nft 'add rule ip6 filter input ct state invalid counter drop'
doas nft 'add rule ip6 filter forward ct state invalid counter drop'
doas nft 'add rule ip6 filter output ct state invalid counter drop'
### Block packets with bogus TCP flags
doas nft 'add rule ip6 filter input tcp flags fin,syn / fin,syn counter drop'
doas nft 'add rule ip6 filter input tcp flags syn,rst / syn,rst counter drop'
doas nft 'add rule ip6 filter input tcp flags fin,rst / fin,rst counter drop'
doas nft 'add rule ip6 filter input tcp flags fin / fin,ack counter drop'
doas nft 'add rule ip6 filter input tcp flags urg / ack,urg counter drop'
doas nft 'add rule ip6 filter input tcp flags psh / psh,ack counter drop'
### Drop NULL packets
doas nft 'add rule ip6 filter input tcp flags 0x0 / fin,syn,rst,psh,ack,urg counter drop'
### Drop XMAS packets
doas nft 'add rule ip6 filter input tcp flags fin,syn,rst,psh,ack,urg / fin,syn,rst,psh,ack,urg counter drop'
### Drop excessive TCP RST packets
doas nft 'add chain ip6 filter input_prerouting'
doas nft 'add rule ip6 filter input tcp flags rst limit rate 2/second burst 2 packets counter jump input_prerouting'
doas nft 'add rule ip6 filter input tcp flags rst counter drop'
### Drop SYN-FLOOD packets
doas nft 'add rule ip6 filter input meta l4proto tcp ct state new limit rate 2/second burst 2 packets counter jump input_prerouting'
doas nft 'add rule ip6 filter input meta l4proto tcp ct state new counter drop'
### Drop fragments
doas nft 'add rule ip6 filter input counter drop'
doas nft 'add rule ip6 filter forward counter drop'
doas nft 'add rule ip6 filter output counter drop'
### Drop SYN packets with suspicious MSS value
doas nft 'add rule ip6 filter input meta l4proto tcp ct state new tcp option maxseg size != 536-65535 counter drop'
### Block spoofed packets
doas nft 'add rule ip6 filter input iifname != "lo" ip6 saddr ::1 counter drop'
### Drop ICMP
doas nft 'add rule ip6 filter input meta l4proto icmp counter drop'
### Allow SMTP
doas nft 'add rule ip6 filter input_prerouting tcp dport 25 counter accept'
doas nft 'add rule ip6 filter input_prerouting tcp dport 587 counter accept'
### Allow POP & POPS
doas nft 'add rule ip6 filter input_prerouting tcp dport 110 counter accept'
doas nft 'add rule ip6 filter input_prerouting tcp dport 995 counter accept'
### Allow IMAP & IMAPS
doas nft 'add rule ip6 filter input_prerouting tcp dport 143 counter accept'
doas nft 'add rule ip6 filter input_prerouting tcp dport 993 counter accept'
### Allow mDNS
doas nft 'add rule ip6 filter input_prerouting udp dport 5353 counter accept'
### Allow http & https (for wget)
doas nft 'add rule ip6 filter input_prerouting tcp dport 80 counter accept'
doas nft 'add rule ip6 filter input_prerouting tcp dport 443 counter accept'
### Allow Transmission
doas nft 'add rule ip6 filter input_prerouting udp dport 51413 counter accept'
### Allow established connections
doas nft 'add rule ip6 filter input ct state related,established counter accept'
### Save rules to /etc/nftables.conf
doas sh -c 'nft -s list ruleset >/etc/nftables.conf'

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
        echo '#!/usr/bin/env bash'
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

# Set default rust if rustup is installed
source ~/.bash_profile
[[ -n $(which rustup) ]] >/dev/null 2>&1 &&
    rustup default stable

# Install flatpaks
[[ -n $(which flatpak) ]] >/dev/null 2>&1 &&
    xargs -n 1 doas flatpak install --system -y --noninteractive <"$SCRIPT_DIR/pkgs-flatpak.txt"

# Install paru-bin
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
## FIXME: Hack to avoid gnupg errors
{
    echo "disable-ipv6"
    echo "standard-resolver"
} >"$GNUPGHOME"/dirmgr.conf
gpgconf --kill all
sleep 5
## AUR packages
# FIXME: The next line is a temporary fix; see: https://aur.archlinux.org/packages/python-rchitect#comment-998515
paru -S --noprogressbar --noconfirm --needed python-pip
paru -S --noprogressbar --noconfirm --needed - <"$SCRIPT_DIR/pkgs-post.txt"
paru -Syu --noprogressbar --noconfirm
paru -Scc

# Prepare dot-files (vscodium)
/dot-files.sh vscodium
doas su -lc '/dot-files.sh vscodium' "$VIRTUSER"
doas su -lc '/dot-files.sh vscodium' "$HOMEUSER"
doas su -lc '/dot-files.sh vscodium' "$GUESTUSER"
chmod +x ~/post-gui.sh

# Enable systemd services
pacman -Qq "nftables" >/dev/null 2>&1 &&
    systemctl enable nftables.service

# Enable systemd user services
pacman -Qq "usbguard-notifier" >/dev/null 2>&1 &&
    systemctl enable --user usbguard-notifier.service

# Remove repo
rm -rf ~/git

# Remove scripts
doas rm -f /dot-files.sh
doas rm -f /root/.bash_history
rm -f "$GNUPGHOME"/dirmgr.conf
rm -f ~/.bash_history
rm -f "$SCRIPT_DIR/pkgs-post.txt"
rm -f "$SCRIPT_DIR/pkgs-flatpak.txt"
rm -f "$SCRIPT_DIR/post.sh"
