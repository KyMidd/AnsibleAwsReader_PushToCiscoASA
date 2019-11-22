#!/bin/bash
# Author: Kyler Middleton

# Exit script if any command exits with a non-zero status
set -e

# This script downloads the IP ranges from AWS, filters them, and writes them to a file

# Set variables
DATE=`date '+%m-%d-%Y %H:%M:%S'`

# cd to the script directory
cd /home/svc_ansible/awsPe1FwUpdater

# Download ip-ranges from AWS. Stored as ip-ranges.json
echo "Fetching ip-ranges from AWS"
wget -N https://ip-ranges.amazonaws.com/ip-ranges.json

## Check if ip-ranges.json has updated in past 3 minutes, exit. 3 minutes chosen because scripts runs every 3 minutes
if [[ $(find ip-ranges.json -mmin +3) ]]; then
 echo "No changes, exiting"
 echo $DATE "No updated IPs from AWS, exiting script - failed=0" >> /var/log/ansible.log
 exit
fi

# filter json with jq, output list of prefixes in CIDR notation. Output stored as CIDRlist
echo "Building CIDR list and filtering"
jq -r '[.prefixes[] | select(.region=="us-east-1" and .service=="AMAZON").ip_prefix] | .[]' ip-ranges.json > CIDRlist

# Remove old version of playbook
rm -f AWS2ASAPlaybook > /dev/null 2>&1

# Build new file
# Write static
cat <<EOL >> AWS2ASAPlaybook
---
- hosts: pe1_fw
  gather_facts: yes
  connection: local

  tasks:
  - name: Include Login Credentials
    include_vars: secrets.yml

  - name: Define Provider
    set_fact:
      provider:
        host: "{{ ansible_host }}"
        username:  "{{ creds['username'] }}"
        password:  "{{ creds['password'] }}"
        authorize: yes
        auth_pass: "{{ creds['auth_pass'] }}"

  - name: SAVE "Write Commands"
    asa_config:
      provider: "{{ provider }}"
      commands:
        - no access-list PE1_CORE_IN-ACL permit tcp 10.45.0.0 255.255.0.0 object-group outside_ansible_AWSGlobalEast1_groupB eq 443
        - no access-list PE1_CORE_IN-ACL permit tcp 10.48.0.0 255.255.0.0 object-group outside_ansible_AWSGlobalEast1_groupB eq 443
        - no access-list PE1_CORE_IN-ACL remark Ansible AWS global East-1 groupB
        - no object-group network outside_ansible_AWSGlobalEast1_groupB


  - name: SAVE "Write Commands"
    asa_config:
      provider: "{{ provider }}"
      commands:
EOL

# Write dynamic
input="CIDRlist"
while IFS= read -r read
do
    subnet=$(echo "${read%%/*}")
    netmask=$(ipcalc -m "$read")
    netmask=$(echo "${netmask#*=}")
    echo "        - network-object $subnet $netmask" >> AWS2ASAPlaybook
done < "$input"

# Write static
cat <<EOL >> AWS2ASAPlaybook
        - description last updated at $DATE
      parents: ['object-group network outside_ansible_AWSGlobalEast1_groupB']


  - name: SAVE "Write Commands"
    asa_config:
      provider: "{{ provider }}"
      commands:
        - access-list PE1_CORE_IN-ACL line 1 remark Ansible AWS global East-1 groupB
        - access-list PE1_CORE_IN-ACL line 2 permit tcp 10.45.0.0 255.255.0.0 object-group outside_ansible_AWSGlobalEast1_groupB eq 443
        - access-list PE1_CORE_IN-ACL line 3 permit tcp 10.48.0.0 255.255.0.0 object-group outside_ansible_AWSGlobalEast1_groupB eq 443


  - name: SAVE "Write Commands"
    asa_config:
      provider: "{{ provider }}"
      commands:
        - no access-list PE1_CORE_IN-ACL permit tcp 10.45.0.0 255.255.0.0 object-group outside_ansible_AWSGlobalEast1_groupA eq 443
        - no access-list PE1_CORE_IN-ACL permit tcp 10.48.0.0 255.255.0.0 object-group outside_ansible_AWSGlobalEast1_groupA eq 443
        - no access-list PE1_CORE_IN-ACL remark Ansible AWS global East-1 groupA
        - no object-group network outside_ansible_AWSGlobalEast1_groupA


  - name: SAVE "Write Commands"
    asa_config:
      provider: "{{ provider }}"
      commands:
EOL

# Write dynamic
input="CIDRlist"
while IFS= read -r read
do
    subnet=$(echo "${read%%/*}")
    netmask=$(ipcalc -m "$read")
    netmask=$(echo "${netmask#*=}")
    echo "        - network-object $subnet $netmask" >> AWS2ASAPlaybook
done < "$input"

# Write static
cat <<EOL >> AWS2ASAPlaybook
        - description last updated at $DATE
      parents: ['object-group network outside_ansible_AWSGlobalEast1_groupA']

  - name: SAVE "Write Commands"
    asa_config:
      provider: "{{ provider }}"
      commands:
        - access-list PE1_CORE_IN-ACL line 1 remark Ansible AWS global East-1 groupA
        - access-list PE1_CORE_IN-ACL line 2 permit tcp 10.45.0.0 255.255.0.0 object-group outside_ansible_AWSGlobalEast1_groupA eq 443
        - access-list PE1_CORE_IN-ACL line 3 permit tcp 10.48.0.0 255.255.0.0 object-group outside_ansible_AWSGlobalEast1_groupA eq 443
EOL

# Execute AWS2ASAPlaybook playbook - script pushes to ASA
echo "Executing playbook with ansible"
ansible-playbook AWS2ASAPlaybook

# Finish?
FINISHDATE=`date '+%m-%d-%Y %H:%M:%S'`
echo "Pe1Fw AWS IPs updated by Ansible on" $FINISHDATE "by" $HOSTNAME
