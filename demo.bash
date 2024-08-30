#!/usr/bin/bash
sudo ufw disable
sudo snap install lxd
sudo lxd init --auto
sudo lxc network set lxdbr0 ipv6.address none
sudo lxc config set core.https_address [::]:8443

sudo lxc network create maas-ctrl
cat << __EOF | sudo lxc network edit maas-ctrl
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

sudo lxc network create maas-kvm
cat << __EOF | sudo lxc network edit maas-kvm
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

sudo lxc profile create maas
cat << __EOF | sudo lxc profile edit maas
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

sudo lxc launch ubuntu:jammy maas -p default -p maas
sudo lxc config device add maas eth0 nic name=eth0 nictype=bridged parent=maas-ctrl
sudo lxc config device set maas eth0 ipv4.address 10.10.0.2
echo "Restarting maas LXC container"
sudo lxc restart maas
sleep 30

cat << __EOF | sudo lxc exec maas -- tee /etc/netplan/99-maas-kvm-net.yaml
network:
    version: 2
    ethernets:
        eth1:
            addresses:
                - 10.20.0.2/24
__EOF
sudo lxc exec maas -- chmod 0600 /etc/netplan/99-maas-kvm-net.yaml
sudo lxc exec maas -- netplan apply

sudo lxc exec maas -- snap install maas-test-db

sudo lxc exec maas -- snap install maas

sudo lxc exec maas -- maas init region+rack --maas-url="http://10.10.0.2:5240/MAAS" --database-uri maas-test-db:///

sudo lxc exec maas -- maas createadmin --username maas --password maas --email maas@example.com

sudo lxc exec maas -- bash -c "maas apikey --username=maas | tee ./api-key"

while [[ "$(curl -k -s -o /dev/null -w "%{http_code}" http://10.10.0.2:5240/MAAS/api/2.0/)" == "502" ]]
do
	echo "Waiting for MAAS API to start"
	sleep 5
done
sudo lxc exec maas -- bash -c 'maas login maas http://10.10.0.2:5240/MAAS/api/2.0/ $(cat api-key)'
sudo lxc exec maas -- maas maas maas set-config name=upstream_dns value=8.8.8.8
sudo lxc exec maas -- maas logout maas

sudo lxc exec maas -- bash -c 'maas login maas http://10.10.0.2:5240/MAAS/api/2.0/ $(cat api-key)'
sudo lxc exec maas -- maas maas boot-resources import
sudo lxc exec maas -- maas logout maas

sudo lxc exec maas -- bash -c 'maas login maas http://10.10.0.2:5240/MAAS/api/2.0/ $(cat api-key)'
rack_controllers=$(sudo lxc exec maas -- maas maas rack-controllers read)
target_rack_controller=$(echo $rack_controllers | jq --raw-output .[].system_id)
target_fabric_id=$(echo $rack_controllers | jq '.[].interface_set[].links[] | select(.subnet.name | startswith('\"10.20.0.\"')) | .subnet.vlan.fabric_id')
sudo lxc exec maas -- maas maas subnet update 10.20.0.0/24 gateway_ip=10.20.0.1
export ip_range=$(sudo lxc exec maas -- maas maas ipranges create type=dynamic start_ip=10.20.0.99 end_ip=10.20.0.254 comment='To enable dhcp')
sudo lxc exec maas -- maas maas vlan update $target_fabric_id untagged dhcp_on=True primary_rack=$target_rack_controller
sudo lxc exec maas -- maas logout maas

token=$(sudo lxc config trust add --name maas | tail -1)
sudo lxc exec maas -- bash -c 'maas login maas http://10.10.0.2:5240/MAAS/api/2.0/ $(cat api-key)'
sudo lxc exec maas -- maas maas vm-hosts create type=lxd power_address=10.10.0.1 project=maas name=maas-host password="$token"
sudo lxc exec maas -- maas logout maas

sudo lxc exec maas -- bash -c 'maas login maas http://10.10.0.2:5240/MAAS/api/2.0/ $(cat api-key)'
sudo lxc exec maas -- maas maas vm-host compose 1 cores=12 memory=32000 storage=0:80 hostname=sunbeam-one
sudo lxc exec maas -- maas logout maas

sudo lxc exec maas -- bash -c 'maas login maas http://10.10.0.2:5240/MAAS/api/2.0/ $(cat api-key)'
system_id=$(sudo lxc exec maas -- maas maas machines read hostname=sunbeam-one | jq -r '.[0] | .system_id')
while [[ "$(sudo lxc exec maas -- maas maas machine read $system_id | jq -r .status_name)" != "Ready" ]]
do
	echo "Waiting for LXD VM to reach Ready status"
	sleep 5;
done
sudo lxc exec maas -- maas maas machine deploy $system_id

sudo lxc exec sunbeam-one --project maas -- snap install openstack --channel 2024.1/edge

sudo lxc exec sunbeam-one --project maas --user 1000 --group 1000 --cwd /home/ubuntu/ -- bash -c 'sunbeam prepare-node-script | tee /home/ubuntu/prepare-node.sh'
sudo lxc exec sunbeam-one --project maas --user 1000 --group 1000 --cwd /home/ubuntu/ --env HOME=/home/ubuntu/ -- bash /home/ubuntu/prepare-node.sh

sudo lxc exec sunbeam-one --project maas --user 1000 --group 584788 --cwd /home/ubuntu/ -- sunbeam cluster bootstrap --accept-defaults

sudo lxc exec sunbeam-one -- project maas --user 1000 --group 584788 --cwd /home/ubuntu/ -- sudo snap install data-science-stack --channel latest/stable

sudo lxc exec sunbeam-one --project maas --user 1000 --group 584788 --cwd /home/ubuntu/ -- dss initialize --kubeconfig"$(sudo microk8s config)"

sudo lxc exec sunbeam-one --project maas --user 1000 --group 584788 --cwd /home/ubuntu/ -- dss create my-notebook --image=kubeflownotebookswg/jupyter-scipy:v1.8.0