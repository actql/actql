// Physical-manifest object snapshot and Store consumption. Canonical identity,
// aggregate counts and bounded admission are owned by portable MoonBit.
import {localStoreOwnsBody, localRetainedStoreAvailable, RetainedFileError} from './files.mjs';
import {withVerifiedDelegatedFile} from './direct-file.mjs';
import type {LocalRetainedStore} from './files.mjs';

type RetainedBody = Awaited<ReturnType<ReturnType<LocalRetainedStore['reserve']>['sealPhysical']>>;
type Chunk = Readonly<{cid: string; byte_length: number; row_count: number}>;
type Manifest = Readonly<{
  version: string;
  schema_contract_cid: string;
  view_contract_cid: string;
  codec_contract_cid: string;
  row_count: number;
  chunks: readonly Chunk[];
}>;
type ManifestSnapshot = Readonly<{manifest: Manifest; cid: string; bytes: number; referencedBytes: number}>;
type ManifestLimits = Readonly<{maxChunks: number; maxManifestBytes: number; maxReferencedBytes: number}>;
type DecodeChunk = (file: Parameters<Parameters<typeof withVerifiedDelegatedFile>[1]>[0],
  index: number, chunk: Chunk) => unknown;
export type PhysicalManifestControl = Readonly<{
  physicalManifestAdmit(version: string, schemaContractCid: string, viewContractCid: string,
    codecContractCid: string, rowCount: number, chunkCids: string[], chunkByteLengths: bigint[],
    chunkRowCounts: number[], maxChunks: number, maxManifestBytes: number, maxReferencedBytes: bigint): unknown;
}>;

const fail: (code: string) => never = code => { throw new RetainedFileError(code); };
const quantity = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) >= 0;
const fields = ['version', 'schema_contract_cid', 'view_contract_cid', 'codec_contract_cid', 'row_count', 'chunks'] as const;
const admittedSnapshots = new WeakSet<object>();
const admittedManifests = new WeakMap<object, ManifestSnapshot>();

function record<Key extends string>(value: unknown, keys: readonly Key[]): Record<Key, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(value))) fail('InvalidPhysicalManifest');
  const descriptors = Object.getOwnPropertyDescriptors(value);
  if (Reflect.ownKeys(descriptors).length !== keys.length) fail('InvalidPhysicalManifest');
  const result = Object.create(null) as Record<Key, unknown>;
  for (const key of keys) {
    const d = descriptors[key];
    if (!d || !Object.hasOwn(d, 'value') || !d.enumerable) fail('InvalidPhysicalManifest');
    result[key] = d.value;
  }
  return result;
}

function sum(a: number, b: number) {
  if (!quantity(a) || !quantity(b) || b > Number.MAX_SAFE_INTEGER - a) {
    fail('PhysicalManifestCountOverflow');
  }
  return a + b;
}

const semanticIssue = (code: unknown) => {
  if (code === 'limit') return 'PhysicalManifestLimit';
  if (code === 'overflow') return 'PhysicalManifestCountOverflow';
  if (code === 'row-count') return 'PhysicalManifestRowCountMismatch';
  return 'InvalidPhysicalManifest';
};

const safeProjectionCount = (value: unknown) => {
  if (typeof value !== 'string' || !/^\d+$/.test(value)) {
    fail('InvalidPhysicalManifestControl');
  }
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < 0) {
    fail('InvalidPhysicalManifestControl');
  }
  return number;
};

export function admittedPhysicalManifestSnapshot(value: unknown) {
  if (value === null || typeof value !== 'object') return undefined;
  if (admittedSnapshots.has(value)) return value as ManifestSnapshot;
  return admittedManifests.get(value);
}

