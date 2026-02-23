#!/bin/bash

# Bootstrap script for Debian-based systems
# Installs required dependencies: curl, ipset

ROOT="$(dirname "$0")"
source "$ROOT/sources/extra.sh"

# --- Check for root/sudo ---
if [ "$EUID" -ne 0 ]; then
    c_print "Red" "Error: This script must be run as root or with sudo."
    exit 1
fi

# --- Check for apt ---
c_print "Bold" "Checking for 'apt' package manager..." 1
if ! command -v apt &>/dev/null; then
    c_print "BRed" "[NOT FOUND]"
    c_print "Red" "Error: 'apt' is not available. This script requires a Debian-based system."
    exit 1
fi
c_print "BGreen" "[FOUND]"

# --- Update package index ---
c_print "Bold" "Updating package index..." no_newline
apt update -qq
check_retval "$?"

# --- Install dependencies ---
PACKAGES=("curl" "ipset")

for pkg in "${PACKAGES[@]}"; do
    c_print "Bold" "Installing '$pkg'..." no_newline
    apt install -y "$pkg" -qq
    check_retval "$?"
done

c_print "Green" "Bootstrap complete. All dependencies are installed."
exit 0
