### Kubernetes

# Deploy kubernetes-core with juju and re-use existing machines.
juju deploy kubernetes-core --map-machines=existing,0=0,1=1

# add the new kubernetes as a cloud to juju
mkdir ~/.kube
juju scp kubernetes-master/0:/home/ubuntu/config ~/.kube/config

# add storage relations
juju add-relation ceph-mon:admin kubernetes-master
juju add-relation ceph-mon:client kubernetes-master

# add k8s to juju (choose option 1, client only)
juju add-k8s my-k8s
juju bootstrap my-k8s
juju controllers

### Deploy a test application on K8s cluster

# Create a model in juju, which creates a namespace in K8s
juju add-model hello-kubecon

# Deploy the charm "hello-kubecon", and set a hostname for the ingress
juju deploy hello-kubecon --config juju-external-hostname=kubecon.test

# Deploy the ingress integrator - this is a helper to setup the ingress
juju deploy nginx-ingress-integrator ingress

# trust the ingress (it needs cluster credentials to make changes)
juju trust ingress --scope=cluster

# Relate our app to the ingress - this causes the ingress to be setup
juju relate hello-kubecon ingress

# Explore the setup
kubectl describe ingress -n hello-kubecon
kubectl get svc -n hello-kubecon
kubectl describe svc hello-kubecon-service -n hello-kubecon
kubectl get pods -n hello-kubecon

# Lastly, in order to be able to reach the service from outside our host machine,
# we can use port forwarding. Replace 10.10.10.5 with the IP seen on the ingress.
sudo iptables -t nat -A PREROUTING -p tcp -i $INTERFACE --dport 8000 -j DNAT --to-destination 10.10.10.5:80
echo
echo "If you want to persist this, run sudo dpkg-reconfigure iptables-persistent"
echo
echo "Now you should be able to open a browser and navigate to http://$IP_ADDRESS:8000"
echo
# scale our kubernetes cluster - find a machine
# Avoid kubernetes-master or existing kubernetes-worker machines
# https://discourse.charmhub.io/t/scaling-applications/1075
juju switch maas-cloud-default
juju status

# add a kubernetes-worker
juju add-unit kubernetes-worker --to 2

# add another kubecon unit
juju switch my-k8s
juju add-unit -n 1 hello-kubecon
juju status

# what happened to the ingress?
kubectl get ingress -n hello-kubecon
