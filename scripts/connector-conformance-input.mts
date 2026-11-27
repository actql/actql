// The CLI and the installed runner select the same finite input.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {isAbsolute} from 'node:path';

type NormalConformanceCohort = {
  sourceSha: string;
  sourceTree: string;
  manifestPath: string;
  manifestSha256: string;
  outputRoot: string;
};

export type RestConformanceInput = NormalConformanceCohort & {
  kind: 'actql-standard-rest-normal/0.1'; accountConfigurationPath: string;
} & (
  {mode: 'empty' | 'one' | 'paged' | 'notion-users'} |
  {mode: 'author'; casePath: string; caseSha256: string}
);

export type RecordApprovalConformanceInput = NormalConformanceCohort & {
  kind: 'actql-record-approval-normal/0.1'; casePath: string; caseSha256: string;
  consumerRoot: string; decision: 'approved' | 'rejected';
} & ({mode: 'mock'; connector: 'salesforce' | 'hubspot' | 'kintone'} |
  {mode: 'http'; connector: 'hubspot' | 'kintone'});

export type ExternalInstalledConformanceInput = NormalConformanceCohort & {
  kind: 'actql-external-installed-normal/0.1'; mode: 'provider-bundle'; consumerRoot: string;
};

const sha256 = (value: unknown) => typeof value === 'string' && /^[a-f0-9]{64}$/u.test(value);
const gitIdentity = (value: unknown) => typeof value === 'string' && /^[a-f0-9]{40}$/u.test(value);
const absolute = (value: unknown) => typeof value === 'string' && isAbsolute(value);

export function readConnectorConformanceInput(path: string):
  RestConformanceInput | RecordApprovalConformanceInput | ExternalInstalledConformanceInput {
  const selected: unknown = JSON.parse(readFileSync(path, 'utf8'));
  assert(selected !== null && typeof selected === 'object' && !Array.isArray(selected), 'Invalid conformance descriptor');
  const value = selected as Record<string, unknown>;
  const cohort = ['kind', 'sourceSha', 'sourceTree', 'manifestPath', 'manifestSha256', 'outputRoot', 'mode'];
  const closed = (...fields: string[]) => Object.keys(value).length === cohort.length + fields.length &&
    [...cohort, ...fields].every(key => Object.hasOwn(value, key));
  const hasCase = () => absolute(value.casePath) && sha256(value.caseSha256);
  assert(gitIdentity(value.sourceSha) && gitIdentity(value.sourceTree) && sha256(value.manifestSha256) &&
    absolute(value.manifestPath) && absolute(value.outputRoot), 'Invalid conformance cohort descriptor');
  if (value.kind === 'actql-external-installed-normal/0.1') {
    assert(closed('consumerRoot') && absolute(value.consumerRoot) && value.mode === 'provider-bundle',
      'Invalid composed external conformance descriptor');
    return value as ExternalInstalledConformanceInput;
  }
  if (value.kind === 'actql-record-approval-normal/0.1') {
    assert(closed('casePath', 'caseSha256', 'connector', 'consumerRoot', 'decision') && hasCase() && absolute(value.consumerRoot) &&
      (value.decision === 'approved' || value.decision === 'rejected') &&
      (value.mode === 'mock' && value.connector === 'salesforce' ||
        (value.mode === 'mock' || value.mode === 'http') && (value.connector === 'hubspot' || value.connector === 'kintone')),
    'Invalid record approval conformance descriptor');
    return value as RecordApprovalConformanceInput;
  }
  const author = value.mode === 'author';
  assert(value.kind === 'actql-standard-rest-normal/0.1' &&
    closed('accountConfigurationPath', ...(author ? ['casePath', 'caseSha256'] : [])) &&
    absolute(value.accountConfigurationPath) && (author ? hasCase() : ['empty', 'one', 'paged', 'notion-users'].includes(value.mode as string)),
  'Invalid actql-standard-rest-normal/0.1 descriptor; select a runtime, Account and case explicitly');
  return value as RestConformanceInput;
}

export function readRestConformanceInput(path: string): RestConformanceInput {
  const input = readConnectorConformanceInput(path);
  assert(input.kind === 'actql-standard-rest-normal/0.1', 'Invalid REST read conformance descriptor');
  return input;
}
