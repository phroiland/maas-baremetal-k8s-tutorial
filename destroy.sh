# scale down hello-kubecon
juju remove-unit --num-units 1  hello-kubecon

# scaledown kubernetes
juju switch maas-cloud-default
juju remove-unit kubernetes-worker/1
juju status

# if you want to test destroying your hello-kubecon:
juju switch my-k8s
juju destroy-model hello-kubecon --release-storage

# if you want to destroy your kubenetes controller for juju
juju switch maas-cloud-default
juju destroy-controller my-k8s

# if you want to remove your k8s cluster:
juju switch maas-cloud-default
juju remove-application kubernetes-master kubernetes-worker etcd flannel easyrsa

# if you want to remove ceph
juju switch maas-cloud-default
juju remove-application ceph-mon ceph-osd

# To clean up everything:
juju destroy-controller -y --destroy-all-models --destroy-storage maas-cloud-default

echo
echo "And the machines created in MAAS can be deleted easily in the MAAS GUI."
echo

