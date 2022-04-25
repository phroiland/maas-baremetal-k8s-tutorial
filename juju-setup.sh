### Juju setup (note, this section requires manual intervention)
# cd ~
sudo snap install juju --classic
sed -i "s/IP_ADDRESS/$IP_ADDRESS/" ~/dev/maas-baremetal-k8s-tutorial/maas-cloud.yaml
juju add-cloud --local maas-cloud ~/dev/maas-baremetal-k8s-tutorial/maas-cloud.yaml
juju add-credential maas-cloud
juju clouds --local
juju credentials

# Bootstrap the maas-cloud - get a coffee
juju bootstrap maas-cloud --bootstrap-constraints "tags=juju-controller mem=2G"

# fire up the juju gui to view the fun
# if it's a remote machine, you can use an SSH tunnel to get access to it:
# e.g. ssh ubuntu@x.x.x.x -L8080:10.10.10.2:17070
juju dashboard

# get coffee

# check jujus view of machines
juju machines

# add machines to juju from the maas cloud
# it will grab the 3 we already created since they are in a "READY state"

for ID in 1 2 3
do
    juju add-machine
done

# take a look at machines list again, should see 3 machines
juju machines

### Ceph

# deploy ceph-mon to LXD VMs inside our metal machines
juju deploy -n 3 ceph-mon --to lxd:0,lxd:1,lxd:2
# juju deploy -n 1 ceph-mon --to lxd:0

# deploy ceph-osd directly to the machines
juju deploy --config ~/dev/maas-baremetal-k8s-tutorial/ceph-osd.yaml cs:ceph-osd -n 3 --to 0,1,2
# juju deploy --config ~/dev/maas-baremetal-k8s-tutorial/ceph-osd.yaml cs:ceph-osd -n 1 --to 0

# relate ceph-mon and ceph-osd
juju add-relation ceph-mon ceph-osd

# watch the fun (with a another coffee).
watch -c juju status --color
