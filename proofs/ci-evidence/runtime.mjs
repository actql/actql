// Observe actual installation bytes; this is not an OS/runtime closure witness.
// Keep unmodelled environment, loaders and execution-time mutation explicit.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {constants, openSync, closeSync, readSync, fstatSync, lstatSync,
  opendirSync, readlinkSync, readFileSync} from 'node:fs';
import {join} from 'node:path';
import {release} from 'node:os';
import {performance} from 'node:perf_hooks';
import {hash} from './inputs.mjs';
import {encode, environmentNames} from '../bounded-session/action-inputs.mjs';

const stable = (a, b) => ['dev', 'ino', 'mode', 'size', 'mtimeNs', 'ctimeNs'].every(key => a[key] === b[key]);
const residual = 'comparison only: distribution/core, loader, runtime configuration and external dependencies require reviewed closure';
export const runtimeResiduals = Object.freeze([residual,
  'OS/loader/system libraries/CPU and inherited runtime configuration are not a reviewed deterministic execution boundary',
  'distribution observations are not an atomic snapshot held through action execution',
]);

// No symlink traversal, installer/cache scan, extraction, subprocess or build.
// Bound both membership and bytes; a limit is incomplete coverage, never empty.
export function inventoryDistribution(root, {maxEntries = 50000, maxBytes = 2 * 1024 ** 3} = {}) {
  assert(Number.isSafeInteger(maxEntries) && maxEntries > 0);
  assert(Number.isSafeInteger(maxBytes) && maxBytes >= 0);
  const entries = [], unresolved = new Set();
  let bytes = 0, limit = false;
  function visit(relative) {
    if (limit) return;
    if (entries.length >= maxEntries) { unresolved.add('entry limit'); limit = true; return; }
    const path = relative ? join(root, relative) : root;
    try {
      const before = lstatSync(path, {bigint: true}), mode = Number(before.mode & 0o7777n);
      if (before.isSymbolicLink()) {
        const target = readlinkSync(path);
        entries.push({path: relative, kind: 'symlink', mode, targetDigest: hash(target)});
        unresolved.add(`untraversed symlink: ${relative || '.'}`);
      } else if (before.isDirectory()) {
        const members = [], directory = opendirSync(path);
        try {
          let member;
          while ((member = directory.readSync()) !== null) {
            if (members.length >= maxEntries) { unresolved.add('entry limit'); limit = true; break; }
            members.push(member.name);
          }
        } finally { directory.closeSync(); }
        members.sort();
        entries.push({path: relative, kind: 'directory', mode, members});
        for (const member of members) visit(relative ? `${relative}/${member}` : member);
      } else if (before.isFile()) {
        assert(before.size <= BigInt(maxBytes - bytes), 'byte limit');
        let fd;
        try {
          fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
          const opened = fstatSync(fd, {bigint: true});
          assert(opened.isFile() && stable(before, opened), 'file changed before read');
          const digest = createHash('sha256'), chunk = Buffer.alloc(1024 * 1024);
          const size = Number(before.size);
          let count = 0, n;
          while ((n = readSync(fd, chunk, 0, Math.min(chunk.length, size - count + 1))) > 0) {
            count += n; assert(count <= size, 'file grew'); digest.update(chunk.subarray(0, n));
          }
          assert(count === size && stable(before, fstatSync(fd, {bigint: true})), 'file changed during read');
          entries.push({path: relative, kind: 'file', mode, bytes: count, digest: digest.digest('hex')});
          bytes += count;
        } finally { if (fd !== undefined) closeSync(fd); }
      } else {
        entries.push({path: relative, kind: 'special', mode});
        unresolved.add(`nonregular input: ${relative || '.'}`);
      }
      assert(stable(before, lstatSync(path, {bigint: true})), 'input changed during observation');
    } catch (error) {
      const reason = error.code === 'ENOENT' ? 'missing input' : error.code === 'EACCES' ? 'unreadable input'
        : error.message === 'byte limit' ? 'byte limit' : 'unstable or unsupported input';
      unresolved.add(`${reason}: ${relative || '.'}`);
      if (reason === 'byte limit') limit = true;
    }
  }
  visit('');
  return {entries, observedBytes: bytes, unresolved: [...unresolved].sort()};
}

