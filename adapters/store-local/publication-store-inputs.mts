import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {cidPattern, exactKeys, fail, quantity} from './publication-store-io.mjs';

type OptionalEvidenceKey = Readonly<{privateEvidenceKey?: unknown}>;

type StoreConfiguration = Readonly<{
  directory: string;
  storeAuthorityCid: unknown;
  capacityBytes: number;
  maxObjectBytes: number;
  maxObjects: number;
  maxContractNodes: number;
  maxContractDepth: number;
  privateEvidenceKey: Buffer | undefined;
}>;

type ContractControlFields = Readonly<{
  admit?: unknown;
  recordTransition?: unknown;
  deliveryTransition?: unknown;
  deliverySuccessValid?: unknown;
  trustedClockNotBefore?: unknown;
  recordAllowsCommit?: unknown;
  effectFreeCommitValid?: unknown;
}>;

export function validateConfiguration(options: unknown): StoreConfiguration {
  const fields = [
    'directory',
    'storeAuthorityCid',
    'capacityBytes',
    'maxObjectBytes',
    'maxObjects',
    'maxContractNodes',
    'maxContractDepth',
  ] as const;
  if ((!exactKeys(options, fields) &&
      !exactKeys(options, [...fields, 'privateEvidenceKey'] as const)) ||
      (options as OptionalEvidenceKey).privateEvidenceKey !== undefined &&
        (!((options as OptionalEvidenceKey).privateEvidenceKey instanceof Uint8Array) ||
          ((options as OptionalEvidenceKey).privateEvidenceKey as Uint8Array).byteLength !== 32) ||
      typeof options.directory !== 'string' ||
      options.directory.length === 0 ||
      !cidPattern.test(options.storeAuthorityCid as string) ||
      !quantity(options.capacityBytes) ||
      !quantity(options.maxObjectBytes) || options.maxObjectBytes === 0 ||
      !quantity(options.maxObjects) || options.maxObjects === 0 ||
      !quantity(options.maxContractNodes) || options.maxContractNodes === 0 ||
      !quantity(options.maxContractDepth) || options.maxContractDepth === 0) {
    fail('InvalidPublicationStoreConfiguration');
  }
  return Object.freeze({...options, directory: resolve(options.directory),
    privateEvidenceKey: (options as OptionalEvidenceKey).privateEvidenceKey === undefined
      ? undefined : Buffer.from((options as OptionalEvidenceKey).privateEvidenceKey as Uint8Array)}) as StoreConfiguration;
}

export function validateContractControl<Control>(value: Control): Control {
  if (value === null || typeof value !== 'object' ||
      typeof (value as ContractControlFields).admit !== 'function' ||
      typeof (value as ContractControlFields).recordTransition !== 'function' ||
      typeof (value as ContractControlFields).deliveryTransition !== 'function' ||
      typeof (value as ContractControlFields).deliverySuccessValid !== 'function' ||
      typeof (value as ContractControlFields).trustedClockNotBefore !== 'function' ||
      typeof (value as ContractControlFields).recordAllowsCommit !== 'function' ||
      typeof (value as ContractControlFields).effectFreeCommitValid !== 'function') {
    fail('InvalidPublicationContractControl');
  }
  return value;
}

export function indexKey(value: unknown) {
  if (!exactKeys(value, [
    'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
  ] as const) || typeof value.namespaceId !== 'string' || value.namespaceId.length === 0 ||
      !cidPattern.test(value.authorityScopeCid as string) ||
      !cidPattern.test(value.runDefinitionCid as string)) {
    fail('InvalidPublicationIndexKey');
  }
  const hash = createHash('sha256');
  hash.update('actql-local-public-index-key/0.1\0', 'utf8');
  for (const text of [value.namespaceId, value.authorityScopeCid,
    value.runDefinitionCid]) {
    const bytes = Buffer.from(text as string, 'utf8');
    const length = Buffer.alloc(8);
    length.writeBigUInt64BE(BigInt(bytes.byteLength));
    hash.update(length);
    hash.update(bytes);
  }
  return hash.digest('hex');
}
