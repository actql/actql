import assert from 'node:assert/strict';
import {existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync,
  rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {initRestConnector, projectRestConnector, writeRestConnector} from './connector-authoring.mjs';
import {connectorCommand} from './connector.mjs';
import {resolveConnectorBuildInputs} from './connector-build-inputs.mjs';
import {checkHostBundle, generateInstallations} from './connector-host-bundles.mjs';
import {checkNodeAssembly} from './connector-node-bundles.mjs';
import {localNodePackageInputs} from './local-node-package-inputs.mjs';
import {localNodeAdapterSourceInputs} from './build-local-node-adapters.mjs';

function fixture(t) {
  const root = mkdtempSync(join(realpathSync(tmpdir()), 'actql-rest-author-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const input = initRestConnector(join(root, 'author'), 'acme');
  const definition = JSON.parse(readFileSync(input, 'utf8'));
  const output = join(root, 'package');
  const put = (path, value) => { mkdirSync(dirname(path), {recursive: true}); writeFileSync(path, value); };
  const build = () => writeRestConnector({definitionPath: input, outputRoot: output});
  return {root, input, output, definition, put, build};
}

test('one author definition projects original closed Host and SourceViews without a MoonBit package', t => {
  const f = fixture(t), original = readFileSync(f.input, 'utf8'), report = f.build();
  const host = JSON.parse(readFileSync(join(f.output, 'src/connectors/acme/host-bundle.json')));
  assert.deepEqual(host.installation, {registration: 'acme', revision: 'acme/0.1',
    responseHeaders: [], assets: ['src/connectors/acme/rest-source.json', 'src/connectors/acme/source-views.json'],
    source: {profileVersion: 'actql-installed-acme-rest-source/0.1',
      module: 'adapters/connectors/acme/host/installation.mjs',
      exports: {check: 'checkProfile', identityParts: 'identityParts', publish: 'publish', load: 'load'}}});
  assert.deepEqual(JSON.parse(readFileSync(join(f.output, 'src/connectors/acme/source-views.json'))),
    {views: [{resource: 'records', resource_kind: 'record', fields: [{name: 'id', type: 'string', nullable: false}]}]});
  assert.equal(checkHostBundle(f.output, 'acme', join(f.output, 'src/connectors/acme/host-bundle.json')).providerBundle, undefined);
  assert.equal(readFileSync(f.input, 'utf8'), original);
  assert.deepEqual(report.authorFiles, ['connector.json']);
  assert.equal(report.customMoonBitPackages, 0);
  assert.equal(existsSync(join(f.output, 'moon.mod')), false);
  assert.equal(report.runtimeExecuted, false);
  assert.doesNotMatch(readFileSync(join(f.output, 'adapters/connectors/acme/host/installation.mjs'), 'utf8'),
    /Ledger|NodeManagedRunAdmission|PreparationCapacity|RunCheck|reserve_capacity|clientProgramNode|requestStop|cleanupConfirmed/);
});

test('author projection retains exact typed field DATA and optional one-file response transform', t => {
  const f = fixture(t);
  const fields = [{name: 'id', type: 'string', nullable: false},
    {name: 'e\u0301', type: 'decimal', precision: 38, scale: 10, nullable: true}];
  f.definition.sources.records.fields = fields;
  f.definition.transform = 'transform.mjs';
  writeFileSync(f.input, JSON.stringify(f.definition));
  const transform = 'export function decodePage(body) { return {rows: body.records, next: null}; }\n';
  f.put(join(dirname(f.input), 'transform.mjs'), transform);
  const report = f.build();
  assert.deepEqual(report.authorFiles, ['connector.json', 'transform.mjs']);
  assert.equal(readFileSync(join(f.output, 'adapters/connectors/acme/host/transform.mjs'), 'utf8'), transform);
  assert.deepEqual(JSON.parse(readFileSync(join(f.output, 'src/connectors/acme/source-views.json'))).views[0].fields, fields);
  const projected = projectRestConnector(f.definition);
  assert(Object.isFrozen(projected));
  assert.throws(() => { projected.manifest.installation.registration = 'other'; }, TypeError);
});

test('fixed origin request and pagination wiring reject dynamic authority or lifecycle knobs', t => {
  const f = fixture(t);
  const bad = [];
  for (const origin of ['http://api.example.invalid', 'https://user:secret@api.example.invalid',
    'https://api.example.invalid/path']) bad.push({...f.definition, origin});
  for (const path of ['//other.invalid/records', '/v1/../secret', '/v1/%2e%2e/secret',
    '/v1/records?url=other', '/v1\\records']) {
    const d = structuredClone(f.definition); d.sources.records.read.path = path; bad.push(d);
  }
  for (const key of ['capacity', 'Ledger', 'cleanupConfirmed', 'credential']) {
    bad.push({...f.definition, [key]: true});
  }
  const d = structuredClone(f.definition); d.sources.records.pagination.items = ['__proto__']; bad.push(d);
  for (const value of bad) assert.throws(() => projectRestConnector(value), /InvalidRestConnectorDefinition/);
  assert.equal(projectRestConnector(f.definition).manifest.installation.registration, 'acme');
});

test('existing author commands scaffold once and freshness check refuses stale output', t => {
  const f = fixture(t);
  assert.throws(() => initRestConnector(dirname(f.input), 'acme'), /nonempty scaffold/);
  const report = connectorCommand(['build', f.input, f.output]);
  assert.equal(report.runtimeExecuted, false);
  assert.deepEqual(connectorCommand(['test', f.input, f.output]), report);
  const path = join(f.output, 'src/connectors/acme/source-views.json');
  writeFileSync(path, '{}\n');
  assert.throws(() => connectorCommand(['test', f.input, f.output]), /StaleRestConnectorProjection/);
  assert.equal(readFileSync(path, 'utf8'), '{}\n');
  assert.throws(() => connectorCommand(['test', f.input]), /Usage:/);
});

function packageFixture(t) {
  const f = fixture(t); f.build();
  const core = join(f.root, 'core'), host = join(f.root, 'host');
  f.put(join(core, 'moon.mod'), 'name = "actql/actql"\nversion = "0.0.1"\nsource = "src"\n');
  mkdirSync(join(core, 'src'));
  f.put(join(core, 'packages/local-node/package.json'), JSON.stringify({name: '@actql/local-node', version: '0.0.0-development'}));
  f.put(join(host, 'moon.mod'), 'name = "example/host"\nversion = "0.0.1"\nsource = "src"\nimport { "actql/actql@0.0.1", }\n');
  mkdirSync(join(host, 'src'));
  const configuration = {target: 'js', modules: [
    {namespace: 'actql/actql', version: '0.0.1', root: core},
    {namespace: 'example/host', version: '0.0.1', root: host}], host: 'example/host',
    packages: [{name: '@actql-connectors/acme', version: '0.0.1', root: f.output}],
    connectors: [{name: 'acme', package: '@actql-connectors/acme', directory: 'src/connectors/acme'}]};
  return {...f, core, host, configuration};
}

test('generated npm-only REST installation reaches the actual normal Host copy graph without a provider compiler', async t => {
  const f = fixture(t);f.build();
  const core = fileURLToPath(new URL('../', import.meta.url)), host = join(f.root, 'host');
  f.put(join(host, 'moon.mod'), 'name = "fixture/rest_host"\nversion = "0.0.1"\n' +
    'source = "src"\nimport { "actql/actql@0.0.1", }\n');
  mkdirSync(join(host, 'src'), {recursive: true});
  const buildInputs = resolveConnectorBuildInputs({target: 'js', modules: [
    {namespace: 'actql/actql', version: '0.0.1', root: core},
    {namespace: 'fixture/rest_host', version: '0.0.1', root: host}], host: 'fixture/rest_host',
    packages: [{name: '@actql-connectors/acme', version: '0.0.1', root: f.output}],
    connectors: [{name: 'acme', package: '@actql-connectors/acme', directory: 'src/connectors/acme'}]});
  // Existing generation and packaging graph only: no compiler, prepack,
  // runtime module import, Site, Account or public operation is executed.
  checkNodeAssembly(host, true, {buildInputs, installations: true});
  const inputs = localNodePackageInputs(host, {buildInputs});
  assert.deepEqual(inputs.providerBundles, []);
  assert.equal(inputs.runtimeInputs.some(input => input.moduleRoot === f.output), false);
  const copies = await localNodeAdapterSourceInputs({root: host, inputs});
  for (const path of ['adapters/host-node/installed-rest-source.mjs',
    'adapters/host-node/rest-source-metadata.mjs', 'adapters/host-node/rest-source-page.mjs',
    'adapters/host-node/installed-host-services.mjs', 'adapters/host-node/installed-credential-source-reader.mjs',
    'adapters/connectors/acme/host/installation.mjs']) {
    assert.equal(copies.filter(input => input.path === path).length, 1, path);
  }
  const table = inputs.installationTable.render(join(host, 'package'));
  assert.match(table, /registration: "acme"/u);
  assert.doesNotMatch(table, /providerBundle/u);
  const api = readFileSync(join(core, 'packages/local-node/connector-installation.mjs'), 'utf8');
  assert.match(api, /export \{createInstalledRestSource\} from\s+'\.\/adapters\/host-node\/installed-rest-source\.mjs'/u);
  assert.equal(existsSync(join(f.output, 'moon.mod')), false);
});

test('same external resolver accepts an explicitly pinned npm-only Source contribution', t => {
  const f = packageFixture(t), resolved = resolveConnectorBuildInputs(f.configuration);
  assert.equal(resolved.hostEntries.length, 1);
  assert.equal(resolved.hostEntries[0].providerBundle, undefined);
  assert.deepEqual(resolved.computeEntries, []);
  assert.deepEqual(resolved.nodeEntries, []);
  assert.equal(resolved.modules.filter(x => x.kind === 'npm').length, 1);
  const generated = generateInstallations(resolved.hostEntries,
    join(f.host, 'adapters/installed.mjs'), f.host);
  assert.match(generated, /registration: "acme"/);
  assert.doesNotMatch(generated, /providerBundle/);
  assert.equal(existsSync(join(f.output, 'moon.mod')), false);
  assert.deepEqual(readdirSync(f.output).sort(), ['adapters', 'package.json', 'src']);
});

test('npm-only contribution keeps original ownership and pinned Host dependency refusals', t => {
  const f = packageFixture(t), packagePath = join(f.output, 'package.json');
  const original = JSON.parse(readFileSync(packagePath));
  for (const change of [{name: '@other/acme'}, {version: '9.0.0'},
    {peerDependencies: {'@actql/local-node': '*'}}, {dependencies: {yaml: '1.0.0'}},
    {scripts: {install: 'node hidden.mjs'}}]) {
    writeFileSync(packagePath, JSON.stringify({...original, ...change}));
    assert.throws(() => resolveConnectorBuildInputs(f.configuration), /identity or Host dependency/);
  }
  writeFileSync(packagePath, JSON.stringify(original));
  f.put(join(f.output, 'moon.mod'), 'name = "hidden/module"\n');
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /Ambiguous/);
  rmSync(join(f.output, 'moon.mod'));
  const alias = join(f.root, 'alias'); symlinkSync(f.output, alias);
  assert.throws(() => resolveConnectorBuildInputs({...f.configuration,
    packages: [{...f.configuration.packages[0], root: alias}]}), /aliased/);
  assert.throws(() => resolveConnectorBuildInputs({...f.configuration,
    packages: [{...f.configuration.packages[0], root: f.core}]}), /overlapping/);
});

test('npm-only route cannot disguise a compiled provider or inject an undeclared role', t => {
  const f = packageFixture(t), path = join(f.output, 'src/connectors/acme/host-bundle.json');
  const original = JSON.parse(readFileSync(path));
  writeFileSync(path, JSON.stringify({installation: {...original.installation,
    providerBundle: 'connectors/acme/host_node'}}));
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /cannot select a MoonBit/);
  writeFileSync(path, JSON.stringify(original));
  f.put(join(f.output, 'src/connectors/acme/compute-bundle.json'), '{}');
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /cannot select a MoonBit/);
  rmSync(join(f.output, 'src/connectors/acme/compute-bundle.json'));
  writeFileSync(path, JSON.stringify({installation: {...original.installation, source:
    {...original.installation.source, module: '../outside.mjs'}}}));
  assert.throws(() => resolveConnectorBuildInputs(f.configuration), /module/);
});