export function snapshotPhysicalManifest(supplied: unknown, limits: ManifestLimits,
  control: PhysicalManifestControl): ManifestSnapshot {
  if (!limits || !quantity(limits.maxChunks) ||
      !quantity(limits.maxManifestBytes) ||
      !quantity(limits.maxReferencedBytes)) {
    fail('InvalidPhysicalManifestLimits');
  }
  if (control === null || typeof control !== 'object' ||
      typeof control.physicalManifestAdmit !== 'function') {
    fail('InvalidPhysicalManifestControl');
  }
  const input = record(supplied, fields);
  if (!quantity(input.row_count) ||
      !Array.isArray(input.chunks)) fail('InvalidPhysicalManifest');
  // Only dense ordinary arrays; avoid invoking getters while admitting metadata.
  if (Object.getPrototypeOf(input.chunks) !== Array.prototype ||
      Reflect.ownKeys(input.chunks).length !== input.chunks.length + 1) fail('InvalidPhysicalManifest');
  const chunks: Chunk[] = [];
  for (let index = 0; index < input.chunks.length; index++) {
    const descriptor = Object.getOwnPropertyDescriptor(input.chunks, String(index));
    if (!descriptor || !Object.hasOwn(descriptor, 'value')) fail('InvalidPhysicalManifest');
    const chunk = record(descriptor.value, ['cid', 'byte_length', 'row_count']);
    if (typeof chunk.cid !== 'string' || !quantity(chunk.byte_length) ||
        !quantity(chunk.row_count)) fail('InvalidPhysicalManifest');
    chunks.push(Object.freeze({
      byte_length: chunk.byte_length,
      cid: chunk.cid,
      row_count: chunk.row_count,
    }));
  }
  let projection: unknown;
  try {
    projection = control.physicalManifestAdmit(
      input.version as string,
      input.schema_contract_cid as string,
      input.view_contract_cid as string,
      input.codec_contract_cid as string,
      input.row_count,
      chunks.map(chunk => chunk.cid),
      chunks.map(chunk => BigInt(chunk.byte_length)),
      chunks.map(chunk => chunk.row_count),
      limits.maxChunks,
      limits.maxManifestBytes,
      BigInt(limits.maxReferencedBytes),
    );
  } catch {
    fail('InvalidPhysicalManifestControl');
  }
  if (!Array.isArray(projection) || projection.length < 2) {
    fail('InvalidPhysicalManifestControl');
  }
  if (projection[0] === 'error') fail(semanticIssue(projection[1]));
  if (projection.length !== 5 || projection[0] !== 'ok' ||
      typeof projection[1] !== 'string' ||
      !/^sha256:[a-f0-9]{64}$/.test(projection[1])) {
    fail('InvalidPhysicalManifestControl');
  }
  const bytes = safeProjectionCount(projection[2]);
  const referencedBytes = safeProjectionCount(projection[3]);
  const admittedRows = safeProjectionCount(projection[4]);
  if (admittedRows !== input.row_count) fail('InvalidPhysicalManifestControl');
  const manifest = Object.freeze({
    chunks: Object.freeze(chunks), codec_contract_cid: input.codec_contract_cid as string,
    row_count: input.row_count, schema_contract_cid: input.schema_contract_cid as string,
    version: input.version as string, view_contract_cid: input.view_contract_cid as string,
  });
  const snapshot = Object.freeze({
    manifest,
    cid: projection[1],
    bytes,
    referencedBytes,
  });
  admittedSnapshots.add(snapshot);
  admittedManifests.set(manifest, snapshot);
  return snapshot;
}

// All bodies are pinned before native use, including later chunks. Duplicated
// occurrences share one holding but are decoded in each manifest position.
// The installed decoder must settle all use before returning its actual count;
// output remains provisional until this entire operation succeeds. The expected
// interpretation pins come from Host admission, not from the manifest itself.
export async function consumePhysicalManifestFiles(store: object, supplied: unknown, suppliedBodies: RetainedBody[],
  expected: unknown, limits: ManifestLimits, session: string, decode: DecodeChunk, control: PhysicalManifestControl,
  signal?: AbortSignal, beforeRead?: (bytes: number, index: number) => unknown) {
  signal?.throwIfAborted();
  if (!localRetainedStoreAvailable(store)) fail('ForeignPhysicalManifestHolding');
  if (typeof decode !== 'function' || (beforeRead !== undefined && typeof beforeRead !== 'function') ||
      typeof session !== 'string' || !session.length || session.length > 256) fail('InvalidPhysicalManifestReader');
  const admitted = snapshotPhysicalManifest(supplied, limits, control);
  const interpretation = record(expected, ['schema_contract_cid', 'view_contract_cid', 'codec_contract_cid']);
  for (const key of Object.keys(interpretation)) {
    if (interpretation[key as keyof typeof interpretation] !== admitted.manifest[key as keyof typeof interpretation]) fail('ForeignPhysicalManifestInterpretation');
  }
  if (!Array.isArray(suppliedBodies) || suppliedBodies.length !== admitted.manifest.chunks.length) fail('ForeignPhysicalManifestHolding');
  const bodies = suppliedBodies.slice(), borrows = new Map<RetainedBody, ReturnType<RetainedBody['delegateRead']>>();
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
      const borrow = borrows.get(bodies[index])!, chunk = admitted.manifest.chunks[index];
      let result;
      try {
        result = await withVerifiedDelegatedFile(borrow.descriptor, async file => {
          live();
          const rowCount = await decode(file, index, chunk);
          live();
          if (!quantity(rowCount) || rowCount !== chunk.row_count) fail('PhysicalManifestDecodedCountMismatch');
        }, signal, async bytes => { live(); await beforeRead?.(bytes, index); live(); });
      } catch (error) {
        if (['RetainedBodyChanged', 'RetainedBodyTruncated', 'ForeignStoreFile', 'ENOENT'].includes((error as {code: string} | null | undefined)?.code!)) bodies[index].close();
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
