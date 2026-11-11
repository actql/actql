import {hubspotApprovalProvider} from './provider.mjs';

export function hubspotApprovalInstallation(selection) {
  const provider = hubspotApprovalProvider(selection);
  return {connectorId: 'hubspot', resource: 'companies', alias: 'hubspot.companies', selection, provider,
    metadata: {version: 'actql-hubspot-read-metadata/0.1', portalId: '7',
      accountBody: Buffer.from(JSON.stringify(provider.account)).toString('base64'),
      objects: [{resource: 'companies', objectType: 'companies',
        propertiesBody: Buffer.from(JSON.stringify(provider.properties)).toString('base64')}]},
    source: {portalId: '7', resources: [{resource: 'companies', objectType: 'companies'}],
      metadataResources: {account: 'account', properties: 'properties'},
      limits: {maxResponseBytes: 16384, maxNodes: 8000, maxDepth: 32, maxProperties: 16,
        maxNameUnits: 512, maxPages: 2, maxRows: 4, maxRequests: 6, perPage: 2,
        maxColumns: 3, maxCursorUnits: 128, maxValueNodes: 8000, maxValueTextBytes: 16384,
        maxRowsWireBytes: 16384, maxRowsWireNodes: 8000, maxRowsWireDepth: 32,
        maxObjects: 2, maxDeclarationBytes: 65536, maxDeclarationNodes: 8000, maxSecretBytes: 128}},
    write: {resource: 'companies', fields: ['name'], markerProperty: 'actql_request_id'}};
}
