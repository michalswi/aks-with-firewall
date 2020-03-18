# aks-with-firewall

Terraform **v0.12.20**  
Helm **v3.0.2**  

### \# **flow**

VNet_1 [ Azure Firewall ] >> VNet peering >> VNet_2 [ AKS (ingress >> service) ]


### \# **firewall**

```
$ az extension add -n azure-firewall
$ az extension add --name aks-preview

# Set up Terraform access to Azure then:
$ export TF_VAR_client_id=<> && export TF_VAR_client_secret=<>

$ terraform init
$ terraform plan -out out.plan
$ terraform apply out.plan
```


### \# **aks**

```
# aks backend related
# https://docs.microsoft.com/en-us/azure/terraform/terraform-create-k8s-cluster-with-tf-and-aks

$ RG_NAME=msstgrg && \
  export AZURE_STORAGE_ACCOUNT=msbackupsstg && \
  TF_BACKEND_NAME=tfstate && \
  export AZURE_STORAGE_KEY=$(az storage account keys list \
  --resource-group $RG_NAME \
  --account-name $AZURE_STORAGE_ACCOUNT \
  --query "[0].value" \
  --output tsv)

$ export TF_VAR_client_id=<> && \
  export TF_VAR_client_secret=<>

$ BACKEND_STATE_NAME=k8s.backupstate.tfstate

$ terraform init \
   -backend-config="storage_account_name=$AZURE_STORAGE_ACCOUNT" \
   -backend-config="container_name=$TF_BACKEND_NAME" \
   -backend-config="access_key=$AZURE_STORAGE_KEY" \
   -backend-config="key=$BACKEND_STATE_NAME"

$ terraform plan -out out.plan

$ az storage container list --output table

$ az storage blob list \
    --container-name $TF_BACKEND_NAME \
    --output table

$ terraform apply out.plan

$ echo "$(terraform output kube_config)" > ./azurek8s
$ export KUBECONFIG=./azurek8s

$ k get pods --all-namespaces
```


### \# **network**

```
# firewall and aks is ready

$ FWRG=msfwrg && \
   FWNAME=msfw && \
   FWPUBLICIPNAME=msfw-ip && \
   FWPUBLICIP=$(az network public-ip show -g $FWRG -n $FWPUBLICIPNAME --query "ipAddress" -o tsv) && \
   echo $FWRG $FWNAME $FWPUBLICIPNAME $FWPUBLICIP


# Create UDR (User Defined Route) and add a route for Azure Firewall
# https://docs.microsoft.com/en-us/azure/aks/egress-outboundtype#create-a-udr-with-a-hop-to-azure-firewall

$ FWPRIVATEIP=$(az network firewall show -g $FWRG -n $FWNAME --query "ipConfigurations[0].privateIpAddress" -o tsv) && \
   FWROUTETABLENAME=k8sRouteTable && \
   K8SRGNAME=msk8srg
   
$ az network route-table create \
--resource-group "${K8SRGNAME}" \
--name "${FWROUTETABLENAME}"

$ az network route-table list \
--resource-group "${K8SRGNAME}" \
--query "[].name" --output tsv

$ az network route-table route create \
--name "k8sRoute" \
--next-hop-type VirtualAppliance \
--resource-group "${K8SRGNAME}" \
--route-table-name "${FWROUTETABLENAME}" \
--next-hop-ip-address "${FWPRIVATEIP}" \
--address-prefix "0.0.0.0/0"


# Add Network FW Rules 
# https://docs.microsoft.com/en-us/azure/aks/egress-outboundtype#adding-network-firewall-rules

$ az network firewall network-rule create \
--resource-group "${FWRG}" \
--firewall-name "${FWNAME}" \
--collection-name "k8sfwnr" \
--name "allow-all" \
--protocols "ANY" \
--source-addresses "*" \
--destination-addresses "*" \
--destination-ports "*" \
--action allow \
--priority 100


# Add Application FW Rules (AKS required egress endpoints)
# https://docs.microsoft.com/en-us/azure/aks/egress

$ az network firewall application-rule create \
    -g $FWRG \
    -f $FWNAME \
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


# Associate the route table to AKS
# https://docs.microsoft.com/en-us/azure/aks/egress-outboundtype#associate-the-route-table-to-aks

$ K8SSUBNETNAME=msk8s-subnet && \
   K8SVNETNAME=msk8s-vnet
   
$ az network vnet subnet update \
   -g $K8SRGNAME \
   --vnet-name $K8SVNETNAME \
   --name $K8SSUBNETNAME \
   --route-table $FWROUTETABLENAME


# Peering two VNets (AKS + firewall)  

$ K8SVNETID=$(az network vnet list \
--resource-group "${K8SRGNAME}" \
--query "[?contains(name, 'msk8s-vnet')].id" --output tsv)

$ FWVNETID=$(az network vnet show \
--resource-group "${FWRG}" \
--name "${FWNAME}-vnet" \
--query id --out tsv)

$ az network vnet peering create \
--name "k8s-peer-firewall" \
--resource-group "${K8SRGNAME}" \
--vnet-name "${K8SVNETNAME}" \
--remote-vnet "${FWVNETID}" \
--allow-vnet-access

$ az network vnet peering create \
--name "firewall-peer-k8s" \
--resource-group "${FWRG}" \
--vnet-name "${FWNAME}-vnet" \
--remote-vnet "${K8SVNETID}" \
--allow-vnet-access


# Deploy ingress controller

$ cd aks/
$ view internal-ingress.yaml

$ helm install stable/nginx-ingress \
    -f internal-ingress.yaml \
    --set controller.replicaCount=1 \
    --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --generate-name

$ k get svc
NAME                                       TYPE           CLUSTER-IP    EXTERNAL-IP   PORT(S)                      AGE
kubernetes                                 ClusterIP      10.0.0.1      <none>        443/TCP                      23m
nginx-ingress-1584540489-controller        LoadBalancer   10.0.73.85    10.20.1.35    80:32552/TCP,443:30152/TCP   45s
nginx-ingress-1584540489-default-backend   ClusterIP      10.0.240.44   <none>        80/TCP                       45s


# Run application: https://github.com/michalswi/url-shortener

$ k apply -f urlshort.yaml


# Add a dnat rule to azure firewall

$ az network firewall nat-rule create \
--collection-name "k8s-example" \
--destination-addresses "${FWPUBLICIP}" \
--destination-ports 80 \
--firewall-name "${FWNAME}" \
--name inboundrule \
--protocols Any \
--resource-group "${FWRG}" \
--source-addresses "*" \
--translated-port 80 \
--action Dnat \
--priority 100 \
--translated-address "10.20.1.35"               << ingress controller external ip


# FQDN firewall's public IP

$ az network public-ip show \
--name ${FWPUBLICIPNAME} \
--resource-group "${FWRG}" \
--query "dnsSettings.fqdn" --output tsv

#output: testms.westeurope.cloudapp.azure.com   << 'testms' was defined in 'firewall.tf'

$ curl testms.westeurope.cloudapp.azure.com/us/home

```