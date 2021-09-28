#!/bin/bash

# This script is run from the hypervisor (which hosts undercloud and controler vms) as root
# The setup is done via infrared

OPT="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
VHOST1=$(ssh "$OPT" stack@undercloud-0 "source overcloudrc; openstack network show vhostuser1 -c id -f value ")
VHOST2=$(ssh "$OPT" stack@undercloud-0 "source overcloudrc; openstack network show vhostuser2 -c id -f value ")
ansible-playbook play.yaml -e network_ids="$VHOST1,$VHOST2" -e resource_names="intelnics_vhost1,intelnics_vhost2"
