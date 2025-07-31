# Up-to-date firewall rules against malicious IPs
Scripts to make updated lists of IP sets to be blocked.

Current scripts create an `ipset` for the following publicly available IPs:
 - spamhaus DROP
 - SANS ISC
 - blocklist.de

After getting the lists and parsing them, `ipset` is created for each, which can be applied in your firewall, e.g., `iptables`, `ufw`.


