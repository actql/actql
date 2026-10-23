// Public installation data, not an execution, credential or read authority.
// The Native adoption/Account/Policy owners still admit the selected originals.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {constants, closeSync, fstatSync, lstatSync, openSync, readSync} from 'node:fs';
import {join} from 'node:path';

export const LOCAL_RUNTIME_MAX_BYTES = 64 * 1024 * 1024;
const MANIFEST_MAX_BYTES = 65536;
const DATA_MAX_BYTES = 65536;
const LICENSE_MAX_BYTES = 1024 * 1024;
const roles = ['environment', 'registry', 'values', 'fragment', 'ordered', 'result-policy'];
const systems = {
  'darwin-arm64': new Set(['/usr/lib/libSystem.B.dylib', '/usr/lib/libz.1.dylib']),
  'linux-x64-gnu': new Set(['libc.so.6', 'libm.so.6', 'libdl.so.2', 'libpthread.so.0', 'librt.so.1', 'ld-linux-x86-64.so.2']),
};
export const localRuntimeHash = bytes => createHash('sha256').update(bytes).digest('hex');
const exact = (value, keys) => {
  assert(value && typeof value === 'object' && !Array.isArray(value));
  assert.deepEqual(Object.keys(value).sort(), [...keys].sort());
};
const digest = value => assert.equal(typeof value === 'string' && /^[a-f0-9]{64}$/u.test(value), true);
const filename = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/u.test(value);
const boundedRead = (descriptor, size) => {
  const bytes = Buffer.alloc(size + 1);
  let position = 0;
  while (position < bytes.length) {
    const count = readSync(descriptor, bytes, position, bytes.length - position, null);
    if (count === 0) break;
    position += count;
  }
  assert.equal(position, size);
  return bytes.subarray(0, size);
};

export function admitLocalLibraryBytes(bytes, platform) {
  assert(bytes.length >= 32);
  if (platform === 'darwin-arm64') {
    assert.equal(bytes.readUInt32LE(0), 0xfeedfacf);
    assert.equal(bytes.readUInt32LE(4), 0x0100000c);
    assert.equal(bytes.readUInt32LE(12), 6);
  } else {
    assert.equal(platform, 'linux-x64-gnu');
    assert.equal(bytes.subarray(0, 4).toString('hex'), '7f454c46');
    assert.equal(bytes[4], 2); assert.equal(bytes[5], 1);
    assert.equal(bytes.readUInt16LE(18), 62);
    assert.equal(bytes.readUInt16LE(16), 3);
  }
  // A matching header is necessary, not ABI or execution acceptance.
}

