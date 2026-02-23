#!/bin/bash

# Define the root directory of the script for sourcing extra.sh
ROOT="$(dirname "$0")"
source "$ROOT/sources/extra.sh"

# --- Configuration ---
# Default values for ipset name and threat intelligence URL
# These can be overridden by command-line arguments.
DEFAULT_IPSET_NAME="blocklist_de"
DEFAULT_BLOCKLIST_DE_URL="https://lists.blocklist.de/lists/all.txt"
# --- End Configuration ---

# Variables that will hold the final (default or overridden) values
IPSET_NAME=$DEFAULT_IPSET_NAME
BLOCKLIST_DE_URL=$DEFAULT_BLOCKLIST_DE_URL

# Function to display help message
function show_help ()
{
    c_print "Green" "This script gets the latest update from Blocklist.de and creates/updates an ipset to be used by firewalls!"
    c_print "Bold" "Example: sudo ./update_blocklist_de.sh [-i IPSET_NAME] [-u BLOCKLIST_DE_URL] "
    c_print "Bold" "\t-i <IPSET_NAME>: Define the name of the ipset (Default: ${DEFAULT_IPSET_NAME})."
    c_print "Bold" "\t-u <BLOCKLIST_DE_URL>: Blocklist.de list URL (Default: ${DEFAULT_BLOCKLIST_DE_URL})."
    exit $1
}

# --- Argument Parsing ---
# Check if no arguments were provided
if [ "$#" -eq 0 ]; then
    c_print "Yellow" "No arguments were provided, falling back to defaults..."
fi

# Parse command-line arguments
while getopts "h?i:u:" opt
do
    case "$opt" in
    h|\?)
        show_help 0
        ;;
    i)
        IPSET_NAME=$OPTARG
        ;;
    u)
        BLOCKLIST_DE_URL=$OPTARG
        ;;
    *)
        show_help 1 # Exit with non-zero for invalid option
        ;;
    esac
done

# Define the log file. It's now dynamic based on IPSET_NAME.
LOG_FILE="${ROOT}/logs/${IPSET_NAME}_update.log"

# Define a temporary file for downloading the list
TEMP_FILE="${ROOT}/temp/${IPSET_NAME}_latest.list"


# Shift off the options and their arguments
shift $((OPTIND-1))

# --- Pre-requisite Checks ---
c_print "Bold" "--- $(date) ---"

# Check for required commands (these are sourced from extra.sh)
check_command "ipset" "ipset"
check_command "curl" "curl"
# grep, sed, tee, mktemp are typically part of coreutils and almost always present.

# Display the variables being used
c_print "Bold" "Using the following variables:"
c_print "Bold" "  IPSET_NAME: ${IPSET_NAME}"
c_print "Bold" "  BLOCKLIST_DE_URL: ${BLOCKLIST_DE_URL}"

# --- Main Script Logic ---

# Redirect all output (stdout and stderr) to the log file and stdout
# This ensures that both console and log file get the "fancy" output.
exec > >(tee -a "$LOG_FILE") 2>&1

c_print "Bold" "Starting update for ipset '$IPSET_NAME' from '$BLOCKLIST_DE_URL'..." 

# Check if the ipset set already exists. If not, create it.
if ! sudo ipset list "$IPSET_NAME" &>/dev/null; then
    c_print "Yellow" "Ipset set '$IPSET_NAME' does not exist. Creating it now..." no_newline
    # Changed from hash:net to hash:ip for individual IP addresses
    sudo ipset create "$IPSET_NAME" hash:ip family inet hashsize 1024 maxelem 1048576
    check_retval "$?" # Pass actual exit status
else
    c_print "Green" "Ipset set '$IPSET_NAME' already exists. Proceeding with update."
fi

# Download the list, filter out comments (lines starting with '#') and empty lines.
# No awk needed as it's one IP per line.
c_print "Bold" "Downloading and filtering threat intelligence list..." no_newline
curl -s "$BLOCKLIST_DE_URL" | \
        grep -v '^#' | \
        grep -v '^$' > "$TEMP_FILE"
check_retval "$?" # Pass actual exit status

