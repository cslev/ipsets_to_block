#!/bin/bash

# Sets up daily cron jobs for all ipset update scripts.
# Runs as root via sudo crontab since ipset requires root privileges.

ROOT="$(dirname "$(realpath "$0")")"
source "$ROOT/sources/extra.sh"

# --- Check for root/sudo ---
if [ "$EUID" -ne 0 ]; then
    c_print "Red" "Error: This script must be run as root or with sudo."
    exit 1
fi

# --- Global crontab path ---
GLOBAL_CRONTAB="/etc/crontab"

# --- Cron schedule configuration ---
# /etc/crontab requires an explicit username field (root).
# Adjust times to stagger the jobs and avoid simultaneous network/CPU load.
CRON_BLOCKLIST_DE="0 2 * * * root $ROOT/update_blocklist_de.sh"   # 02:00 daily
CRON_SANS_DSHIELD="15 2 * * * root $ROOT/update_sans_dshield.sh"  # 02:15 daily
CRON_SPAMHAUS_DROP="30 2 * * * root $ROOT/update_spamhaus_drop.sh" # 02:30 daily

# --- Install cron jobs ---
c_print "Bold" "Installing cron jobs into $GLOBAL_CRONTAB..."

add_cron_job() {
    local job="$1"
    local label="$2"

    c_print "Bold" "  Adding cron job: $label..." no_newline
    if grep -qF "$label" "$GLOBAL_CRONTAB" 2>/dev/null; then
        c_print "BGreen" "[SKIP - already exists]"
    else
        echo "$job" >> "$GLOBAL_CRONTAB"
        c_print "BGreen" "[ADDED]"
    fi
}

add_cron_job "$CRON_BLOCKLIST_DE"  "update_blocklist_de.sh"
add_cron_job "$CRON_SANS_DSHIELD"  "update_sans_dshield.sh"
add_cron_job "$CRON_SPAMHAUS_DROP" "update_spamhaus_drop.sh"

c_print "Green" "Cron jobs installed successfully into $GLOBAL_CRONTAB."

# --- Show relevant entries ---
c_print "Bold" "Current ipset entries in $GLOBAL_CRONTAB:"
grep -E "update_blocklist_de|update_sans_dshield|update_spamhaus_drop" "$GLOBAL_CRONTAB"

exit 0
