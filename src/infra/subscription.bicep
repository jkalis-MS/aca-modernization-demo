targetScope = 'subscription'

@description('All resources are deployed into this new resource group.')
@minLength(1)
param resourceGroupName string

@minLength(1)
param location string

@minLength(1)
param environmentName string

@description('Microsoft Entra object ID of the operator bootstrapping SQL database access.')
param sqlAdministratorObjectId string

param sqlAdministratorLogin string

@description('Public IPv4 address of the deployment workstation, allowed only as a /32 SQL firewall rule.')
param sqlDeploymentClientIp string

param deployApplication bool = false
param containerImage string = ''

param demoEnabled bool = false
param demoIsolatedEnvironment bool = false
param demoTokenSecretUri string = ''
@minValue(1)
@maxValue(4)
param demoMinReplicas int = 2
@minValue(1)
@maxValue(4)
param demoMaxReplicas int = 4
@minValue(1)
@maxValue(100)
param httpConcurrency int = 5
@allowed(['Single', 'Multiple'])
param revisionMode string = demoEnabled ? 'Multiple' : 'Single'
param revisionSuffix string = ''
param revisionTraffic array = [{ latestRevision: true, weight: 100 }]
@minValue(1)
@maxValue(30)
param readinessPeriodSeconds int = demoEnabled ? 5 : 30
@minValue(1)
@maxValue(10)
param readinessTimeoutSeconds int = demoEnabled ? 3 : 10
@minValue(1)
@maxValue(10)
param readinessFailureThreshold int = demoEnabled ? 2 : 3

resource resourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
  tags: {
    application: 'musicstore'
    environment: environmentName
  }
}

module infrastructure './main.bicep' = {
  name: 'musicstore-infrastructure'
  scope: resourceGroup
  params: {
    location: location
    environmentName: environmentName
    sqlAdministratorObjectId: sqlAdministratorObjectId
    sqlAdministratorLogin: sqlAdministratorLogin
    sqlDeploymentClientIp: sqlDeploymentClientIp
    deployApplication: deployApplication
    containerImage: containerImage
    demoEnabled: demoEnabled
    demoIsolatedEnvironment: demoIsolatedEnvironment
    demoTokenSecretUri: demoTokenSecretUri
    demoMinReplicas: demoMinReplicas
    demoMaxReplicas: demoMaxReplicas
    httpConcurrency: httpConcurrency
    revisionMode: revisionMode
    revisionSuffix: revisionSuffix
    revisionTraffic: revisionTraffic
    readinessPeriodSeconds: readinessPeriodSeconds
    readinessTimeoutSeconds: readinessTimeoutSeconds
    readinessFailureThreshold: readinessFailureThreshold
  }
}

output resources object = infrastructure.outputs.resources
