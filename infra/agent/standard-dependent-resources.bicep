// Creates Azure dependent resources for Azure AI studio

@description('Azure region of the deployment')
param location string = resourceGroup().location

@description('Tags to add to the resources')
param tags object = {}

@description('AI services name')
param aiServicesName string

@description('The name of the AI Search resource')
param aiSearchName string

@description('The name of the Cosmos DB account')
param cosmosDbName string

@description('Name of the storage account')
param storageName string

@description('Model name for deployment')
param modelName string 

@description('Model format for deployment')
param modelFormat string 

@description('Model version for deployment')
param modelVersion string 

@description('Model deployment SKU name')
param modelSkuName string 

@description('Model deployment capacity')
param modelCapacity int 

@description('Model/AI Resource deployment location')
param modelLocation string 

@description('The AI Service Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param aiServiceAccountResourceId string

@description('The AI Search Service full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param aiSearchServiceResourceId string 

@description('The AI Storage Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param aiStorageAccountResourceId string 

@description('The AI Cosmos DB Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param aiCosmosDbAccountResourceId string

var aiServiceExists = aiServiceAccountResourceId != ''
var acsExists = aiSearchServiceResourceId != ''
var aiStorageExists = aiStorageAccountResourceId != ''
var cosmosExists = aiCosmosDbAccountResourceId != ''

// Create an AI Service account and model deployment if it doesn't already exist

var aiServiceParts = split(aiServiceAccountResourceId, '/')

resource existingAIServiceAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = if (aiServiceExists) {
  name: aiServiceParts[8]
  scope: resourceGroup(aiServiceParts[2], aiServiceParts[4])
}

resource aiServices 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = if(!aiServiceExists) {
  name: aiServicesName
  location: modelLocation
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: toLower('${(aiServicesName)}')
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }    
    publicNetworkAccess: 'Enabled'
    // API-key based auth is not supported for the Agent service
    disableLocalAuth: false
  }
}
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview'= if(!aiServiceExists){
  parent: aiServices
  name: modelName
  sku : {
    capacity: modelCapacity
    name: modelSkuName
  }
  properties: {
    model:{
      name: modelName
      format: modelFormat
      version: modelVersion
    }
  }
}

// Create an AI Search Service if it doesn't already exist

var acsParts = split(aiSearchServiceResourceId, '/')

resource existingSearchService 'Microsoft.Search/searchServices@2023-11-01' existing = if (acsExists) {
  name: acsParts[8]
  scope: resourceGroup(acsParts[2], acsParts[4])
}
resource aiSearch 'Microsoft.Search/searchServices@2024-06-01-preview' = if(!acsExists) {
  name: aiSearchName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    disableLocalAuth: false
    authOptions: { aadOrApiKey: { aadAuthFailureMode: 'http401WithBearerChallenge'}}
    encryptionWithCmk: {
      enforcement: 'Unspecified'
    }
    hostingMode: 'default'
    partitionCount: 1
    publicNetworkAccess: 'enabled'
    replicaCount: 1
    semanticSearch: 'disabled'
  }
  sku: {
    name: 'standard'
  }
}

// Create a Storage account if it doesn't already exist

var aiStorageParts = split(aiStorageAccountResourceId, '/')

resource existingAIStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = if (aiStorageExists) {
  name: aiStorageParts[8]
  scope: resourceGroup(aiStorageParts[2], aiStorageParts[4])
}

param sku string = 'Standard_LRS'

resource storage 'Microsoft.Storage/storageAccounts@2022-05-01' = if(!aiStorageExists) {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: {
    name: sku
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
      virtualNetworkRules: []
    }
    allowSharedKeyAccess: false
  }
}

// Create a Cosmos DB Account if it doesn't already exist

var cosmosAccountParts = split(aiCosmosDbAccountResourceId, '/')

resource existingCosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = if (cosmosExists) {
  name: cosmosAccountParts[8]
  scope: resourceGroup(cosmosAccountParts[2], cosmosAccountParts[4])
}

var canaryRegions = ['eastus2euap', 'centraluseuap']
var cosmosDbRegion = contains(canaryRegions, location) ? 'eastus2' : location
resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = if(!cosmosExists) {
  name: cosmosDbName
  location: cosmosDbRegion
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    disableLocalAuth: true
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    enableFreeTier: false
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    databaseAccountOfferType: 'Standard'
  }
}

// Outputs

output aiServicesName string =  aiServiceExists ? existingAIServiceAccount.name : aiServicesName
output aiservicesID string = aiServiceExists ? existingAIServiceAccount.id : aiServices.id
output aiservicesTarget string = aiServiceExists ? existingAIServiceAccount.properties.endpoint : aiServices.properties.endpoint
output aiServiceAccountResourceGroupName string = aiServiceExists ? aiServiceParts[4] : resourceGroup().name
output aiServiceAccountSubscriptionId string = aiServiceExists ? aiServiceParts[2] : subscription().subscriptionId 

output aiSearchName string = acsExists ? existingSearchService.name : aiSearch.name
output aisearchID string = acsExists ? existingSearchService.id : aiSearch.id
output aiSearchServiceResourceGroupName string = acsExists ? acsParts[4] : resourceGroup().name
output aiSearchServiceSubscriptionId string = acsExists ? acsParts[2] : subscription().subscriptionId

output storageAccountName string = aiStorageExists ? existingAIStorageAccount.name :  storage.name
output storageId string =  aiStorageExists ? existingAIStorageAccount.id :  storage.id
output storageAccountResourceGroupName string = aiStorageExists ? aiStorageParts[4] : resourceGroup().name
output storageAccountSubscriptionId string = aiStorageExists ? aiStorageParts[2] : subscription().subscriptionId

output cosmosDbAccountName string = cosmosExists ? existingCosmosDbAccount.name : cosmosDbAccount.name
output cosmosDbAccountId string = cosmosExists ? existingCosmosDbAccount.id : cosmosDbAccount.id
output cosmosDbAccountResourceGroupName string = cosmosExists ? cosmosAccountParts[4] : resourceGroup().name
output cosmosDbAccountSubscriptionId string = cosmosExists ? cosmosAccountParts[2] : subscription().subscriptionId
