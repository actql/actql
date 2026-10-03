// Stage B observation only. Nothing in this module authorizes evidence reuse.
import { createHash } from 'node:crypto';
import { constants, accessSync, closeSync, fstatSync, lstatSync, openSync, readSync,
  readdirSync, readlinkSync, realpathSync } from 'node:fs';
import { basename, delimiter, dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { release } from 'node:os';

export const schema = 'actql-bounded-session-action-inputs/0.1';
export const domain = 'actql-bounded-session-action-key/0.1\0';
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const digestPattern = /^[a-f0-9]{64}$/;
const compareText = (a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b));
// Fixed execution configuration names only. Never publish arbitrary inherited
// variable names/values or secret-derived hashes into CI evidence artifacts.
export const environmentNames = Object.freeze([
  'PATH', 'HOME', 'USERPROFILE', 'TMPDIR', 'TMP', 'TEMP', 'LANG', 'LANGUAGE',
  'LC_ALL', 'LC_CTYPE', 'LC_COLLATE', 'LC_MESSAGES', 'LC_MONETARY', 'LC_NUMERIC', 'LC_TIME', 'TZ',
  'LEAN_PATH', 'LEAN_SRC_PATH', 'LEAN_SYSROOT', 'LEAN_ABORT_ON_PANIC', 'LEAN_NUM_THREADS',
  'ELAN_HOME', 'ELAN_TOOLCHAIN', 'NODE_OPTIONS', 'NODE_PATH', 'LD_LIBRARY_PATH', 'LD_PRELOAD',
  'DYLD_LIBRARY_PATH', 'DYLD_FALLBACK_LIBRARY_PATH', 'DYLD_INSERT_LIBRARIES',
]);
const knownSources = {
  'check.mjs': '32b0fe354922e5b89870e19aef05a00fbc5679bdc960717bb6ffce392b33392a',
  'Session.lean': 'd5a9f5e62e5a360b52d5cf0d886f6832c38a00088737c3378b01dff6b6b1a434',
  'Claims.lean': '70084213e510d49a17797e52509c8e2b3b0d5231519322665f686ba1f151fdd1',
};
const residual = [
  'runtime-boundary: OS, loader, system shared libraries, CPU features and Node built-ins are not closed',
  'environment-boundary: only allowlisted execution configuration is bound; all other inherited names/values (including secrets), external services, locale databases and runtime configuration reads remain unmodelled',
  'filesystem-boundary: observations are not an atomic execution-time filesystem snapshot',
];
function requireThat(condition, message) { if (!condition) throw new Error(message); }
function string(value) {
  requireThat(typeof value === 'string' && value.isWellFormed(), 'Expected well-formed Unicode string');
  return value;
}
// Compact JSON, UTF-8, no newline/BOM, object keys in UTF-8 byte order. Arrays
// are ordered. No Unicode/path normalization; only safe integers are numbers.
export function encode(value) {
  if (value === null || typeof value === 'boolean') return JSON.stringify(value);
  if (typeof value === 'string') return JSON.stringify(string(value));
  if (typeof value === 'number') {
    requireThat(Number.isSafeInteger(value) && !Object.is(value, -0), 'Expected safe integer');
    return String(value);
  }
  requireThat(value && typeof value === 'object', 'Unsupported encoding value');
  if (Array.isArray(value)) {
    requireThat(Object.keys(value).length === value.length, 'Sparse or augmented array');
    return `[${value.map(encode).join(',')}]`;
  }
  requireThat(Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null, 'Expected plain object');
  return `{${Object.keys(value).sort(compareText).map(key => `${JSON.stringify(string(key))}:${encode(value[key])}`).join(',')}}`;
}
function exact(value, names) {
  requireThat(value && typeof value === 'object' && !Array.isArray(value), 'Expected object');
  requireThat(encode(Object.keys(value).sort()) === encode([...names].sort()), 'Unknown/missing schema fields');
}
function uniqueSorted(entries, key) {
  requireThat(Array.isArray(entries), 'Expected inventory array');
  const result = [...entries].sort((a, b) => compareText(string(a[key]), string(b[key])));
  requireThat(new Set(result.map(entry => entry[key])).size === result.length, 'Duplicate inventory entry');
  return result;
}
function normalized(inputs) {
  return { ...inputs, files: uniqueSorted(inputs.files, 'path'),
    environment: uniqueSorted(inputs.environment, 'name') };
}
export function keyForInputs(inputs) { return sha(domain + encode(normalized(inputs))); }

