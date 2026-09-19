// Installed representation contracts for one checked managed output. These
// pins describe physical decoding and logical row order; neither is a logical
// content identity or permission to publish the result.
import {snapshotPhysicalManifest} from './managed-manifest.mjs';

const cid = value => typeof value === 'string' &&
  /^sha256:[a-f0-9]{64}$/.test(value);
const quantity = value => Number.isSafeInteger(value) && value >= 0;
const fail = code => { throw Object.assign(new Error(code), {code}); };

export function managedPhysicalRepresentation(
  body, rowCount, codecContractCid, fieldsFrame, storageOrder, control,
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
  let contracts;
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
    viewContractCid] = contracts;
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
