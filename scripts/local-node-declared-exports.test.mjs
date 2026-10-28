import assert from 'node:assert/strict';
import {mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join, relative, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {resolveConnectorBuildInputs} from './connector-build-inputs.mjs';
import {inspectExternalLocalNodeAdapterGraph} from './build-local-node-adapters.mjs';
import {rewriteLocalNodePackageImports} from './local-node-package-imports.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
function fixture(t) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'local-node-export-boundary-')));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const put = (path, contents) => {
    mkdirSync(dirname(path), {recursive: true});
    writeFileSync(path, contents);
  };
  const core = join(root, 'core'), provider = join(root, 'provider'), host = join(root, 'host');
  for (const [directory, name, imports] of [
    [core, 'actql/actql', []], [provider, 'fixture/provider', ['actql/actql@0.0.1']],
    [host, 'fixture/host', ['actql/actql@0.0.1', 'fixture/provider@0.0.1']],
  ]) {
    put(join(directory, 'moon.mod'), `name = "${name}"\nversion = "0.0.1"\nsource = "src"\n` +
      (imports.length ? `import {${imports.map(value => JSON.stringify(value)).join(',')}}\n` : ''));
    mkdirSync(join(directory, 'src'), {recursive: true});
  }
  const manifests = {};
  for (const name of ['local-node', 'sdk', 'client-wire', 'run-host-core']) {
    const path = join(core, 'packages', name, 'package.json');
    const original = readFileSync(join(repository, 'packages', name, 'package.json'), 'utf8');
    const manifest = manifests[name] = JSON.parse(original);
    put(path, original);
    // These are inert file placeholders for metadata/path inspection only;
    // dependency modules remain external and are never imported or executed.
    for (const entry of Object.values(manifest.exports)) {
      const target = typeof entry === 'string' ? entry : entry.default;
      if (typeof target === 'string') put(join(core, 'packages', name, target), 'export {};\n');
    }
  }
  const buildInputs = resolveConnectorBuildInputs({target: 'js',
    modules: [{namespace: 'actql/actql', version: '0.0.1', root: core},
      {namespace: 'fixture/provider', version: '0.0.1', root: provider},
      {namespace: 'fixture/host', version: '0.0.1', root: host}],
    host: 'fixture/host', connectors: []});
  const coreProbe = join(core, 'adapters/host-node/probe.mjs');
  const providerProbe = join(provider, 'adapters/connectors/fixture/host/probe.mjs');
  const inputs = {coreRoot: core, buildInputs,
    installationTable: {source: join(host, 'adapters/installations.mjs'), destination: 'adapters/installations.mjs'},
    installations: [{root: provider, name: 'fixture', assetSources: []}],
    runtimeFiles: ['admitted/admitted.js'], adapterInputs: []};
  const graph = (specifier, owner = 'core') => {
    const source = owner === 'core' ? coreProbe : providerProbe;
    put(source, `import ${JSON.stringify(specifier)};\nexport {};\n`);
    return inspectExternalLocalNodeAdapterGraph({...inputs, adapterInputs: [{source}]});
  };
  const update = (name, change) => {
    const value = JSON.parse(JSON.stringify(manifests[name]));
    change(value);
    put(join(core, 'packages', name, 'package.json'), JSON.stringify(value));
  };
  return {core, provider, coreProbe, providerProbe, put, graph, update, manifests};
}

test('Core Source preparation edge uses the canonical rewrite and exact declared SDK export', async t => {
  const f = fixture(t);
  assert.equal(f.manifests.sdk.exports['./_internal/source-preparation'], './internal/private-source-preparation.mjs');
  const graph = await f.graph('../../packages/sdk/internal/private-source-preparation.mjs');
  const imports = Object.values(graph.metafile.inputs).flatMap(value => value.imports);
  assert.deepEqual(imports.map(value => [value.path, value.external]),
    [['@actql/sdk/_internal/source-preparation', true]]);
  assert(!Object.keys(graph.metafile.inputs).some(path => path.includes('/packages/sdk/')));
});

