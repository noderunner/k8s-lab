# k8s-lab
Notes, scripts, manifests, how-to's, etc. for my Kubernetes home lab environment. This is intended to be a general-purpose lab environment for any kind of testing I might want to perform. It's suited to my personal convenience and might not be suitable for yours.

My needs are:
  - Runs under Fedora with little fuss.
  - Suitable for IT/Ops testing as well as app development.

## Why Aren't You Using...

### Minikube?
Minikube is cool for app development against a bare-bones k8's environment. But it's made more for ease-of-use for app development than IT/Ops related work. It doesn't reflect how any rational org would build and architect a real-world k8's cluster. I'm going more for maximum control than one-click install. In fact, the more "manual" the setup, the better for learning.

### Kind?
Kind is running a k8's cluster with Docker. I think it's an even better approach for app-developers than Minikube, but an even worse analogy for how one might build a "real-world" cluster.

### Terraform?
Terraform is quite popular in most orgs, but I've found that TF providers for enterprise targets like Dell and HP are a lot more mature than libvirt/QEMU. I may go back to fiddling with TF as a provisioner for our QEMU virtual machines, but for now we'll just use simple scripts with `virsh`.

## Architecture
  - **libvirt/QEMU:** Not very elegant, I know. But it's easier to build an analogy to bare-metal installations, which will ultimately be better for testing how things might be done on a "production" cluster.
    - We'll connect the VM's to a bridged network instead of NAT to keep things simple when we want to connect to the cluster from anywhere in our home network.
  - **Fedora CoreOS:** for the VM's which is likely to be a popular option for real world orgs building on-prem clusters.
  - **RKE2:** which is a popular Kubernetes distribution for organizations to meet CIS and FIPS 140-2 security standards.
  - **Rancher:** Most orgs will be running Rancher for cluster management, RBAC, and user Auth.
  - **Calico:** We will set up Calico for our CNI which is a popular choice, but keep things flexible so we can expermiment with alternatives.
  - This is just the base. From here we can continue to build and experiement with more. Some likely candidates are:
    - OpenTelemetry + Promscale
    - Trivy
    - Neuvector
    - Flux
    - CircleCI
    - GitLab CI
    - Hashicorp Vault

## Docs
If you want to follow along in a tutorial style, read about opinions, find links, etc., relevent to what I'm doing here that's all under `docs/` and in simple markdown. 

## Scripts
This might turn into a bit of a dump-ing ground of bash and python snippets for common things that I don't find worth memorizing, but I'll try and keep things organized.

## Kustomize
I prefer the simpler, flat manifests of Kustomize over Helm and will be dumping all my stuff in the `ks/` folder for that.
