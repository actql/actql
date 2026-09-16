// Physical-manifest admission for installed managed execution wiring. This
// module issues no ActQL completion, logical CID, codec or authorization proof.
import {createHash} from 'node:crypto';
import {localStoreOwnsBody, localRetainedStoreAvailable, RetainedFileError} from './files.mjs';
import {withVerifiedDelegatedFile} from './direct-file.mjs';

const fail = code => { throw new RetainedFileError(code); };
const quantity = value => Number.isSafeInteger(value) && value >= 0;
const cid = value => typeof value === 'string' && /^sha256:[a-f0-9]{64}$/.test(value);
const fields = ['version', 'schema_contract_cid', 'view_contract_cid', 'codec_contract_cid', 'row_count', 'chunks'];

function record(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(value))) fail('InvalidPhysicalManifest');
  const descriptors = Object.getOwnPropertyDescriptors(value);
  if (Reflect.ownKeys(descriptors).length !== keys.length) fail('InvalidPhysicalManifest');
  const result = Object.create(null);
  for (const key of keys) {
    const d = descriptors[key];
    if (!d || !Object.hasOwn(d, 'value') || !d.enumerable) fail('InvalidPhysicalManifest');
    result[key] = d.value;
  }
  return result;
}

function sum(a, b) {
  if (b > Number.MAX_SAFE_INTEGER - a) fail('PhysicalManifestCountOverflow');
  return a + b;
}

export function snapshotPhysicalManifest(supplied, limits) {
  if (!limits || !quantity(limits.maxChunks) || !quantity(limits.maxManifestBytes) ||
      !quantity(limits.maxReferencedBytes)) fail('InvalidPhysicalManifestLimits');
  const input = record(supplied, fields);
  if (input.version !== 'actql-managed-physical-manifest/0.1' ||
      !cid(input.schema_contract_cid) || !cid(input.view_contract_cid) ||
      !cid(input.codec_contract_cid) || !quantity(input.row_count) ||
      !Array.isArray(input.chunks)) fail('InvalidPhysicalManifest');
  if (input.chunks.length > limits.maxChunks) fail('PhysicalManifestLimit');
  // Only dense ordinary arrays; avoid invoking getters while admitting metadata.
  if (Object.getPrototypeOf(input.chunks) !== Array.prototype ||
      Reflect.ownKeys(input.chunks).length !== input.chunks.length + 1) fail('InvalidPhysicalManifest');
  const chunks = [], hash = createHash('sha256');
  let bytes = 0, rows = 0, referencedBytes = 0;
  const emit = text => {
    // All accepted values are ASCII constants, lowercase CID text and integers.
    if (text.length > limits.maxManifestBytes - bytes) fail('PhysicalManifestLimit');
    bytes += text.length;
    hash.update(text, 'utf8');
  };
  emit('{"chunks":[');
  for (let index = 0; index < input.chunks.length; index++) {
    const descriptor = Object.getOwnPropertyDescriptor(input.chunks, String(index));
    if (!descriptor || !Object.hasOwn(descriptor, 'value')) fail('InvalidPhysicalManifest');
    const chunk = record(descriptor.value, ['cid', 'byte_length', 'row_count']);
    if (!cid(chunk.cid) || !quantity(chunk.byte_length) || !quantity(chunk.row_count)) fail('InvalidPhysicalManifest');
    rows = sum(rows, chunk.row_count);
    referencedBytes = sum(referencedBytes, chunk.byte_length);
    if (referencedBytes > limits.maxReferencedBytes) fail('PhysicalManifestLimit');
    // Canonical key order; neither sorting nor a full metadata JSON tree is needed.
    const frozen = Object.freeze({byte_length: chunk.byte_length, cid: chunk.cid, row_count: chunk.row_count});
    emit((index ? ',' : '') + JSON.stringify(frozen));
    chunks.push(frozen);
  }
  if (rows !== input.row_count) fail('PhysicalManifestRowCountMismatch');
  emit(`],"codec_contract_cid":${JSON.stringify(input.codec_contract_cid)},"row_count":${input.row_count},"schema_contract_cid":${JSON.stringify(input.schema_contract_cid)},"version":"actql-managed-physical-manifest/0.1","view_contract_cid":${JSON.stringify(input.view_contract_cid)}}`);
  const manifest = Object.freeze({
    chunks: Object.freeze(chunks), codec_contract_cid: input.codec_contract_cid,
    row_count: input.row_count, schema_contract_cid: input.schema_contract_cid,
    version: input.version, view_contract_cid: input.view_contract_cid,
  });
  return Object.freeze({manifest, cid: `sha256:${hash.digest('hex')}`, bytes, referencedBytes});
}

