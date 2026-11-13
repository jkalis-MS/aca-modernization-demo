targetScope = 'resourceGroup'

@minLength(1)
param location string
param containerAppName string
param containerAppEnvironmentName string
param tags object
param identityName string
param registryName string
param keyVaultName string
param logWorkspaceName string
param applicationInsightsName string
param sqlServerName string
param databaseNames array
param deployApplication bool = false
param containerImage string = ''
@minValue(1)
@maxValue(1)
param replicaCount int = 1
param demoEnabled bool = false
param demoIsolatedEnvironment bool = false
@description('Versioned secret URI in the existing vault; never pass the token value.')
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

// Dependencies remain in this resource group and their original regions.
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: identityName
}
resource registry 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: registryName
}
resource logs 'Microsoft.OperationalInsights/workspaces@2026-03-01' existing = {
  name: logWorkspaceName
}
resource insights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}
resource sql 'Microsoft.Sql/servers@2025-01-01' existing = {
  name: sqlServerName
}

resource environment 'Microsoft.App/managedEnvironments@2026-07-01' = {
  name: containerAppEnvironmentName
  location: location
  tags: tags
  properties: {
    workloadProfiles: [
      { name: 'Consumption', workloadProfileType: 'Consumption' }
    ]
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logs.properties.customerId
        sharedKey: logs.listKeys().primarySharedKey
      }
    }
  }
}

resource app 'Microsoft.App/containerApps@2026-07-01' = if (deployApplication) {
  name: containerAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'web' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    environmentId: environment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: revisionMode
      ingress: {
        external: true
        allowInsecure: false
        targetPort: 8080
        transport: 'http'
        traffic: revisionTraffic
      }
      registries: [
        { server: registry.properties.loginServer, identity: identity.id }
      ]
      secrets: concat([
        { name: 'appinsights', value: insights.properties.ConnectionString }
      ], demoEnabled ? [
        { name: 'demo-token', keyVaultUrl: demoTokenSecretUri, identity: identity.id }
      ] : [])
    }
    template: {
      revisionSuffix: empty(revisionSuffix) ? null : revisionSuffix
      containers: [
        {
          name: 'web'
          image: containerImage
          resources: { cpu: json('0.5'), memory: '1Gi' }
          env: concat([
            { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
            { name: 'ASPNETCORE_FORWARDEDHEADERS_ENABLED', value: 'true' }
            { name: 'AZURE_CLIENT_ID', value: identity.properties.clientId }
            { name: 'KeyVaultName', value: keyVaultName }
            { name: 'Database__RecreateOnStartup', value: 'false' }
            { name: 'ApplicationInsights__ConnectionString', secretRef: 'appinsights' }
            {
              name: 'ConnectionStrings__MusicStoreEntities'
              value: 'Server=tcp:${sql.properties.fullyQualifiedDomainName},1433;Initial Catalog=${databaseNames[0]};Authentication=Active Directory Managed Identity;User Id=${identity.properties.clientId};Encrypt=True;TrustServerCertificate=False;Pooling=True;Load Balance Timeout=30;'
            }
            {
              name: 'ConnectionStrings__DefaultConnection'
              value: 'Server=tcp:${sql.properties.fullyQualifiedDomainName},1433;Initial Catalog=${databaseNames[1]};Authentication=Active Directory Managed Identity;User Id=${identity.properties.clientId};Encrypt=True;TrustServerCertificate=False;Pooling=True;Load Balance Timeout=30;'
            }
          ], demoEnabled ? [
            { name: 'Demo__Enabled', value: 'true' }
            { name: 'Demo__IsolatedEnvironment', value: string(demoIsolatedEnvironment) }
            { name: 'Demo__Token', secretRef: 'demo-token' }
          ] : [])
          probes: [
            {
              type: 'Startup'
              httpGet: { path: '/health/ready', port: 8080, scheme: 'HTTP' }
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 60
            }
            {
              type: 'Readiness'
              httpGet: { path: '/health/ready', port: 8080, scheme: 'HTTP' }
              periodSeconds: readinessPeriodSeconds
              timeoutSeconds: readinessTimeoutSeconds
              failureThreshold: readinessFailureThreshold
            }
            {
              type: 'Liveness'
              httpGet: { path: '/health/live', port: 8080, scheme: 'HTTP' }
              periodSeconds: 30
              timeoutSeconds: 5
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: demoEnabled ? demoMinReplicas : replicaCount
        maxReplicas: demoEnabled ? demoMaxReplicas : replicaCount
        rules: demoEnabled ? [
          { name: 'demo-http', http: { metadata: { concurrentRequests: string(httpConcurrency) } } }
        ] : []
      }
    }
  }
}

output appName string = containerAppName
output environmentName string = environment.name
output applicationUrl string = deployApplication ? 'https://${app!.properties.configuration.ingress.fqdn}' : ''
