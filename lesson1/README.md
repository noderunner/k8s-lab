# Cluster Build Tutorial From Scratch
This is a tutorial-style walkthrough to build our core Kubernetes lab cluster. This is done in a fairly manual approach so that you can get a better understanding of all the different layers, components, and their relationships. We can work on automating the build of the cluster later so that it's a lot faster to update versions and change things around.

## Assumptions
I'm making the following assumptions in how I explain things here, namely: 
  - You are comfortable with Linux, networking, containers, Bash, etc.
  - You are setting this up on Fedora Linux as your host OS, or at least have enough knowledge to translate to whatever it is you are using.
  - You have enough system resources to dedicate 12 CPU cores and 24GB of memory to the cluster. If not, you can scale down to just a single worker node but won't be able to test a lot of scenarios that way.
  - You have full root/admin access to your system, a reliable network, non-restricted Internet access, etc. Basically, I can't help you if you are building this at work in some heavily firewall-restricted environment.

## Goal
At the end of this tutorial, you should have a very bare-bones Kubernetes cluster that you can interact with using `kubectl` and run pods on.

## Kubernetes Node Architecture
We are going to use a simple layout for the Kubernetes cluster: A single control plane node with 2 worker nodes. If you are completely clueless about the Kubernetes architecture and what the different core components do, it would be a good idea to review that soon, if not now. We will create 3 Virtual Machines with the following roles:

  - **kmgmt:** A single "management" VM will be our control-plane node. Later on, we will also run Rancher here.
  - **worker1:** Dedicated as a worker node.
  - **worker2:** Dedicated as a 2nd worker node.

## Plan Static IP Space
We'll be connecting our guest VM's to the same network as the hypervisor over a bridge. Your home network probably has a DHCP server which would hand out IP's to the guest VM's after booting up, but our cluster nodes will need to be able to talk to each other easily and it will be a pain over time to maintain and update `/etc/hosts` entries whenever we want to rebuild these nodes. So instead, let's just plan to make our lives easier and assign static IP addresses to our guest VM's.

To make sure I don't have any IP conflicts on my home network, I logged into my home router and modified the default DHCP address pool from `192.168.1.2 - .254` to `192.168.1.2 - .100`. I'll assign static IP's in the .101-254 range as follows:

  - kmgmt:   .110
  - worker1: .101
  - worker2: .102

I want to be able to access these nodes from my hypervisor later by their name, so I'll add the above entries to my `/etc/hosts` file on my hypervisor:

```
192.168.1.110 kmgmt
192.168.1.101 worker1
192.168.1.102 worker2
```

You'll want to then edit each of the {kmgmt,worker1,worker2}.bu files in this `lesson1` dir of this repo and modify the IP addresses to match your network schema:
```
    # Static Networking Config
    - path: /etc/NetworkManager/system-connections/enp1s0.nmconnection
      mode: 0600
      contents:
        inline: |
          [connection]
          id=enp1s0
          type=ethernet
          interface-name=enp1s0
          [ipv4]
          address1=192.168.1.110/24,192.168.1.1
          dns=192.168.1.1;
          dns-search=
          may-fail=false
          method=manual
    # Static hosts file setup
    - path: /etc/hosts
      mode: 0644
      overwrite: true
      contents:
        inline: |
          192.168.1.110 kmgmt
          192.168.1.101 worker1
          192.168.1.102 worker2
```

We can look at getting fancier in later lessons to simulate the automation you'd likely want to use in a real environment, but for now using a static IP schema like this will keep things simple and clean.

## 1 - Install Virtualization Packages
We'll need to install several packages in order to turn our Fedora workstation into a fully-functional hypervisor. If you aren't already familiar with each of these tools and how they work together, it's well worth spending the additional time to understand them better. You should have a pretty clear understanding of why we are installing these packages and how they are going to be used. Some of these packages are optional (we won't actually have a need for openvswitch until we want to do more elaborate network testing), but this should cover everything we need for a good while.

Note that `podman` is not for virtualization but for running containers. We'll use that for some of our steps later on. Why are we not using Docker to run containers? Because it's not 2018 anymore and its time to switch to more open standards, that's why.

```
sudo dnf -y install \
  qemu-kvm \
  libvirt \
  libvirt-client \
  python3-libvirt \
  virt-manager \
  bridge-utils \
  qemu-system-x86 \
  virt-install \
  virt-top \
  openvswitch \
  podman
```

## 2 - Generate SSH Keypair
If you don't already have an SSH keypair you want to use when logging into your VM's, generate one now. Note that if you try to use older, weaker encryption key types such as RSA or DSA, the modern CoreOS guests configured with more up-to-date security requirements will simply reject it. So use a more modern key type such as ECDSA. I'm not going to put a passphrase on my key so that I can SSH into my VM's more easily.

`ssh-keygen -t ecdsa`


## Configure libvirt for Modular Daemons
While libvirt supports multiple drivers for managing different types of virtual machines (VirtualBox, QEMU/KVM, LXC, etc.), it has recently transistion from a monolithic architecture where those drivers are built-in toward a more modular architecture where a separate libvirt{driver}d daemon is maintained for each type of driver. Most Linux distributions are switching to the modular runtime mode of libvirt by default, but some distros still running the default libvirtd.service.

Here we will configure libvirtqemud as our modular daemon of choice, managed by systemd. More information about the monolithic vs. modular approach and different types of daemons available can be found in the libvirt documentaion: https://libvirt.org/daemons.html

Running `systemctl status libvirtd.service` on my Fedora 38 system, I can see that the monolithic version of libvirtd is the current default on my system:

