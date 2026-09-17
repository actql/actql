// Installed representation contracts for one checked managed output. These
// pins describe physical decoding and logical row order; neither is a logical
// content identity or permission to publish the result.
import {createHash} from 'node:crypto';
import {snapshotPhysicalManifest} from './managed-manifest.mjs';

const sha = text => `sha256:${createHash('sha256').update(text).digest('hex')}`;
const cid = value => typeof value === 'string' &&
  /^sha256:[a-f0-9]{64}$/.test(value);
const quantity = value => Number.isSafeInteger(value) && value >= 0;
const fail = code => { throw Object.assign(new Error(code), {code}); };

export function managedPhysicalRepresentation(
  body, rowCount, codecContractCid, fieldsFrame, storageOrder,
) {
  if (!body || !cid(body.cid) || !quantity(body.bytes) ||
      !quantity(rowCount) || !cid(codecContractCid) ||
      typeof fieldsFrame !== 'string' || !Array.isArray(storageOrder) ||
      storageOrder.some(value => !quantity(value))) {
    fail('InvalidManagedPhysicalRepresentation');
  }
  let fields;
  try { fields = JSON.parse(fieldsFrame); }
  catch { fail('InvalidManagedPhysicalRepresentation'); }
  if (!Array.isArray(fields) || fields.length !== storageOrder.length ||
      new Set(storageOrder).size !== storageOrder.length ||
      storageOrder.some(index => index >= fields.length)) {
    fail('InvalidManagedPhysicalRepresentation');
  }
  const storedFields = storageOrder.map(index => fields[index]);
  const schemaContract = JSON.stringify({
    fields: storedFields,
    version: 'actql-managed-physical-schema/0.1',
  });
  const schemaContractCid = sha(schemaContract);
  const viewContract = JSON.stringify({
    order: 'managed-output-occurrence-ascending',
    schema_contract_cid: schemaContractCid,
    version: 'actql-managed-physical-view/0.1',
  });
  const manifest = {
    version: 'actql-managed-physical-manifest/0.1',
    schema_contract_cid: schemaContractCid,
    view_contract_cid: sha(viewContract),
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
    maxManifestBytes: 4096 + Buffer.byteLength(fieldsFrame),
    maxReferencedBytes: body.bytes,
  });
  return Object.freeze({
    ...admitted,
    schemaContract,
    viewContract,
  });
}
