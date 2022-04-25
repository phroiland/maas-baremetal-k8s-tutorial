# Copyright 2012-2021 Canonical Ltd.  This software is licensed under the
# GNU Affero General Public License version 3 (see the file LICENSE).

# README FIRST
# You need a reasonably powerful bare metal machine, 4 or more cores with 32 GB of RAM and 500GB of free disk space. Assumes a fresh install of Ubuntu server (20.04 or higher) on the machine.
# You need a bare metal machine is because nesting multiple layers of VMs will not work and/or have performance problems.
# Note: this tutorial has not been tested on versions prior to 20.04.
# DATE=$(date +%Y%N)

# lxd / maas issue. either upgrade lxd or maas to 3.1
sudo snap install --channel=latest/stable lxd
sudo snap refresh --channel=latest/stable lxd
sudo snap install jq
sudo snap refresh jq
sudo snap install maas
sudo snap refresh maas
# sudo snap install maas-test-db
# sudo snap refresh maas-test-db

# get local interface name (this assumes a single default route is present)
export INTERFACE=$(ip route | grep default | cut -d ' ' -f 5)
echo $INTERFACE
export IP_ADDRESS=$(ip -4 addr show dev $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo $IP_ADDRESS
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sysctl -p
sudo iptables -t nat -A POSTROUTING -o $INTERFACE -j SNAT --to $IP_ADDRESS

#TODO inbound port forwarding/load balancing
# Persist NAT configuration
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo apt-get install iptables-persistent -y

# LXD init
sudo cat ~/dev/maas-baremetal-k8s-tutorial/lxd.conf | lxd init --preseed
lxc network show lxdbr0
lxd waitready

# Postgres setup
export MAAS_DB_OWNER=maas
export MAAS_DB_NAME=maas
export MAAS_DB_PASSWD=maas
sudo -u postgres psql -c "CREATE ROLE \"$MAAS_DB_OWNER\" LOGIN PASSWORD '$MAAS_DB_PASSWD'"
sudo -u postgres createdb -O "$MAAS_DB_OWNER" "$MAAS_DB_NAME"
sudo -u postgres psql -c "GRANT all privileges on DATABASE \"$MAAS_DB_NAME\" to \"$MAAS_DB_OWNER\""
export PG_HBA=$(sudo -u postgres psql -c "show hba_file" | sed -ne '/etc/p')
echo $PG_HBA | sed -e 's/\ *$//g'
# echo "host    $MAAS_DB_OWNER            $MAAS_DB_NAME            0/0                     md5" | sudo tee -a $PG_HBA

# Initialise MAAS
sudo maas init region+rack --database-uri "postgres://$MAAS_DB_OWNER:$MAAS_DB_PASSWD@localhost/$MAAS_DB_NAME" --maas-url http://${IP_ADDRESS}:5240/MAAS

# sleep 15

# Create MAAS admin and grab API key
sudo maas createadmin --username admin --password admin --email admin

export APIKEY=$(sudo maas apikey --username admin)
echo $APIKEY
maas login admin http://$IP_ADDRESS:5240/MAAS/ $APIKEY

# Configure MAAS networking (set gateways, vlans, DHCP on etc)
export SUBNET=10.10.10.0/24

echo $SUBNET

export FABRIC_ID=$(maas admin subnet read "${SUBNET}" | jq -r ".vlan.fabric_id")

echo $FABRIC_ID

export VLAN_TAG=$(maas admin subnet read "${SUBNET}" | jq -r ".vlan.vid")

echo $VLAN_TAG

export PRIMARY_RACK=$(maas admin rack-controllers read | jq -r ".[] | .system_id")

echo $PRIMARY_RACK

maas admin subnet update $SUBNET gateway_ip=10.10.10.1 > /dev/null
maas admin ipranges create type=dynamic start_ip=10.10.10.200 end_ip=10.10.10.254 > /dev/null
maas admin vlan update $FABRIC_ID $VLAN_TAG dhcp_on=True primary_rack=$PRIMARY_RACK > /dev/null
maas admin maas set-config name=upstream_dns value=8.8.8.8 > /dev/null

# Add LXD as a VM host for MAAS and capture the VM_HOST_ID
export VM_HOST_ID=$(maas admin vm-hosts create password=password type=lxd power_address="https://${IP_ADDRESS}:8443" project=maas | jq '.id')
echo $VM_HOST_ID

# allow high CPU oversubscription so all VMs can use all cores
maas admin vm-host update $VM_HOST_ID cpu_over_commit_ratio=4

# create tags for MAAS
maas admin tags create name=juju-controller comment='This tag should to machines that will be used as juju controllers'
maas admin tags create name=metal comment='This tag should to machines that will be used as bare metal'

exit
### creating VMs for Juju controller and our "bare metal"

# add a VM for the juju controller with minimal memory
maas admin vm-host compose $VM_HOST_ID cores=3 memory=4096 architecture="amd64/generic" storage="main:16(pool1)" hostname="juju-controller"

# get the system-id and tag the machine with "juju-controller"
export JUJU_SYSID=$(maas admin machines read | jq  '.[] | select(."hostname"=="juju-controller") | .["system_id"]' | tr -d '"')
echo $JUJU_SYSID

maas admin tag update-nodes "juju-controller" add=$JUJU_SYSID

## Create 3 "bare metal" machines and tag them with "metal"
# export ID=1
for ID in 1 2 3
  do
    maas admin vm-host compose $VM_HOST_ID cores=2 memory=8192 architecture="amd64/generic" storage="main:25(pool1),ceph:100(pool1)" hostname="metal-${ID}"
    SYSID=$(maas admin machines read | jq -r --arg MACHINE "metal-${ID}" '.[] | select(."hostname"==$MACHINE) | .["system_id"]' | tr -d '"')
    echo $SYSID
    maas admin tag update-nodes "metal" add=$SYSID
  done
# endfor

### Reference materials notes
# https://jaas.ai/ceph-base
# https://jaas.ai/canonical-kubernetes/bundle/471
# https://medium.com/swlh/kubernetes-external-ip-service-type-5e5e9ad62fcd
# https://charmhub.io/nginx-ingress-integrator
# https://drive.google.com/file/d/1estQna40vz4uS5tBd9CvKdILdwAmcNFH/view - hello-kubecon
# https://ubuntu.com/kubernetes/docs/troubleshooting - troubleshooting
# https://juju.is/blog/deploying-mattermost-and-kubeflow-on-kubernetes-with-juju-2-9

### END