```
[mstevenson@fedora terraform-provider-libvirt]$ systemctl status libvirtd.service
○ libvirtd.service - Virtualization daemon
     Loaded: loaded (/usr/lib/systemd/system/libvirtd.service; enabled; preset: disabled)
    Drop-In: /usr/lib/systemd/system/service.d
             └─10-timeout-abort.conf
     Active: inactive (dead) since Mon 2023-10-23 22:04:14 EDT; 1 week 4 days ago
   Duration: 28.849s
TriggeredBy: ● libvirtd-ro.socket
             ● libvirtd.socket
             ○ libvirtd-tls.socket
             ○ libvirtd-tcp.socket
             ● libvirtd-admin.socket
       Docs: man:libvirtd(8)
             https://libvirt.org
    Process: 178343 ExecStart=/usr/sbin/libvirtd $LIBVIRTD_ARGS (code=exited, status=0/SUCCESS)
   Main PID: 178343 (code=exited, status=0/SUCCESS)
      Tasks: 2 (limit: 32768)
     Memory: 7.4M
        CPU: 168ms
     CGroup: /system.slice/libvirtd.service
             ├─176791 /usr/sbin/dnsmasq --conf-file=/var/lib/libvirt/dnsmasq/virbr10.conf --leasefile-ro --dhcp-script=/usr/lib>
             └─176792 /usr/sbin/dnsmasq --conf-file=/var/lib/libvirt/dnsmasq/virbr10.conf --leasefile-ro --dhcp-script=/usr/lib>
```

I'll be following the "Switching to modular daemons" section of the [libvirt docs](https://libvirt.org/daemons.html) for configuring the more modular *libvirtqemud* service:

1. Stop the current monolithic daemon and its socket units:
```
sudo systemctl stop libvirtd.service
sudo systemctl stop libvirtd{,-ro,-admin,-tcp,-tls}.socket
```

2. For extra protection, I use systemd to *mask* instead of just disabling the above services so they do not accidentally get re-enabled:
```
sudo systemctl mask libvirtd.service
sudo systemctl mask libvirtd{,-ro,-admin,-tcp,-tls}.socket
```

3. Enable the new daemons for the qemu driver, including secondary drivers to accompany it:
```
sudo su
for drv in qemu interface network nodedev nwfilter secret storage; do
systemctl unmask virt${drv}d.service
systemctl unmask virt${drv}d{,-ro,-admin}.socket
systemctl enable virt${drv}d.service
systemctl enable virt${drv}d{,-ro,-admin}.socket
done
```

4. Start the sockets for each daemon. There is no need to start the services, as they will get started by systemd when the first socket connection is established:

```
sudo su
for drv in qemu network nodedev nwfilter secret storage; do
systemctl start virt${drv}d{,-ro,-admin}.socket
done
```

5. We will also enable the virtproxyd service. Not not because there is a need to support controlling libvirt remotely, but because virtproxyd will provide a compatibility layer for libvirt clients that insist on connecting to the UNIX socket at `/var/run/libvirt/libvirt-sock`. This will allow us to use tools like Terraform to provision virtual machines even though we plan to run virtqemud in non-privileged "session" mode.
```
sudo systemctl unmask virtproxyd.service
sudo systemctl unmask virtproxyd{,-ro,-admin}.socket
sudo systemctl enable virtproxyd.service
sudo systemctl enable virtproxyd{,-ro,-admin}.socket
sudo systemctl start virtproxyd{,-ro,-admin}.socket
```

6. If you actually do want to manage virtqemud remotely on your network, you should also enable `virtproxyd-tls` to provide a TLS-protected TCP socket for remote clients. I have no need for this, so I skip this step:

```
sudo systemctl unmask virtproxyd-tls.socket
sudo systemctl enable virtproxyd-tls.socket
sudo systemctl start virtproxyd-tls.socket
```


