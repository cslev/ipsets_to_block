#!/bin/bash

# Makes the ipsets survive a reboot:
#  - installs ipset_persist.sh to /usr/local/sbin (so boot does not depend on this repo's location)
#  - installs and enables ipsets-to-block.service, which restores the sets right before ufw starts
#  - saves the currently loaded sets to /var/lib/ipsets_to_block
# Safe to run multiple times (e.g., after pulling a new version of this repo).

ROOT="$(dirname "$(realpath "$0")")"
source "$ROOT/sources/extra.sh"

INSTALLED_SCRIPT="/usr/local/sbin/ipset_persist.sh"
UNIT_NAME="ipsets-to-block.service"
UNIT_FILE="/etc/systemd/system/${UNIT_NAME}"
# Unit from older versions of the README; it has an ordering cycle with ufw.service
OLD_UNIT_NAME="restore-ipset.service"

# --- Check for root/sudo ---
if [ "$EUID" -ne 0 ]; then
    c_print "Red" "Error: This script must be run as root or with sudo."
    exit 1
fi

check_command "ipset" "ipset"
check_command "systemctl" "systemd"

c_print "Bold" "Installing $INSTALLED_SCRIPT..." no_newline
install -m 755 "$ROOT/ipset_persist.sh" "$INSTALLED_SCRIPT"
check_retval "$?"

# ufw.service runs with DefaultDependencies=no, before network-pre.target and right after local-fs.target.
# This unit must do the same, otherwise ufw starts first, cannot find the sets referenced in
# before.rules, and fails to load any rules at all.
c_print "Bold" "Installing $UNIT_FILE..." no_newline
cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Restore blocklist ipsets before ufw starts
Documentation=https://github.com/cslev/ipsets_to_block
DefaultDependencies=no
Wants=local-fs.target
After=local-fs.target
Before=ufw.service network-pre.target shutdown.target
Conflicts=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$INSTALLED_SCRIPT restore

[Install]
WantedBy=ufw.service multi-user.target
EOF
check_retval "$?"

if systemctl list-unit-files "$OLD_UNIT_NAME" &>/dev/null && systemctl is-enabled "$OLD_UNIT_NAME" &>/dev/null; then
    c_print "Bold" "Disabling old $OLD_UNIT_NAME..." no_newline
    systemctl disable "$OLD_UNIT_NAME" &>/dev/null
    check_retval "$?"
    c_print "Yellow" "You can now remove /etc/systemd/system/${OLD_UNIT_NAME} and /etc/ufw/rules.v4.ipsets."
fi

c_print "Bold" "Saving currently loaded ipsets..."
"$INSTALLED_SCRIPT" save

c_print "Bold" "Enabling $UNIT_NAME..." no_newline
systemctl daemon-reload && systemctl enable --now "$UNIT_NAME" &>/dev/null
check_retval "$?"

c_print "Green" "Persistence set up. Saved sets:"
ls -l /var/lib/ipsets_to_block/

exit 0
