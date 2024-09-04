# Sovereign AI Cloud Demo - OIF Summit Asia 2024

This repo contains a script - `demo.bash` - to provision a proof-of-concept demonstration of the software you can use to create a sovereign AI cloud.

## Requirements

1. Physical machine with at the following minimum specifications:
    - 8 cores/16 threads
    - 64GB of RAM
    - 500GB of storage
2. Support for nested virtualization
3. Ubuntu Jammy 22.04
4. Bash (comes with Ubuntu Jammy 22.04 by default)
5. Snapd (comes with Ubuntu Jammy 22.04 by default)
6. Curl

## What does the demo do?
The demo does the following set of actions:
1. Disable UFW if it is enabled
2. Install the LXD snap
3. Auto-initialize LXD
4. Disable IPV6 addressing for LXD
5. Set LXD to listen on local port 8443
6. Create a LXD network called "maas-ctrl" for provisioning a VM
7. Create a LXD network called "maas-kvm" for tenant networking for VMs
8. Create a LXD profile for a MAAS LXD container
9. Launch an Ubuntu Jammy LXD container with the MAAS profile
10. Set a static IP address on the network interface for the maas-ctrl network for the MAAS LXD container
11. Add a second network interface for the maas-kvm network for the MAAS LXD container using netplan
12. Install the maas-test-db snap to provide a test database
13. Install maas snap to install MAAS
14. Initialize new MAAS region and rack controllers using the test database
15. Create an admin user for MAAS
16. Generate an API key for MAAS
17. Login to the MAAS API using the API key from the previous step
18. Set the upstream DNS resolver for MAAS
19. Import boot resources (UEFI, PXE, OS images, etc.)  to MAAS
20. Configure the maas-kvm network in MAAS
21. Register the outer LXD service as a LXD VM host in MAAS
22. Compose a LXD VM wtih 12 vCPU, 32 GB of memory, and 80GB of storage using LXD in MAAS
23. Deploy the LXD VM using Ubuntu Jammy
24. Logout of the MAAS API
25. Install the OpenStack Sunbeam snap on the LXD VM
26. Execute the OpenStack Sunbeam prepare-node-script
27. Bootstrap a single-node OpenStack Sunbeam cluster
28. Install the Canonical Data Science Stack snap
29. Initialize the Canonical Data Science Stack on the MicroK8s that OpenStack Sunbeam bootstraps
30. Create a Kubeflow Jupyter notebook through the Canonical Data Science Stack

## How to run the demo
**This script will make changes to the system on which you run the script. For best results, you should run the demo script on a physical machine you can use for the demonstration.**

To run this demo, clone the repo, `cd` into the directory, and run the script `demo.bash` using `bash` as below:
```
git clone https://github.com/canonical/sovereign-ai-cloud-demo
cd ./sovereign-ai-cloud-demo
bash ./demo.bash
```

### How to access the demo environment
If the demo script runs successfully, the demo environment is a LXD VM running on your physical machine. You can access the demo environment by using the following command:
```
lxc exec --user 1000 --group 584788 --cwd /home/ubuntu sunbeam-one --project maas -- /usr/bin/bash
```

After you run that command, you will have a shell session as the `ubuntu` user in the demo environment. The `ubuntu` user is the user that has access to OpenStack Sunbeam and the Canonical Data Science Stack in the demo environment.

You can access OpenStack Sunbeam through the `sunbeam` command and the Canonical Data Science Stack through the `dss` command.

#### Access the demo Jupyter notebook
From within the demo environment, use `kubectl` to find the full name of the `my-notebook` pod like in the following command:
```
sudo kubectl get pods -n dss
```
If you run the previous command, you should see output that looks similar to this example:
```
ubuntu@sunbeam-one:/home/ubuntu$ sudo kubectl get pods -n dss
NAME                           READY   STATUS    RESTARTS   AGE
mlflow-7fcf655ff9-vrphc        1/1     Running   0          122m
my-notebook-55cd95df56-ljp79   1/1     Running   0          121m
```
The pod name in this example is `my-notebook-55cd95df56-ljp79`. Find the name of your `my-notebook` pod and save that name.

Use `kubectl` to set up port forwarding from the LXD VM to the Jupyter notebook container like in the following command:
```
sudo kubectl port-forward -n dss --address 0.0.0.0 <NOTEBOOK_POD_NAME> 8080:8888
```
Replace `<NOTEBOOK_POD_NAME>` with the actual pod name you saved in the previous step. If the command works successfully you should see output like the following:
```
ubuntu@sunbeam-one:/home/ubuntu$ sudo kubectl port-forward -n dss --address 0.0.0.0 my-notebook-55cd95df56-ljp79 8080:8888
Forwarding from 0.0.0.0:8080 -> 8888
```
At this point you should be able to access the Jupyter Notebook web interface by connecting to port 8080 on the LXD VM. If you have a web browser on the machine on which you ran the demo, navigate to 10.20.0.3:8080/ to see the Jupyter Notebook web interface. If you ran the demo on a machine without a web browser or graphical interface, you can use an SSH tunnel to enable a connection from your local machine if you are using SSH to manage the machine running the demo. Here is an example SSH tunnel command:
```
ssh -L 8080:10.20.0.3:8080 your-user@your-physical-machine-address
```
Replace `your-user@your-physical-machine-address` with the username and IP address or domain name of the machine running the demo. If you get an SSH session on the machine running the demo, the tunnel is active. You can then navigate to http://localhost:8080 in your web browser on your local machine to view the demo Jupyter Notebook. When you are done with the SSH tunnel, disconnect (that is, exit or logout) the SSH session with the tunneling command.
### Clean up select demo artifacts
If you need to rerun the demo, there is a clean up script that will clean the assets that will prevent the script from running again. Run the clean up script from within the cloned repo directory with the following command:
```
bash ./cleanup.bash
```

This command deletes the MAAS LXD container, deletes the composed LXD VM, removes the `maas` LXD profile, removes the `maas` trust configuration from LXD, and deletes the `maas-ctrl` and `maas-kvm` LXD networks.

**The clean up script will not restore your system to its original state. The clean up script is for development purposes to enable re-running the demo script as changes are made to the demo script.**
## What is a sovereign AI cloud?
A sovereign AI cloud is a private cloud optimized for running AI workloads inside of your own data center. The **sovereign** part of the sovereign AI cloud refers to your complete control over the data, environment, and resources making up your AI workloads. This is in contrast to a public AI cloud where someone other than you owns almost every part of your AI workload except for the data you feed into the public AI cloud.

Sovereign AI clouds are becoming increasingly attractive as organizations look to protect their private data from platforms and service providers that have proven themselves to be poor custodians of their customers' secrets and proprietary data. In addition, sovereign AI clouds grow in importance as organizations either seek to comply with local government regulations around on-shoring data or avoid intrusion from foreign governments on their off-shore infrastructure.