## 3 - Create Ignition Scripts
[Ignition](https://docs.fedoraproject.org/en-US/fedora-coreos/producing-ign/) is the tool FCOS uses during installation for setting up disks and writing files. We can pass scripts to Ignition when each of the FCOS virtual machines boot to help automate the installation of the Fedora Core OS on each of our 3 VM's so that we don't have to manually click through install menu's and enter information. This will obviously be much better and allow us to easily rebuild our VM's quickly whenever we want to change them.

Ignition scripts must be in JSON for Ignition to accept them. Writing raw JSON parsable by Ignition is doable, but not very fun. So there is a tool called `butane` to take a more friendly YAML formatted Ignition script and convert it to JSON, which we'll do here for readability sake. Literally we are just converting YAML to JSON which is a pretty common thing to have dedicated CLI tools for, but we get some extra linting checks, butane will compress text elements after a certain size to keep things small, and well, that's the way things are done now in the Fedora/RHEL CoreOS ecosystem so best to just get over it.

So to recap, we are going to make 3 scripts (one for each of our 3 virtual machines) as YAML files, then use `butane` to convert the YAML files into JSON files, which will then be passed into the VM's when we power them up for the first time to auto-install the OS on each one.

The butane configs for each of the 3 VM's are in the "conf" dir of this repository and named after each virtual machine:
  - kmgmt.bu
  - worker1.bu
  - worker2.bu

You can't use each one directly as-is in this repo. You'll need to add some values:

  - First, you'll want to copy the public key for the SSH key you generated in the previous step into the into the `ssh_authorized_keys` value of each .bu file. This is how the default `core` user is set up so that you can easily SSH into each VM after it builds.
  - I also like to generate a default root password for each system and put the password hash in here. This isn't strictly necessary since you should be able to use `sudo` as the core user, but I just like adding this in case I want to get into the console as root to fix something. You can use podman to run the `mkpasswd` utility and generate a password hash for your password by running `podman run -ti --rm quay.io/coreos/mkpasswd --method=yescrypt` entering the password you want to use for the root user, and then copying the resulting hash into the .bu files.
  
The rest of the .bu files can be left as is, but you should go through them and understand what they are doing:
  - Setting up the CRI-O DNF module so that we can use CRI-O instead of the default containerd (more on this later).
  - Setting the hostname of each VM.
  - Setting up the official kubernetes YUM repository for installing Kubernetes packages.
  - Enabling netfilter on the bridge network interface that each VM will be configured to use.
  - Setting up some kernel network parameters for kublet to work properly on each VM.

## 4 - Convert Butane configs to Ignition Configs
We don't have to install butane to convert the configs from YAML to JSON. Again, we can use podman to fetch a container image of the latest version of butane and run it locally, then delete it again after running with:
```
podman run --interactive --rm \
quay.io/coreos/butane:release \
--pretty --strict < kmgmt.bu > kmgmt.ign
```

We might be running this option and that's a lot to type out, so why not make a bash alias to make it easier?
```
echo 'alias butane="podman run --interactive --rm quay.io/coreos/butane:release --pretty --strict"' >> ~/.bashrc
```

And now whenever we want to update the scripts we can just run `butane < file.bu > file.ign`

## 5 - Configure Network Bridge
If we were to start building VM's now, libvirt would add each guest VM to the "default" network managed by libvirt. This is what *most* people want *most* of the time, but this is *not* one of those times. The "default" network uses what some call a "routing bridge", which operates at layer-3 and performs Network Address Translation and uses routing tables with IP's. That's normally fine. But if we want to play with Calico and its ability to advertise BGP routes to devices on the home network to simulate how we might do so in a production environment, this could get a little funky.

Instead we will opt for a plain old bridge. This (virtual) bridge device will take over the IP address of our "real" network interface on the hypervisor. We will then connect our real, physical network device to the bridge, causing our real NIC to show up as a slave device. The other VM's will also have their virtual interfaces joined to the same bridge. 

As a result, both our host OS and the guest VM's will appear to be on the same "flat" network with no routers in-between (because there won't be). The destination of packets will be determined by MAC address instead of IP address. This will make our VM guests appear as if they are additional hosts on the same network as our hypervisor.

There are several tools we could use to create and configure the bridge interface, such as `ip link add`, `brctl create`, as well as manually editing files in `/etc`. If you search around for tutorials on how to create bridge devices and set up networking in Linux, especially for purposes of running libvirt guest VM's, you'll find various ways of doing it that could all work. 

I'm on Fedora and I'm going to use the built-in *Network Manager* system, with the CLI tool `nmcli` to create mine. This has the advantage of also creating persistent configuration for the bridge device in `/etc/NetworkManager/system-connections/` so that the bridge device persists across reboots. Let's get to it.

First verify the device name of your physical NIC by running `ip a`:
```
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute 
       valid_lft forever preferred_lft forever
2: enp5s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 00:d8:61:7b:c4:38 brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.25/24 brd 192.168.1.255 scope global dynamic noprefixroute enp5s0
       valid_lft 86392sec preferred_lft 86392sec
    inet6 fe80::2d50:463d:a45c:c00b/64 scope link noprefixroute 
       valid_lft forever preferred_lft forever
3: wlo1: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default qlen 1000
    link/ether 76:22:9c:40:06:f7 brd ff:ff:ff:ff:ff:ff permaddr 90:78:41:92:3e:e3
    altname wlp0s20f3
```

You can see that my Fedora workstation has the standard loopback interface `lo`, a currently unused 802.11 wireless device `wlo1`, and an Ethernet Network Port `enp5s0` with the IP address assigned from my home WiFi Router via DHCP as `192.168.1.25`. 

Let's also take a look at my network devices as seen through Network Manager, which adds an additional layer of abstraction above network *devices* called *connections* by running: `sudo nmcli connection show`:

```
[root@fedora system-connections]# sudo nmcli connection show
NAME                UUID                                  TYPE      DEVICE 
Wired connection 1  dfbd61e1-e9f2-439b-bc0c-c8f0212efdf5  ethernet  enp5s0 
lo                  a3ef685c-d0b1-451c-9877-459a2d6ad608  loopback  lo   
```

Here you can see that my `enp5s0` device is given the more friendly name `Wired connection 1`. We don't see my `wl01` wireless device here because I have never bothered to configure it, so there is no *connection* configured for the device.

***Be prepared to lose network connectivity for a few minutes while you perform the next few steps!***

We are going to start by deleting the wired connection because we want the DHCP server on my local network to assign an IP address to the new virtual bridge device we are about to create, not directly to the real physical interface:
```
[root@fedora system-connections]# sudo nmcli connection delete "Wired connection 1"
Connection 'Wired connection 1' (dfbd61e1-e9f2-439b-bc0c-c8f0212efdf5) successfully deleted.

[root@fedora system-connections]# sudo nmcli connection show
NAME  UUID                                  TYPE      DEVICE 
lo    a3ef685c-d0b1-451c-9877-459a2d6ad608  loopback  lo  

[root@fedora system-connections]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute 
       valid_lft forever preferred_lft forever
2: enp5s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 00:d8:61:7b:c4:38 brd ff:ff:ff:ff:ff:ff
3: wlo1: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default qlen 1000
    link/ether 36:03:47:c3:73:77 brd ff:ff:ff:ff:ff:ff permaddr 90:78:41:92:3e:e3
    altname wlp0s20f3
```

After deleting the connection, I lose all network connectivity and you can see that while my physical device still exists of course, it no longer has an IP Address assigned to it.