const sameStat = (a, b) => ['dev', 'ino', 'size', 'mode', 'mtimeNs', 'ctimeNs'].every(key => a[key] === b[key]);
function readRegular(path, expected, capture = false) {
  let fd;
  try {
    fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
    const before = fstatSync(fd, { bigint: true });
    requireThat(before.isFile() && sameStat(expected, before), 'Changed/nonregular file');
    requireThat(Number.isSafeInteger(Number(before.size)) && before.size >= 0n, 'Invalid input size');
    const expectedSize = Number(before.size);
    const hash = createHash('sha256'), buffer = Buffer.alloc(1024 * 1024), chunks = [];
    let count, size = 0;
    // Read at most the observed size plus one byte, even if a writer grows the
    // file continuously. The extra byte detects growth without an EOF loop.
    while ((count = readSync(fd, buffer, 0, Math.min(buffer.length, expectedSize - size + 1))) !== 0) {
      size += count; requireThat(size <= expectedSize, 'Input grew during read');
      hash.update(buffer.subarray(0, count));
      if (capture) chunks.push(Buffer.from(buffer.subarray(0, count)));
    }
    requireThat(sameStat(before, fstatSync(fd, { bigint: true })) && sameStat(before, lstatSync(path, { bigint: true })), 'Changed file during read');
    requireThat(size === Number(before.size), 'Changed file size');
    return { bytes: size, digest: hash.digest('hex'), content: capture ? Buffer.concat(chunks) : null };
  } finally { if (fd !== undefined) closeSync(fd); }
}
export function readManifestFile(path) {
  const stat = lstatSync(path, { bigint: true });
  requireThat(stat.isFile() && stat.size <= 32n * 1024n * 1024n, 'Manifest must be a regular file of at most 32 MiB');
  return parseManifest(readRegular(path, stat, true).content);
}

