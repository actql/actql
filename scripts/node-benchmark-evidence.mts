// Read-only ordinary installation evidence shared by the benchmark and packed consumers.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import type {BinaryLike} from 'node:crypto';
import {lstat, readFile, readdir} from 'node:fs/promises';
import {dirname, join, relative} from 'node:path';

type FileFact = {path: string; bytes: number; mode: number; sha256: string};
type PackageFact = {name: string; file: string; bytes: number; sha256: string; integrity: string;
  files: readonly FileFact[]};
export type BenchmarkPackageManifest = {packages: readonly PackageFact[]};
type ErrorReference = Partial<Record<'namespaceId' | 'authorityScopeCid' | 'runDefinitionCid', string>>;
type ErrorObservation = Partial<Record<'run_id' | 'status' | 'revision' | 'result_available', string | boolean | number>>;
type ErrorEntry = {
  edge: string;
  name: string;
  code: string | null;
  message: string;
  status?: number;
  requestId?: string;
  cleanupPending?: boolean;
  executionRef?: ErrorReference;
  observation?: ErrorObservation;
};

export const hash = (bytes: BinaryLike) => createHash('sha256').update(bytes).digest('hex');

// Keep failure inspection outside successful sample timing. Read only bounded
// public data: never call execution/status/result/cleanup methods to diagnose it.
export function nodeBenchmarkFailure(error: unknown) {
  const data = (value: unknown, key: PropertyKey): unknown => {
    try {
      for (let depth = 0; value !== null && typeof value === 'object' && depth < 4;
        depth++, value = Object.getPrototypeOf(value)) {
        const property = Object.getOwnPropertyDescriptor(value, key);
        if (property) return Object.hasOwn(property, 'value') ? property.value : undefined;
      }
    } catch { /* An unreadable diagnostic must not replace the original failure. */ }
  };
  const text = (value: unknown) => typeof value === 'string' ? value.slice(0, 2048) : undefined;
  const reference = (value: unknown) => {
    const result: ErrorReference = {};
    for (const key of ['namespaceId', 'authorityScopeCid', 'runDefinitionCid'] as const) {
      const field = text(data(value, key)); if (field !== undefined) result[key] = field;
    }
    return Object.keys(result).length ? result : undefined;
  };
  const queue = [{edge: 'primary', value: error}], seen = new Set<object>(), chain: ErrorEntry[] = [];
  while (queue.length && chain.length < 8) {
    const {edge, value} = queue.shift()!;
    if (value === null || typeof value !== 'object' || seen.has(value)) continue;
    seen.add(value);
    const entry: ErrorEntry = {edge, name: text(data(value, 'name')) ?? 'Error',
      code: text(data(value, 'code')) ?? null, message: text(data(value, 'message')) ?? ''};
    const status = data(value, 'status'), requestId = text(data(value, 'requestId'));
    if (Number.isSafeInteger(status)) entry.status = status as number;
    if (requestId !== undefined) entry.requestId = requestId;
    const cleanupPending = data(value, 'cleanupPending');
    if (typeof cleanupPending === 'boolean') entry.cleanupPending = cleanupPending;
    const executionRef = reference(data(value, 'executionRef')) ?? reference(data(data(value, 'execution'), 'ref'));
    if (executionRef) entry.executionRef = executionRef;
    const observation = data(value, 'observation'), state: ErrorObservation = {};
    for (const key of ['run_id', 'status', 'revision', 'result_available'] as const) {
      const field = data(observation, key);
      if (typeof field === 'string') state[key] = text(field);
      else if (typeof field === 'boolean' || Number.isSafeInteger(field)) state[key] = field as boolean | number;
    }
    if (Object.keys(state).length) entry.observation = state;
    chain.push(entry);
    for (const key of ['cause', 'original_error', 'cleanup_error', 'originalError', 'cleanupError']) {
      const child = data(value, key);
      if (child !== null && typeof child === 'object') queue.push({edge: key, value: child});
    }
  }
  const primary = chain[0] ?? {name: 'Error', code: null,
    message: typeof error === 'string' ? text(error) : 'Uninspectable thrown value'};
  return {...primary, errorChain: chain, ...(queue.length ? {errorChainTruncated: true} : {})};
}
export async function verifyNodeBenchmarkPackages(manifest: BenchmarkPackageManifest, manifestPath: string, consumer: string) {
  assert(Array.isArray(manifest.packages) && manifest.packages.length > 0);
  assert(manifest.packages.some(row => row.name === '@actql/node'));
  const observations = [], names = new Set();
  for (const pkg of manifest.packages) {
    assert(/^(?:@actql\/)?[a-z0-9-]+$/u.test(pkg.name) && !names.has(pkg.name));
    names.add(pkg.name);
    assert.equal(pkg.file, pkg.file.split('/').at(-1));
    const tar = await readFile(join(dirname(manifestPath), pkg.file));
    assert.equal(tar.length, pkg.bytes); assert.equal(hash(tar), pkg.sha256);
    assert.equal('sha512-' + createHash('sha512').update(tar).digest('base64'), pkg.integrity);
    const base = join(consumer, 'node_modules', pkg.name), files: FileFact[] = [];
    async function visit(dir: string) {
      assert(!(await lstat(dir)).isSymbolicLink(), 'Installed package cannot be a source symlink');
      for (const name of (await readdir(dir)).sort()) {
        const file = join(dir, name), st = await lstat(file);
        assert(!st.isSymbolicLink(), 'Installed product payload cannot be linked');
        if (st.isDirectory()) await visit(file);
        else {
          assert(st.isFile()); const data = await readFile(file);
          files.push({path: relative(base, file), bytes: data.length, mode: st.mode & 0o777, sha256: hash(data)});
        }
      }
    }
    await visit(base);
    const sort = (rows: readonly FileFact[]) => rows.toSorted((a, b) => a.path.localeCompare(b.path));
    assert.deepEqual(sort(files), sort(pkg.files));
    observations.push({package: pkg.name, files});
  }
  return observations;
}