Now I'll create a new virtual bridge device named "vbr0":
```
[root@fedora system-connections]# sudo nmcli connection add type bridge autoconnect yes con-name vbr0 ifname vbr0
Connection 'vbr0' (5d42e8fd-2ac9-47a5-bb17-28b95881adc6) successfully added.

[root@fedora system-connections]# sudo nmcli con show
NAME  UUID                                  TYPE      DEVICE 
vbr0  5d42e8fd-2ac9-47a5-bb17-28b95881adc6  bridge    vbr0   
lo    a3ef685c-d0b1-451c-9877-459a2d6ad608  loopback  lo     

[root@fedora system-connections]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute 
       valid_lft forever preferred_lft forever
2: enp5s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 00:d8:61:7b:c4:38 brd ff:ff:ff:ff:ff:ff
3: wlo1: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default qlen 1000
    link/ether 36:03:47:c3:73:77 brd ff:ff:ff:ff:ff:ff permaddr 90:78:41:92:3e:e3
    altname wlp0s20f3
5: vbr0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default qlen 1000
    link/ether 3e:d0:1a:5d:89:b1 brd ff:ff:ff:ff:ff:ff
```

You can see that after I create the virtual bridge device, it is not assigned an IP address from my DHCP server yet and the state of the `vbr0` interface shows as "DOWN". This is because after creating the virtual bridge device, I didn't actually *connect* that bridge to the physical NIC on my machine, so it isn't seeing any of the packets on my home network yet. Let's do that now:

```
[root@fedora system-connections]# sudo nmcli connection add type bridge-slave ifname enp5s0 master vbr0
Connection 'bridge-slave-enp5s0' (ae318094-28f6-47a0-9494-e549245cd3f3) successfully added.

[root@fedora system-connections]# sudo nmcli connection show
NAME                 UUID                                  TYPE      DEVICE 
vbr0                 5d42e8fd-2ac9-47a5-bb17-28b95881adc6  bridge    vbr0   
lo                   a3ef685c-d0b1-451c-9877-459a2d6ad608  loopback  lo     
bridge-slave-enp5s0  ae318094-28f6-47a0-9494-e549245cd3f3  ethernet  enp5s0 

[root@fedora system-connections]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute 
       valid_lft forever preferred_lft forever
2: enp5s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel master vbr0 state UP group default qlen 1000
    link/ether 00:d8:61:7b:c4:38 brd ff:ff:ff:ff:ff:ff
3: wlo1: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default qlen 1000
    link/ether c6:56:c5:c0:4e:d8 brd ff:ff:ff:ff:ff:ff permaddr 90:78:41:92:3e:e3
    altname wlp0s20f3
5: vbr0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default qlen 1000
    link/ether 00:d8:61:7b:c4:38 brd ff:ff:ff:ff:ff:ff

```

You can see that now there is a *connection* between my virtual bridge device and my physical ethernet device. There is a new *connection* to show this when using `nmcli`, while our *devices* look the same when running `ip a`. 

But wait, we still don't have an IP address or working network connectivity. What gives? This is normal. We just need to bring the bridge device down and then back up again so it that it sends a DHCP REQEST out on our home network asking to be assigned an IP address when it first starts up:

```
[root@fedora system-connections]# sudo nmcli con down vbr0
Connection 'vbr0' successfully deactivated (D-Bus active path: /org/freedesktop/NetworkManager/ActiveConnection/5)

[root@fedora system-connections]# sudo nmcli con up vbr0
Connection successfully activated (master waiting for slaves) (D-Bus active path: /org/freedesktop/NetworkManager/ActiveConnection/7)

[root@fedora system-connections]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute 
       valid_lft forever preferred_lft forever
2: enp5s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel master vbr0 state UP group default qlen 1000
    link/ether 00:d8:61:7b:c4:38 brd ff:ff:ff:ff:ff:ff
3: wlo1: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default qlen 1000
    link/ether ea:f3:a7:27:37:66 brd ff:ff:ff:ff:ff:ff permaddr 90:78:41:92:3e:e3
    altname wlp0s20f3
6: vbr0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 00:d8:61:7b:c4:38 brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.25/24 brd 192.168.1.255 scope global dynamic noprefixroute vbr0
       valid_lft 86237sec preferred_lft 86237sec
    inet6 fe80::e8e8:fcc5:75b0:8619/64 scope link noprefixroute 
       valid_lft forever preferred_lft forever

[root@fedora system-connections]# ping -c 3 8.8.8.8
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=60 time=3.43 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=60 time=3.34 ms
64 bytes from 8.8.8.8: icmp_seq=3 ttl=60 time=3.85 ms

--- 8.8.8.8 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2003ms
rtt min/avg/max/mdev = 3.340/3.539/3.848/0.221 ms
```

In my case, it took a good 30 seconds or so for my vbr0 bridge device to pick up an IP address from the network again, so just be patient and then verify your network is up again. Notice that the IP address is now assigned to our virtual bridge `vbr0` instead of our physical interface `enp5s0`. This is what we want.

Next we need to make sure that IP forwarding is properly enabled on our hypervisor:
```
[root@fedora sysctl.d]# echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-sysctl.conf
[root@fedora sysctl.d]# sysctl -p /etc/sysctl.d/99-sysctl.conf
[root@fedora sysctl.d]# sysctl -n net.ipv4.ip_forward
1
```

That last line is just confirming that the value is set to 1 actively in the kernel.

Lastly, we'll want to disable any netfilter rules set up by default on our Fedora workstation, as they tend to filter by IP's and the conntrack table. A default set of firewall rules in netfilter has a good chance of blocking some of the traffic inteded for our guest VM's. I don't have any firewall filters set up on my system, but you can confirm yours with `iptables -nL`. You'll want to either disable or modify Firewalld or any other netfilter configs you have set up before moving on to make sure nothing blocks traffic to our guest VM's.

