#!/bin/bash

# Saves/restores the blocklist ipsets to/from disk so they survive a reboot.
#
# Each set is stored in its own file: ${SAVE_DIR}/<IPSET_NAME>.save
# The update scripts call 'save' after every successful update, and
# ipsets-to-block.service calls 'restore' at boot, right before ufw starts.
#
# This script is intentionally standalone (no sources/extra.sh), because a copy
# of it is installed to /usr/local/sbin and run at early boot by systemd.

SAVE_DIR="${IPSET_SAVE_DIR:-/var/lib/ipsets_to_block}"
DEFAULT_SETS=("spamhaus_drop" "sans_dshield" "blocklist_de")

function show_help ()
{
    echo "Usage: $0 save [IPSET_NAME...] | restore"
    echo -e "\tsave:    write the given ipsets (Default: ${DEFAULT_SETS[*]}) to ${SAVE_DIR}/<name>.save"
    echo -e "\trestore: load every ${SAVE_DIR}/*.save into the kernel (sets that already exist are left alone)"
    echo -e "\tThe directory can be overridden with the IPSET_SAVE_DIR environment variable."
    exit $1
}

function save_sets ()
{
    local sets=("$@")
    local retval=0

    [ "${#sets[@]}" -eq 0 ] && sets=("${DEFAULT_SETS[@]}")
    mkdir -p "$SAVE_DIR" || return 1

    for set_name in "${sets[@]}"; do
        if ! ipset list -n "$set_name" &>/dev/null; then
            echo "Skipping '$set_name': no such ipset in the kernel."
            continue
        fi
        # Write to a temp file first and rename, so a crash mid-save never leaves a truncated file
        if ipset save "$set_name" > "${SAVE_DIR}/${set_name}.save.tmp"; then
            mv -f "${SAVE_DIR}/${set_name}.save.tmp" "${SAVE_DIR}/${set_name}.save"
            echo "Saved '$set_name' to ${SAVE_DIR}/${set_name}.save"
        else
            rm -f "${SAVE_DIR}/${set_name}.save.tmp"
            echo "Error: failed to save '$set_name'." >&2
            retval=1
        fi
    done
    return $retval
}

function restore_sets ()
{
    local retval=0

    shopt -s nullglob
    local files=("$SAVE_DIR"/*.save)
    if [ "${#files[@]}" -eq 0 ]; then
        echo "Warning: no saved ipsets found in ${SAVE_DIR}. Run the update scripts first." >&2
        return 0
    fi

    for file in "${files[@]}"; do
        local set_name
        set_name="$(basename "$file" .save)"
        # Never touch a live set: it may be referenced by iptables rules already
        if ipset list -n "$set_name" &>/dev/null; then
            echo "Skipping '$set_name': already exists in the kernel."
            continue
        fi
        if ipset restore -exist -file "$file"; then
            echo "Restored '$set_name' from $file"
        else
            # Fall back to an empty set: ufw refuses to load before.rules if a referenced set is missing,
            # which would leave the machine with no firewall at all. The next cron run refills it.
            echo "Error: failed to restore '$set_name' from $file, creating it empty instead." >&2
            ipset destroy "$set_name" &>/dev/null
            grep '^create ' "$file" | ipset restore -exist
            retval=1
        fi
    done
    return $retval
}

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root or with sudo." >&2
    exit 1
fi

if ! command -v ipset &>/dev/null; then
    echo "Error: 'ipset' is not installed." >&2
    exit 1
fi

case "$1" in
    save)
        shift
        save_sets "$@"
        ;;
    restore)
        restore_sets
        ;;
    -h|--help|help)
        show_help 0
        ;;
    *)
        show_help 1
        ;;
esac
