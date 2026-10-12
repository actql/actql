// Finite sidecar assembly for the existing Native artifact recipe. Inputs are
// explicitly selected and hashed by the producer, never discovered/downloaded
// from a consumer environment. This creates no Host or execution authority.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {constants, closeSync, fstatSync, lstatSync, openSync, readSync} from 'node:fs';
import {mkdir, writeFile} from 'node:fs/promises';
import {join, basename} from 'node:path';
import {
  LOCAL_RUNTIME_MAX_BYTES, localRuntimeHash, validateLocalRuntimeManifest,
  admitLocalLibraryBytes, admitInstalledLocalRuntime,
} from '../packages/native-cli/lib/local-runtime.mjs';

function original(input, maxBytes) {
  assert.deepEqual(Object.keys(input).sort(), ['bytes', 'path', 'sha256']);
  assert(Number.isSafeInteger(input.bytes) && input.bytes > 0 && input.bytes <= maxBytes);
  assert.match(input.sha256, /^[a-f0-9]{64}$/u);
  const before = lstatSync(input.path);
  assert(before.isFile() && !before.isSymbolicLink() && before.size === input.bytes);
  const descriptor = openSync(input.path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const opened = fstatSync(descriptor);
    assert(opened.isFile() && opened.dev === before.dev && opened.ino === before.ino && opened.size === input.bytes);
    const bytes = Buffer.alloc(input.bytes + 1);
    let offset = 0;
    while (offset < bytes.length) {
      const count = readSync(descriptor, bytes, offset, bytes.length - offset, null);
      if (!count) break;
      offset += count;
    }
    assert.equal(offset, input.bytes);
    const after = fstatSync(descriptor), named = lstatSync(input.path);
    assert(after.size === opened.size && after.mtimeMs === opened.mtimeMs && after.ctimeMs === opened.ctimeMs);
    assert(named.isFile() && !named.isSymbolicLink() && named.dev === opened.dev && named.ino === opened.ino);
    const result = bytes.subarray(0, input.bytes);
    assert.equal(localRuntimeHash(result), input.sha256);
    return result;
  } finally { closeSync(descriptor); }
}

export function inspectLocalLibrary(path, platform, names, execute = execFileSync) {
  const inspect = args => execute(platform === 'darwin-arm64' ? 'otool' : 'readelf', args,
    {encoding: 'utf8', timeout: 15000, maxBuffer: 1024 * 1024});
  let dependencies, abi;
  if (platform === 'darwin-arm64') {
    const ids = inspect(['-D', path]).split('\n').slice(1).map(s => s.trim()).filter(Boolean);
    assert.equal(ids.length, 1, 'Selected dylib must have one install identity');
    const loads = inspect(['-l', path]);
    const minimum = /\bcmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform 1\s+minos (\d+\.\d+(?:\.\d+)?)/u.exec(loads)?.[1]
      ?? /\bcmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version (\d+\.\d+(?:\.\d+)?)/u.exec(loads)?.[1];
    assert(minimum, 'No observed dylib deployment requirement');
    // This first product profile uses explicit loader-relative references.
    // An rpath search or environment-specific search directory is not admitted.
    assert(!/\bcmd LC_RPATH\b/u.test(loads), 'Local library must not require an ambient rpath search');
    dependencies = inspect(['-L', path]).split('\n').slice(1).filter(s => s.trim()).map(s => {
      const match = /^\s*(\S+) \(compatibility version [^\n]+\)$/u.exec(s);
      assert(match, 'Malformed dylib dependency observation'); return match[1];
    }).filter(s => s !== ids[0]).map(s => {
      if (s.startsWith('@loader_path/')) {
        const name = s.slice('@loader_path/'.length);
        assert(names.has(name), 'Missing loader-relative bundled library'); return name;
      }
      assert.equal(s, '/usr/lib/libSystem.B.dylib', 'Unbundled non-system dylib'); return s;
    });
    abi = {minimumMacOS: minimum};
  } else {
    assert.equal(platform, 'linux-x64-gnu');
    const dynamic = inspect(['-d', path]);
    const needed = [...dynamic.matchAll(/\(NEEDED\).*?\[([^\]]+)\]/gu)].map(v => v[1]);
    const paths = [...dynamic.matchAll(/\((?:RPATH|RUNPATH)\).*?\[([^\]]*)\]/gu)].map(v => v[1]);
    assert(paths.every(s => s === '$ORIGIN'), 'Unbundled shared-library search path');
    if (needed.some(s => names.has(s))) assert(paths.length > 0, 'Bundled dependency needs its own loader-relative path');
    dependencies = needed;
    const versionInfo = inspect(['--version-info', path]);
    assert(!/\b(?:GLIBCXX|CXXABI)_/u.test(versionInfo), 'Undeclared C++ runtime ABI');
    const versions = [...versionInfo.matchAll(/\bGLIBC_(\d+)\.(\d+)(?:\.(\d+))?\b/gu)]
      .map(v => v.slice(1).filter(Boolean).map(Number)).sort((a,b) => {
        for (let i = 0; i < 3; i++) if ((a[i] ?? 0) !== (b[i] ?? 0)) return (a[i] ?? 0) - (b[i] ?? 0);
        return 0;
      });
    assert(versions.length, 'No observed shared-library glibc requirements');
    abi = {minimumGlibc: versions.at(-1).join('.')};
  }
  assert.equal(new Set(dependencies).size, dependencies.length);
  return {dependencies, abi};
}