export function validateLocalRuntimeManifest(value, {sourceSha, platform}) {
  exact(value, ['sourceSha', 'platform', 'libraries', 'assets', 'licenses']);
  assert.match(sourceSha, /^[a-f0-9]{40}$/u);
  assert.equal(value.sourceSha, sourceSha);
  assert(systems[platform]); assert.equal(value.platform, platform);
  assert(Array.isArray(value.libraries) && value.libraries.length >= 2 && value.libraries.length <= 8);
  assert(Array.isArray(value.assets) && value.assets.length >= 5 && value.assets.length <= 6);
  assert(Array.isArray(value.licenses) && value.licenses.length >= 1 && value.licenses.length <= 8);
  const paths = new Set(), libraryNames = new Set(), libraryRoles = new Set(), assetRoles = new Set();
  let bytes = 0;
  const member = (item, prefix, maxBytes) => {
    assert(filename(item.path.slice(prefix.length)) && item.path.startsWith(prefix));
    assert(!paths.has(item.path)); paths.add(item.path);
    assert(Number.isSafeInteger(item.bytes) && item.bytes > 0 && item.bytes <= maxBytes);
    digest(item.sha256); bytes += item.bytes;
    assert(bytes <= LOCAL_RUNTIME_MAX_BYTES);
  };
  for (const item of value.licenses) {
    exact(item, ['path', 'bytes', 'sha256']); member(item, 'licenses/', LICENSE_MAX_BYTES);
  }
  const licenses = new Set(value.licenses.map(item => item.path));
  for (const item of value.libraries) {
    exact(item, ['role', 'path', 'bytes', 'sha256', 'license', 'dependencies', 'abi']);
    const minimum = platform === 'darwin-arm64' ? 'minimumMacOS' : 'minimumGlibc';
    exact(item.abi, [minimum]);
    assert.equal(typeof item.abi[minimum], 'string');
    assert.match(item.abi[minimum], /^\d+\.\d+(?:\.\d+)?$/u);
    assert(['sqlite', 'crypto', 'dependency'].includes(item.role));
    if (item.role !== 'dependency') {
      assert(!libraryRoles.has(item.role)); libraryRoles.add(item.role);
    }
    member(item, 'lib/', LOCAL_RUNTIME_MAX_BYTES);
    assert(licenses.has(item.license));
    assert(Array.isArray(item.dependencies) && item.dependencies.length <= 8);
    assert.equal(new Set(item.dependencies).size, item.dependencies.length);
    libraryNames.add(item.path.slice(4));
  }
  assert(libraryRoles.has('sqlite') && libraryRoles.has('crypto'));
  for (const item of value.libraries) for (const dependency of item.dependencies) {
    // Only explicit bundled names or the selected platform's finite OS ABI.
    // Homebrew paths, search directories and an ambient loader fallback fail.
    assert(libraryNames.has(dependency) || systems[platform].has(dependency));
  }
  for (const item of value.assets) {
    exact(item, ['role', 'path', 'bytes', 'sha256']);
    assert(roles.includes(item.role) && !assetRoles.has(item.role)); assetRoles.add(item.role);
    assert.equal(item.path, `data/${item.role}.json`); member(item, 'data/', DATA_MAX_BYTES);
  }
  for (const role of ['environment', 'registry', 'values', 'fragment', 'result-policy']) assert(assetRoles.has(role));
  // Every packaged notice must apply to an actual bundled library.
  assert(value.licenses.every(item => value.libraries.some(library => library.license === item.path)));
  return value;
}

export function readLocalRuntimeMember(root, item, maxBytes) {
  // Each manifest path has one fixed directory and one closed file name.
  // Reject directory/file symlinks rather than following a dependency elsewhere.
  const [directory, name] = item.path.split('/');
  assert(filename(name) && ['lib', 'data', 'licenses'].includes(directory));
  assert.equal(item.path, `${directory}/${name}`);
  assert(Number.isSafeInteger(item.bytes) && item.bytes > 0 && item.bytes <= maxBytes);
  const parent = lstatSync(join(root, directory));
  assert(parent.isDirectory() && !parent.isSymbolicLink());
  const path = join(root, item.path);
  const before = lstatSync(path);
  assert(before.isFile() && !before.isSymbolicLink() && before.size === item.bytes);
  const descriptor = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const opened = fstatSync(descriptor);
    assert(opened.isFile() && opened.dev === before.dev && opened.ino === before.ino && opened.size === item.bytes);
    const bytes = boundedRead(descriptor, item.bytes);
    const after = fstatSync(descriptor), named = lstatSync(path);
    assert(after.dev === opened.dev && after.ino === opened.ino && after.size === opened.size &&
      after.mtimeMs === opened.mtimeMs && after.ctimeMs === opened.ctimeMs);
    assert(named.isFile() && !named.isSymbolicLink() && named.dev === opened.dev && named.ino === opened.ino);
    assert.equal(bytes.length, item.bytes); assert.equal(localRuntimeHash(bytes), item.sha256);
    return bytes;
  } finally { closeSync(descriptor); }
}

