// Installed representation contracts for one checked managed output. These
// pins describe physical decoding and logical row order; neither is a logical
// content identity or permission to publish the result.
import {snapshotPhysicalManifest} from './managed-manifest.mjs';
import type {PhysicalManifestControl} from './managed-manifest.mjs';

type RepresentationControl = PhysicalManifestControl & Readonly<{
  physicalRepresentationContracts(fieldsFrame: string, storageOrder: readonly number[], contractLimit: number): unknown;
}>;

const cid = (value: unknown): value is string => typeof value === 'string' &&
  /^sha256:[a-f0-9]{64}$/.test(value);
const quantity = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) >= 0;
const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };

export function managedPhysicalRepresentation(
  body: Readonly<{cid: string; bytes: number}>, rowCount: number, codecContractCid: string,
  fieldsFrame: string, storageOrder: readonly number[], control: RepresentationControl,
) {
  if (!body || !cid(body.cid) || !quantity(body.bytes) ||
      !quantity(rowCount) || !cid(codecContractCid) ||
      typeof fieldsFrame !== 'string' || !Array.isArray(storageOrder) ||
      storageOrder.some(value => !quantity(value)) || control === null ||
      typeof control !== 'object' ||
      typeof control.physicalRepresentationContracts !== 'function') {
    fail('InvalidManagedPhysicalRepresentation');
  }
  const contractLimit = 4096 + Buffer.byteLength(fieldsFrame);
  let contracts: unknown;
  try {
    contracts = control.physicalRepresentationContracts(
      fieldsFrame, storageOrder, contractLimit,
    );
  } catch {
    fail('InvalidManagedPhysicalRepresentation');
  }
  if (!Array.isArray(contracts) || contracts.length !== 5 ||
      contracts[0] !== 'ok' || typeof contracts[1] !== 'string' ||
      !cid(contracts[2]) || typeof contracts[3] !== 'string' ||
      !cid(contracts[4])) fail('InvalidManagedPhysicalRepresentation');
  const [, schemaContract, schemaContractCid, viewContract,
    viewContractCid] = contracts as [unknown, string, string, string, string];
  const manifest = {
    version: 'actql-managed-physical-manifest/0.1',
    schema_contract_cid: schemaContractCid,
    view_contract_cid: viewContractCid,
    codec_contract_cid: codecContractCid,
    row_count: rowCount,
    chunks: [{
      cid: body.cid,
      byte_length: body.bytes,
      row_count: rowCount,
    }],
  };
  const admitted = snapshotPhysicalManifest(manifest, {
    maxChunks: 1,
    maxManifestBytes: contractLimit,
    maxReferencedBytes: body.bytes,
  }, control);
  return Object.freeze({
    ...admitted,
    schemaContract,
    viewContract,
  });
}
