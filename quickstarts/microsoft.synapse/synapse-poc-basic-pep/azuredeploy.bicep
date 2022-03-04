// param artifactsLocation string = deployment().properties.templateLink.uri

// @secure()
// param artifactsLocationSASToken string = ''

@description('Location for your deployment.')
param location string = resourceGroup().location

@description('Set of tags to apply to all resources.')
param tags object = {}

@description('This is a Three Letter Acronym for your company name. \'CON\' for Contoso for example.')
param namePrefix string

@description('Allow connections to the workspace from all IP addresses (True or False)?')
@allowed([
  'true'
  'false'
])
param allowAllConnections string = 'true'

@description('Create managed private endpoint to this storage account or not.')
param dlsManagedPep bool = false

@description('\'True\' deploys an Apache Spark pool as well as a SQL pool. \'False\' does not deploy an Apache Spark pool.')
@allowed([
  'true'
  'false'
])
param sparkDeployment string = 'false'

@description('This parameter will determine the node size if SparkDeployment is true')
@allowed([
  'Small'
  'Medium'
  'Large'
])
param sparkNodeSize string = 'Small'

@description('Specify deployment type: DevTest, POC, Prod, Shared. This will also be used in the naming convention.')
@allowed([
  'devtest'
  'poc'
  'prod'
  'shared'
])
param deploymentType string = 'poc'

@description('The username of the SQL Administrator')
param sqlAdministratorLogin string

@description('The password for the SQL Administrator')
@secure()
param sqlAdministratorLoginPassword string

@description('\'True\' deploys a dedicated SQL pool. \'False\' does not deploy a dedicated SQL pool.')
@allowed([
  'true'
  'false'
])
param sqlDeployment string = 'false'

@description('Select the SKU of the SQL pool.')
@allowed([
  'DW100c'
  'DW200c'
  'DW300c'
  'DW400c'
  'DW500c'
  'DW1000c'
  'DW1500c'
  'DW2000c'
  'DW2500c'
  'DW3000c'
])
param sku string = 'DW100c'

@description('Choose whether you want to synchronise metadata.')
param metadataSync bool = false

@description('Existing Virtual network name for Synapse private endpoint.')
param vnetName string

@description('Existing Virtual Network Resource Group for Synapse private endpoint.')
param vnetResourceGroupName string

@description('Existing Virtual Network Subscription ID for Synapse private endpoint.')
param vnetSubscriptionId string

@description('Existing Subnet name for Synapse private endpoint.')
param subnetName string

// Variable inputs
var synapseName = toLower('${namePrefix}${deploymentType}')
var dlsName_var = toLower('adls${namePrefix}${deploymentType}')
var dlsFsName = toLower('${dlsName_var}fs1')
var sqlPoolName = toLower('${workspaceName_var}p1')
var workspaceName_var = toLower('${synapseName}ws1')
var resourceGroupName_var = resourceGroup().name
var synapseMRGName_var = toLower('${resourceGroupName_var}-${workspaceName_var}')
var sparkPoolName = toLower('synasp1')


resource dlsName 'Microsoft.Storage/storageAccounts@2019-06-01' = {
  name: dlsName_var
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    isHnsEnabled: true
  }
}

resource dlsName_default_dlsFsName 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${dlsName_var}/default/${dlsFsName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    dlsName
  ]
}

resource workspaceName 'Microsoft.Synapse/workspaces@2019-06-01-preview' = {
  name: workspaceName_var
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    defaultDataLakeStorage: {
      accountUrl: reference(dlsName_var).primaryEndpoints.dfs
      createManagedPrivateEndpoint: dlsManagedPep
      filesystem: dlsFsName
    }
    managedResourceGroupName: synapseMRGName_var
    sqlAdministratorLogin: sqlAdministratorLogin
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
    managedVirtualNetwork: 'default'
    privateEndpointConnections: [
      {
        properties: {
          privateEndpoint: {}
          privateLinkServiceConnectionState: {
            description: '${workspaceName_var}-pep'
            status: 'Approved'
          }
        }
      }
    ]
  }
  dependsOn: [
    dlsName
    dlsName_default_dlsFsName
  ]
}

resource workspaceName_allowAll 'Microsoft.Synapse/workspaces/firewallrules@2019-06-01-preview' = if (allowAllConnections == 'true') {
  parent: workspaceName
  name: 'allowAll'
  location: location
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

resource workspaceName_AllowAllWindowsAzureIps 'Microsoft.Synapse/workspaces/firewallrules@2019-06-01-preview' = {
  parent: workspaceName
  name: 'AllowAllWindowsAzureIps'
  location: location
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource workspaceName_default 'Microsoft.Synapse/workspaces/managedIdentitySqlControlSettings@2019-06-01-preview' = {
  parent: workspaceName
  name: 'default'
  location: location
  properties: {
    grantSqlControlToManagedIdentity: {
      desiredState: 'Enabled'
    }
  }
}

resource workspaceName_sqlPoolName 'Microsoft.Synapse/workspaces/sqlPools@2019-06-01-preview' = if (sqlDeployment == 'true') {
  parent: workspaceName
  name: sqlPoolName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    createMode: 'Default'
    collation: 'SQL_Latin1_General_CP1_CI_AS'
  }
}

resource workspaceName_sqlPoolName_config 'Microsoft.Synapse/workspaces/sqlPools/metadataSync@2019-06-01-preview' = if (metadataSync) {
  parent: workspaceName_sqlPoolName
  name: 'config'
  properties: {
    enabled: metadataSync
  }
}

resource workspaceName_sparkPoolName 'Microsoft.Synapse/workspaces/bigDataPools@2019-06-01-preview' = if (sparkDeployment == 'true') {
  parent: workspaceName
  name: sparkPoolName
  location: location
  tags: tags
  properties: {
    nodeCount: 5
    nodeSizeFamily: 'MemoryOptimized'
    nodeSize: sparkNodeSize
    autoScale: {
      enabled: true
      minNodeCount: 3
      maxNodeCount: 40
    }
    autoPause: {
      enabled: true
      delayInMinutes: 15
    }
    sparkVersion: '2.4'
  }
}

resource Microsoft_Authorization_roleAssignments_dlsName 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  scope: dlsName
  name: guid(uniqueString(dlsName_var))
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: reference(workspaceName.id, '2019-06-01-preview', 'Full').identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Creating symbolic name for an existing virtual network
resource vnetexisting 'Microsoft.Network/virtualNetworks@2020-07-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetSubscriptionId, vnetResourceGroupName)
}

resource synwspep 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: 'pep-${workspaceName_var}'
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      {
        name: 'pep-${workspaceName_var}'
        properties: {
          privateLinkServiceId: workspaceName.id
          groupIds: [
            'SqlOnDemand'
          ]
          privateLinkServiceConnectionState: {
            status: 'Approved'
          }
        }
      }
    ]
    manualPrivateLinkServiceConnections: []
    subnet: {
      id: '${vnetexisting.id}/subnets/${subnetName}'
    }
    customDnsConfigs: []
  }
}

resource sqlPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-01-01' = {
  name: 'privatelink.sql.azuresynapse.net'
  location: 'global'
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-11-01' = {
  parent: synwspep
  name: 'SqlOnDemand'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-sql-azuresynapse-net'
        properties: {
          privateDnsZoneId: sqlPrivateDnsZone.id
        }
      }
    ]
  }
}
