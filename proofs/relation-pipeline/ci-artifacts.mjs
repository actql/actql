// Transport only: fresh producer evidence is never a cache or executable input.
// The pinned Actions service transports one sealed TAR. Its outer ZIP digest is
// diagnostic metadata; the inner TAR and every extracted file are checked here.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {closeSync, constants, copyFileSync, existsSync, fstatSync, lstatSync,
  mkdirSync, openSync, readFileSync, readSync, readdirSync, statSync,
  writeFileSync, writeSync, chmodSync} from 'node:fs';
import {dirname, join, resolve, sep} from 'node:path';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {hash, snapshot} from './inventory.mjs';
import {currentFoundation} from './history.mjs';
import {decision} from './exploration-impact.mjs';
import {auditFixture, fixturePath} from './fixture.mjs';

export const schema = 'actql-pipeline-ci-artifact/0.1';
const producers = ['mutations', 'capacity'];
const targets = ['js', 'wasm', 'native'];
const digestPattern = /^[0-9a-f]{64}$/u;
const shaPattern = /^[0-9a-f]{40}$/u;
const maxFiles = 50000, maxFileBytes = 4 * 1024 ** 3, maxTotalBytes = 16 * 1024 ** 3;
const maxManifestBytes = 32 * 1024 ** 2;
const manifestName = 'ci-seal.json';
const prefix = '.artifacts/relation-pipeline/';
export const requiredStages = Object.freeze({
  mutations: ['foundation', 'focused', 'baseline', 'mutations'],
  capacity: ['foundation', 'capacity', 'capacity-audit', 'capacity-negative', 'final-normal'],
});
const encode = value => `${JSON.stringify(value, null, 2)}\n`;
function canonicalJson(path, limit = maxManifestBytes) {
  const info = regularFile(path);
  assert(info.size <= limit, 'Oversized JSON evidence');
  const chunks = []; let size = 0;
  streamFile(path, bytes => {size += bytes.length; assert(size <= limit, 'Oversized JSON evidence'); chunks.push(Buffer.from(bytes));});
  const bytes = Buffer.concat(chunks), value = JSON.parse(bytes);
  assert(bytes.equals(Buffer.from(encode(value))), 'Noncanonical or ambiguous JSON evidence');
  return value;
}
export function safePath(path) {
  assert(typeof path === 'string' && path.length > 0 && path.length <= 255 &&
    /^[A-Za-z0-9_.+-]+(?:\/[A-Za-z0-9_.+-]+)*$/u.test(path) &&
    !path.split('/').some(part => part === '.' || part === '..'), 'Unsafe evidence path');
  assert(!path.split('/').some(part => ['_build', 'workspaces', 'node_modules'].includes(part)), 'Build/workspace payload is forbidden');
  return path;
}
function noLinks(path) {
  const full = resolve(path);
  let current = sep;
  for (const part of full.split(sep).filter(Boolean)) {
    current = join(current, part);
    assert(!lstatSync(current).isSymbolicLink(), `Linked evidence path: ${current}`);
  }
}
function regularFile(path) {
  noLinks(path);
  const info = lstatSync(path);
  assert(info.isFile() && info.nlink === 1, 'Evidence must be an unlinked regular file');
  assert(Number.isSafeInteger(info.size) && info.size <= maxTotalBytes + maxFiles * 1024, 'Oversized evidence file');
  return info;
}
function streamFile(path, consume) {
  const expected = regularFile(path);
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const before = fstatSync(fd);
    for (const key of ['dev', 'ino', 'mode', 'size', 'mtimeMs', 'ctimeMs', 'nlink']) assert.equal(before[key], expected[key], 'Evidence changed before opening');
    const buffer = Buffer.alloc(1024 * 1024);
    let count = 0, size;
    while ((size = readSync(fd, buffer, 0, buffer.length, null)) > 0) {
      count += size; assert(count <= expected.size, 'Evidence grew while reading');
      consume(buffer.subarray(0, size));
    }
    const after = fstatSync(fd);
    assert.equal(count, expected.size, 'Truncated evidence file');
    const named = regularFile(path);
    for (const key of ['dev', 'ino', 'mode', 'size', 'mtimeMs', 'ctimeMs', 'nlink']) {
      assert.equal(after[key], before[key], 'Evidence changed while reading');
      assert.equal(named[key], before[key], 'Evidence path replaced while reading');
    }
  } finally { closeSync(fd); }
}
export function fileDigest(path) {
  const hash = createHash('sha256'); streamFile(path, bytes => hash.update(bytes)); return hash.digest('hex');
}
export function inventory(directory, {excludeManifest = false} = {}) {
  noLinks(directory); assert(lstatSync(directory).isDirectory());
  const result = []; let total = 0;
  function walk(relative = '') {
    for (const name of readdirSync(join(directory, relative)).sort()) {
      const path = relative ? `${relative}/${name}` : name;
      if (excludeManifest && path === manifestName) continue;
      const full = join(directory, path), stat = lstatSync(full);
      assert(!stat.isSymbolicLink(), 'Linked artifact input');
      // Passed mutation scratch owners remove their children on exit.
      if (path === 'workspaces') {
        assert(stat.isDirectory() && readdirSync(full).length === 0, 'Mutation workspaces are not closed');
        continue;
      }
      safePath(path);
      if (stat.isDirectory()) walk(path);
      else {
        regularFile(full); assert(stat.size <= maxFileBytes, 'Oversized evidence member'); total += stat.size;
        assert(total <= maxTotalBytes && result.length < maxFiles, 'Evidence inventory budget exceeded');
        result.push({path, kind: 'file', size: stat.size, sha256: fileDigest(full)});
      }
    }
  }
  walk(); return result.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
}
export function contextFromEnvironment(root, env = process.env) {
  const testedSha = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
  assert.equal(testedSha, env.GITHUB_SHA, 'Checkout is not the actual CI tested SHA');
  let prHeadSha = null;
  if (env.GITHUB_EVENT_PATH) prHeadSha = JSON.parse(readFileSync(env.GITHUB_EVENT_PATH)).pull_request?.head?.sha ?? null;
  const context = {repository: env.GITHUB_REPOSITORY, runId: env.GITHUB_RUN_ID,
    runAttempt: env.GITHUB_RUN_ATTEMPT, testedSha, prHeadSha};
  validateContext(context); return context;
}
function validateContext(context) {
  assert.deepEqual(Object.keys(context).sort(), ['repository', 'runId', 'runAttempt', 'testedSha', 'prHeadSha'].sort());
  assert(/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/u.test(context.repository));
  for (const key of ['runId', 'runAttempt']) assert(/^[1-9][0-9]*$/u.test(context[key]), `Invalid ${key}`);
  assert(shaPattern.test(context.testedSha));
  assert(context.prHeadSha === null || shaPattern.test(context.prHeadSha));
}
function sourceState(root) {
  const source = snapshot(root), foundation = currentFoundation(root);
  return {context: contextFromEnvironment(root), source: {digest: source.digest},
    foundation: {digest: hash(encode(foundation))}, exploration: decision(root),
    toolchain: {moonbit: JSON.parse(readFileSync(join(root, 'toolchain.json'))),
      lean: readFileSync(join(root, 'proofs/bounded-session/lean-toolchain'), 'utf8').trim(),
      setupDigest: hash(readFileSync(join(root, '.github/actions/setup-toolchain/action.yml'))),
      leanSetupDigest: hash(readFileSync(join(root, 'proofs/bounded-session/setup-lean.mjs'))), node: '22.22.0'}};
}
function assertReports(directory, producer, expected) {
  const read = path => canonicalJson(join(directory, safePath(path)));
  const refs = [], reports = producer === 'mutations'
    ? ['base-js.json', 'fixed-mutations.json', ...(expected.exploration.required ? ['mutations.json'] : [])]
    : ['capacity/all.json', ...targets.map(target => `${target}.json`)];
  if (producer === 'mutations') assert.deepEqual(read('exploration-decision.json'), expected.exploration);
  for (const name of reports) {
    const report = read(name);
    assert.equal(report.revision, expected.context.testedSha, 'Report is not from the tested checkout');
    assert.equal(report.source.digest, expected.source.digest, 'Report has unrelated source');
    assert.equal(hash(JSON.stringify(report.source.sources)), expected.source.digest);
    assert.deepEqual(report.toolchain, expected.toolchain.moonbit, 'Unpinned report toolchain');
    if (name === 'base-js.json') assert.equal(report.target, 'js');
    else if (targets.some(target => name === `${target}.json`)) assert.equal(report.target, name.slice(0, -5));
    if (report.results) {
      assert.deepEqual(report.decision, expected.exploration);
      for (const result of report.results) refs.push(...result.executions, ...result.healthyExecutions);
    } else refs.push(...report.executions);
  }
  const paths = new Set(), observations = new Set(), receipts = [];
  for (const execution of refs) {
    assert(execution.path.startsWith(prefix), 'Non-local receipt reference');
    const path = safePath(execution.path.slice(prefix.length));
    assert(!paths.has(path), 'Receipt reused across obligations'); paths.add(path);
    const receipt = read(path);
    assert.deepEqual(receipt, execution.receipt, 'Report and receipt differ');
    assert.equal(hash(JSON.stringify(receipt)), execution.digest, 'Receipt digest differs');
    assert(targets.includes(receipt.target));
    assert.equal(receipt.compiler, expected.toolchain.moonbit.moonc);
    const local = path => {
      assert(path.startsWith(prefix)); return join(directory, safePath(path.slice(prefix.length)));
    };
    auditFixture(receipt, readFileSync(local(receipt.fixturePath)), readFileSync(local(receipt.logPath), 'utf8'), receipt.target);
    assert(Array.isArray(receipt.cases) && receipt.cases.length > 0, 'Empty execution receipt');
    for (const entry of receipt.cases) {
      assert(typeof entry.id === 'string' && entry.id.length > 0, 'Missing observation identity');
      assert(!observations.has(entry.id), 'Observation reused across obligations'); observations.add(entry.id);
    }
    receipts.push({path, target: receipt.target, boundary: receipt.boundary, buildIdentity: receipt.buildIdentity});
  }
  assert(receipts.length, 'No execution receipts');
  return receipts.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
}
function ownedPath(producer, path) {
  if (['current-foundation.json', 'session-model.log', 'chain-model.log'].includes(path) || /^sources\/[0-9a-f]{64}\.json$/u.test(path)) return true;
  if (/^[0-9]+-[0-9]+-[0-9]{4}-[A-Za-z0-9_-]+\.(?:json|inputs\.json|fixture\.mbt|log)$/u.test(path)) return true;
  return producer === 'mutations'
    ? ['base-js.json', 'fixed-mutations.json', 'mutations.json', 'exploration-decision.json'].includes(path)
    : ['js.json', 'wasm.json', 'native.json'].includes(path) || path.startsWith('capacity/') || /^final-artifacts\/(?:js|wasm|native)\//u.test(path);
}
export function validateEnvelope(manifest, expected) {
  assert.deepEqual(Object.keys(manifest).sort(), ['schema', 'producer', 'context', 'source', 'foundation', 'exploration', 'toolchain', 'completedStages', 'restoration', 'files', 'receipts'].sort(), 'Unknown envelope fields');
  assert.equal(manifest.schema, schema); assert(producers.includes(manifest.producer));
  assert.equal(manifest.producer, expected.producer);
  validateContext(manifest.context); assert.deepEqual(manifest.context, expected.context, 'Different run, attempt or tested checkout');
  for (const key of ['source', 'foundation', 'exploration', 'toolchain']) assert.deepEqual(manifest[key], expected[key], `Different ${key}`);
  assert(digestPattern.test(manifest.source.digest) && digestPattern.test(manifest.foundation.digest));
  assert.deepEqual(manifest.completedStages, requiredStages[manifest.producer], 'Incomplete producer stages');
  assert.deepEqual(manifest.restoration, {sourceRestored: true, fixtureClosed: true, workspacesClosed: true}, 'Unclosed producer');
  assert(Array.isArray(manifest.files) && manifest.files.length > 0 && manifest.files.length <= maxFiles);
  const paths = new Set(); let total = 0;
  for (const file of manifest.files) {
    assert.deepEqual(Object.keys(file).sort(), ['path', 'kind', 'size', 'sha256'].sort());
    safePath(file.path); assert(ownedPath(manifest.producer, file.path), 'File is outside producer ownership');
    assert.notEqual(file.path, manifestName); assert.equal(file.kind, 'file');
    assert(!paths.has(file.path), 'Duplicate inventory path'); paths.add(file.path);
    assert(Number.isSafeInteger(file.size) && file.size >= 0 && file.size <= maxFileBytes);
    total += file.size; assert(total <= maxTotalBytes); assert(digestPattern.test(file.sha256));
  }
  assert.deepEqual(manifest.files.map(file => file.path), [...paths].sort(), 'Noncanonical inventory order');
  assert(Array.isArray(manifest.receipts) && manifest.receipts.length > 0);
  const receipts = new Set();
  for (const receipt of manifest.receipts) {
    assert.deepEqual(Object.keys(receipt).sort(), ['path', 'target', 'boundary', 'buildIdentity'].sort());
    safePath(receipt.path); assert(paths.has(receipt.path)); assert(!receipts.has(receipt.path), 'Duplicate receipt'); receipts.add(receipt.path);
    assert(targets.includes(receipt.target)); assert.equal(receipt.boundary.target, receipt.target);
    assert(['normal', 'mutable', 'pristine'].includes(receipt.boundary.role));
    assert.equal(receipt.buildIdentity, hash(JSON.stringify(receipt.boundary)), 'Changed compiled identity');
  }
  return manifest;
}
export function sealEvidence({root, directory, producer, context, stages, source, foundation, exploration, toolchain}) {
  assert(root, 'Producer checkout root is required');
  assert(!existsSync(join(root, fixturePath)), 'Executor fixture was not closed');
  assert.equal(snapshot(root).digest, source.digest, 'Producer source was not restored');
  const expected = {producer, context, source, foundation, exploration, toolchain};
  const archivedFoundation = canonicalJson(join(directory, 'current-foundation.json'));
  assert.equal(archivedFoundation.sourceRevision, context.testedSha);
  assert.equal(fileDigest(join(directory, 'current-foundation.json')), foundation.digest, 'Stale archived foundation');
  const receipts = assertReports(directory, producer, expected);
  const manifest = {...expected, schema, completedStages: stages,
    restoration: {sourceRestored: true, fixtureClosed: true, workspacesClosed: true},
    files: inventory(directory, {excludeManifest: true}), receipts};
  validateEnvelope(manifest, expected);
  writeFileSync(join(directory, manifestName), encode(manifest), {flag: 'wx'});
  return manifest;
}
// Deliberately small USTAR reader/writer: no compression, links, PAX/GNU
// extensions, sparse files, directories, devices, or extraction libraries.
function writeAll(fd, bytes) {
  let offset = 0;
  while (offset < bytes.length) {const count = writeSync(fd, bytes, offset, bytes.length - offset); assert(count > 0, 'Incomplete archive write'); offset += count;}
}
function octal(value, length) { const text = value.toString(8); assert(text.length < length); return `${text.padStart(length - 1, '0')}\0`; }
function header(path, size) {
  safePath(path); const out = Buffer.alloc(512); let name = path, prefix = '';
  if (Buffer.byteLength(name) > 100) {
    const split = [...path.matchAll(/\//gu)].map(match => match.index).reverse().find(index => index <= 155 && path.length - index - 1 <= 100);
    assert(split !== undefined, 'USTAR path too long'); prefix = path.slice(0, split); name = path.slice(split + 1);
  }
  out.write(name, 0, 100); out.write(octal(0o444, 8), 100); out.write(octal(0, 8), 108); out.write(octal(0, 8), 116);
  out.write(octal(size, 12), 124); out.write(octal(0, 12), 136); out.fill(32, 148, 156);
  out[156] = 48; out.write('ustar\0', 257); out.write('00', 263); out.write(prefix, 345, 155);
  out.write([...out].reduce((sum, byte) => sum + byte, 0).toString(8).padStart(6, '0') + '\0 ', 148);
  return out;
}
export function packArchive(directory, archive) {
  const files = inventory(directory); assert(files.some(file => file.path === manifestName), 'Unsealed archive');
  assert(!resolve(archive).startsWith(resolve(directory) + sep), 'Archive must be outside its evidence tree');
  mkdirSync(dirname(archive), {recursive: true}); noLinks(dirname(archive));
  const fd = openSync(archive, 'wx', 0o600);
  try {
    for (const file of files) {
      writeAll(fd, header(file.path, file.size));
      const actual = createHash('sha256'); streamFile(join(directory, file.path), bytes => {writeAll(fd, bytes); actual.update(bytes);});
      assert.equal(actual.digest('hex'), file.sha256, 'Evidence changed during packing');
      if (file.size % 512) writeAll(fd, Buffer.alloc(512 - file.size % 512));
    }
    writeAll(fd, Buffer.alloc(1024));
  } finally { closeSync(fd); }
  return fileDigest(archive);
}
export function unpackArchive(archive, destination, expectedDigest = null) {
  const info = regularFile(archive); assert(info.size <= maxTotalBytes + maxFiles * 1024 && info.size % 512 === 0, 'Invalid TAR size');
  assert(!existsSync(destination), 'Extraction destination already exists');
  mkdirSync(dirname(destination), {recursive: true}); noLinks(dirname(destination)); mkdirSync(destination);
  const fd = openSync(archive, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK); let offset = 0, total = 0;
  const identity = fstatSync(fd), extractedHash = createHash('sha256');
  for (const key of ['dev', 'ino', 'mode', 'size', 'mtimeMs', 'ctimeMs', 'nlink']) assert.equal(identity[key], info[key], 'Archive changed before extraction');
  const seen = new Set();
  const exact = size => {const bytes = Buffer.alloc(size); assert.equal(readSync(fd, bytes, 0, size, offset), size, 'Truncated TAR'); offset += size; extractedHash.update(bytes); return bytes;};
  const text = (bytes, start, end) => {
    const part = bytes.subarray(start, end), zero = part.indexOf(0);
    assert(part.every(byte => byte < 128), 'Non-ASCII TAR field');
    if (zero >= 0) assert(part.subarray(zero).every(byte => byte === 0), 'Ambiguous TAR string');
    return part.subarray(0, zero < 0 ? part.length : zero).toString('ascii');
  };
  const number = (bytes, start, end) => {const value = text(bytes, start, end).trim(); assert(/^[0-7]+$/u.test(value)); return parseInt(value, 8);};
  try {
    while (offset < info.size) {
      const block = exact(512);
      if (block.every(byte => byte === 0)) {
        assert(exact(512).every(byte => byte === 0), 'Missing TAR end marker');
        assert.equal(offset, info.size, 'Trailing TAR content'); assert(seen.size > 0);
        const after = fstatSync(fd), named = regularFile(archive);
        for (const key of ['dev', 'ino', 'mode', 'size', 'mtimeMs', 'ctimeMs', 'nlink']) {
          assert.equal(after[key], identity[key], 'Archive changed during extraction');
          assert.equal(named[key], identity[key], 'Archive path changed during extraction');
        }
        const digest = extractedHash.digest('hex');
        if (expectedDigest !== null) assert.equal(digest, expectedDigest, 'Extracted archive bytes differ');
        return;
      }
      const checksum = number(block, 148, 155); const check = Buffer.from(block); check.fill(32, 148, 156);
      assert.equal([...check].reduce((sum, byte) => sum + byte, 0), checksum, 'Invalid TAR checksum');
      assert.equal(block[156], 48, 'Unsupported TAR kind (links/extensions forbidden)');
      assert.equal(text(block, 157, 257), '', 'TAR link target forbidden');
      assert.equal(block.subarray(257, 265).toString(), 'ustar\u000000', 'Unsupported TAR format');
      const part = text(block, 345, 500), name = text(block, 0, 100), path = safePath(part ? `${part}/${name}` : name);
      assert(!seen.has(path), 'Duplicate TAR path'); seen.add(path); assert(seen.size <= maxFiles);
      const size = number(block, 124, 136); total += size;
      assert(Number.isSafeInteger(size) && size <= maxFileBytes && total <= maxTotalBytes && offset + size + 1024 <= info.size, 'Invalid TAR member size');
      const to = join(destination, path); mkdirSync(dirname(to), {recursive: true}); noLinks(dirname(to));
      const output = openSync(to, 'wx', 0o444);
      try {let remaining = size; while (remaining > 0) {const bytes = exact(Math.min(remaining, 1024 * 1024)); writeAll(output, bytes); remaining -= bytes.length;}} finally {closeSync(output);}
      if (size % 512) assert(exact(512 - size % 512).every(byte => byte === 0), 'Nonzero TAR padding');
    }
    assert.fail('Missing TAR end marker');
  } finally {closeSync(fd);}
}
export function verifyArchive(staging, destination, expectedDigest) {
  assert(digestPattern.test(expectedDigest), 'Missing inner archive digest');
  noLinks(staging); assert.deepEqual(readdirSync(staging), ['evidence.tar'], 'Unexpected transport payload');
  const archive = join(staging, 'evidence.tar');
  assert.equal(fileDigest(archive), expectedDigest, 'Inner archive digest differs');
  unpackArchive(archive, destination, expectedDigest);
}
export function joinEvidence({root, inputs, expected, destination}) {
  assert.deepEqual(inputs.map(input => input.producer), producers, 'Missing or duplicate producers');
  const ids = inputs.map(input => input.artifactId);
  assert(ids.every(id => /^[1-9][0-9]*$/u.test(id)), 'Missing exact producer artifact ID');
  assert.equal(new Set(ids).size, 2, 'Repeated producer artifact ID');
  assert(!existsSync(destination), 'Joined evidence destination already exists');
  const merged = new Map(), receiptPaths = new Set(), observations = new Set(), manifests = [];
  const shared = new Set(['current-foundation.json', 'session-model.log', 'chain-model.log', `sources/${expected.source.digest}.json`]);
  for (const input of inputs) {
    assert.equal(input.result, 'success', 'Producer failed, cancelled or skipped');
    assert(digestPattern.test(input.manifestDigest)); assert(digestPattern.test(input.artifactDigest), 'Missing outer transport digest');
    const manifestPath = join(input.directory, manifestName);
    assert.equal(fileDigest(manifestPath), input.manifestDigest, 'Manifest digest differs');
    const manifest = canonicalJson(manifestPath);
    assert.equal(hash(encode(manifest)), input.manifestDigest, 'Parsed manifest digest differs');
    validateEnvelope(manifest, {...expected, producer: input.producer});
    assert.deepEqual(inventory(input.directory, {excludeManifest: true}), manifest.files, 'Transferred file inventory differs');
    assert.equal(fileDigest(join(input.directory, 'current-foundation.json')), expected.foundation.digest, 'Transferred foundation differs');
    assert.equal(canonicalJson(join(input.directory, 'current-foundation.json')).sourceRevision, expected.context.testedSha);
    assert.deepEqual(assertReports(input.directory, input.producer, expected), manifest.receipts, 'Transferred receipt bindings differ');
    for (const receipt of manifest.receipts) {
      assert(!receiptPaths.has(receipt.path), 'Receipt path collides across producers'); receiptPaths.add(receipt.path);
      for (const entry of canonicalJson(join(input.directory, receipt.path)).cases) {
        assert(!observations.has(entry.id), 'Observation identity collides across producers'); observations.add(entry.id);
      }
    }
    for (const file of manifest.files) {
      if (merged.has(file.path)) {
        assert(shared.has(file.path), `Evidence path collision: ${file.path}`);
        assert.deepEqual(merged.get(file.path).file, file, 'Shared artifact bytes differ');
      } else merged.set(file.path, {file, directory: input.directory});
    }
    manifests.push(manifest);
  }
  mkdirSync(dirname(destination), {recursive: true}); noLinks(dirname(destination)); mkdirSync(destination);
  for (const {file, directory} of merged.values()) {
    const to = join(destination, file.path); mkdirSync(dirname(to), {recursive: true});
    copyFileSync(join(directory, file.path), to, constants.COPYFILE_EXCL); chmodSync(to, 0o444);
    assert.equal(fileDigest(to), file.sha256, 'Materialized join bytes differ');
  }
  return {schema: 'actql-pipeline-ci-join/0.1', context: expected.context,
    producers: inputs.map(({producer, artifactId, artifactDigest, manifestDigest, archiveDigest}) =>
      ({producer, artifactId, artifactDigest, manifestDigest, archiveDigest})),
    foundation: expected.foundation, source: expected.source, fileCount: merged.size,
    expandedBytes: [...merged.values()].reduce((sum, {file}) => sum + file.size, 0),
    receiptCount: receiptPaths.size, observationCount: observations.size, manifests};
}
function outputs(values) {
  assert(process.env.GITHUB_OUTPUT, 'Missing Actions step output file');
  for (const [key, value] of Object.entries(values)) {
    assert(/^[a-z-]+$/u.test(key) && /^[A-Za-z0-9.-]+$/u.test(String(value)));
    writeFileSync(process.env.GITHUB_OUTPUT, `${key}=${value}\n`, {flag: 'a'});
  }
}
async function main() {
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const [command, producer] = process.argv.slice(2);
  const stateRoot = join(root, '.artifacts/pipeline-ci'), directory = join(root, prefix);
  if (command === 'begin') {
    assert(producers.includes(producer));
    const state = sourceState(root);
    assert(!existsSync(join(root, fixturePath)), 'Fixture exists before campaign');
    assert.equal(fileDigest(join(directory, 'current-foundation.json')), state.foundation.digest);
    const output = join(stateRoot, producer); mkdirSync(output, {recursive: true});
    writeFileSync(join(output, 'start.json'), encode(state), {flag: 'wx'});
    writeFileSync(join(output, 'stages.json'), encode(['foundation']), {flag: 'wx'});
  } else if (command === 'stage') {
    assert(producers.includes(producer)); const stage = process.argv[4];
    const path = join(stateRoot, producer, 'stages.json'), stages = canonicalJson(path);
    assert.equal(stage, requiredStages[producer][stages.length], 'Wrong producer stage ordering');
    stages.push(stage); writeFileSync(path, encode(stages));
  } else if (command === 'seal') {
    assert(producers.includes(producer)); const out = join(stateRoot, producer);
    const expected = canonicalJson(join(out, 'start.json'));
    assert.deepEqual(sourceState(root), expected, 'Producer source/toolchain/foundation was not restored');
    assert(!existsSync(join(root, fixturePath)), 'Executor fixture was not closed');
    sealEvidence({root, directory, producer, ...expected, stages: canonicalJson(join(out, 'stages.json'))});
    const archiveDigest = packArchive(directory, join(out, 'evidence.tar'));
    outputs({'archive-digest': archiveDigest, 'manifest-digest': fileDigest(join(directory, manifestName))});
  } else if (command === 'join') {
    const needs = JSON.parse(process.env.PIPELINE_NEEDS ?? '{}');
    assert.deepEqual(Object.keys(needs).sort(), producers.map(value => `pipeline-${value}`).sort());
    const expected = sourceState(root), began = performance.now();
    const staging = process.env.PIPELINE_STAGING; assert(staging);
    const inputs = producers.map(producer => {
      const job = needs[`pipeline-${producer}`]; assert.equal(job.result, 'success', `pipeline-${producer} did not succeed`);
      const output = job.outputs;
      return {producer, result: job.result, artifactId: output['artifact-id'], artifactDigest: output['artifact-digest'],
        archiveDigest: output['archive-digest'], manifestDigest: output['manifest-digest'], directory: join(staging, `${producer}-verified`)};
    });
    assert(inputs.every(input => /^[1-9][0-9]*$/u.test(input.artifactId)) && new Set(inputs.map(input => input.artifactId)).size === 2, 'Invalid producer artifact IDs');
    for (const input of inputs) verifyArchive(join(staging, input.producer), input.directory, input.archiveDigest);
    const result = joinEvidence({root, inputs, expected, destination: directory});
    result.verificationMs = performance.now() - began;
    mkdirSync(stateRoot, {recursive: true}); writeFileSync(join(stateRoot, 'join.json'), encode(result));
    console.log(`Verified ${result.fileCount} files / ${result.expandedBytes} bytes from two fresh producers in ${Math.round(result.verificationMs)}ms`);
  } else assert.fail('Use begin|stage|seal mutations|capacity, or join');
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
