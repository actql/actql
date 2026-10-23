import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';

const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const host = ast.body.map(node => node.declaration ?? node).find(node =>
  node.type === 'FunctionDeclaration' && node.id.name === 'openInstalledHost');
const nodes = [];
function collect(node) {
  if (node === null || typeof node !== 'object') return;
  nodes.push(node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(collect);
    else if (value !== null && typeof value === 'object') collect(value);
  }
}
collect(host.body);
const selected = nodes.filter(node => node.type === 'VariableDeclaration' &&
  node.declarations.some(item => item.id.name === 'installationSourcePreparation'));
assert.equal(selected.length, 1);
const branch = nodes.filter(node => node.type === 'IfStatement' &&
  node.test.type === 'BinaryExpression' &&
  node.test.left.name === 'installationSourcePreparation');
assert.equal(branch.length, 1);
// Execute the actual Host selection and its post-await original fence. The
// factory, Account and runtime ports below are explicit stopping doubles;
// these tests establish neither a Source supplier nor a public Host success.
const assemble = compileFunction(`return (async () => {
  let sourceProfile;
  ${source.slice(selected[0].start, selected[0].end)}
  ${source.slice(branch[0].start, branch[0].end)}
  return sourceProfile;
})();`, ['preparation', 'moon', 'baseEnvironmentWire', 'authorization',
  'principalId', 'createLocalAuthorizationGate', 'loadInstalledSources',
  'selectedSourcePaths', 'root', 'runtimeUrl', 'resolveSourceSecret',
  'connectorTable', 'clientOperationError']);

function fixture(overrides = {}) {
  const f = {moon: {}, base: 'original environment', authorization: {},
    principal: 'original actor', paths: ['original live profile'],
    root: 'original root', runtime: {}, secret() {}, table: {}, ...overrides};
  f.run = preparation => assemble(preparation, f.moon, f.base, f.authorization,
    f.principal, f.gate, f.load, f.paths, f.root, f.runtime, f.secret, f.table,
    code => Object.assign(new Error(code), {code}));
  return f;
}

test('actual unselected Host keeps its original live Source installation path', async () => {
  const original = {}, f = fixture();
  f.gate = () => assert.fail('NoMockAccountGate');
  f.load = async (paths, options) => {
    assert.strictEqual(paths, f.paths);
    assert.deepEqual(options, {root: f.root, principalId: f.principal,
      moon: f.moon, runtimeUrl: f.runtime, baseEnvironmentWire: f.base,
      resolveSecret: f.secret, connectorTable: f.table});
    return original;
  };
  const preparation = {sourcePreparation: () => undefined,
    installMockSources() {assert.fail('NoMockSourceInstallation');}};
  assert.strictEqual(await f.run(preparation), original);
});

test('actual selected Host retains original Source factory and explicit Account inputs without live fallback', async () => {
  const original = {}, admission = {}, gate = {}, account = 'explicit account original';
  const f = fixture({authorization: {accountConfiguration: account}});
  let gates = 0;
  f.gate = async options => {
    gates++;
    assert.deepEqual(options, {accountConfiguration: account, principal: f.principal});
    return gate;
  };
  f.load = () => assert.fail('NoLiveSourceFallback');
  const preparation = {sourcePreparation: () => admission,
    async installMockSources(runtime, environment, authorizationFor) {
      assert.strictEqual(this, preparation);
      assert.strictEqual(runtime, f.moon);
      assert.equal(environment, f.base);
      assert.strictEqual(await authorizationFor('original connection'), gate);
      return original;
    }};
  assert.strictEqual(await f.run(preparation), original);
  assert.equal(gates, 1);
});

test('actual selected Host preserves missing Account refusal without adding a permission or live fallback', async () => {
  const marker = Object.freeze(new Error('OriginalMissingAccountStop'));
  const f = fixture({authorization: undefined});
  f.gate = async options => {
    assert.deepEqual(options, {principal: f.principal});
    throw marker;
  };
  f.load = () => assert.fail('NoLiveSourceFallback');
  const preparation = {sourcePreparation: () => preparation,
    async installMockSources(_runtime, _environment, authorizationFor) {
      await authorizationFor('original connection');
      assert.fail('NoSourceAfterAccountStop');
    }};
  await assert.rejects(f.run(preparation), error => error === marker);
});

test('actual selected Host refuses a changed original Source preparation after installation await', async () => {
  let original = {};
  const f = fixture();
  f.load = () => assert.fail('NoLiveSourceFallback');
  const preparation = {sourcePreparation: () => original,
    async installMockSources() {await Promise.resolve(); original = {}; return {};}};
  await assert.rejects(f.run(preparation), {code: 'InstalledSourcePreparationChanged'});
});
