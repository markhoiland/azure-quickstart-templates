// Execute this main file to configure Azure Machine Learning end-to-end in a moderately secure set up

// Parameters
@minLength(2)
@maxLength(10)
@description('Prefix for all resource names.')
param prefix string

@description('Azure region used for the deployment of all resources.')
param location string = resourceGroup().location

@description('Set of tags to apply to all resources.')
param tags object = {}

@description('New or existing virtual network?')
@allowed([
  'new'
  'existing'
])
param vnetNewOrExisting string = 'new'

## New Vnet Params
@description('Virtual network address prefix')
param vnetAddressPrefix string = '192.168.0.0/16'

@description('Training subnet address prefix')
param trainingSubnetPrefix string = '192.168.0.0/24'

@description('Scoring subnet address prefix')
param scoringSubnetPrefix string = '192.168.1.0/24'

@description('Bastion subnet address prefix')
param azureBastionSubnetPrefix string = '192.168.250.0/27'

@description('Existing Virtual network name')
param vnetName string

@description('Existing Virtual Network Resource Group')
param vnetResourceGroupName string

@description('Existing Virtual Network Subscription ID')
param vnetSubscriptionId string

@description('Training subnet name')
param trainingSubnetName string

@description('Scoring subnet name')
param scoringSubnetName string

@description('Deploy a Bastion jumphost to access the network-isolated environment?')
param deployJumphost bool = false

@description('Jumphost virtual machine username')
param dsvmJumpboxUsername string

@secure()
@minLength(8)
@description('Jumphost virtual machine password')
param dsvmJumpboxPassword string

@description('Enable public IP for Azure Machine Learning compute nodes')
param amlComputePublicIp bool = true

// Variables
var name = toLower('${prefix}')

// Create a short, unique suffix, that will be unique to each resource group
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 4)


// Virtual network and network security group
module nsg 'modules/nsg.bicep' = if (vnetNewOrExisting == 'new') { 
  name: 'nsg-${name}-${uniqueSuffix}-deployment'
  params: {
    location: location
    tags: tags 
    nsgName: 'nsg-${name}-${uniqueSuffix}'
  }
}


module vnet 'modules/vnet.bicep' = if (vnetNewOrExisting == 'new') { 
  name: 'vnet-${name}-${uniqueSuffix}-deployment'
  params: {
    location: location
    virtualNetworkName: 'vnet-${name}-${uniqueSuffix}'
    networkSecurityGroupId: nsg.outputs.networkSecurityGroup
    vnetAddressPrefix: vnetAddressPrefix
    trainingSubnetPrefix: trainingSubnetPrefix
    scoringSubnetPrefix: scoringSubnetPrefix
    tags: tags
  }
}

// Creating symbolic name for an existing virtual network
resource vnetexisting 'Microsoft.Network/virtualNetworks@2020-07-01' existing = if (vnetNewOrExisting == 'existing') {
  name: vnetName
  scope: resourceGroup(vnetSubscriptionId, vnetResourceGroupName)
}

// Dependent resources for the Azure Machine Learning workspace
module keyvault 'modules/keyvault.bicep' = {
  name: 'kv-${name}-${uniqueSuffix}-deployment'
  params: {
    location: location
    keyvaultName: 'kv-${name}-${uniqueSuffix}'
    keyvaultPleName: 'ple-${name}-${uniqueSuffix}-kv'
    subnetId: '${vnetexisting.id}/subnets/${trainingSubnetName}'
    virtualNetworkId: '${vnetexisting.id}'
    tags: tags
  }
}

module storage 'modules/storage.bicep' = {
  name: 'st${name}${uniqueSuffix}-deployment'
  params: {
    location: location
    storageName: 'st${name}${uniqueSuffix}'
    storagePleBlobName: 'ple-${name}-${uniqueSuffix}-st-blob'
    storagePleFileName: 'ple-${name}-${uniqueSuffix}-st-file'
    storageSkuName: 'Standard_LRS'
    subnetId: '${vnetexisting.id}/subnets/${trainingSubnetName}'
    virtualNetworkId: '${vnetexisting.id}'
    tags: tags
  }
}

module containerRegistry 'modules/containerregistry.bicep' = {
  name: 'cr${name}${uniqueSuffix}-deployment'
  params: {
    location: location
    containerRegistryName: 'cr${name}${uniqueSuffix}'
    containerRegistryPleName: 'ple-${name}-${uniqueSuffix}-cr'
    subnetId: '${vnetexisting.id}/subnets/${trainingSubnetName}'
    virtualNetworkId: '${vnetexisting.id}'
    tags: tags
  }
}

module applicationInsights 'modules/applicationinsights.bicep' = {
  name: 'appi-${name}-${uniqueSuffix}-deployment'
  params: {
    location: location
    applicationInsightsName: 'appi-${name}-${uniqueSuffix}'
    tags: tags
  }
}

module azuremlWorkspace 'modules/machinelearning.bicep' = {
  name: 'mlw-${name}-${uniqueSuffix}-deployment'
  params: {
    // workspace organization
    machineLearningName: 'mlw-${name}-${uniqueSuffix}'
    machineLearningFriendlyName: 'Private link endpoint sample workspace'
    machineLearningDescription: 'This is an example workspace having a private link endpoint.'
    location: location
    prefix: name
    tags: tags

    // dependent resources
    applicationInsightsId: applicationInsights.outputs.applicationInsightsId
    containerRegistryId: containerRegistry.outputs.containerRegistryId
    keyVaultId: keyvault.outputs.keyvaultId
    storageAccountId: storage.outputs.storageId

    // networking
    subnetId: '${vnetexisting.id}/subnets/${trainingSubnetName}'
    computeSubnetId: '${vnetexisting.id}/subnets/${trainingSubnetName}'
    aksSubnetId: '${vnetexisting.id}/subnets/${scoringSubnetName}'
    virtualNetworkId: '${vnetexisting.id}'
    machineLearningPleName: 'ple-${name}-${uniqueSuffix}-mlw'

    // compute
    amlComputePublicIp: amlComputePublicIp
    mlAksName: 'aks-${name}-${uniqueSuffix}'
  }
  dependsOn: [
    keyvault
    containerRegistry
    applicationInsights
    storage
  ]
}

// Optional VM and Bastion jumphost to help access the network isolated environment
module dsvm 'modules/dsvmjumpbox.bicep' = if (deployJumphost) {
  name: 'vm-${name}-${uniqueSuffix}-deployment'
  params: {
    location: location
    virtualMachineName: 'vm-${name}-${uniqueSuffix}'
    subnetId: '${vnetexisting.id}/subnets/${trainingSubnetName}'
    adminUsername: dsvmJumpboxUsername
    adminPassword: dsvmJumpboxPassword
    networkSecurityGroupId: nsg.outputs.networkSecurityGroup 
  }
}

module bastion 'modules/bastion.bicep' = if (deployJumphost) {
  name: 'bas-${name}-${uniqueSuffix}-deployment'
  params: {
    bastionHostName: 'bas-${name}-${uniqueSuffix}'
    location: location
    vnetName: vnetexisting.name
    addressPrefix: azureBastionSubnetPrefix
  }
  dependsOn: [
    vnetexisting
  ]
}
