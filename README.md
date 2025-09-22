# Up-to-date firewall rules against malicious IPs
Scripts to make updated lists of IP sets to be blocked.

Current scripts create an `ipset` for the following publicly available IPs:
 - spamhaus DROP
 - SANS ISC
 - blocklist.de

After getting the lists and parsing them, `ipset` is created for each, which can be applied in your firewall, e.g., `iptables`, `ufw`.

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

# Make them permanent
This is a necessary step, otherwise after reboot the lists are not available for `ufw` to load, and then the whole `ufw` firewall stuck.

## Save current list
Let's save the ipset to a file
```
# ipset save -file /etc/ufw/rules.v4.ipsets
```

## Service to (re)store
Create a systemd service
```
# nano /etc/systemd/system/restore-ipset.service
```
Copy-paste the following into it (modify the path at will)
```
[Unit]
Description=Restore IPsets for Firewall
Before=ufw.service
After=network-online.target

[Service]
Type=oneshot
ExecStart=/sbin/ipset restore -exist --file /etc/ufw/rules.v4.ipsets
ExecStop=/sbin/ipset save -file /etc/ufw/rules.v4.ipsets

[Install]
WantedBy=multi-user.target
```
As you can see, the important part is `ExecStart`, which restores the ipsets from the file we created above. It also stores it when the service stop is being called to have the latest set in the memory to be stored.
The second important setting is the `Before` part that tells `systemd` to call this before `ufw` starts, so they will be readily available for `ufw`.

### Why not this script at startup
It would be a simple solution to make a service out of these scripts instead of the store-and-restore, but the lists can be huge and would take a lot of time everytime our system boots. Better to let the `crontab` update the list at 3 am everyday, and any time we reboot, we just restore quickly the latest set.

## Enable service
```
systemctl enable restore-ipset.service
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

The log entries will be sent to your system's logging service. On most systems, you can find them in one of these files:
```
/var/log/ufw.log
/var/log/syslog
/var/log/kern.log
```

You can use grep to easily find all log entries from your ipset rules by searching for the prefix you defined:
Bash

## This will show you all recent logged attempts from the SANS DShield blocklist
```
grep "UFW-SANS-DROP" /var/log/ufw.log
```
## This is a more general search if you are unsure which file to check
```
grep "UFW-SANS-DROP" /var/log/*
```
A sample log entry will look something like this:
```
[UFW-SANS-DROP: IN=eth0 OUT= MAC=... SRC=198.51.100.25 DST=203.0.113.12 LEN=44 TOS=0x00 PREC=0x00 TTL=112 ID=0 DF PROTO=TCP SPT=45423 DPT=22 WINDOW=1024 RES=0x00 SYN URGP=0 ]
```

All set up, thank me later :P
