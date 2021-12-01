# aks-with-firewall

Terraform **v1.0.11**  
Helm **v3.6.3**  


### \# **Architecture**

```VNet_1 [ Azure Firewall ] >> VNet peering >> VNet_2 [ AKS (ingress >> service) ]```

Firewall is the front-end-point exposed to the internet, the load balancer is internal, behind the firewall. Firewall forwards the ingress traffic (with some rules) to the internal load balancer and then LB routes the traffic to the configured ingress routes. Access to AKS is public (for admin). Access to exposed service is available only over the ingress (for user).


### \# **Firewall**

```
az login

az extension add -n azure-firewall

cd firewall/
terraform init
terraform plan -out out.plan
terraform apply out.plan
```


### \# **AKS**

```
az login

az extension add -n aks-preview

terraform init
terraform plan -out out.plan
terraform apply out.plan

echo "$(terraform output -raw kube_config)" > /tmp/azurek8s
export KUBECONFIG=/tmp/azurek8s

kubectl get pods --all-namespaces
```


### \# **Network**

```
# Firewall and AKS are ready

FWRG=demo-fw-rg && \
FWNAME=msfw && \
FWPUBLICIPNAME=msfw-ip && \
FWPUBLICIP=$(az network public-ip show -g $FWRG -n $FWPUBLICIPNAME --query "ipAddress" -o tsv) && \
echo $FWRG $FWNAME $FWPUBLICIPNAME $FWPUBLICIP


# Create UDR (User Defined Route) and add a route for Azure Firewall
# https://docs.microsoft.com/en-us/azure/aks/egress-outboundtype#create-a-udr-with-a-hop-to-azure-firewall

FWPRIVATEIP=$(az network firewall show -g $FWRG -n $FWNAME --query "ipConfigurations[0].privateIpAddress" -o tsv) && \
FWROUTETABLENAME=k8sRouteTable && \
K8SRGNAME=demo-k8s-rg
   
az network route-table create \
--resource-group "${K8SRGNAME}" \
--name "${FWROUTETABLENAME}"

az network route-table list \
--resource-group "${K8SRGNAME}" \
--query "[].name" --output tsv

az network route-table route create \
--name "k8sRoute" \
--next-hop-type VirtualAppliance \
--resource-group "${K8SRGNAME}" \
--route-table-name "${FWROUTETABLENAME}" \
--next-hop-ip-address "${FWPRIVATEIP}" \
--address-prefix "0.0.0.0/0"


# Add Network FW Rules 
# https://docs.microsoft.com/en-us/azure/aks/egress-outboundtype#adding-network-firewall-rules

az network firewall network-rule create \
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

az network firewall application-rule create \
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

K8SSUBNETNAME=demo-subnet && \
K8SVNETNAME=demo-vnet
   
az network vnet subnet update \
-g $K8SRGNAME \
--vnet-name $K8SVNETNAME \
--name $K8SSUBNETNAME \
--route-table $FWROUTETABLENAME


# Peering two VNets (AKS + Firewall)  

K8SVNETID=$(az network vnet list \
--resource-group "${K8SRGNAME}" \
--query "[?contains(name, 'demo-vnet')].id" --output tsv)

FWVNETID=$(az network vnet show \
--resource-group "${FWRG}" \
--name "${FWNAME}-vnet" \
--query id --out tsv)

az network vnet peering create \
--name "k8s-peer-firewall" \
--resource-group "${K8SRGNAME}" \
--vnet-name "${K8SVNETNAME}" \
--remote-vnet "${FWVNETID}" \
--allow-vnet-access

az network vnet peering create \
--name "firewall-peer-k8s" \
--resource-group "${FWRG}" \
--vnet-name "${FWNAME}-vnet" \
--remote-vnet "${K8SVNETID}" \
--allow-vnet-access


# Deploy ingress controller
# https://docs.microsoft.com/en-us/azure/aks/ingress-internal-ip#create-an-ingress-controller

cd aks/

helm install nginx-ingress \
ingress-nginx/ingress-nginx \
-f yamls/internal-ingress.yaml \
--set controller.replicaCount=1 \
--set controller.admissionWebhooks.patch.nodeSelector."kubernetes\.io/os"=linux \
--set defaultBackend.nodeSelector."kubernetes\.io/os"=linux

$ kubectl get svc
NAME                                               TYPE           CLUSTER-IP    EXTERNAL-IP   PORT(S)                      AGE
kubernetes                                         ClusterIP      10.0.0.1      <none>        443/TCP                      19m
nginx-ingress-ingress-nginx-controller             LoadBalancer   10.0.151.83   10.20.2.35    80:30853/TCP,443:30870/TCP   88s
nginx-ingress-ingress-nginx-controller-admission   ClusterIP      10.0.81.17    <none>        443/TCP                      88s


# Run application
# https://github.com/michalswi/url-shortener

kubectl apply -f yamls/urlshort.yaml


# Add a dnat rule to azure firewall

az network firewall nat-rule create \
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
--translated-address "10.20.2.35"              << ingress controller external ip


# FQDN firewall's public IP

$ az network public-ip show \
--name ${FWPUBLICIPNAME} \
--resource-group "${FWRG}" \
--query "dnsSettings.fqdn" --output tsv

msus.westeurope.cloudapp.azure.com             << 'dns_prefix' in variable.tf

curl -i msus.westeurope.cloudapp.azure.com/us/home
curl -sS msus.westeurope.cloudapp.azure.com/us/health | jq
```