Obviously, this isn't reflective of a real environment. We'll look at multiple security tools in later lessons to start building out the security better and making it look more like a real production system. But let's not get ahead of ourselves.

## 6 - Configure libvirt non-root Access
By default, you'll need to manage VM's as the root user on your hypervisor. This is going to quickly become annoying, so let's take the time now to allow our regular user account full use of the virtualization system:

```
[mstevenson@fedora system-connections]$ sudo usermod -aG mstevenson,wheel,libvirt,qemu,kvm mstevenson
[sudo] password for mstevenson: 
[mstevenson@fedora system-connections]$ newgrp libvirt
[mstevenson@fedora system-connections]$ newgrp qemu
[mstevenson@fedora system-connections]$ newgrp kvm
[mstevenson@fedora system-connections]$ groups
kvm wheel qemu libvirt mstevenson
```

## 7 - Whitelist Bridge for QEMU
We want to manage the VM's as our normal, un-privileged user for convenience sake, but QEMU by default requires root privileges when attaching VM's to bridge devices. Let's make that easier by adding the virtual bridge interface to a kind of whitelist config file:

```
echo "allow vrbr0" > /etc/qemu/bridge.conf
systemctl restart libvirtd
```

## 8 - Download Fedora CoreOS Image
Now let's download an install image of FCOS. Since we are using QEMU, we want to download a .qcow2 image. You can head to the [download page](https://fedoraproject.org/coreos/download/?stream=stable) to do so, or you can install and use the `coreos-install` cli tool to do the same thing, your choice:

```
[mstevenson@fedora ~]$ sudo dnf -y install coreos-installer

[mstevenson@fedora ~]$ coreos-installer download -p qemu -f qcow2.xz -d -C ~/Downloads/
Downloading Fedora CoreOS stable x86_64 qemu image (qcow2.xz) and signature
> Read disk 616.5 MiB/616.5 MiB (100%)   
gpg: Signature made Wed 04 Oct 2023 04:21:24 AM EDT
gpg:                using RSA key 6A51BBABBA3D5467B6171221809A8D7CEB10B464
gpg: checking the trustdb
gpg: marginals needed: 3  completes needed: 1  trust model: pgp
gpg: depth: 0  valid:   4  signed:   0  trust: 0-, 0q, 0n, 0m, 0f, 4u
gpg: Good signature from "Fedora (38) <fedora-38-primary@fedoraproject.org>" [ultimate]
/home/mstevenson/Downloads/fedora-coreos-38.20230918.3.0-qemu.x86_64.qcow2
```

## 9 - Build Cluster VM's
We are ready to start building our guest VM's for the cluster. To do this, we'll use the `virt-install` command, passing in the following important information:
  - The CPU, memory, and disk allocation for the guest VM
  - Bridging to the vbr0 bridge we created previously
  - The image to boot into (we just downloaded this)
  - The Ignition config file to use for the automated OS installation

Since the command to do this is long and hard to remember, I've created 3 bash scripts in the `lesson1/` dir, one for each guest. Be sure to edit each one to size the guest VM resources appropriately for what your system can handle. Yes, we *could* get this down to one script and pass in some of the node-specific information as variables, but we are only working with 3 nodes here and when we are really ready to add additional layers of automation and abstraction to this part in order to simulate are more realistic production environment, we'll use something more robust like Terraform or another alternative. For now, let's just keep it simple.

To build a each guest, you'll simply create the ignition config file for the guest in the local directory of the script:
```
[mstevenson@fedora scripts]$ butane --pretty --strict < ~/kmgmt.bu > kmgmt.ign
[mstevenson@fedora scripts]$ butane --pretty --strict < ~/worker1.bu > worker1.ign
[mstevenson@fedora scripts]$ butane --pretty --strict < ~/worker2.bu > worker2.ign
```

Before the build scripts will work correctly, you'll need to edit each one and update the `IGNITION_CONFIG=` line to provide the **full path** to the correct .ign file. The `virt-install` tool will fail to pass in the Ignition file correctly if you do not use a full path here.

Once that's done, we can run the script and pass in the full path to the .qcow2 image for FCOS that you want to use for the build:
```
[mstevenson@fedora scripts]$ ./kmgmt_kvm.sh ~/Downloads/fedora-coreos-38.20230918.3.0-qemu.x86_64.qcow2
```

If all goes as planned, your terminal will connect to the console of the guest VM as it builds. Build time should go pretty quick and you should end up with a login prompt inside the VM. This is why I bothered to set a root password within my Ignition script, so that once the VM is finished building and presents a login prompt at the console, I can log in as the root user and confirm the network comes up as expected.

I logged into my kmgmt host and verified that it eventually obtained an IP address from my local network and that I appear to have working Internet capability inside the VM:

```
[root@kmgmt ~]# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute 
       valid_lft forever preferred_lft forever
2: enp1s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 52:54:00:b2:a0:b5 brd ff:ff:ff:ff:ff:ff
    inet 192.168.1.110/24 brd 192.168.1.255 scope global dynamic noprefixroute enp1s0
       valid_lft 49539sec preferred_lft 49539sec
    inet6 fe80::f346:860b:5877:c9ca/64 scope link noprefixroute 
       valid_lft forever preferred_lft forever

[root@kmgmt ~]# ping -c 3 8.8.8.8
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=60 time=3.36 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=60 time=3.44 ms

[root@kmgmt ~]# dig www.google.com

; <<>> DiG 9.18.17 <<>> www.google.com
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 50552
;; flags: qr rd ra; QUERY: 1, ANSWER: 6, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 65494
;; QUESTION SECTION:
;www.google.com.			IN	A

;; ANSWER SECTION:
www.google.com.		28	IN	A	142.250.31.99
www.google.com.		28	IN	A	142.250.31.147
www.google.com.		28	IN	A	142.250.31.104
www.google.com.		28	IN	A	142.250.31.103
www.google.com.		28	IN	A	142.250.31.106
www.google.com.		28	IN	A	142.250.31.105

;; Query time: 4 msec
;; SERVER: 127.0.0.53#53(127.0.0.53) (UDP)
;; WHEN: Sun Oct 08 14:15:26 UTC 2023
;; MSG SIZE  rcvd: 139
```

