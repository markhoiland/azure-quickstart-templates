@description('The location into which regionally scoped resources should be deployed. Note that Front Door is a global resource.')
param appLocationPrim string = 'eastus'

@description('The location into which regionally scoped resources should be deployed. Note that Front Door is a global resource.')
param appLocationSec string = 'westus'

@description('The name of the App Service application to create. This must be globally unique.')
param appName string = 'afddemo'

@description('The name of the SKU to use when creating the App Service plan.')
param appServicePlanSkuName string = 'S1'

@description('The number of worker instances of your App Service plan that should be provisioned.')
param appServicePlanCapacity int = 1

@description('The name of the Front Door endpoint to create. This must be globally unique.')
param frontDoorEndpointName string = 'afd-${uniqueString(resourceGroup().id)}'

@description('The name of the SKU to use when creating the Front Door profile.')
@allowed([
  'Standard_AzureFrontDoor'
  'Premium_AzureFrontDoor'
])
param frontDoorSkuName string = 'Standard_AzureFrontDoor'

var appServicePlanNamePrim = 'asp-${appName}-${appLocationPrim}-${uniqueString(resourceGroup().id)}'
var appServicePlanNameSec = 'asp-${appName}-${appLocationSec}-${uniqueString(resourceGroup().id)}'
var appNamePrim = 'app-${appName}-${appLocationPrim}-${uniqueString(resourceGroup().id)}'
var appNameSec = 'app-${appName}-${appLocationSec}-${uniqueString(resourceGroup().id)}'

var frontDoorProfileName = 'afd-${appName}-${uniqueString(resourceGroup().id)}'
var frontDoorOriginGroupName = 'afdog-${appName}-${uniqueString(resourceGroup().id)}'
var frontDoorOriginName = 'afdorigin-${appName}-${uniqueString(resourceGroup().id)}'
var frontDoorRouteName = 'afdroute-${appName}-${uniqueString(resourceGroup().id)}'

resource frontDoorProfile 'Microsoft.Cdn/profiles@2021-06-01' = {
  name: frontDoorProfileName
  location: 'global'
  sku: {
    name: frontDoorSkuName
  }
}

resource appServicePlanPrim 'Microsoft.Web/serverFarms@2020-06-01' = {
  name: appServicePlanNamePrim
  location: appLocationPrim
  sku: {
    name: appServicePlanSkuName
    capacity: appServicePlanCapacity
  }
  kind: 'app'
}

resource appPrim 'Microsoft.Web/sites@2020-06-01' = {
  name: appNamePrim
  location: appLocationPrim
  kind: 'app'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanPrim.id
    httpsOnly: true
    siteConfig: {
      detailedErrorLoggingEnabled: true
      httpLoggingEnabled: true
      requestTracingEnabled: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      ipSecurityRestrictions: [
        {
          tag: 'ServiceTag'
          ipAddress: 'AzureFrontDoor.Backend'
          action: 'Allow'
          priority: 100
          headers: {
            'x-azure-fdid': [
              frontDoorProfile.properties.frontDoorId
            ]
          }
          name: 'Allow traffic from Front Door'
        }
      ]
    }
  }
}

resource appServicePlanSec 'Microsoft.Web/serverFarms@2020-06-01' = {
  name: appServicePlanNameSec
  location: appLocationSec
  sku: {
    name: appServicePlanSkuName
    capacity: appServicePlanCapacity
  }
  kind: 'app'
}

resource appSec 'Microsoft.Web/sites@2020-06-01' = {
  name: appNameSec
  location: appLocationSec
  kind: 'app'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanSec.id
    httpsOnly: true
    siteConfig: {
      detailedErrorLoggingEnabled: true
      httpLoggingEnabled: true
      requestTracingEnabled: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      ipSecurityRestrictions: [
        {
          tag: 'ServiceTag'
          ipAddress: 'AzureFrontDoor.Backend'
          action: 'Allow'
          priority: 100
          headers: {
            'x-azure-fdid': [
              frontDoorProfile.properties.frontDoorId
            ]
          }
          name: 'Allow traffic from Front Door'
        }
      ]
    }
  }
}

resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2021-06-01' = {
  name: frontDoorEndpointName
  parent: frontDoorProfile
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

resource frontDoorOriginGroup 'Microsoft.Cdn/profiles/originGroups@2021-06-01' = {
  name: frontDoorOriginGroupName
  parent: frontDoorProfile
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
    }
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'HEAD'
      probeProtocol: 'Http'
      probeIntervalInSeconds: 100
    }
  }
}

resource frontDoorOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2021-06-01' = {
  name: frontDoorOriginName
  parent: frontDoorOriginGroup
  properties: {
    hostName: appPrim.properties.defaultHostName
    httpPort: 80
    httpsPort: 443
    originHostHeader: appPrim.properties.defaultHostName
    priority: 1
    weight: 1000
  }
}

resource frontDoorRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2021-06-01' = {
  name: frontDoorRouteName
  parent: frontDoorEndpoint
  dependsOn: [
    frontDoorOrigin // This explicit dependency is required to ensure that the origin group is not empty when the route is created.
  ]
  properties: {
    originGroup: {
      id: frontDoorOriginGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
  }
}

output appServiceHostNamePrim string = appPrim.properties.defaultHostName
output appServiceHostNameSec string = appSec.properties.defaultHostName
output frontDoorEndpointHostName string = frontDoorEndpoint.properties.hostName