// All bodies are pinned before native use, including later chunks. Duplicated
// occurrences share one holding but are decoded in each manifest position.
// The installed decoder must settle all use before returning its actual count;
// output remains provisional until this entire operation succeeds. The expected
// interpretation pins come from Host admission, not from the manifest itself.
export async function consumePhysicalManifestFiles(store, supplied, suppliedBodies,
  expected, limits, session, decode, signal, beforeRead) {
  signal?.throwIfAborted();
  if (!localRetainedStoreAvailable(store)) fail('ForeignPhysicalManifestHolding');
  if (typeof decode !== 'function' || (beforeRead !== undefined && typeof beforeRead !== 'function') ||
      typeof session !== 'string' || !session.length || session.length > 256) fail('InvalidPhysicalManifestReader');
  const admitted = snapshotPhysicalManifest(supplied, limits);
  const interpretation = record(expected, ['schema_contract_cid', 'view_contract_cid', 'codec_contract_cid']);
  for (const key of Object.keys(interpretation)) {
    if (interpretation[key] !== admitted.manifest[key]) fail('ForeignPhysicalManifestInterpretation');
  }
  if (!Array.isArray(suppliedBodies) || suppliedBodies.length !== admitted.manifest.chunks.length) fail('ForeignPhysicalManifestHolding');
  const bodies = suppliedBodies.slice(), borrows = new Map();
  const live = () => {
    signal?.throwIfAborted();
    if (!localRetainedStoreAvailable(store)) fail('RetainedUnavailable');
    for (const body of borrows.keys()) if (!body.available()) fail('RetainedUnavailable');
  };
  try {
    for (let index = 0; index < bodies.length; index++) {
      const body = bodies[index], chunk = admitted.manifest.chunks[index];
      if (!localStoreOwnsBody(store, body) || !body.available() ||
          body.cid !== chunk.cid || body.bytes !== chunk.byte_length) fail('ForeignPhysicalManifestHolding');
      if (!borrows.has(body)) borrows.set(body, body.delegateRead(session));
    }
    let integrityReadBytes = 0;
    for (let index = 0; index < bodies.length; index++) {
      live();
      const borrow = borrows.get(bodies[index]), chunk = admitted.manifest.chunks[index];
      let result;
      try {
        result = await withVerifiedDelegatedFile(borrow.descriptor, async file => {
          live();
          const rowCount = await decode(file, index, chunk);
          live();
          if (!quantity(rowCount) || rowCount !== chunk.row_count) fail('PhysicalManifestDecodedCountMismatch');
        }, signal, async bytes => { live(); await beforeRead?.(bytes, index); live(); });
      } catch (error) {
        if (['RetainedBodyChanged', 'RetainedBodyTruncated', 'ForeignStoreFile', 'ENOENT'].includes(error?.code)) bodies[index].close();
        throw error;
      }
      borrow.verify(result.report);
      live();
      integrityReadBytes = sum(integrityReadBytes, chunk.byte_length);
    }
    live();
    return Object.freeze({manifestCid: admitted.cid, rowCount: admitted.manifest.row_count,
      chunkOccurrences: bodies.length, integrityReadBytes, metadataBytes: admitted.bytes});
  } finally {
    // Awaited readers have stopped even on failure. Revocation and Store cleanup
    // remain owned by the original holding; do not close the source on failure.
    for (const borrow of borrows.values()) borrow.confirmStopped();
  }
}
