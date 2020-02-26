#! /bin/bash

## Constants
PREFIX="kevinzha"
RG="${PREFIX}-aks-egress"
LOC="eastus"
AKS_NAME="${PREFIX}-aks"
VNET_NAME="${PREFIX}-vnet"
AKSSUBNET_NAME="${PREFIX}-akssubnet"
SVCSUBNET_NAME="${PREFIX}-svcsubnet"
FWSUBNET_NAME="AzureFirewallSubnet"
FWNAME="${PREFIX}-fw"
FWPUBLICIP_NAME="${PREFIX}-fwip"
FWIPCONFIG_NAME="${PREFIX}-fwconfig"
FWROUTE_TABLE_NAME="${PREFIX}-fwrt"
FWROUTE_NAME="${PREFIX}-fwrn"
FWROUTE_NAME_INTERNET="${PREFIX}-fwinternet"

## Install the aks-preview extension
az extension add --name aks-preview
## Install Firewall extension
az extension add --name azure-firewall

## Configure default location to East US
az configure --defaults location=$LOC

## Create resource group and configure it as default resource group
az group create -n $RG
az configure --defaults group=$RG

## Create VNET and subnets
az network vnet create \
    --resource-group $RG \
    --name $VNET_NAME \
    --address-prefixes 100.64.0.0/16 \
    --subnet-name $AKSSUBNET_NAME \
    --subnet-prefix 100.64.1.0/24

#### Subnet for AKS service objects
az network vnet subnet create \
    --resource-group $RG \
    --vnet-name $VNET_NAME \
    --name $SVCSUBNET_NAME \
    --address-prefix 100.64.2.0/24

#### Subnet for Firewall
az network vnet subnet create \
    --resource-group $RG \
    --vnet-name $VNET_NAME \
    --name $FWSUBNET_NAME \
    --address-prefix 100.64.3.0/24

## Public IP for Azure Firewall
az network public-ip create -g $RG -n $FWPUBLICIP_NAME -l $LOC --sku "Standard"

## Deploy a new Firewall
az network firewall create -g $RG -n $FWNAME -l $LOC

## Assign the Public IP to Azure Firewall frontend
az network firewall ip-config create -g $RG -f $FWNAME -n $FWIPCONFIG_NAME \
    --public-ip-address $FWPUBLICIP_NAME \
    --vnet-name $VNET_NAME

## Capture Firewall's Public IP and Private IP
FWPUBLIC_IP=$(az network public-ip show -g $RG -n $FWPUBLICIP_NAME --query "ipAddress" -o tsv)
FWPRIVATE_IP=$(az network firewall show -g $RG -n $FWNAME --query "ipConfigurations[0].privateIpAddress" -o tsv)

## Create UDR and add a route for Azure Firewall
az network route-table create -g $RG --name $FWROUTE_TABLE_NAME
az network route-table route create -g $RG --name $FWROUTE_NAME \
    --route-table-name $FWROUTE_TABLE_NAME \
    --address-prefix 0.0.0.0/0 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address $FWPRIVATE_IP
az network route-table route create -g $RG --name $FWROUTE_NAME_INTERNET \
    --route-table-name $FWROUTE_TABLE_NAME \
    --address-prefix $FWPUBLIC_IP/32 --next-hop-type Internet

# Add Network FW Rules
az network firewall network-rule create -g $RG -f $FWNAME --collection-name 'aksfwnr' -n 'netrules' --protocols 'Any' --source-addresses '*' --destination-addresses '*' --destination-ports '*' --action allow --priority 100

## Add Application FW Rules
## IMPORTANT: Add AKS required egress endpoints
az network firewall application-rule create -g $RG -f $FWNAME \
    --collection-name 'AKS_Global_Required' \
    --action allow \
    --priority 100 \
    -n 'required' \
    --source-addresses '*' \
    --protocols 'http=80' 'https=443' \
    --target-fqdns \
        'aksrepos.azurecr.io' \
        '*blob.core.windows.net' \
        'mcr.microsoft.com' \
        '*cdn.mscr.io' \
        '*.data.mcr.microsoft.com' \
        'management.azure.com' \
        'login.microsoftonline.com' \
        'ntp.ubuntu.com' \
        'packages.microsoft.com' \
        'acs-mirror.azureedge.net'

## Associate route table with next hop to Firewall to the AKS subnet
az network vnet subnet update -g $RG --vnet-name $VNET_NAME \
    --name $AKSSUBNET_NAME \
    --route-table $FWROUTE_TABLE_NAME

## Deploy AKS
AKSSUBNET_ID=$(az network vnet subnet show --vnet-name $VNET_NAME -n $AKSSUBNET_NAME --query "id" -o tsv)
az aks create -g $RG -n $AKS_NAME -l $LOC \
  --node-count 3 \
  --network-plugin azure --generate-ssh-keys \
  --service-cidr 192.168.0.0/16 \
  --dns-service-ip 192.168.0.10 \
  --docker-bridge-address 172.22.0.1/29 \
  --vnet-subnet-id $AKSSUBNET_ID \
  --load-balancer-sku standard \
  --outbound-type userDefinedRouting 
##  --api-server-authorized-ip-ranges $FWPUBLIC_IP

## Get AKS kubeconfig
az aks get-credentials -n $AKS_NAME -f - > aks-udr.kubeconfig
## Install kubectl
az aks install-cli --install-location ~/kubectl

## Create app and service
kubectl apply -f user-app.yml --kubeconfig aks-udr.kubeconfig
kubectl apply -f user-app-udr.yml --kubeconfig aks-udr.kubeconfig

## Add DNAT rule in Azure Firewall
az network firewall nat-rule create --collection-name "${AKS_NAME}-ingress" \
    --destination-addresses $FWPUBLIC_IP \
    --destination-ports 80 \
    --firewall-name $FWNAME \
    --name inboundrule \
    --protocols Any \
    --resource-group $RG \
    --source-addresses '*' \
    --translated-port 80 \
    --action Dnat \
    --priority 100 \
    --translated-address <INSERT IP OF K8s SERVICE>



