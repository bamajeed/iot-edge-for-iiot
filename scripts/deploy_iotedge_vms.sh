#!/usr/bin/env bash

function show_help() {
   # Display Help
   echo "Run this script to deploy multiple Azure VMs with Azure IoT Edge pre-installed across a simulated Purdue Network in Azure."
   echo
   echo "Syntax: ./deploy_iotedge_vms.sh [-flag parameter]"
   echo "-l                Azure region to deploy resources to."
   echo "-rg               Prefix used for all new Azure Resource Groups created by this script."
   echo ""
   echo "List of optional flags:"
   echo "-h                Print this help."
   echo "-c                Path to configuration file with IoT Edge VMs information."
   echo "-n                Name of the Azure Virtual Network with the Purdue Network."
   echo "-s                Azure subscription to use to deploy resources."
   echo "-nrg              Azure Resource Group with the Purdue Network."
   echo "-vmSize          Size of the Azure VMs to deploy."
   echo "-adminUsername   Administrator username of the Azure VMs to deploy."
   echo "-adminPassword   Administrator password of the Azure VMs to deploy."
   echo ""
}

function passArrayToARM() {
   array=("$@")
   output="["
   i=0
   for item in "${array[@]}"
   do
        if [[ $i -eq 0 ]]
        then
            output="${output}\"${item}\""
        else
            output="${output}, \"${item}\""
        fi
        ((i++))
   done
   output="${output}]"
   echo ${output}
}

#global variable
scriptFolder=$(dirname "$(readlink -f "$0")")

# Default settings
networkName="PurdueNetwork"
configFilePath="${scriptFolder}/../config.txt"
adminUsername="iotedgeadmin"
vmSize="Standard_D3_v2"

# Get arguments
while :; do
    case $1 in
        -h|-\?|--help)
            show_help
            exit;;
        -c=?*)
            configFilePath=${1#*=}
            if [ ! -f "${configFilePath}" ]; then
              echo "Configuration file not found. Exiting."
              exit 1
            fi;;
        -c=)
            echo "Missing configuration file path. Exiting."
            exit;;
        -n=?*)
            networkName=${1#*=}
            ;;
        -n=)
            echo "Missing network name. Exiting."
            exit;;
        -l=?*)
            location=${1#*=}
            ;;
        -l=)
            echo "Missing location. Exiting."
            exit;;
        -s=?*)
            subscription=${1#*=}
            ;;
        -s=)
            echo "Missing subscription. Exiting."
            exit;;
        -rg=?*)
            resourceGroupPrefix=${1#*=}
            ;;
        -rg=)
            echo "Missing resource group prefix. Exiting."
            exit;;
        -nrg=?*)
            networkResourceGroupName=${1#*=}
            ;;
        -nrg=)
            echo "Missing network resourge group. Exiting."
            exit;;
        -vmSize=?*)
            vmSize=${1#*=}
            ;;
        -vmSize=)
            echo "Missing vmSize. Exiting."
            exit;;
        -adminUsername=)
            echo "Missing VM adminitrator username. Exiting."
            exit;;
        -adminUsername=?*)
            adminUsername=${1#*=}
            ;;
        -adminPassword=)
            echo "Missing VM adminitrator password. Exiting."
            exit;;
        -adminPassword=?*)
            adminPassword=${1#*=}
            ;;
        --)
            shift
            break;;
        *)
            break
    esac
    shift
done

# Derived default settings
networkResourceGroupName="${resourceGroupPrefix}-RG-network"
iotedgeResourceGroupName="${resourceGroupPrefix}-RG-iotedge"

#Verifying that mandatory parameters are there
if [ -z ${configFilePath} ]; then
    echo "Missing configuration file path. Exiting."
    exit 1
fi

# Prepare CLI
if [ ! -z $subscription ]; then
  az account set --subscription $subscription
fi
# subscriptionName=$(az account show --query 'name' -o tsv)
# echo "Executing script with Azure Subscription: ${subscriptionName}" 

echo "==========================================================="
echo "==	          IoT Edge VMs                         =="
echo "==========================================================="
echo ""

if ( $(az group exists -n "$iotedgeResourceGroupName") )
then
  echo "Existing IoT Edge VMs resource group found: $iotedgeResourceGroupName"
else
  az group create --name "$iotedgeResourceGroupName" --location "$location" --tags "$resourceGroupPrefix" "CreationDate"=$(date --utc +%Y%m%d_%H%M%SZ)  1> /dev/null
  echo "IoT Edge VMs Resource group: $iotedgeResourceGroupName"
fi
echo ""

# Load IoT Edge VMs to deploy from config file
source ${scriptFolder}/parseConfigFile.sh $configFilePath

iotedgeDeployFilePath="${scriptFolder}/ARM-templates/iotedgedeploy.json"
if [ ! -z $adminPassword ]; then
    iotedgeVMsOutput=$(az deployment group create --name iotedgeDeployment --resource-group $iotedgeResourceGroupName --template-file "$iotedgeDeployFilePath" --parameters \
        networkName="$networkName" networkResourceGroupName="$networkResourceGroupName" subnetNames="$(passArrayToARM ${iotEdgeDevicesSubnets[@]})" \
        machineNames="$(passArrayToARM ${iotEdgeDevices[@]})" machineAdminName="$adminUsername" machineAdminPassword="$adminPassword" vmSize="$vmSize" \
        --query "properties.outputs.vms.value[].[iotEdgeVmMachineName, iotEdgeVmMachinePrivateIPAddress, iotEdgeVmAdminUsername, iotEdgeVmAdminPassword]" -o tsv)
else
    iotedgeVMsOutput=$(az deployment group create --name iotedgeDeployment --resource-group $iotedgeResourceGroupName --template-file "$iotedgeDeployFilePath" --parameters \
        networkName="$networkName" networkResourceGroupName="$networkResourceGroupName" subnetNames="$(passArrayToARM ${iotEdgeDevicesSubnets[@]})" \
        machineNames="$(passArrayToARM ${iotEdgeDevices[@]})" machineAdminName="$adminUsername" vmSize="$vmSize" \
        --query "properties.outputs.vms.value[].[iotEdgeVmMachineName, iotEdgeVmMachinePrivateIPAddress, iotEdgeVmAdminUsername, iotEdgeVmAdminPassword]" -o tsv)
fi

echo "IoT Edge VMs created. Key values:"
echo ""
iotedgeVMsOutputs=($iotedgeVMsOutput)
for (( i=0; i<${#iotedgeVMsOutputs[@]}-1; i+=4))
do
    echo ""
    echo "IoT Edge VM machine name:       ${iotedgeVMsOutputs[i]}"
    echo "IoT Edge VM Private IP address: ${iotedgeVMsOutputs[i+1]}"
    echo "IoT Edge VM user name:          ${iotedgeVMsOutputs[i+2]}"
    echo "IoT Edge VM password:           ${iotedgeVMsOutputs[i+3]}"
    echo "IoT Edge VM ssh:                ssh ${iotedgeVMsOutputs[i+2]}@${iotedgeVMsOutputs[i]}"
done
echo ""
echo ""
echo "Please remember that there have been outbound security rules enabled on the NSGs that have been added for ease of post setup, please remember or run the lockdown_purdue.sh script next."
