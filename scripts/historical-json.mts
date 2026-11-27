import {createHash} from 'node:crypto';
import {readFileSync, statSync} from 'node:fs';
import {resolve} from 'node:path';

export const archiveDirectory = 'portability/corpus/historical/archive';
export const format = 'actql-historical-json/0.1';
export type JsonValue = null | boolean | number | string | JsonValue[] | {[key: string]: JsonValue};
type Scalar = null | boolean | number | string;
type ArchiveNode = ['r', string] | ['v', Scalar] | ['a', ArchiveNode[]] | ['o', [string, ArchiveNode][]];
type Receipt = {raw_sha256: string; raw_bytes: number; canonical_sha256: string;
  canonical_bytes: number; root: unknown};
export type Archive = {manifest: {format: string; snapshots: Record<string, Receipt>};
  objects: Record<string, unknown>};
export type SnapshotInputs = Readonly<Record<string, string>>;
type Bounds = Readonly<{depth: number; visits: number; bytes: number}>;

const hash = (text: string) => createHash('sha256').update(text).digest('hex');
const encoded = (value: unknown) => JSON.stringify(value);
export const canonical = (value: JsonValue): string => Array.isArray(value)
  ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key]!)}`).join(',')}}`
    : JSON.stringify(value);
function fail(message: string): never { throw new Error(`Historical JSON archive: ${message}`); }
const isHash = (value: unknown): value is string => typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);
export const limits = Object.freeze({depth: 256, visits: 2_000_000, bytes: 32 * 1024 * 1024});

// Every node is tagged, including literal arrays and objects. No JSON key is reserved.
export function packSnapshots(inputs: SnapshotInputs): Archive {
  const counts = new Map<string, number>();
  const scan = (value: JsonValue): void => {
    const text = encoded(value);
    if (Buffer.byteLength(text) >= 128) counts.set(text, (counts.get(text) ?? 0) + 1);
    if (Array.isArray(value)) value.forEach(scan);
    else if (value !== null && typeof value === 'object') Object.values(value).forEach(scan);
  };
  const parsed = Object.entries(inputs).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([path, raw]) => {
    const value: JsonValue = JSON.parse(raw);
    if (`${JSON.stringify(value, null, 2)}\n` !== raw) fail(`unsupported original formatting: ${path}`);
    scan(value);
    return [path, raw, value] as const;
  });
  const objects: Record<string, ArchiveNode> = Object.create(null);
  const cache = new Map<string, string>();
  const encode = (value: JsonValue): ArchiveNode => {
    const text = encoded(value);
    const shared = (counts.get(text) ?? 0) > 1;
    const cached = shared ? cache.get(text) : undefined;
    if (cached !== undefined) return ['r', cached];
    const node: ArchiveNode = Array.isArray(value) ? ['a', value.map(encode)]
      : value !== null && typeof value === 'object' ? ['o', Object.entries(value).map(([key, child]) => [key, encode(child)])]
        : ['v', value];
    if (!shared) return node;
    const digest = hash(encoded(node));
    objects[digest] = node;
    cache.set(text, digest);
    return ['r', digest];
  };
  const snapshots = Object.fromEntries(parsed.map(([path, raw, value]) => {
    const text = canonical(value);
    return [path, {raw_sha256: hash(raw), raw_bytes: Buffer.byteLength(raw), canonical_sha256: hash(text), canonical_bytes: Buffer.byteLength(text), root: encode(value)}];
  }));
  return {manifest: {format, snapshots}, objects: Object.fromEntries(Object.entries(objects).sort(([a], [b]) => a < b ? -1 : 1))};
}

