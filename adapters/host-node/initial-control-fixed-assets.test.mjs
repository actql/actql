import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {compileFunction} from 'node:vm';
import test from 'node:test';
import {parse} from 'acorn';
import ownerModule from './initial-control-installation-owner.cjs';

const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const declaration = name => tree.body.map(node => node.declaration ?? node)
  .find(node => node.type === 'FunctionDeclaration' && node.id.name === name);
function find(node, predicate) {
  if (!node || typeof node !== 'object') return undefined;
  if (predicate(node)) return node;
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) {
      for (const child of value) {const result = find(child, predicate); if (result) return result;}
    } else if (value && typeof value === 'object') {const result = find(value, predicate); if (result) return result;}
  }
}
const opening = declaration('openInstalledHost'), connecting = declaration('openPreparedInstalledHost');
assert.ok(opening && connecting);
const preparationNode = find(connecting.body, node => node.type === 'VariableDeclarator' && node.id.name === 'preparation').init;
const assets = [
  {name: 'numericProfile', path: 'spec/contracts/actql-numeric-reduction.json'},
  {name: 'graphLaw', path: 'spec/dependencies/actql-graph-laws.json'},
  {name: 'registry', path: 'spec/dependencies/aoa-pipeline-registry.json'},
  {name: 'aoa', path: 'spec/contracts/actql-aoa.json'},
];
const statements = assets.map(asset => {
  const node = find(opening.body, node => asset.name === 'registry'
    ? node.type === 'ExpressionStatement' && node.expression.type === 'AssignmentExpression' && node.expression.left.name === 'registry'
    : node.type === 'VariableDeclaration' && node.declarations.some(value => value.id.name === asset.name));
  assert.ok(node, asset.name);
  return {...asset, statement: source.slice(node.start, node.end)};
});

// Execute the actual preparation constructor and fixed-asset Host statements,
// not another Host/issuer implementation. The operational callbacks are explicit
// fixtures in a real private Owner instance; no selected-runtime or funding
// positive is inferred from these source-expression component tests.
function fixture() {
  const originals = Object.freeze({host: {}, installation: {}, generation: {}, supplier() {}, moduleLifetime: {}});
  const wires = new Map(assets.map(asset => [asset.path, ' {"original":' + JSON.stringify(asset.path) + '} \n']));
  const reads = [];
  let current = true, closes = 0, onRead;
  const cause = Object.freeze(new Error('OriginalAssetCurrentRefused'));
  const operational = {assertCurrent(held) {
    assert.equal(this, operational);
    for (const key of Object.keys(originals)) assert.equal(held[key], originals[key]);
    if (!current) throw cause;
  }, readAsset(held, path) {
    assert.equal(this, operational); assert.equal(held.host, originals.host);
    assert.ok(wires.has(path)); reads.push(path); onRead?.(path);
    return wires.get(path);
  }, close() {assert.equal(this, operational); closes++; return {pending: false};}};
  const owner = ownerModule.createInitialControlInstallationOwner(operational), scope = owner.begin(originals);
  const construct = (control = scope, same = originals) => compileFunction(
    'let referenceRetirement;return ' + source.slice(preparationNode.start, preparationNode.end) + ';',
    ['host', 'initialControl', 'control', 'originals', 'readInitialControlInstallationAsset', 'clientOperationError'])
    (same.host, {}, control, same, owner.readAsset, code => Object.assign(new Error(code), {code}));
  return {originals, wires, reads, owner, scope, cause, construct,
    onRead(callback) {onRead = callback;}, stale() {current = false;}, get closes() {return closes;}};
}
function reader(asset, readFile = () => {assert.fail('Prepared asset must not reread its pathname');}) {
  return compileFunction('return async function(preparation){' +
    (asset.name === 'registry' ? 'let registry;' : '') + asset.statement + '\nreturn ' + asset.name + ';};',
    ['readFile', 'join', 'packageRoot'])(readFile, join, '/original-package');
}
const expected = (asset, wire) => asset.name === 'registry' ? wire : JSON.parse(wire);

test('prepared Host fixed assets use the same original Scope and captured bytes without pathname reads', async () => {
  const f = fixture(), preparation = f.construct();
  for (const asset of statements) assert.deepEqual(await reader(asset)(preparation), expected(asset, f.wires.get(asset.path)));
  assert.deepEqual(f.reads, assets.map(asset => asset.path));
  assert.equal((await f.scope.close()).pending, false); assert.equal(f.closes, 1);
});

test('missing captured fixed asset never falls back to a pathname and retains the original cleanup duty', async () => {
  for (const asset of statements) {
    const f = fixture(), record = {held: f.wires.get(asset.path)}, duty = f.scope.retainPreparation(record);
    const cause = Object.freeze(Object.assign(new Error('OriginalAssetUnavailable'), {cleanupHandle: {status() {return {pending: true};}}}));
    f.onRead(() => {throw cause;});
    await assert.rejects(reader(asset)(f.construct()), error => error === cause && error.cleanupHandle.status().pending);
    assert.equal((await f.scope.close()).pending, true); assert.equal(f.closes, 0);
    record.held = undefined; duty.releaseReferences(record);
    assert.equal((await f.scope.close()).pending, false); assert.equal(f.closes, 1);
  }
});

test('copied foreign and changed original pairs refuse before every captured fixed asset read', async () => {
  const f = fixture();
  const pairs = [[{}, f.originals], [{...f.scope}, f.originals],
    ...Object.keys(f.originals).map(key => [f.scope, {...f.originals, [key]: {}}])];
  for (const [scope, originals] of pairs) for (const asset of statements) {
    await assert.rejects(reader(asset)(f.construct(scope, originals)), {code: 'NodeInitialControlOriginalChanged'});
  }
  assert.deepEqual(f.reads, []); assert.equal((await f.scope.close()).pending, false);
});

test('current refusal after a fixed asset callback preserves the same original pending custody', async () => {
  const f = fixture(), record = {original: f.wires}, duty = f.scope.retainPreparation(record);
  f.onRead(() => f.stale());
  await assert.rejects(reader(statements[0])(f.construct()), error => error === f.cause);
  assert.equal(f.reads.length, 1); assert.equal((await f.scope.close()).pending, true); assert.equal(f.closes, 0);
  record.original = undefined; duty.releaseReferences(record);
  assert.equal((await f.scope.close()).pending, false);
});

test('a retired preparation cannot borrow any fixed asset after its same original close', async () => {
  const f = fixture(), preparation = f.construct();
  assert.equal((await f.scope.close()).pending, false);
  for (const asset of statements) await assert.rejects(reader(asset)(preparation), {code: 'NodeInitialControlOriginalChanged'});
  assert.deepEqual(f.reads, []); assert.equal(f.closes, 1);
});

test('independent unprepared Host keeps the four original physical path reads and exact bytes', async () => {
  const f = fixture(), paths = [];
  for (const asset of statements) {
    const read = reader(asset, async (path, encoding) => {
      assert.equal(path, join('/original-package', asset.path)); assert.equal(encoding, 'utf8');
      paths.push(path); return f.wires.get(asset.path);
    });
    assert.deepEqual(await read(undefined), expected(asset, f.wires.get(asset.path)));
  }
  assert.equal(paths.length, 4); assert.deepEqual(f.reads, []);
  assert.equal((await f.scope.close()).pending, false);
});