# Create a new temporary set for atomic swap
c_print "Bold" "Creating temporary ipset set for atomic swap..." 
# Changed from hash:net to hash:ip
sudo ipset create "${IPSET_NAME}_new" hash:ip family inet hashsize 1024 maxelem 1048576
TEMP_CREATE_STATUS=$? # Capture status of first create attempt
if [ "$TEMP_CREATE_STATUS" -ne 0 ]; then
    # If initial creation failed, it might exist from a previous failed run; try to destroy and recreate
    c_print "Yellow" "Temporary ipset set might already exist, attempting to recreate..." no_newline
    sudo ipset destroy "${IPSET_NAME}_new" # Destroy previous attempt if it exists
    sudo ipset create "${IPSET_NAME}_new" hash:ip family inet hashsize 1024 maxelem 1048576
    check_retval "$?" # Pass actual status of the recreate attempt
else
    check_retval "$TEMP_CREATE_STATUS" # Pass original success status
fi

COUNT=$(wc -l < "$TEMP_FILE")
# Start a progress printout without a newline
c_print "Bold" "Adding ${COUNT} IP addresses to the temporary set..." 
# Add IPs to the new set
while IFS= read -r ip_entry; do
    ADD_COUNT_PROCESSED=$((ADD_COUNT_PROCESSED + 1))
    
    # Use tr for robustness against any leading/trailing whitespace
    ip_address=$(echo "$ip_entry" | tr -d '[:space:]')
    
    if [[ -n "$ip_address" ]]; then # Ensure it's not empty
        # Add to ipset quietly; individual failures are often due to malformed entries or duplicates
        sudo ipset add "${IPSET_NAME}_new" "$ip_address" 2>/dev/null
        if [ "$?" -eq 0 ]; then # Check if the add command itself was successful
            ADD_COUNT_SUCCESS=$((ADD_COUNT_SUCCESS + 1))
        fi
    fi

    # Print the progress on the same line, overwriting the previous one
    # We update every 50 entries to avoid excessive I/O, and at the end.
    if [ $((ADD_COUNT_PROCESSED % 50)) -eq 0 ] || [ "$ADD_COUNT_PROCESSED" -eq "$COUNT" ]; then
        # The '\r' moves the cursor to the beginning of the line
        printf "\rAdding %'d of %'d addresses..." "$ADD_COUNT_PROCESSED" "$COUNT"
    fi
done < "$TEMP_FILE"
# After the loop, print a final newline to ensure subsequent output starts on a new line
echo ""

# Check success of the adding process - any actual failures would be logged by ipset,
# but the loop itself finishing is a 'success' for the process of attempting to add.
c_print "Cyan" "Added $ADD_COUNT_SUCCESS of $ADD_COUNT_PROCESSED entries to temporary set ($(( ADD_COUNT_PROCESSED - ADD_COUNT_SUCCESS )) duplicates/invalid skipped)." no_newline
check_retval 0 # Assuming loop execution is a success, individual add failures are minor


# Swap the new set with the active one atomically
c_print "Bold" "Swapping new set with active set..." no_newline
sudo ipset swap "${IPSET_NAME}_new" "$IPSET_NAME"
check_retval "$?" # Pass actual exit status

# Destroy the old set (which is now named "${IPSET_NAME}_new" after the swap)
c_print "Bold" "Destroying old (temporary) set..." 
sudo ipset destroy "${IPSET_NAME}_new"
DESTROY_STATUS=$? # Capture status of destroy
if [ "$DESTROY_STATUS" -ne 0 ]; then
    # This is typically not fatal, as the main set is active. Log a warning but don't exit.
    c_print "Orange" "Warning: Failed to destroy old temporary ipset set '${IPSET_NAME}_new'. Status: $DESTROY_STATUS"
fi
# No check_retval here, as we explicitly want to *not* exit on this non-fatal warning.

# Clean up temporary file
# The following lines are commented out as per your baseline
# c_print "Bold" "Cleaning up temporary file..." no_newline
# rm "$TEMP_FILE"
# check_retval "$?" # Pass actual exit status

c_print "Green" "Blocklist.de list update finished for ipset '$IPSET_NAME'."

# Print summary of the active ipset
c_print "Bold" "--- Ipset summary for '$IPSET_NAME' ---"
sudo ipset list "$IPSET_NAME" -t

c_print "Bold" "--- End $(date) ---"

# Exit with success code
exit 0