test('rewritten Core imports refuse missing dependency export or contradictory target metadata', async t => {
  for (const [name, change] of [
    ['local-node', value => { delete value.dependencies['@actql/sdk']; }],
    ['sdk', value => { delete value.exports['./_internal/source-preparation']; }],
    ['sdk', value => { value.exports['./_internal/source-preparation'] = './index.mjs'; }],
    ['sdk', value => { value.exports['./_internal/source-preparation'] = {types: './index.d.ts'}; }],
    ['sdk', value => { value.name = '@fixture/foreign'; }],
  ]) {
    const f = fixture(t);
    f.update(name, change);
    await assert.rejects(f.graph('../../packages/sdk/internal/private-source-preparation.mjs'),
      /UndeclaredLocalNodeDependency:@actql\/sdk\/_internal\/source-preparation/);
  }
});

test('package checks retain exact self optional-peer and undeclared run-host-core boundaries', async t => {
  const f = fixture(t);
  for (const specifier of ['@actql/sdk/host-port', '@actql/client-wire',
    '@actql/local-node/connector-installation', '@duckdb/node-api', '@duckdb/node-api/package.json']) {
    const graph = await f.graph(specifier, 'provider');
    assert(Object.values(graph.metafile.inputs).some(value =>
      value.imports.some(edge => edge.path === specifier && edge.external)));
  }
  for (const specifier of ['@actql/run-host-core', '@actql/local-node/runtime',
    '@actql/local-node/unknown', '@duckdb/node-api/lib/hidden.js']) {
    await assert.rejects(f.graph(specifier, 'provider'), /UndeclaredLocalNodeDependency/);
  }
  await assert.rejects(f.graph('../../packages/run-host-core/index.mjs'), /UndeclaredLocalNodeDependency/);
  f.update('local-node', value => { delete value.peerDependencies['@duckdb/node-api']; });
  await assert.rejects(f.graph('@duckdb/node-api'), /UndeclaredLocalNodeDependency/);
});

test('metadata recognition never hides cross-owner nonconcrete source or unlisted runtime edges', async t => {
  const f = fixture(t);
  f.put(join(f.core, 'adapters/host-node/helper.mjs'), 'export {};\n');
  const foreign = relative(dirname(f.providerProbe),
    join(f.core, 'packages/sdk/internal/private-source-preparation.mjs')).split(sep).join('/');
  await assert.rejects(f.graph(foreign, 'provider'), /CrossOwnerLocalNodeAdapterImport/);
  for (const specifier of ['@actql/sdk/unknown', '@actql/sdk/internal/private-source-preparation.mjs',
    '@actql/sdk/../index.mjs', '@actql/sdk/host-port?query', '@actql/sdk/host-port#fragment',
    'https://example.invalid/module.mjs']) {
    await assert.rejects(f.graph(specifier), /UndeclaredLocalNodeDependency/);
  }
  for (const specifier of ['./helper.mjs?query', './helper.mjs#fragment']) {
    await assert.rejects(f.graph(specifier), /NonconcreteLocalNodeAdapterImport/);
  }
  const runtime = join(f.core, '_build/js/release/build/unlisted/unlisted.js');
  f.put(runtime, 'export {};\n');
  await assert.rejects(f.graph(relative(dirname(f.coreProbe), runtime).split(sep).join('/')),
    /UndeclaredLocalNodeRuntime/);
  f.update('sdk', value => { value.exports['./host-port'] = '../outside.mjs'; });
  await assert.rejects(f.graph('@actql/sdk/host-port'), /UndeclaredLocalNodeDependency/);
});

test('canonical native asset rewriting remains exact and does not admit other checkout assets', () => {
  for (const arch of ['arm64', 'x64']) {
    assert.equal(rewriteLocalNodePackageImports(
      `require('../../packages/local-node/_build/native/directory-darwin-${arch}.node');`, 'probe.mjs'),
    `require('../../_build/native/directory-darwin-${arch}.node');`);
  }
  for (const asset of ['directory-original.json', 'directory-darwin-other.node', 'directory-darwin-arm64.node.js']) {
    assert.throws(() => rewriteLocalNodePackageImports(
      `require('../../packages/local-node/_build/native/${asset}');`, 'probe.mjs'), /UnpackagedLocalNodeImport/);
  }
});
