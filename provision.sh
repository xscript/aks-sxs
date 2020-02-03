#! /bin/bash

## Configure default location to East US
az configure --defaults location=eastus

## Create resource group and configure it as default resource group
az group create -n kevinzha-aks-sxs
az configure --defaults group=kevinzha-aks-sxs

## Create VNET and subnets
az network vnet create -n kevinzha-sxs-vnet --address-prefixes 10.0.0.0/8
az configure --defaults vnet=kevinzha-sxs-vnet

## System AKS Subnet -> 10.0.0.0/16
az network vnet subnet create -n kevinzha-sxs-subnet-1 --vnet-name kevinzha-sxs-vnet --address-prefixes 10.0.0.0/16 --verbose

## System AKS service CIDR -> 10.1.0.0/16
az aks create --name kevinzha-sxs-aks-system --network-plugin azure --dns-service-ip 10.1.0.10 --docker-bridge-address 172.17.0.1/16 --service-cidr 10.1.0.0/16 --vnet-subnet-id "/subscriptions/685ba005-af8d-4b04-8f16-a7bf38b2eb5a/resourceGroups/kevinzha-aks-sxs/providers/Microsoft.Network/virtualNetworks/kevinzha-sxs-vnet/subnets/kevinzha-sxs-subnet-1" --generate-ssh-keys --load-balancer-sku basic --verbose

## User AKS Subnet -> 10.2.0.0/16
az network vnet subnet create -n kevinzha-sxs-subnet-2 --vnet-name kevinzha-sxs-vnet --address-prefixes 10.2.0.0/16 --verbose

## User AKS service CIDR -> 10.3.0.0/16
az aks create --name kevinzha-sxs-aks-user --network-plugin azure --dns-service-ip 10.3.0.10 --docker-bridge-address 172.17.0.1/16 --service-cidr 10.3.0.0/16 --vnet-subnet-id "/subscriptions/685ba005-af8d-4b04-8f16-a7bf38b2eb5a/resourceGroups/kevinzha-aks-sxs/providers/Microsoft.Network/virtualNetworks/kevinzha-sxs-vnet/subnets/kevinzha-sxs-subnet-2" --generate-ssh-keys --load-balancer-sku basic --verbose

## Get System and User AKS kubeconfig files
az aks get-credentials -n kevinzha-sxs-aks-system -f - > system.kubeconfig
az aks get-credentials -n kevinzha-sxs-aks-user -f - > user.kubeconfig

# Install kubectl
az aks install-cli --install-location ~/kubectl

## Deploy user app w/ services
kubectl apply -f user-app.yml --kubeconfig user.kubeconfig
kubectl apply -f user-app-cluster-ip.yml --kubeconfig user.kubeconfig
kubectl apply -f user-app-internal-lb.yml --kubeconfig user.kubeconfig

## Deploy system app w/o services
kubectl apply -f system-app.yml --kubeconfig system.kubeconfig

## Deploy IngressController in system AKS
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.28.0/deploy/static/mandatory.yaml --kubeconfig system.kubeconfig
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.28.0/deploy/static/provider/cloud-generic.yaml --kubeconfig system.kubeconfig