It did take a minute or two for my guest VM to be assigned an IP address, so just be patient if that is the case for you. You'll want to use the same process for building the worker1 and worker2 VM's and verify that they have connectivity. You should also make sure that each node can ping the other nodes by their name as expected:
```
[root@kmgmt ~]# ping -c 2 worker1
PING worker1 (192.168.1.101) 56(84) bytes of data.
64 bytes from worker1 (192.168.1.101): icmp_seq=1 ttl=64 time=0.313 ms
64 bytes from worker1 (192.168.1.101): icmp_seq=2 ttl=64 time=0.266 ms

--- worker1 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1057ms
rtt min/avg/max/mdev = 0.266/0.289/0.313/0.023 ms

[root@kmgmt ~]# ping -c 2 worker2
PING worker2 (192.168.1.102) 56(84) bytes of data.
64 bytes from worker2 (192.168.1.102): icmp_seq=1 ttl=64 time=0.205 ms
64 bytes from worker2 (192.168.1.102): icmp_seq=2 ttl=64 time=0.231 ms

--- worker2 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1030ms
rtt min/avg/max/mdev = 0.205/0.218/0.231/0.013 ms
```

When you are ready to log out and detach from the console of the VM, just type the escape sequence at any time, which is `Control + ]` and you will be returned to your original bash shell on the hypervisor. 

If you are new to using libvirt, a few essential commands are as follows:

  - View your VMs: `virsh list`
  - Connect to the serial console of a VM: `virsh console <domain>`
  - Power off a VM: `virsh destroy <domain>`
  - Power on a VM: `virsh start <domain>`
  - Completely delete a VM: `virsh undefine <domain>`

**Note: The names of your VM's are called "domains" in libvirt.**

We should also verify that we can SSH into the VM from our hypervisor as the default "core" user account using the SSH key we set up in the Ignition script:

```
[mstevenson@fedora scripts]$ ssh core@worker1
The authenticity of host 'worker1 (192.168.1.101)' can't be established.
ED25519 key fingerprint is SHA256:xcS+2x7sdR9ZnekJheEiaG7k2Rq58sSceqCMmqQXrLc.
This key is not known by any other names
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added 'worker1' (ED25519) to the list of known hosts.
Fedora CoreOS 38.20230918.3.0
Tracker: https://github.com/coreos/fedora-coreos-tracker
Discuss: https://discussion.fedoraproject.org/tag/coreos

[core@worker1 ~]$ 
```

Before moving on, I just want to point out a few interesting bits of the `virt-install` command we run in these scripts:
```
IGNITION_CONFIG="/home/mstevenson/git/k8s-lab/scripts/kmgmt.ign"
IMAGE="$1"
VM_NAME="kmgmt"
VCPUS="4"
RAM_MB="8192"
STREAM="stable"
DISK_GB="20"
NETWORK="bridge=vbr0"
IGNITION_DEVICE_ARG=(--qemu-commandline="-fw_cfg name=opt/com.coreos/config,file=${IGNITION_CONFIG}")

# Setup the correct SELinux label to allow access to the config
chcon --verbose --type svirt_home_t ${IGNITION_CONFIG}

virt-install --connect="qemu:///session" --name="${VM_NAME}" --vcpus="${VCPUS}" --memory="${RAM_MB}" \
        --os-variant="fedora-coreos-$STREAM" --import --graphics=none \
        --disk="size=${DISK_GB},backing_store=${IMAGE}" \
        --network "${NETWORK}" "${IGNITION_DEVICE_ARG[@]}"
```

  - If you don't set the correct `svirt_home_t` security context of the Ignition file, SELinux enforcing policy will deny our build from working. At lot of folks are in the habit of just disabling SELinux on all their systems so they don't have to fiddle with it, but we are going to try and avoid that throughout these lessons so that we can learn to integrate SELinux policy properly.
  - The `--connect="qemu:///session` URL passed to virt-install is key because we are executing this build as a non-root user. The default URL when using `virt-install` is `qemu:///system`, which changes the context that the guest VM will run within and what it can access, but requires working with libvirt as the root user. The "session" context is inteded for user-level access for un-privileged user accounts.

## 10 - Core Package Install
Now it's time to start setting up the core Kubernetes services. Remember, we are intentionally doing this manually in this lesson to get a better feel for overall architecture of the system. Take it slow, look around, and get a feel for how things are connected. Ok, let's continue...

SSH into the kmgmt node and install our initial set of components for the control plane. These packages will be pulled down from the public Kubernetes repositories, but we already configured these repositories on each host within our Ignition config files, so we don't need to do that here. So let's just run the following:
```
[core@kmgmt ~]$ sudo rpm-ostree install kubelet kubeadm kubectl cri-o
  ...
Added:
  conntrack-tools-1.4.7-1.fc38.x86_64
  cri-o-1.26.1-1.fc38.x86_64
  cri-tools-1.26.0-0.x86_64
  kubeadm-1.28.2-0.x86_64
  kubectl-1.28.2-0.x86_64
  kubelet-1.28.2-0.x86_64
  libnetfilter_cthelper-1.0.0-23.fc38.x86_64
  libnetfilter_cttimeout-1.0.0-21.fc38.x86_64
  libnetfilter_queue-1.0.5-4.fc38.x86_64
Changes queued for next boot. Run "systemctl reboot" to start a reboot
```