export async function prepareNativeLocalRuntime(directory, options, execute = execFileSync) {
  assert.deepEqual(Object.keys(options).sort(), ['assets', 'libraries', 'licenses', 'platform', 'sourceSha']);
  const {sourceSha, platform, libraries, assets, licenses} = options;
  for (const item of libraries) assert.deepEqual(Object.keys(item).sort(), ['dependencies', 'license', 'name', 'original', 'role']);
  for (const item of assets) assert.deepEqual(Object.keys(item).sort(), ['original', 'role']);
  for (const item of licenses) assert.deepEqual(Object.keys(item).sort(), ['name', 'original']);
  const libraryBytes = libraries.map(item => {
    const bytes = original(item.original, LOCAL_RUNTIME_MAX_BYTES);
    admitLocalLibraryBytes(bytes, platform); return bytes;
  });
  const observations = libraries.map(item => inspectLocalLibrary(item.original.path, platform,
    new Set(libraries.map(v => v.name)), execute));
  for (const [index, item] of libraries.entries()) assert.deepEqual(
    [...item.dependencies].sort(), [...observations[index].dependencies].sort(), 'Declared and physical loader dependencies differ');
  const manifest = {
    sourceSha, platform,
    libraries: libraries.map((item, index) => ({role: item.role, path: `lib/${item.name}`,
      bytes: item.original.bytes, sha256: item.original.sha256,
      license: `licenses/${item.license}`, dependencies: item.dependencies, abi: observations[index].abi})),
    assets: assets.map(item => ({role: item.role, path: `data/${item.role}.json`,
      bytes: item.original.bytes, sha256: item.original.sha256})),
    licenses: licenses.map(item => ({path: `licenses/${item.name}`,
      bytes: item.original.bytes, sha256: item.original.sha256})),
  };
  validateLocalRuntimeManifest(manifest, {sourceSha, platform});
  // Verify every selected original before mutating the new artifact directory.
  const contents = new Map();
  for (const [index, item] of libraries.entries()) {
    assert.equal(basename(item.name), item.name);
    const bytes = libraryBytes[index];
    // Recheck the original after tool observation; a changed file cannot be
    // bound to bytes captured before the tool inspected its loader metadata.
    assert.deepEqual(original(item.original, LOCAL_RUNTIME_MAX_BYTES), bytes);
    contents.set(manifest.libraries[index].path, bytes);
  }
  for (const [index, item] of assets.entries()) {
    const bytes = original(item.original, 65536);
    // Preserve the original bytes, including strings, whitespace and line ends.
    // Semantic engine/environment/Policy admission belongs to Native Owners.
    JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));
    contents.set(manifest.assets[index].path, bytes);
  }
  for (const [index, item] of licenses.entries()) {
    const bytes = original(item.original, 1024 * 1024);
    assert(bytes.toString('utf8').trim().length > 0);
    contents.set(manifest.licenses[index].path, bytes);
  }
  const root = lstatSync(directory); assert(root.isDirectory() && !root.isSymbolicLink());
  for (const child of ['lib', 'data', 'licenses']) await mkdir(join(directory, child));
  for (const [path, bytes] of contents) await writeFile(join(directory, path), bytes, {flag: 'wx', mode: 0o644});
  const wire = Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`);
  assert(wire.length <= 65536);
  const metadata = {path: 'local-runtime.json', bytes: wire.length, sha256: localRuntimeHash(wire)};
  await writeFile(join(directory, metadata.path), wire, {flag: 'wx', mode: 0o644});
  admitInstalledLocalRuntime({root: directory, expected: {sourceSha, platform, localRuntimeSha256: metadata.sha256}, metadata});
  return metadata;
}