export function admitLocalRuntimePlatform(manifest, {macOS, glibc}) {
  const key = manifest.platform === 'darwin-arm64' ? 'minimumMacOS' : 'minimumGlibc';
  const actual = manifest.platform === 'darwin-arm64' ? macOS : glibc;
  const parse = text => typeof text === 'string' && /^\d+\.\d+(?:\.\d+)?$/u.test(text)
    ? [...text.split('.').map(Number), 0].slice(0, 3) : null;
  const current = parse(actual);
  for (const item of manifest.libraries) {
    const required = parse(item.abi[key]);
    const difference = current && required && current.map((v, i) => v - required[i]).find(v => v !== 0);
    if (!current || !required || difference < 0) throw Object.assign(
      Error(`Unsupported Local runtime platform; bundled ${item.role} requires ${key} ${item.abi[key]}.`), {exitCode: 64});
  }
}

function readInstalledLocalRuntimeManifest({root, expected, metadata}) {
  try {
    const directory = lstatSync(root);
    assert(directory.isDirectory() && !directory.isSymbolicLink());
    exact(metadata, ['path', 'bytes', 'sha256']);
    assert.equal(metadata.path, 'local-runtime.json'); digest(metadata.sha256);
    assert.equal(metadata.sha256, expected.localRuntimeSha256);
    assert(Number.isSafeInteger(metadata.bytes) && metadata.bytes > 0 && metadata.bytes <= MANIFEST_MAX_BYTES);
    const path = join(root, metadata.path), stat = lstatSync(path);
    assert(stat.isFile() && !stat.isSymbolicLink() && stat.size === metadata.bytes);
    const descriptor = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
    let bytes;
    try {
      const opened = fstatSync(descriptor);
      assert(opened.isFile() && opened.dev === stat.dev && opened.ino === stat.ino && opened.size === metadata.bytes);
      bytes = boundedRead(descriptor, metadata.bytes);
      const after = fstatSync(descriptor), named = lstatSync(path);
      assert(after.size === opened.size && after.mtimeMs === opened.mtimeMs && after.ctimeMs === opened.ctimeMs);
      assert(named.isFile() && !named.isSymbolicLink() && named.dev === opened.dev && named.ino === opened.ino);
    } finally { closeSync(descriptor); }
    assert.equal(bytes.length, metadata.bytes); assert.equal(localRuntimeHash(bytes), metadata.sha256);
    return validateLocalRuntimeManifest(JSON.parse(bytes.toString('utf8')), expected);
  } catch {
    throw Object.assign(Error('Native Local runtime identity or dependency mismatch; reinstall the fixed package cohort.'), {exitCode: 65});
  }
}

export function admitInstalledLocalRuntime({root, expected, metadata}) {
  try {
    const manifest = readInstalledLocalRuntimeManifest({root, expected, metadata});
    for (const item of manifest.libraries) {
      admitLocalLibraryBytes(readLocalRuntimeMember(root, item, LOCAL_RUNTIME_MAX_BYTES), expected.platform);
    }
    for (const item of manifest.assets) readLocalRuntimeMember(root, item, DATA_MAX_BYTES);
    for (const item of manifest.licenses) {
      const text = readLocalRuntimeMember(root, item, LICENSE_MAX_BYTES).toString('utf8');
      assert(text.trim().length > 0);
    }
    return manifest;
  } catch {
    throw Object.assign(Error('Native Local runtime identity or dependency mismatch; reinstall the fixed package cohort.'), {exitCode: 65});
  }
}

// The launcher selects bounded installation metadata and the required OS ABI.
// Native verifies each physical member before loading it and retains its actual
// file lifetime. Selection is neither physical admission nor permission.
export function installedLocalRuntimeEnvironment({root, expected, metadata, platformFacts, environment}) {
  const manifest = readInstalledLocalRuntimeManifest({root, expected, metadata});
  admitLocalRuntimePlatform(manifest, platformFacts);
  const result = {...environment};
  result.ACTQL_NATIVE_LOCAL_RUNTIME = JSON.stringify({
    root, sourceSha: manifest.sourceSha, platform: manifest.platform,
    manifestSha256: metadata.sha256,
  });
  return result;
}
