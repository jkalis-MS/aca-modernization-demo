targetScope = 'resourceGroup'

@minLength(1)
@maxLength(32)
param environmentName string

@minLength(1)
param location string

param sqlAdministratorObjectId string
param sqlAdministratorLogin string
param sqlDeploymentClientIp string
param deployApplication bool = false
param containerImage string = ''

@allowed(['Basic'])
param sqlSkuName string = 'Basic'

@minValue(1)
@maxValue(1)
@description('The app uses in-memory session state; keep a single replica until session/key storage is externalized.')
param replicaCount int = 1

@description('Opt in only for anonymous catalog demos; cart/session continuity is not supported across replicas.')
param demoEnabled bool = false
param demoIsolatedEnvironment bool = false
@description('Versioned Key Vault secret URI for a random demo token; never supply the token itself.')
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
@description('Explicit named revision traffic. In Multiple mode, do not use latestRevision for a controlled release.')
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

var token = uniqueString(subscription().id, resourceGroup().id, environmentName)
var tags = {
  application: 'musicstore'
  'azd-env-name': environmentName
}
var databaseNames = ['MvcMusicStore', 'MvcMusicStore-Identity']

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-musicstore-${token}'
  location: location
  tags: tags
}

resource logs 'Microsoft.OperationalInsights/workspaces@2026-03-01' = {
  name: 'log-musicstore-${token}'
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    sku: { name: 'PerGB2018' }
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-musicstore-${token}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
  }
}

resource registry 'Microsoft.ContainerRegistry/registries@2025-11-01' = {
  name: 'acrmusic${token}'
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

resource registryPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, identity.id, 'AcrPull')
  scope: registry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource vault 'Microsoft.KeyVault/vaults@2026-05-15' = {
  name: 'kv-music-${token}'
  location: location
  tags: tags
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource vaultRead 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, identity.id, 'KeyVaultSecretsUser')
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource sql 'Microsoft.Sql/servers@2025-01-01' = {
  name: 'sql-musicstore-${token}'
  location: location
  tags: tags
  properties: {
    minimalTlsVersion: '1.2'
    version: '12.0'
    publicNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'User'
      login: sqlAdministratorLogin
      sid: sqlAdministratorObjectId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: true
    }
  }
}

// Demo networking: this permits authenticated connections from Azure, not just this app.
resource azureSqlAccess 'Microsoft.Sql/servers/firewallRules@2025-01-01' = {
  parent: sql
  name: 'AllowAzureServices'
  properties: { startIpAddress: '0.0.0.0', endIpAddress: '0.0.0.0' }
}

resource deploymentSqlAccess 'Microsoft.Sql/servers/firewallRules@2025-01-01' = {
  parent: sql
  name: 'DeploymentClient'
  properties: {
    startIpAddress: sqlDeploymentClientIp
    endIpAddress: sqlDeploymentClientIp
  }
}

resource databases 'Microsoft.Sql/servers/databases@2025-01-01' = [for databaseName in databaseNames: {
  parent: sql
  name: databaseName
  location: location
  tags: tags
  sku: { name: sqlSkuName, tier: 'Basic', capacity: 5 }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648
  }
}]

resource environment 'Microsoft.App/managedEnvironments@2026-07-01' = {
  name: 'cae-musicstore-${token}'
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
  name: 'ca-musicstore-${token}'
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
            { name: 'KeyVaultName', value: vault.name }
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
  dependsOn: [registryPull, vaultRead, databases]
}

output resources object = {
  resourceGroupName: resourceGroup().name
  registryName: registry.name
  registryEndpoint: registry.properties.loginServer
  sqlServerName: sql.name
  sqlServerEndpoint: sql.properties.fullyQualifiedDomainName
  databaseNames: databaseNames
  identityName: identity.name
  identityPrincipalId: identity.properties.principalId
  identityClientId: identity.properties.clientId
  keyVaultName: vault.name
  logWorkspaceName: logs.name
  applicationInsightsName: insights.name
  environmentName: environment.name
  appName: 'ca-musicstore-${token}'
  applicationUrl: deployApplication ? 'https://${app!.properties.configuration.ingress.fqdn}' : ''
  logWorkspaceId: logs.properties.customerId
}
