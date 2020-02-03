# AKS side-by-side

## Overview

This repo is the PoC of running AKS side-by-side.
- One AKS (system AKS) is hosting ingress controller to do TLS termination and traffic routing
- The other AKS (user AKS) is hosting user microservice apps

Major validation points:
- Network Connectivity between two AKS
- COGS

## Steps

Follow below steps to run this PoC:
1. Launch [Azure Cloud Shell](https://shell.azure.com)
1. Clone this repo in Azure Cloud Shell

        git clone https://github.com/xscript/aks-sxs.git

1. Run `provision.sh` script to set up resources.

        source provision.sh

1. Check all pods and services are created successfully in user AKS. Take note of all services' IP addresses for further use.

        kubectl get all --kubeconfig user.kubeconfig

1. Get a remote shell of system app.

        kubectl exec --kubeconfig system.kubeconfig deploy/system-app --it -- /bin/bash

1. In the remote shell of system app, run below commands to test network connectivity to user app in user AKS cluster.

        apt update
        apt install -y curl
        curl http://<user app service IPs>
