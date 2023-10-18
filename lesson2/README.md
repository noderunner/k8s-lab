# Lesson 2 - Poking Around
This lesson will focus on exploring the core components of the cluster built in lesson 1. We'll make a few changes here and there, but use the same "lesson 1" version of the cluster as a base. Lessons 3 and up will get more into expanding the cluster with new components and getting it to look like more of a facsimile of something more "production"-like. But it's really important to avoid moving on too fast before you are comfortable with the core system, which is what we are doing today.

## 1 - NGINX Ingress Controller
Right now we can't easily connect to services inside the cluster from outside the cluster. The most common way to do that is through an ingress, and the most popular open-source ingress is `nginx-ingress`. So let's install the nginx-ingress controller into our cluster so we can start accessing things from the outside.

I'm not going to re-create the docs here that already exist on how to install the nginx-ingress controller. Besides, if this is all pretty new to you, you'll want to get familiar with some of the most popular projects out there, where there documentation is, and how to find it. 

So head on over to [https://docs.nginx.com/nginx-ingress-controller/](https://docs.nginx.com/nginx-ingress-controller/) and see if you can get the controller up and running in your cluster. I'll be using normal manifests to install mine instead of a Helm chart, so I can see all the individual resources that make up the controller and get a feel for what they are and what they do. I recommend actually looking at these manifests before you apply them, and reading at least a brief summary of what each unfamiliar resource is.

If you get the controller up and running, see if you can create your own ingress for the `test` deployment of the previous lesson. We had to connect to that from within the `kmgmt` VM last time. See if you can set up an ingress for the service for external access from your hypervisor.

## 3 - kubelet

## 4 - 