When you first run the install, it will take a minute for your client to update all of the remote repository metadata.

On the worker1 and worker2 nodes, we don't really need kubectl, but we need the other components:
```
[core@worker1 ~]$ sudo rpm-ostree install kubelet kubeadm cri-o
```

You may be tempted to run an `rpm -qa |grep kube` and you would notice that you don't see any of your packages installed. Where are they? FCOS is encouraging the adoption of using `rpm-ostree` for package management instead of tools like `rpm`, `yum`, or even `dnf`. Why? Well `rpm-ostree` works with images as well as RPMs and is done using cleaner atomic transactions. This makes it easier to rollback to different snapshots in time in a clean way. You won't see the packages yet because `rpm-ostree` simply staged the packages it downloaded into a transaction. The packages themselves will be installed as the system is going through its boot sequence the next time you reboot. Let's reboot all 3 nodes and then we can look at the packages installed on the system again:

```
[mstevenson@fedora scripts]$ ssh core@kmgmt
Fedora CoreOS 38.20230918.3.0
Tracker: https://github.com/coreos/fedora-coreos-tracker
Discuss: https://discussion.fedoraproject.org/tag/coreos

Last login: Sun Oct  8 23:11:01 2023 from 192.168.1.25

[core@kmgmt ~]$ rpm -qa |grep kube
kubectl-1.28.2-0.x86_64
kubelet-1.28.2-0.x86_64
kubeadm-1.28.2-0.x86_64
```

Now let's log into all 3 nodes and start up the crio and kubelet services:
```
[core@kmgmt ~]$ sudo systemctl enable --now crio kubelet
Created symlink /etc/systemd/system/cri-o.service → /usr/lib/systemd/system/crio.service.
Created symlink /etc/systemd/system/multi-user.target.wants/crio.service → /usr/lib/systemd/system/crio.service.
Created symlink /etc/systemd/system/multi-user.target.wants/kubelet.service → /usr/lib/systemd/system/kubelet.service.
```

