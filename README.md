# Up-to-date firewall rules against malicious IPs
Scripts to make updated lists of IP sets to be blocked.

Current scripts create an `ipset` for the following publicly available IPs:
 - spamhaus DROP
 - SANS ISC
 - blocklist.de

After getting the lists and parsing them, an `ipset` is created and kept up to date for each source.

> [!WARNING]
> **These scripts only manage the `ipset` lists — they do NOT protect your system by themselves.**
> Simply running the scripts does not block any traffic. To be protected, you must manually add the ipsets to your firewall (`ufw`, `iptables`, etc.).
> See the **[Add `ipset` to `ufw`](#add-ipset-to-ufw)** section at the bottom of this file for step-by-step instructions. This is a one-time manual setup.

# Bootstrap — Install Dependencies
Before running any update scripts, make sure the required dependencies (`curl` and `ipset`) are installed. A bootstrap script is provided to handle this automatically on Debian-based systems.

```bash
sudo ./bootstrap.sh
```

This will:
1. Verify the system uses `apt`
2. Run `apt update`
3. Install `curl` and `ipset`

---

# Use
All scripts below must be run separately/sequentially, and no arguments are needed to be specified. They will all make a relevant `ipset` for each list, which later you can add to `ufw`.

## Spamhaus DROP list (few thousands of rules)
This script get the latest update from Spamhaus DROP list and create an ipset to be used by firewalls!

Example: 
```
./update_spamhaus_drop.sh [-i IPSET_NAME] [-u SPAMHAUS_URL] 
        -i <IPSET_NAME>: define the name of the ipset (Default: spamhaus_drop).
        -u <SPAMHAUS_URL>: update Spamhaus DROP list url (Default: https://www.spamhaus.org/drop/drop.txt).
```
## SANS DShield (a few IP ranges)
This script gets the latest update from SANS ISC DShield Recommended Blocklist and creates/updates an ipset to be used by firewalls!

Example: 
```
sudo ./update_sans_dshield.sh [-i IPSET_NAME] [-u SANS_ISC_URL] 
        -i <IPSET_NAME>: Define the name of the ipset (Default: sans_dshield).
        -u <SANS_ISC_URL>: SANS ISC DShield list URL (Default: https://isc.sans.edu/block.txt).
```
## Blocklist.de (tens of thousands of rules)
This script gets the latest update from Blocklist.de and creates/updates an ipset to be used by firewalls!

Example: 
```
sudo ./update_blocklist_de.sh [-i IPSET_NAME] [-u BLOCKLIST_DE_URL] 
        -i <IPSET_NAME>: Define the name of the ipset (Default: blocklist_de).
        -u <BLOCKLIST_DE_URL>: Blocklist.de list URL (Default: http://lists.blocklist.de/lists/all.txt).
```

# Example output
```
./update_spamhaus_drop.sh 
No arguments were provided, falling back to defaults...
--- Fri 01 Aug 2025 08:56:58 AM +08 ---
Checking for 'ipset' command...                                                                                                [FOUND]
Checking for 'curl' command...                                                                                                 [FOUND]
Using the following variables:
 IPSET_NAME: spamhaus_drop
 SPAMHAUS_URL: https://www.spamhaus.org/drop/drop.txt
--- Fri 01 Aug 2025 08:56:58 AM +08 ---
Starting update for ipset 'spamhaus_drop' from 'https://www.spamhaus.org/drop/drop.txt'...
Ipset set 'spamhaus_drop' already exists. Proceeding with update.
Downloading and filtering threat intelligence list...                                                                          [DONE]
Creating temporary ipset set for atomic swap...                                                                                [DONE]
Adding IP addresses to the temporary set...
Adding 1,577 of 1,577 addresses...
[DONE]
Added entries to temporary set.
Swapping new set with active set...                                                                                            [DONE]
Destroying old (temporary) set...
Spamhaus DROP list update finished for ipset 'spamhaus_drop'.
--- End Fri 01 Aug 2025 08:57:12 AM +08 ---

```

# Automate with Cron
To keep the ipsets updated daily without manual intervention, use the provided `setup_cron.sh` script. It registers all three update scripts into `/etc/crontab`, staggered to avoid simultaneous load.

```bash
sudo ./setup_cron.sh
```

This will add the following jobs to `/etc/crontab`:

```
0  2 * * * root /path/to/update_blocklist_de.sh    # 02:00 daily
15 2 * * * root /path/to/update_sans_dshield.sh   # 02:15 daily
30 2 * * * root /path/to/update_spamhaus_drop.sh  # 02:30 daily
```

The script is **idempotent** — running it multiple times will not create duplicate entries.

To verify the installed jobs:
```bash
grep -E "update_blocklist_de|update_sans_dshield|update_spamhaus_drop" /etc/crontab
```

To remove them, edit `/etc/crontab` directly:
```bash
sudo nano /etc/crontab
```

---

# Make them permanent
This is a necessary step. `ipset`s live in kernel memory only, so after a reboot they are gone, and `ufw` refuses to load `before.rules` if a referenced set is missing — leaving you with **no firewall at all**.

```bash
sudo ./setup_persistence.sh
```

This will:
1. Install [`ipset_persist.sh`](ipset_persist.sh) to `/usr/local/sbin/` (so booting does not depend on where this repo lives)
2. Install and enable `ipsets-to-block.service`, which restores the sets at boot **right before `ufw` starts**
3. Save the currently loaded sets to `/var/lib/ipsets_to_block/<IPSET_NAME>.save`

After that, every update script saves its fresh set to `/var/lib/ipsets_to_block/` at the end of each run, so a reboot always restores the latest lists from the last cron run.

The script is **idempotent** — re-run it after pulling a new version of this repo to refresh the installed copy.

To verify:
```bash
systemctl status ipsets-to-block.service
ls -l /var/lib/ipsets_to_block/
```

### How it works
- **Where the sets are stored:** `/var/lib/ipsets_to_block/`, one file per set. This is not owned by any package, so neither a `ufw` upgrade/purge, nor `ufw reset`, nor a `git pull`/re-clone of this repo touches it. Override with the `IPSET_SAVE_DIR` environment variable.
- **When they are saved:** after every successful update (written to a temp file and renamed, so an interrupted save never leaves a truncated file). They are *not* saved at shutdown, so a failed restore can never overwrite good data with empty sets.
- **When they are restored:** at early boot, ordered exactly like `ufw.service` (`DefaultDependencies=no`, `After=local-fs.target`, `Before=ufw.service network-pre.target`). Sets that already exist are left untouched. If a save file is corrupted, an **empty** set is created instead, so `ufw` still loads all its other rules; the next cron run refills it.

### Restore at boot manually
```bash
sudo /usr/local/sbin/ipset_persist.sh restore
```

### Why not run the update scripts at startup
It would be a simple solution to make a service out of the update scripts instead of the save-and-restore, but the lists can be huge, need network access (which is not up yet when `ufw` starts), and would take a lot of time every time the system boots. Better to let `crontab` update the lists every night, and any time we reboot, we just quickly restore the latest saved sets.

### Migrating from the old `restore-ipset.service`
Earlier versions of this README suggested a hand-written `restore-ipset.service` storing everything in `/etc/ufw/rules.v4.ipsets`. That unit did not work reliably:
- `After=network-online.target` + `Before=ufw.service` is an **ordering cycle**: `ufw.service` runs *before* `network-pre.target`, which is itself before `network-online.target`. systemd breaks the cycle by dropping one of the jobs, so `ufw` often started before the sets existed and failed to load.
- `Type=oneshot` without `RemainAfterExit=yes` makes systemd run `ExecStop` immediately after `ExecStart`, so the "save on shutdown" just re-saved the sets loaded at boot, and the file never received the updates from cron.
- The file lived in `/etc/ufw/`, a directory owned by the `ufw` package.

`setup_persistence.sh` disables the old unit automatically. Afterwards, you can remove the leftovers:
```bash
sudo rm /etc/systemd/system/restore-ipset.service /etc/ufw/rules.v4.ipsets
sudo systemctl daemon-reload
```

# Check your ipsets:
```
sudo ipset list
```

## Inspect the Contents of a Specific ipset Set
```
sudo ipset list spamhaus_drop
```

## Get only the names of your ipset
```
sudo ipset list | grep -i name
```

# Add `ipset` to `ufw`
## Install `ufw` (if haven't already)
```
sudo apt install ufw
```
## Enable `ufw`
```
sudo systemctl enable ufw
sudo systemctl start ufw
sudo ufw enable
```

## Add the rules
Edit `before.rules`:
```
sudo nano /etc/ufw/before.rules 
```
Scroll to the bottom, before the `COMMIT`, and add these lines
```
# Drop all packets from ipset "spamhaus_drop" and add specific LOG tag 
-A ufw-before-input -m set --match-set spamhaus_drop src -j LOG --log-prefix "UFW-SPAMHAUS-DROP: "
-A ufw-before-input -m set --match-set spamhaus_drop src -j DROP

# Drop all packets from ipset "sans_dshield" and add specific LOG tag 
-A ufw-before-input -m set --match-set sans_dshield src -j LOG --log-prefix "UFW-SANS-DROP: "
-A ufw-before-input -m set --match-set sans_dshield src -j DROP

# Drop all packets from ipset "blocklist_de" and add specific LOG tag 
-A ufw-before-input -m set --match-set blocklist_de src -j LOG --log-prefix "UFW-BLOCKLISTDE-DROP: "
-A ufw-before-input -m set --match-set blocklist_de src -j DROP
```

## Reload `ufw`
```
sudo ufw reload
```

## Check rules (with `iptables`)
```
sudo iptables -L ufw-before-input -v -n

[REDACTED]

0     0 DROP       0    --  *      *       0.0.0.0/0            0.0.0.0/0            match-set spamhaus_drop src
0     0 DROP       0    --  *      *       0.0.0.0/0            0.0.0.0/0            match-set sans_dshield src
0     0 DROP       0    --  *      *       0.0.0.0/0            0.0.0.0/0            match-set blocklist_de src
```
You should see the drop rules defined on the `ipsets`. 

# Where to Find the Logs

## Step 1 — Enable UFW logging

UFW logging is **disabled by default**. Without it, no blocked packets will be recorded. Enable it first:
```bash
sudo ufw logging on
sudo ufw status verbose | grep Logging   # verify it's on
```

## Step 2 — Check where logs go

Modern Debian/Ubuntu systems often ship **without `rsyslog`**, meaning there are no flat log files like `/var/log/ufw.log` or `/var/log/syslog`. Logs go to `systemd-journald` instead.

Check whether `rsyslog` is installed:
```bash
systemctl status rsyslog
```

### If rsyslog is NOT installed (journald only)
Read logs directly from the journal:
```bash
# All UFW ipset drops, today
sudo journalctl -k --since today | grep "UFW-"

# Filter by a specific blocklist
sudo journalctl -k --since today | grep "UFW-SANS-DROP"
sudo journalctl -k --since today | grep "UFW-SPAMHAUS-DROP"
sudo journalctl -k --since today | grep "UFW-BLOCKLISTDE-DROP"

# Follow live (like tail -f)
sudo journalctl -k -f | grep "UFW-"
```

Optionally install rsyslog to get flat log files back:
```bash
sudo apt install rsyslog
```

### If rsyslog IS installed (flat log files)
```bash
grep "UFW-SANS-DROP" /var/log/ufw.log
grep "UFW-SANS-DROP" /var/log/syslog
grep "UFW-" /var/log/kern.log
```

## Step 3 — Verify rules are actually matching traffic

If you see no log entries at all, check whether the iptables rules are loaded and if packet counters are incrementing:
```bash
sudo iptables -L ufw-before-input -v -n | grep -E "spamhaus|sans|blocklist"
```
The first two columns are packet and byte counts. If they're all `0     0`, no traffic has matched any blocked IP yet — that's normal if your server hasn't been probed by a listed address.

## Sample log entry
```
[UFW-SANS-DROP: IN=eth0 OUT= MAC=... SRC=198.51.100.25 DST=203.0.113.12 LEN=44 TOS=0x00 PREC=0x00 TTL=112 ID=0 DF PROTO=TCP SPT=45423 DPT=22 WINDOW=1024 RES=0x00 SYN URGP=0 ]
```

All set up, thank me later :P
