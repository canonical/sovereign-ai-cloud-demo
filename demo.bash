#!/usr/bin/bash
sudo ufw disable
sudo snap install lxd
sudo lxd init --auto
lxc network set lxdbr0 ipv6.address none
lxc config set core.https_address [::]:8443

lxc network create maas-ctrl
cat << __EOF | lxc network edit maas-ctrl
config:
  dns.domain: maas-ctrl
  ipv4.address: 10.10.0.1/24
  ipv4.dhcp: "true"
  ipv4.dhcp.ranges: 10.10.0.16-10.10.0.31
  ipv4.nat: "true"
  ipv6.address: none
description: ""
name: maas-ctrl
type: bridge
used_by: []
managed: true
status: Created
locations:
- none
__EOF

lxc network create maas-kvm
cat << __EOF | lxc network edit maas-kvm
config:
  ipv4.address: 10.20.0.1/24
  ipv4.dhcp: "false"
  ipv4.nat: "true"
  ipv6.address: none
description: ""
name: maas-kvm
type: bridge
used_by: []
managed: true
status: Created
locations:
- none
__EOF

lxc profile create maas
cat << __EOF | lxc profile edit maas
config:
  raw.idmap: |
    uid 1000 1000
    gid 1000 1000
  user.vendor-data: |
    #cloud-config
    packages:
    - jq
description: Container for running MAAS server
devices:
  eth0:
    type: nic
    name: eth0
    network: maas-ctrl
  eth1:
    type: nic
    name: eth1
    network: maas-kvm
__EOF

lxc launch ubuntu:jammy maas -p default -p maas
lxc config device add maas eth0 nic name=eth0 nictype=bridged parent=maas-ctrl
lxc config device set maas eth0 ipv4.address 10.10.0.2
echo "Restarting maas LXC container"
lxc restart maas
sleep 30

cat << __EOF | lxc exec maas -- tee /etc/netplan/99-maas-kvm-net.yaml
network:
    version: 2
    ethernets:
        eth1:
            addresses:
                - 10.20.0.2/24
__EOF
lxc exec maas -- chmod 0600 /etc/netplan/99-maas-kvm-net.yaml
lxc exec maas -- netplan apply

lxc exec maas -- snap install maas-test-db

lxc exec maas -- snap install maas

lxc exec maas -- maas init region+rack --maas-url="http://10.10.0.2:5240/MAAS" --database-uri maas-test-db:///

lxc exec maas -- maas createadmin --username maas --password maas --email maas@example.com

lxc exec maas -- bash -c "maas apikey --username=maas | tee ./api-key"

while [[ "$(curl -k -s -o /dev/null -w "%{http_code}" http://10.10.0.2:5240/MAAS/api/2.0/)" != "404" ]]
do
	echo "Waiting for MAAS API to start"
	sleep 5
done
lxc exec maas -- bash -c 'maas login maas http://10.10.0.2:5240/MAAS/api/2.0/ $(cat api-key)'

echo "Set the upstream DNS for MAAS."
lxc exec maas -- maas maas maas set-config name=upstream_dns value=8.8.8.8

echo "Import boot resources (UEFI, PXE, OS images, etc.) to MAAS."
lxc exec maas -- maas maas boot-resources import

echo "Waiting for boot resources (UEFI, PXE, OS images, etc.) to import."
for resource_id in $(lxc exec maas -- maas maas boot-resources read | jq '.[] | .id')
do
  while [[ "$(lxc exec maas -- maas maas boot-resource read $resource_id | jq -r .type)" != "Synced" ]]
  do
    echo "Waiting for boot resource $(lxc exec maas -- maas maas boot-resource read $resource_id | jq -r .name) to sync."
    sleep 5;
  done
done
echo "All boot resources synced successfully."

echo "Configure networking for VMs in MAAS."
rack_controllers=$(lxc exec maas -- maas maas rack-controllers read)
target_rack_controller=$(echo $rack_controllers | jq --raw-output .[].system_id)
target_fabric_id=$(echo $rack_controllers | jq '.[].interface_set[].links[] | select(.subnet.name | startswith('\"10.20.0.\"')) | .subnet.vlan.fabric_id')
lxc exec maas -- maas maas subnet update 10.20.0.0/24 gateway_ip=10.20.0.1
export ip_range=$(lxc exec maas -- maas maas ipranges create type=dynamic start_ip=10.20.0.99 end_ip=10.20.0.254 comment='To enable dhcp')
lxc exec maas -- maas maas vlan update $target_fabric_id untagged dhcp_on=True primary_rack=$target_rack_controller

echo "Create LXD VM Host in MAAS."
token=$(lxc config trust add --name maas | tail -1)
lxc exec maas -- maas maas vm-hosts create type=lxd power_address=10.10.0.1 project=maas name=maas-host password="$token"

echo "Compose a LXD VM in MAAS."
sleep 90
system_id=$(lxc exec maas -- maas maas vm-host compose 1 cores=12 memory=32000 storage=0:80 hostname=sunbeam-one | jq -r .system_id)
status=$(lxc exec maas -- maas maas machine read $system_id | jq -r .status_name)
while [[ "$status" != "Ready" ]]
do
  status=$(lxc exec maas -- maas maas machine read $system_id | jq -r .status_name)
  if [[ $status == "Failed commissioning" ]]
  then
    echo "Commissioning failed. Trying again."
    lxc exec maas -- maas maas machine delete $system_id
    system_id=$(lxc exec maas -- maas maas vm-host compose 1 cores=12 memory=32000 storage=0:80 hostname=sunbeam-one | jq -r .system_id)
    status=$(lxc exec maas -- maas maas machine read $system_id | jq -r .status_name)
  fi
	echo "VM is in $status status. Waiting for LXD VM to reach Ready status"
	sleep 5
done

echo "Deploy the LXD VM in MAAS."
lxc exec maas -- maas maas machine deploy $system_id

while [[ "$status" != "Deployed" ]]
do
  status=$(lxc exec maas -- maas maas machine read $system_id | jq -r .status_name)
	echo "VM is in $status status. Waiting for LXD VM to reach Deployed status"
	sleep 5
done

lxc exec maas -- maas logout maas

lxc exec sunbeam-one --project maas -- snap install openstack --channel 2024.1/edge

lxc exec sunbeam-one --project maas --user 1000 --group 1000 --cwd /home/ubuntu/ -- bash -c 'sunbeam prepare-node-script | tee /home/ubuntu/prepare-node.sh'
lxc exec sunbeam-one --project maas --user 1000 --group 1000 --cwd /home/ubuntu/ --env HOME=/home/ubuntu/ -- bash /home/ubuntu/prepare-node.sh

lxc exec sunbeam-one --project maas --user 1000 --group 584788 --cwd /home/ubuntu/ -- sunbeam cluster bootstrap --accept-defaults

lxc exec sunbeam-one --project maas --user 1000 --group 584788 --cwd /home/ubuntu/ -- sudo snap install data-science-stack --channel latest/stable

lxc exec sunbeam-one --project maas --user 1000 --group 584788 --cwd /home/ubuntu/ -- bash -c 'dss initialize --kubeconfig="$(sudo microk8s config)"'

lxc exec sunbeam-one --project maas --user 1000 --group 584788 --cwd /home/ubuntu/ -- dss create my-notebook --image=kubeflownotebookswg/jupyter-scipy:v1.8.0