If you don't know what these two components are, take a pause here and do a little reading. I won't re-create all the documentation already available on what these components are. This is a tutorial walkthrough, not a complete reference. Instead, here are a few "let me Google that for you" style links:
  - [kubelet](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/)
  - [CRI-O](https://cri-o.io/)

## 11 - Initialize Control Plane
We are going to use the `kubeadm` tool to initialize the "control plane" for the cluster. The most basic components we need for our control plane are:

  - [etcd](https://etcd.io/) - The key/value database that the majority of other cluster services will use to store and retrieve data.
  - [kube-apiserver](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver/) - The REST API server through which all other components interact.
  - [kube-controller-manager](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/) - Monitors the cluster through the API server and constantly attempts to make the current state match the desired state.
  - [kube-proxy](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/) - Performs simple packet forwarding to backend services within the cluster.
  - [kube-scheduler](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-scheduler/) - Assigns which pods run on which nodes.
  - [coredns](https://coredns.io/) - An alternative to kube-dns for dynamically managing DNS services within the cluster.

Both of these components will run as pods on the kmgmt "control plane" node instead of system processes running directly on the VM. If we wanted to be extremely manual, we could configure these containers ourselves and launch them under kubelete (and in turn CRI-O) manually, but that's not really necessary. The `kubeadm` tool was built to do that for us by taking a in a YAML manifest for our cluster and doing the grunt work of downloading the correct images from the public repositories, applying additional config options we specify, and starting up the pods. 

First, let's confirm what version of kubelet is installed on the kmgmt node. We want to sync our version of Kubernetes to the version of kubelet we are running for the best stability:
```
[core@kmgmt ~]$ kubelet --version
Kubernetes v1.28.2
```

Let's configure that manifest now by creating a cp-config.yaml file on the kmgmt node and setting the Kubernetes version to the same as kubelet:
```
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.28.2
controllerManager:
  extraArgs: # specify a R/W directory for FlexVolumes (cluster won't work without this even though we use PVs)
    flex-volume-plugin-dir: "/etc/kubernetes/kubelet-plugins/volume/exec"
networking: # pod subnet definition
  podSubnet: 10.222.0.0/16
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
```

Then let's give our cluster definition to `kubeadm` so that it can set up the cluster for us:

```
[core@kmgmt ~]$ sudo kubeadm init --config cp-config.yaml 
[init] Using Kubernetes version: v1.28.2
[preflight] Running pre-flight checks
   ...
Your Kubernetes control-plane has initialized successfully!
   ...
```

This will probably take a few mintues while several images download, initial config files are bootstraps, certificates are created, etc. Once things are installed, take a few minutes to read through the log output so you can get an idea of all the little things that go into getting the core cluster up and running. Aren't you glad we didn't do this part manually?

## 12 - Setup Kubectl
Once `kubadm` finishes initializing the cluster, it outputs some helpful commands for setting up a KUBECONFIG profile so that you can begin to use the `kubectl` CLI tool for working with the cluster. Do this now for the "core" user:

```
To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

After running the above, it's worth taking a look at the `~/.kube/config` file to get a feel for what kinds of config parameters the `kubectl` tool needs in order to connect to the cluster and make API calls. You should also copy the same KUBECONFIG file to your hypervisor and install the `kubectl` binary on your hypervisor. That way you don't have to SSH into any of the cluster VM's to manage the cluster.

Try a few quick `kubectl` commands to see if everything is working:
```
[core@kmgmt ~]$ kubectl get pods -A
NAMESPACE     NAME                            READY   STATUS    RESTARTS   AGE
kube-system   coredns-5dd5756b68-76jb5        1/1     Running   0          41s
kube-system   coredns-5dd5756b68-z56lw        1/1     Running   0          41s
kube-system   etcd-kmgmt                      1/1     Running   0          54s
kube-system   kube-apiserver-kmgmt            1/1     Running   0          55s
kube-system   kube-controller-manager-kmgmt   1/1     Running   0          54s
kube-system   kube-proxy-6v24s                1/1     Running   0          41s
kube-system   kube-scheduler-kmgmt            1/1     Running   0          54s

[core@kmgmt ~]$ kubectl get nodes
NAME    STATUS   ROLES           AGE   VERSION
kmgmt   Ready    control-plane   74s   v1.28.2
```

You'll notice we only have a single node in our cluster, that's because we still need to join the other worker nodes. We'll do that soon but first we need to install a CNI (Container Networking Interface)...

## 13 - Setup Pod Networking (CNI)
Our pods on this node are up and running, but containers on the other worker nodes won't be visible to the containers on this node without a CNI to network the pods together. There are several options of which CNI to use with Kubernetes. Later on we will install Calico. But for now we are going to stick with the basics and use the very simple `kube-router` CNI. 

The CNI will be deployed into the cluster using `kubectl`, which conveniently allows you to pass in manifest by URL as well as local files. So we can use one of the popular, cookie-cutter recipies made available just for this purpose by running:

```
[core@kmgmt ~]$ kubectl apply -f https://raw.githubusercontent.com/cloudnativelabs/kube-router/master/daemonset/kubeadm-kuberouter.yaml
configmap/kube-router-cfg created
daemonset.apps/kube-router created
serviceaccount/kube-router created
clusterrole.rbac.authorization.k8s.io/kube-router created
clusterrolebinding.rbac.authorization.k8s.io/kube-router created
```

If you look at running pods again, you should see the new `kube-router` pod running:

```
[core@kmgmt ~]$ kubectl get pods -A
NAMESPACE     NAME                            READY   STATUS    RESTARTS   AGE
kube-system   coredns-5dd5756b68-76jb5        1/1     Running   0          10m
kube-system   coredns-5dd5756b68-z56lw        1/1     Running   0          10m
kube-system   etcd-kmgmt                      1/1     Running   0          10m
kube-system   kube-apiserver-kmgmt            1/1     Running   0          10m
kube-system   kube-controller-manager-kmgmt   1/1     Running   0          10m
kube-system   kube-proxy-6v24s                1/1     Running   0          10m
kube-system   kube-router-jn4kx               1/1     Running   0          36s
kube-system   kube-scheduler-kmgmt            1/1     Running   0          10m
```

## 13 - Join Workers to Cluster
Back when we ran `kubeadm` to initialize the cluster, it output a token with instructions on how to join other nodes to the cluster. This token is required for the workers to initially authenticate when they join. If you don't have that output anymore, don't worry. We can have `kubeadm` generate a new token for us and also give us the helpful instructions on what to run on the other worker nodes:

```
[core@kmgmt ~]$ kubeadm token create --print-join-command
kubeadm join 192.168.1.110:6443 --token ksvoik.ul0rkqqvyt5th3fs --discovery-token-ca-cert-hash sha256:925a734ae2d49ef1f2a16f26627f32f0d5116b8ef28ec16beb31c8eea37223db
```

Now we can SSH to worker1 and worker2 and run the above `kubeadm join` command with sudo to connect them. Each node will spit out some details of what it's doing and then we should be able to see our nodes in the cluster when we run `kubectl` back on the kmgmt node:

```
[core@kmgmt ~]$ kubectl get nodes
NAME      STATUS   ROLES           AGE    VERSION
kmgmt     Ready    control-plane   18m    v1.28.2
worker1   Ready    <none>          111s   v1.28.2
worker2   Ready    <none>          95s    v1.28.2
```

Later on, we will assign roles to these worker nodes so that we can more easily control which nodes the scheduler runs pods on. But for now, let's just try one last test before we call it a day...

## 14 - Run Test Deployment
Let's create a simple Deploment called "test" using nginx:

```
[core@kmgmt ~]$ kubectl create deployment test --image nginx --replicas 3
deployment.apps/test created
```

Next let's create a service so that we can connect to the deployment on one of the nodes. I saved this manifest in a file on the kmgmt host called test-svc.yaml:
```
apiVersion: v1
kind: Service
metadata:
  name: testsvc
spec:
  type: NodePort
  selector:
    app: test
  ports:
    - port: 80
      nodePort: 30001
```

Then we can apply the service to the cluster:
```
[core@kmgmt ~]$ kubectl apply -f test-svc.yaml 
service/testsvc created
```

Since we did not specify a *namespace* for the deployment, the "default" namespace was used. We should see our pods running in the "default" namespace and we can use the `-o wide` option to also view which node each pod is running on:

```
[core@kmgmt ~]$ kubectl get pods -n default -o wide
NAME                    READY   STATUS    RESTARTS   AGE     IP           NODE      NOMINATED NODE   READINESS GATES
test-7955cf7657-5sxc2   1/1     Running   0          4m14s   10.222.1.2   worker1   <none>           <none>
test-7955cf7657-bcqr8   1/1     Running   0          4m13s   10.222.2.3   worker2   <none>           <none>
test-7955cf7657-xnm2t   1/1     Running   0          4m13s   10.222.2.2   worker2   <none>           <none>
```

We should also be able to connect to the nginx servers running on any of the nodes on port `30001` as specified in our manifest:

```
[core@kmgmt ~]$ curl http://worker1:30001
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```

And if you like, you should be able to use a web browser from your hypervisor and also connect to http://worker1:30001 to test the service. If everything went as planned, congrats! You have a beginning Kubernets cluster in a home lab. In the next lesson, we are going to explore the core services running so far and refine a few things along the way to see the inner workings of how all this fits together.