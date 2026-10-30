// Normal installed export resolution only. This creates no Host, reader,
// authority or package installation, and never falls back to checkout code.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {realpath, readFile, lstat, mkdtemp, rm} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {dirname, isAbsolute, join, relative, sep} from 'node:path';
import {pathToFileURL} from 'node:url';
import {tmpdir} from 'node:os';
import {CLIENT_PACKAGES} from '../../packed-client-packages.mjs';
import {unpack, inventory} from '../../package-release.mjs';

const inside = (root, path) => {
  const suffix = relative(root, path);
  return suffix !== '..' && !suffix.startsWith('..' + sep) && !isAbsolute(suffix);
};

export async function verifyExternalRestTarballs(manifest, manifestPath) {
  assert(isAbsolute(manifestPath));
  assert.deepEqual(manifest.packages.map(pkg => pkg.name).sort(),
    ['@actql/client-wire', '@actql/local-node', '@actql/node', '@actql/run-host-core', '@actql/sdk']);
  const observations = [];
  for (const pkg of manifest.packages) {
    assert.equal(pkg.file, pkg.file.split('/').at(-1));
    const path = join(dirname(manifestPath), pkg.file), bytes = await readFile(path);
    assert.equal(bytes.length, pkg.bytes);
    const sha256 = createHash('sha256').update(bytes).digest('hex');
    const integrity = 'sha512-' + createHash('sha512').update(bytes).digest('base64');
    assert.equal(sha256, pkg.sha256);
    assert.equal(integrity, pkg.integrity);
    observations.push({name: pkg.name, path, bytes: bytes.length, sha256, integrity});
  }
  return observations;
}

// Consume the supplier's original offer, never mint a replacement manifest.
// The returned inventory is checked DATA for the existing payload verifier.
export async function prepareExternalRestCohort({manifestPath, manifestSha256, sourceSha, sourceTree}) {
  assert(isAbsolute(manifestPath));
  for (const value of [sourceSha, sourceTree]) assert.match(value, /^[a-f0-9]{40}$/u);
  assert.match(manifestSha256, /^[a-f0-9]{64}$/u);
  const hash = bytes => createHash('sha256').update(bytes).digest('hex');
  const metadata = async (path, expected) => {
    assert(isAbsolute(path));
    const info = await lstat(path);
    assert(info.isFile() && !info.isSymbolicLink() && info.size <= 8 * 1024 * 1024);
    const bytes = await readFile(path);assert.equal(hash(bytes), expected);
    return {value: JSON.parse(bytes), binding: {path, bytes: bytes.length, sha256: expected}};
  };
  const selected = await metadata(manifestPath, manifestSha256);
  const offered = selected.value, originalBindings = [selected.binding];
  let manifest, artifactManifestPath = manifestPath;
  if (Array.isArray(offered.packages)) {
    assert.equal(offered.sourceSha, sourceSha);assert.equal(offered.sourceTree, sourceTree);
    manifest = offered;
  } else {
    assert.equal(offered.source, sourceSha);assert.equal(offered.tree, sourceTree);
    assert(offered.producerReturnCode === 0 || offered.status === 'passed');
    assert.equal(offered.sourceClean, true);
    assert.match(offered.manifestSHA256, /^[a-f0-9]{64}$/u);
    const producer = await metadata(offered.manifest, offered.manifestSHA256);
    assert.equal(producer.binding.bytes, offered.manifestBytes);
    assert.equal(producer.value.revision, sourceSha);
    assert.deepEqual(Object.keys(producer.value.tarballs).sort(), [...CLIENT_PACKAGES].sort());
    assert(Array.isArray(offered.tarballs));
    assert.deepEqual(offered.tarballs.map(row => row.package).sort(), [...CLIENT_PACKAGES].sort());
    const packages = offered.tarballs.map(row => {
      assert.equal(row.sha256, producer.value.tarballs[row.package]);
      assert.match(row.sha512, /^[a-f0-9]{128}$/u);
      return {name: '@actql/' + row.package, file: row.file, bytes: row.bytes,
        sha256: row.sha256, integrity: 'sha512-' + Buffer.from(row.sha512, 'hex').toString('base64')};
    });
    manifest = {sourceSha, sourceTree, packages};
    artifactManifestPath = offered.manifest;originalBindings.push(producer.binding);
  }
  const offeredTarballs = await verifyExternalRestTarballs(manifest, artifactManifestPath);
  const scratch = await mkdtemp(join(await realpath(tmpdir()), 'actql-rest-cohort-inventory-'));
  try {
    const packages = [];
    for (const pkg of manifest.packages) {
      const directory = await unpack(join(dirname(artifactManifestPath), pkg.file),
        join(scratch, pkg.name.slice('@actql/'.length)));
      assert.equal(JSON.parse(await readFile(join(directory, 'package.json'), 'utf8')).name, pkg.name);
      const files = await inventory(directory);
      const sorted = rows => rows.toSorted((a, b) => a.path.localeCompare(b.path));
      if (pkg.files !== undefined) assert.deepEqual(sorted(files), sorted(pkg.files));
      packages.push({...pkg, files: pkg.files ?? files});
    }
    // Recheck the same archives after inventory construction; no source file,
    // private installation, package lifecycle or product export was executed.
    await verifyExternalRestTarballs(manifest, artifactManifestPath);
    return {manifest: {...manifest, packages}, artifactManifestPath, originalBindings, offeredTarballs};
  } finally {
    await rm(scratch, {recursive: true, force: true});
  }
}

