import {kintoneApprovalProvider} from './provider.mjs';
import type {RecordFixtureKind} from '../record-approval/cases.mjs';

export function kintoneApprovalInstallation(selection: Parameters<typeof kintoneApprovalProvider>[0], kind: RecordFixtureKind = 'update') {
  const provider = kintoneApprovalProvider(selection, kind);
  const keyed = kind === 'upsert';
  return {connectorId: 'kintone', resource: 'inquiries', alias: 'kintone.inquiries', selection, provider,
    metadata: {version: 'actql-kintone-record-metadata/0.1', appId: '12',
      formBody: Buffer.from(JSON.stringify(provider.form)).toString('base64')},
    source: {appId: '12', resource: 'inquiries', formResource: 'form',
      fieldCodes: keyed ? ['Computed', 'CustomerKey', 'Subject', 'Tags'] : ['Subject', 'Tags', 'Computed'],
      limits: {maxResponseBytes: 16384, maxNodes: 8000, maxDepth: 32, maxFields: 16,
        maxNameUnits: 512, maxColumns: 8, maxCells: 32, maxTableRows: 16,
        maxValueNodes: 8000, maxValueDepth: 32, maxValueTextBytes: 16384,
        maxContractPairs: 100, maxRequestBytes: 2048, maxRequests: 6, maxPages: 2,
        perPage: 2, maxSecretBytes: 128, maxRows: 4, maxDeclarationBytes: 65536, maxDeclarationNodes: 8000}},
    write: kind === 'delete' ? {resource: 'inquiries', kind} : {resource: 'inquiries', ...(keyed ? {kind, key: 'CustomerKey'} : {}), fields: ['Subject']}};
}
