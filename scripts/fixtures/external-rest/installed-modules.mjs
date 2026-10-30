// Normal installed export resolution only. This creates no Host, reader,
// authority or package installation, and never falls back to checkout code.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {realpath, readFile, lstat} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {dirname, isAbsolute, join, relative, sep} from 'node:path';
import {pathToFileURL} from 'node:url';

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