// Rebuilt from the current filesystem every call. Links are recorded, never
// traversed as distribution directories. Their substitution cannot look equal.
export function inventoryAction({ root, env = process.env, executable = process.execPath,
  args = ['proofs/bounded-session/check.mjs'], cwd = root, sourceRevision = null } = {}) {
  root = resolve(root); cwd = resolve(cwd);
  const modelDirectory = join(root, 'proofs/bounded-session');
  const files = new Map(), contents = new Map(), unknown = new Set(residual);
  let totalBytes = 0;
  function inspect(path, capture = false) {
    path = resolve(path);
    if (files.has(path)) return files.get(path);
    let entry;
    try {
      const stat = lstatSync(path, { bigint: true });
      const mode = Number(stat.mode & 0o7777n);
      if (stat.isSymbolicLink()) {
        entry = { path, kind: 'symlink', mode, bytes: null, digest: null, target: readlinkSync(path), error: null };
        unknown.add(`symlink: ${path}`);
      } else if (stat.isDirectory()) {
        entry = { path, kind: 'directory', mode, bytes: null, digest: null, target: null, error: null };
      } else if (stat.isFile()) {
        requireThat(totalBytes + Number(stat.size) <= 8 * 1024 ** 3, 'Inventory byte limit');
        requireThat(!capture || stat.size <= 16n * 1024n * 1024n, 'Source input byte limit');
        const { content, ...identity } = readRegular(path, stat, capture);
        entry = { path, kind: 'file', mode, ...identity, target: null, error: null };
        if (capture) contents.set(path, content);
        totalBytes += entry.bytes;
      } else {
        entry = { path, kind: 'special', mode, bytes: null, digest: null, target: null, error: null };
        unknown.add(`nonregular input: ${path}`);
      }
      requireThat(sameStat(stat, lstatSync(path, { bigint: true })), 'Changed input during observation');
    } catch (error) {
      contents.delete(path);
      entry = { path, kind: 'unknown', mode: null, bytes: null, digest: null, target: null,
        error: error.code ?? error.message };
      unknown.add(`unreadable/unstable input: ${path}`);
    }
    files.set(path, entry);
    return entry;
  }
  function ancestors(path) {
    for (let current = dirname(path);; current = dirname(current)) {
      const entry = inspect(current);
      if (entry.kind !== 'directory') unknown.add(`unresolved parent path: ${current}`);
      if (dirname(current) === current) break;
    }
  }
  function real(path) {
    if (path === null) return null;
    ancestors(path); inspect(path);
    try {
      const result = realpathSync(path); ancestors(result); inspect(result); return result;
    } catch { unknown.add(`unresolved real path: ${path}`); return null; }
  }
  const sourceText = {};
  for (const name of ['check.mjs', 'Session.lean', 'Claims.lean', 'lean-toolchain']) {
    const path = join(modelDirectory, name); ancestors(path);
    const entry = inspect(path, true);
    if (entry.kind !== 'file') { unknown.add(`missing regular source: ${name}`); continue; }
    try {
      const bytes = contents.get(path);
      requireThat(sha(bytes) === entry.digest && Buffer.from(bytes.toString('utf8')).equals(bytes), 'Changed or non-UTF-8 source');
      sourceText[name] = bytes.toString('utf8');
    } catch { unknown.add(`unresolved source text: ${name}`); }
    if (name in knownSources && entry.digest !== knownSources[name]) unknown.add(`unrecognized source structure: ${name}; new imports/dynamic reads require review`);
  }
  const pin = sourceText['lean-toolchain']?.trim() ?? null;
  if (pin !== 'leanprover/lean4:v4.30.0-rc1') unknown.add('unrecognized toolchain pin');
  const model = sourceText['Session.lean'], claims = sourceText['Claims.lean'];
  const names = model === undefined ? [] : [...model.matchAll(/^theorem\s+(\w+)/gm)].map(([, name]) => name);
  if (names.length !== 14) unknown.add('unrecognized theorem inventory');
  const audit = names.map(name => `#print axioms BoundedSession.${name}`).join('\n');
  const stdin = model === undefined || claims === undefined ? null : `${model}\n${claims}\n${audit}\n`;
  const imports = [model, claims].filter(text => text !== undefined).flatMap(text => [...text.matchAll(/^import\s+([^\n]+)/gm)].map(([, modules]) => modules));
  // This is a fingerprinted grammar boundary, not a permissive Lean/JS parser.
  // Even a comment edit requires review; no new dynamic read is silently added.
  if (encode(imports) !== encode(['Lean'])) unknown.add('unrecognized import inventory');
  let lean = null;
  if (process.platform !== 'linux') unknown.add('unsupported executable-resolution platform');
  if (typeof env.PATH !== 'string') unknown.add('PATH is absent; implicit OS search is unresolved');
  else for (const directory of env.PATH.split(delimiter)) {
    const candidate = resolve(modelDirectory, directory, 'lean');
    try { accessSync(candidate, constants.X_OK); if (!lstatSync(candidate).isDirectory()) { lean = candidate; break; } } catch { /* next PATH entry */ }
  }
  if (lean === null) unknown.add('Lean executable not resolved');
  const leanReal = real(lean), nodeReal = real(resolve(cwd, executable));
  let distribution = null;
  if (leanReal !== null && basename(dirname(leanReal)) === 'bin'
      && basename(dirname(dirname(leanReal))) === 'lean-4.30.0-rc1-linux'
      && pin === 'leanprover/lean4:v4.30.0-rc1') distribution = dirname(dirname(leanReal));
  else unknown.add('Lean distribution root unresolved');
  function walk(directory) {
    if (files.size > 50000) { unknown.add('distribution inventory entry limit'); return; }
    const entry = inspect(directory);
    if (entry.kind !== 'directory') return;
    try {
      const before = lstatSync(directory, { bigint: true });
      const children = readdirSync(directory, { encoding: 'buffer' }).sort(Buffer.compare);
      for (const bytes of children) {
        const name = bytes.toString('utf8');
        requireThat(Buffer.from(name).equals(bytes), 'Non-UTF-8 filename');
        const path = join(directory, name);
        if (inspect(path).kind === 'directory') walk(path);
        if (files.size > 50000) { unknown.add('distribution inventory entry limit'); break; }
      }
      requireThat(sameStat(before, lstatSync(directory, { bigint: true })), 'Changed directory inventory');
    } catch { unknown.add(`unresolved directory enumeration: ${directory}`); }
  }
  if (distribution !== null) {
    walk(distribution);
    for (const relative of ['lib/lean/Init.olean', 'lib/lean/Lean.olean']) {
      if (inspect(join(distribution, relative)).kind !== 'file') unknown.add(`missing Lean distribution input: ${relative}`);
    }
  }
  // No release-label/mtime shortcut: distribution and both executable bytes are
  // observed. Arbitrary wrappers/ELAN, external imports and native shared-library
  // resolution remain unresolved even when those bytes match.
  unknown.add('distribution-boundary: enumerated prefix is a conservative candidate; wrapper behavior and external native/import dependencies are not closed');
  if (args.length !== 1 || resolve(cwd, args[0]) !== join(modelDirectory, 'check.mjs')) unknown.add('unrecognized checker launch arguments');
  const inputs = normalized({
    files: [...files.values()],
    environment: environmentNames.filter(name => Object.hasOwn(env, name))
      .map(name => ({ name, digest: sha(Buffer.from(string(env[name]))) })),
    platform: { os: process.platform, arch: process.arch, release: release() },
    paths: { root, cwd, modelDirectory, lean, leanReal, node: resolve(cwd, executable), nodeReal, distribution },
    commands: [
      { executable: resolve(cwd, executable), args: [...args], cwd, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, stdin: null },
      { executable: 'lean', args: ['--short-version'], cwd: modelDirectory, encoding: 'utf8', maxBuffer: 1024 * 1024, stdin: null },
      { executable: 'lean', args: ['-DwarningAsError=true', '--stdin'], cwd: modelDirectory, encoding: 'utf8', maxBuffer: 4 * 1024 * 1024, stdin },
    ],
    generated: { pin, imports, theorems: names, typedClaims: claims ?? null, axiomCommands: audit },
  });
  const manifest = { schema, mode: 'report-only', provenance: { sourceRevision }, inputs,
    actionKey: keyForInputs(inputs), coverage: { status: 'unknown', eligibleForReuse: false, unresolved: [...unknown].sort(compareText) } };
  validateManifest(manifest);
  return manifest;
}