export async function resolveExternalRestModules({consumerRoot, connectorPackage}) {
  assert(isAbsolute(consumerRoot), 'An actual installed consumer root is required');
  assert(/^@actql-connectors\/[a-z][a-z0-9-]*$/u.test(connectorPackage), 'An explicit generated connector package is required');
  const moduleRoot = join(consumerRoot, 'node_modules');
  const moduleStat = await lstat(moduleRoot);
  assert(moduleStat.isDirectory() && !moduleStat.isSymbolicLink(),
    'StandardRestWorkspaceAliasRefused:node_modules');
  const modules = await realpath(moduleRoot);
  assert.equal(modules, moduleRoot, 'StandardRestWorkspaceAliasRefused:node_modules');
  const consumer = createRequire(join(consumerRoot, 'package.json'));
  const resolveNormal = async (require, name) => {
    const path = await realpath(require.resolve(name));
    assert(inside(modules, path), `StandardRestWorkspaceAliasRefused:${name}`);
    return path;
  };
  const node = await resolveNormal(consumer, '@actql/node');
  const host = await resolveNormal(consumer, '@actql/local-node');
  const connector = await resolveNormal(consumer, connectorPackage);
  const nodeRequire = createRequire(node), hostRequire = createRequire(host);
  const sdk = await resolveNormal(nodeRequire, '@actql/sdk');
  assert.equal(await resolveNormal(hostRequire, '@actql/sdk'), sdk, 'StandardRestSdkNamespaceMismatch');
  assert.equal(await resolveNormal(createRequire(connector), '@actql/local-node'), host,
    'StandardRestConnectorHostMismatch');
  return Object.freeze({node, host, sdk, connector});
}

export async function loadExternalRestModules(options) {
  // The caller verifies its ordinary cohort once before selecting this helper.
  const paths = await resolveExternalRestModules(options);
  const node = await import(pathToFileURL(paths.node).href);
  const host = await import(pathToFileURL(paths.host).href);
  const connector = await import(pathToFileURL(paths.connector).href);
  assert.equal(typeof node.connect, 'function');
  assert.equal(typeof host.createInstalledConnectorTable, 'function');
  assert(Array.isArray(connector.installedConnectors) && connector.installedConnectors.length === 1);
  assert.equal(connector.installedConnectors[0].providerBundle, undefined);
  assert.equal(connector.installedConnectors[0].effect, undefined);
  const connectorTable = host.createInstalledConnectorTable(connector.installedConnectors);
  // Same canonical Node require-context as the installed public caller. The
  // conformance helper captures its original getter once before start/await.
  const publicSdk = createRequire(paths.node)('@actql/sdk');
  return Object.freeze({connect: options => Reflect.apply(node.connect, node, [options]),
    publicSdk, connectorTable, paths});
}