// Absolute installation locations belong to execution context, not semantic
// input equality. Relative component membership/mode/bytes remain bound.
export function observeRuntime({root, env = process.env, executable = process.execPath}) {
  const start = performance.now(), pin = JSON.parse(readFileSync(join(root, 'toolchain.json'), 'utf8'));
  const leanPin = readFileSync(join(root, 'proofs/bounded-session/lean-toolchain'), 'utf8').trim();
  assert(/^leanprover\/lean4:v[0-9.]+-rc[0-9]+$/u.test(leanPin), 'Unreviewed Lean distribution name');
  assert(typeof pin.version === 'string' && /^[A-Za-z0-9.+-]+$/u.test(pin.version), 'Unreviewed MoonBit distribution name');
  const home = env.MOON_HOME ?? join(root, '.toolchains', `moonbit-${pin.version}`);
  const leanHome = join(root, '.toolchains', `lean-${leanPin.split(':v')[1]}-linux`);
  const distributions = {
    nodeExecutable: inventoryDistribution(executable),
    moonbit: inventoryDistribution(home),
    lean: inventoryDistribution(leanHome),
  };
  const executables = {};
  for (const [id, path] of [['node', executable], ['moon', join(home, 'bin/moon')],
    ['moonc', join(home, 'bin/moonc')], ['moonrun', join(home, 'bin/moonrun')], ['lean', join(leanHome, 'bin/lean')]]) {
    const observed = inventoryDistribution(path);
    if (!observed.unresolved.length && observed.entries[0]?.kind === 'file') executables[id] = observed.entries[0].digest;
  }
  // No arbitrary inherited names, secret values or secret-derived hashes.
  assert(environmentNames.every(name => !Object.hasOwn(env, name) || typeof env[name] === 'string'), 'Invalid execution configuration');
  const configuration = environmentNames.map(name => ({name, present: Object.hasOwn(env, name),
    digest: Object.hasOwn(env, name) ? hash(env[name]) : null}));
  const unresolved = [...runtimeResiduals, ...Object.entries(distributions).flatMap(([id, observed]) =>
    observed.unresolved.map(reason => `${id}: ${reason}`))];
  if (process.platform !== 'linux' || process.arch !== 'x64') unresolved.push('unreviewed execution platform');
  const summaries = Object.fromEntries(Object.entries(distributions).map(([id, observation]) => [id, distributionSummary(observation)]));
  const runtime = {profile: 'comparison-linux-runtime', platform: process.platform, architecture: process.arch,
    osRelease: release(), nodeVersion: process.version, image: env.ImageVersion ?? 'unrecorded',
    executables, distributions: summaries, configuration, unresolved: [...new Set(unresolved)].sort()};
  return {runtime, distributionInputs: distributions, measurement: {milliseconds: Math.round(performance.now() - start),
    entries: Object.values(distributions).reduce((n, value) => n + value.entries.length, 0),
    bytes: Object.values(distributions).reduce((n, value) => n + value.observedBytes, 0),
    inputDigest: hash(encode(runtime))}};
}

export function distributionSummary(observation) {
  assert(Array.isArray(observation.entries) && Array.isArray(observation.unresolved));
  assert(Number.isSafeInteger(observation.observedBytes) && observation.observedBytes >= 0);
  return {digest: hash(encode(observation)), entries: observation.entries.length,
    bytes: observation.observedBytes, unresolved: observation.unresolved};
}

// The archive keeps one immutable inventory; receipts bind its exact bytes.
// Reconstruct summaries from that inventory instead of trusting copied labels.
export function checkRuntimeObservation(runtime, distributionInputs) {
  assert.equal(runtime.profile, 'comparison-linux-runtime');
  assert(Array.isArray(runtime.unresolved) && runtimeResiduals.every(reason => runtime.unresolved.includes(reason)),
    'Runtime observation cannot erase the unclosed execution boundary');
  assert.deepEqual(Object.keys(distributionInputs).sort(), ['lean', 'moonbit', 'nodeExecutable']);
  assert.equal(encode(runtime.distributions), encode(Object.fromEntries(Object.entries(distributionInputs)
    .map(([id, observation]) => [id, distributionSummary(observation)]))), 'Wrong distribution inventory bytes or coverage');
  for (const [id, observation] of Object.entries(distributionInputs)) {
    assert(observation.unresolved.every(reason => runtime.unresolved.includes(`${id}: ${reason}`)), 'Omitted distribution coverage gap');
  }
  return true;
}
