#!/usr/bin/bash
sudo lxc delete sunbeam-one --force --project maas
sudo lxc delete maas --force
sudo lxc profile delete maas
sudo lxc network delete maas-ctrl
sudo lxc network delete maas-kvm
client_fingerprint=$(sudo lxc query /1.0/certificates?recursion=1 | jq -r '
.[] | select(.name == "maas") | .fingerprint')
sudo lxc config trust remove $client_fingerprint