export function validateManifest(manifest) {
  exact(manifest, ['schema', 'mode', 'provenance', 'inputs', 'actionKey', 'coverage']);
  requireThat(manifest.schema === schema && manifest.mode === 'report-only', 'Unknown manifest schema/mode');
  exact(manifest.provenance, ['sourceRevision']);
  requireThat(manifest.provenance.sourceRevision === null || /^[a-f0-9]{40}$/.test(manifest.provenance.sourceRevision), 'Invalid provenance revision');
  exact(manifest.coverage, ['status', 'eligibleForReuse', 'unresolved']);
  requireThat(manifest.coverage.status === 'unknown' && manifest.coverage.eligibleForReuse === false, 'Reuse permission is unsupported');
  requireThat(Array.isArray(manifest.coverage.unresolved) && residual.every(reason => manifest.coverage.unresolved.includes(reason)), 'Missing unresolved boundary');
  manifest.coverage.unresolved.forEach(string);
  const inputs = manifest.inputs;
  exact(inputs, ['files', 'environment', 'platform', 'paths', 'commands', 'generated']);
  for (const entry of uniqueSorted(inputs.files, 'path')) {
    exact(entry, ['path', 'kind', 'mode', 'bytes', 'digest', 'target', 'error']);
    requireThat(isAbsolute(entry.path) && resolve(entry.path) === entry.path, 'Noncanonical absolute input path');
    requireThat(['file', 'directory', 'symlink', 'special', 'unknown'].includes(entry.kind), 'Unknown input file kind');
    requireThat(entry.kind === 'unknown' ? entry.mode === null : Number.isInteger(entry.mode) && entry.mode >= 0 && entry.mode <= 0o7777, 'Invalid file mode');
    requireThat(entry.kind === 'file' ? Number.isSafeInteger(entry.bytes) && entry.bytes >= 0 && digestPattern.test(entry.digest) : entry.bytes === null && entry.digest === null, 'Invalid byte identity');
    requireThat(entry.kind === 'symlink' ? typeof entry.target === 'string' : entry.target === null, 'Invalid link target');
    requireThat(entry.kind === 'unknown' ? typeof entry.error === 'string' : entry.error === null, 'Invalid input error');
  }
  for (const entry of uniqueSorted(inputs.environment, 'name')) {
    exact(entry, ['name', 'digest']);
    requireThat(environmentNames.includes(entry.name) && digestPattern.test(entry.digest), 'Invalid/unmodelled environment entry');
  }
  exact(inputs.platform, ['os', 'arch', 'release']); Object.values(inputs.platform).forEach(string);
  exact(inputs.paths, ['root', 'cwd', 'modelDirectory', 'lean', 'leanReal', 'node', 'nodeReal', 'distribution']);
  for (const [key, value] of Object.entries(inputs.paths)) {
    requireThat(value === null && ['lean', 'leanReal', 'nodeReal', 'distribution'].includes(key) || typeof value === 'string' && isAbsolute(value) && resolve(value) === value, 'Invalid execution path');
  }
  requireThat(inputs.paths.modelDirectory === join(inputs.paths.root, 'proofs/bounded-session'), 'Inconsistent model directory');
  for (const path of ['check.mjs', 'Session.lean', 'Claims.lean', 'lean-toolchain'].map(name => join(inputs.paths.modelDirectory, name))) {
    requireThat(inputs.files.some(entry => entry.path === path), 'Missing source inventory entry');
  }
  requireThat(Array.isArray(inputs.commands) && inputs.commands.length === 3, 'Invalid command inventory');
  for (const command of inputs.commands) {
    exact(command, ['executable', 'args', 'cwd', 'encoding', 'maxBuffer', 'stdin']);
    string(command.executable); string(command.cwd);
    requireThat(Array.isArray(command.args), 'Invalid argv'); command.args.forEach(string);
    requireThat(command.encoding === 'utf8' && Number.isSafeInteger(command.maxBuffer) && command.maxBuffer > 0, 'Invalid command options');
    requireThat(command.stdin === null || typeof command.stdin === 'string', 'Invalid stdin');
  }
  exact(inputs.generated, ['pin', 'imports', 'theorems', 'typedClaims', 'axiomCommands']);
  for (const key of ['pin', 'typedClaims']) requireThat(inputs.generated[key] === null || typeof inputs.generated[key] === 'string', 'Invalid generated source');
  for (const key of ['imports', 'theorems']) { requireThat(Array.isArray(inputs.generated[key]), 'Invalid generated inventory'); inputs.generated[key].forEach(string); }
  string(inputs.generated.axiomCommands);
  requireThat(manifest.actionKey === keyForInputs(inputs), 'Action key mismatch');
  return manifest;
}