test('projection refuses ancestor and dangling output links before writing any generated file', t => {
  const f = fixture(t), physical = join(f.root, 'physical'), alias = join(f.root, 'alias');
  mkdirSync(physical); symlinkSync(physical, alias);
  assert.throws(() => writeRestConnector({definitionPath: f.input, outputRoot: join(alias, 'new')}), /aliased output/);
  assert.deepEqual(readdirSync(physical), []);
  mkdirSync(f.output);
  symlinkSync(join(f.root, 'not-created'), join(f.output, 'src'));
  assert.throws(f.build, /aliased output/);
  assert.equal(existsSync(join(f.output, 'package.json')), false);
  assert.equal(existsSync(join(f.root, 'not-created')), false);
});

test('optional transform copying refuses an original-path alias', t => {
  const f = fixture(t), original = join(f.root, 'original.mjs');
  writeFileSync(original, 'export function decodePage() { throw new Error("not executed"); }\n');
  symlinkSync(original, join(dirname(f.input), 'transform.mjs'));
  f.definition.transform = 'transform.mjs'; writeFileSync(f.input, JSON.stringify(f.definition));
  assert.throws(f.build, /aliased transform/);
  assert.equal(existsSync(f.output), false);
});


test('a single-page root-array API needs no fictional cursor declaration', t => {
  const f = fixture(t); f.definition.sources.records.pagination = {kind: 'none', items: []};
  const projection = projectRestConnector(f.definition);
  const body = JSON.parse(projection.files['src/connectors/acme/rest-source.json']);
  assert.deepEqual(body.sources[0].pagination, {kind: 'none', items: []});
  assert.equal(Object.hasOwn(body.sources[0].pagination, 'next'), false);
  f.definition.sources.records.pagination.next = ['not-admitted'];
  assert.throws(() => projectRestConnector(f.definition), /InvalidRestConnectorDefinition:pagination/);
});