export function decodeSnapshot(archive: Archive, path: string, bounds: Bounds = limits): JsonValue {
  const {manifest, objects} = archive;
  for (const key of ['depth', 'visits', 'bytes'] as const) if (!Number.isSafeInteger(bounds[key]) || bounds[key] < 1 || bounds[key] > limits[key]) fail('invalid bounds');
  if (manifest?.format !== format || !manifest.snapshots || !objects || Array.isArray(objects)) fail('invalid archive format');
  if (!Object.hasOwn(manifest.snapshots, path)) fail(`unknown snapshot: ${path}`);
  const receipt = manifest.snapshots[path];
  if (!receipt || !isHash(receipt.raw_sha256) || !isHash(receipt.canonical_sha256)
      || !Number.isSafeInteger(receipt.raw_bytes) || receipt.raw_bytes < 0 || receipt.raw_bytes > bounds.bytes
      || !Number.isSafeInteger(receipt.canonical_bytes) || receipt.canonical_bytes < 0 || receipt.canonical_bytes > bounds.bytes) fail('invalid receipt');
  let visits = 0, bytes = 1;
  const active = new Set<string>(), verified = new Set<string>();
  const charge = (count: number) => { bytes += count; if (bytes > bounds.bytes) fail('expanded byte limit'); };
  const decode = (node: unknown, depth: number, logicalDepth = 0): JsonValue => {
    if (++visits > bounds.visits || depth > bounds.depth) fail('expansion limit');
    if (!Array.isArray(node) || node.length !== 2) fail('invalid node');
    const [tag, value]: unknown[] = node;
    if (tag === 'r') {
      if (!isHash(value) || !Object.hasOwn(objects, value)) fail('missing or invalid object reference');
      if (active.has(value)) fail('reference cycle');
      if (!verified.has(value)) {
        if (hash(boundedEncoding(objects[value])) !== value) fail('object digest mismatch');
        verified.add(value);
      }
      active.add(value);
      const result = decode(objects[value], depth + 1, logicalDepth);
      active.delete(value);
      return result;
    }
    if (tag === 'v') {
      if (!(value === null || typeof value === 'string' || typeof value === 'boolean' || (typeof value === 'number' && Number.isFinite(value)))) fail('invalid scalar');
      charge(Buffer.byteLength(encoded(value)));
      return value;
    }
    if (tag === 'a') {
      if (!Array.isArray(value)) fail('invalid array');
      charge(2 + (value.length ? value.length * (1 + 2 * (logicalDepth + 1)) + value.length - 1 + 1 + 2 * logicalDepth : 0));
      return value.map((child: unknown) => decode(child, depth + 1, logicalDepth + 1));
    }
    if (tag === 'o') {
      if (!Array.isArray(value)) fail('invalid object');
      const result: {[key: string]: JsonValue} = {};
      charge(2 + (value.length ? value.length * (1 + 2 * (logicalDepth + 1)) + value.length - 1 + 1 + 2 * logicalDepth : 0));
      for (const entry of value) {
        if (!Array.isArray(entry) || entry.length !== 2 || typeof entry[0] !== 'string' || Object.hasOwn(result, entry[0])) fail('invalid or duplicate object key');
        const key: string = entry[0], child: unknown = entry[1];
        charge(Buffer.byteLength(encoded(key)) + 2);
        Object.defineProperty(result, key, {value: decode(child, depth + 1, logicalDepth + 1), enumerable: true, configurable: true, writable: true});
      }
      return result;
    }
    fail('unknown node tag');
  };
  const value = decode(receipt.root, 0), text = canonical(value), raw = `${JSON.stringify(value, null, 2)}\n`;
  if (Buffer.byteLength(raw) !== receipt.raw_bytes || hash(raw) !== receipt.raw_sha256) fail('original byte digest mismatch');
  if (Buffer.byteLength(text) !== receipt.canonical_bytes || hash(text) !== receipt.canonical_sha256) fail('canonical digest mismatch');
  return value;
}

export function boundedEncoding(value: unknown) {
  const pending: [unknown, number][] = [[value, 0]];
  let count = 0;
  while (pending.length) {
    const [item, depth] = pending.pop()!;
    if (++count > limits.visits || depth > limits.depth * 4) fail('stored node limit');
    if (item && typeof item === 'object') for (const child of Object.values(item)) pending.push([child, depth + 1]);
  }
  const text = encoded(value);
  if (Buffer.byteLength(text) > limits.bytes) fail('stored byte limit');
  return text;
}

export function readArchive(root = '.'): Archive {
  const directory = resolve(root, archiveDirectory);
  const read = (name: string): unknown => {
    const path = resolve(directory, name);
    if (statSync(path).size > limits.bytes) fail('archive file limit');
    return JSON.parse(readFileSync(path, 'utf8'));
  };
  const manifest = read('manifest.json') as Archive['manifest'];
  const objects = read('objects.json') as Archive['objects'];
  const receipts = read('receipts.json') as Record<string, JsonValue>;
  if (manifest?.format !== format || !manifest.snapshots || !receipts || Array.isArray(receipts)) fail('invalid archive format');
  if (encoded(Object.keys(manifest.snapshots).sort()) !== encoded(Object.keys(receipts).sort())) fail('snapshot inventory mismatch');
  for (const [path, receipt] of Object.entries(receipts)) {
    const {root: _root, ...actual} = manifest.snapshots[path]!;
    if (canonical(receipt) !== canonical(actual)) fail('snapshot receipt mismatch');
  }
  return {manifest, objects};
}

let cached: {root: string; archive: Archive} | undefined;
export function readHistoricalJson(path: string, root = '.'): unknown {
  const absolute = resolve(root);
  if (cached?.root !== absolute) cached = {root: absolute, archive: readArchive(absolute)};
  const {archive} = cached;
  // Registered snapshots never fall back to mutable/raw files on corruption.
  if (Object.hasOwn(archive.manifest.snapshots, path)) return decodeSnapshot(archive, path);
  return JSON.parse(readFileSync(resolve(absolute, path), 'utf8'));
}