// Text manifests must use this one unambiguous JSON encoding. This also rejects
// duplicate keys, invalid UTF-8, BOMs and lossy JSON numbers before comparison.
export function serializeManifest(manifest) { validateManifest(manifest); return `${encode(manifest)}\n`; }
export function parseManifest(bytes) {
  const text = Buffer.isBuffer(bytes) ? bytes.toString('utf8') : string(bytes);
  const manifest = JSON.parse(text);
  requireThat(Buffer.from(text).equals(Buffer.from(bytes)) && text === `${encode(manifest)}\n`, 'Noncanonical or ambiguous manifest JSON');
  return validateManifest(manifest);
}
export function compareManifests(left, right) {
  try { validateManifest(left); validateManifest(right); }
  catch (error) { return { status: 'unknown', eligibleForReuse: false, inputEquality: 'unknown', changes: [], reasons: [error.message] }; }
  const changes = [];
  for (const field of Object.keys(left.inputs).sort(compareText)) {
    const a = normalized(left.inputs)[field], b = normalized(right.inputs)[field];
    if (encode(a) !== encode(b)) {
      if (field === 'files' || field === 'environment') {
        const key = field === 'files' ? 'path' : 'name';
        const previous = new Map(a.map(entry => [entry[key], entry])), current = new Map(b.map(entry => [entry[key], entry]));
        for (const name of [...new Set([...previous.keys(), ...current.keys()])].sort(compareText)) {
          if (encode(previous.get(name) ?? null) !== encode(current.get(name) ?? null)) changes.push({ field, name,
            change: !previous.has(name) ? 'added' : !current.has(name) ? 'removed' : 'changed' });
        }
      } else changes.push({ field, change: 'changed' });
    }
  }
  return { status: 'unknown', eligibleForReuse: false, inputEquality: changes.length ? 'changed' : 'equal', changes,
    provenanceChanged: encode(left.provenance) !== encode(right.provenance),
    reasons: [...new Set([...left.coverage.unresolved, ...right.coverage.unresolved])].sort(compareText) };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [mode, ...args] = process.argv.slice(2);
    if (mode === 'compare' && args.length === 2) {
      process.stdout.write(`${encode(compareManifests(readManifestFile(args[0]), readManifestFile(args[1])))}\n`);
    } else if (mode === 'inventory' && (args.length === 0 || args.length === 2 && args[0] === '--source-sha')) {
      const root = fileURLToPath(new URL('../../', import.meta.url));
      process.stdout.write(serializeManifest(inventoryAction({ root, sourceRevision: args[1] ?? null })));
    } else throw new Error('Use inventory [--source-sha SHA] or compare LEFT.json RIGHT.json');
  } catch (error) {
    process.stdout.write(`${encode({ status: 'unknown', eligibleForReuse: false, error: error.message })}\n`);
    process.exitCode = 1;
  }
}
