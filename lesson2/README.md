# Lesson 2 - Poking Around
This lesson will focus on exploring the core components of the cluster built in lesson 1. We'll make a few changes here and there, but use the same "lesson 1" version of the cluster as a base. Lessons 3 and up will get more into expanding the cluster with new components and getting it to look like more of a facsimile of something "production"-like. But it's really important to avoid moving on too fast before you are comfortable with the core system, which is what we are doing today.

## Bash completion and alias for kubectl
Before digging much further, it's worth taking a few minutes to make using `kubectl` on our hypervisor more comfortable. The first thing is to set up shell completion. If you ask `kubectl` nicely, it will output a script/config appropriate for enabling auto-completion on the command-line using various shell environments (including Windows PowerShell!).

  - Check out the `kubectl completion -h` for instructions and supported shells.

I'm using bash, so I start by running:
```
kubectl completion bash > ~/.kube/completion.bash.inc
```

Then I'll edit my `~/.bash_profile` config and add 3 things:
  - Enable the auto-completion script we just saved in `/.kube/completion.bash.inc`
  - Create an alias for `kubectl` that is simply `k`
  - Enable the bash-completion script for the `k` alias in addition to `kubectl`

I do this by adding the following to the end of my `~/.bash_profile`:
```
source $HOME/.kube/completion.bash.inc
alias k=kubectl
complete -F __start_kubectl k
```

And now I can start using tab-completion with my `k` alias to auto-complete things like pod names with ID's that I don't want to type out. Try it!


## 1 - NGINX Ingress Controller
Right now we can't easily connect to services inside the cluster from outside the cluster. The most common way to do that is through an ingress, and the most popular open-source ingress is `nginx-ingress`. The `kubeadm` tool doesn't install nginx-ingress by default, so let's install the nginx-ingress controller into our cluster so we can start accessing things from the outside.

I'm not going to re-create the docs here that already exist on how to install the nginx-ingress controller. Besides, if this is all pretty new to you, you'll want to get familiar with some of the most popular projects out there, where there documentation is, and how to find it. 

So head on over to [https://docs.nginx.com/nginx-ingress-controller/](https://docs.nginx.com/nginx-ingress-controller/) and see if you can get the controller up and running in your cluster. I'll be using normal manifests to install mine instead of a Helm chart, so I can see all the individual resources that make up the controller and get a feel for what they are and what they do. I recommend actually looking at these manifests before you apply them, and reading at least a brief summary of what each unfamiliar resource is.

If you get the controller up and running, see if you can create your own ingress for the `test` deployment of the previous lesson. We had to connect to that from within the `kmgmt` VM last time. See if you can set up an ingress for the service for external access from your hypervisor.

I ended up going with a DaemonSet for my nginx-ingress setup, with an ingress controller running on both worker1 and worker2. Remember, since these ingress controllers are our gateways into the cluster from the outside, they won't be very useful using an internal ClusterIP for their pods which is the default. I ended up modifying the DaemonSet yaml config to set `hostNetwork: true` within the spec for the DaemonSet. This way the bind to the IP address for the worker1 and worker2 nodes themselves and we can reach the ingress controllers from our hypervisor.



## 3 - kubelet

## 4 - 
