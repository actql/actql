import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import ownerModule from './initial-control-installation-owner.cjs';

const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const declaration = name => tree.body.map(node => node.declaration ?? node)
  .find(node => node.type === 'FunctionDeclaration' && node.id.name === name);
const variable = (body, name) => body.body.flatMap(node =>
  node.type === 'TryStatement' ? node.block.body : [node]).find(node =>
  node.type === 'VariableDeclaration' && node.declarations.some(value => value.id.name === name));
const opening = declaration('openInstalledHost');
assert.ok(opening);
const environmentSource = variable(opening.body, 'environmentSource');
const selectedLookupPolicy = variable(opening.body, 'selectedLookupPolicy');
const environmentWire = variable(opening.body, 'baseEnvironmentWire');
assert.ok(environmentSource && selectedLookupPolicy && environmentWire);
const entryGuard = opening.body.body[0];
assert.equal(entryGuard.type, 'IfStatement');
const connecting = declaration('openPreparedInstalledHost');
assert.ok(connecting);
const preparation = variable(connecting.body, 'preparation').declarations[0].init;
assert.equal(source.slice(preparation.callee.start, preparation.callee.end), 'Object.freeze');
const method = preparation.arguments[0].properties.find(node => node.key.name === 'readEnvironmentSource');
assert.ok(method?.method && method.value.params.length === 0);

// Execute only the exact actual Host routing expressions with explicit ports.
// This does not load a Common runtime or issue the selected preload admission.
// The real private Owner below tests original scope/current/custody semantics;
// its test instance cannot add membership to the operational preload instance.
function route({scope, originals, readAsset, select = (moon, wire) => wire,
  selectRemote = (moon, wire) => wire} = {}) {
  const readEnvironmentSource = compileFunction(
    'return function () {' + source.slice(method.value.body.start + 1, method.value.body.end - 1) + '};',
    ['readInitialControlInstallationAsset', 'control', 'originals'],
  )(readAsset, scope, originals);
  const read = compileFunction('return async function (preparation, moon, hostCapacityPolicy, hostLookupExecutionPolicy, mode = "local", effectInstallation, selectedEffectPaths = []) {' +
    source.slice(entryGuard.start, entryGuard.end) + '\n' +
    source.slice(environmentSource.start, environmentSource.end) + '\n' +
    source.slice(selectedLookupPolicy.start, selectedLookupPolicy.end) + '\n' +
    source.slice(environmentWire.start, environmentWire.end) + '\nreturn baseEnvironmentWire;};',
  ['selectInstalledLocalMaterializationEnvironment', 'selectInstalledHostEnvironment'])(select, selectRemote);
  return {preparation: Object.freeze({readEnvironmentSource,
    fundedPreparation() {assert.fail('No Request compile in this routing component');},
    requestPreparation() {assert.fail('No Request issuance in this routing component');}}), read};
}

function fixture() {
  const originals = Object.freeze({host: {}, installation: {}, generation: {}, supplier() {}, moduleLifetime: {}});
  const source = ' {"original":"environment"} \n';
  let current = true, assetReads = 0, closes = 0, onRead;
  const refused = Object.freeze(new Error('OriginalCurrentRefused'));
  const root = {assertCurrent(held) {
    assert.equal(this, root);
    for (const name of Object.keys(originals)) assert.equal(held[name], originals[name]);
    if (!current) throw refused;
  }, readAsset(held, path) {
    assert.equal(this, root); assert.equal(held.host, originals.host);
    assert.equal(path, 'spec/local-check-environment.json');
    assetReads++; onRead?.(); return source;
  }, close() {assert.equal(this, root); closes++; return {pending: false};}};
  const owner = ownerModule.createInitialControlInstallationOwner(root), scope = owner.begin(originals);
  return {originals, source, owner, scope, refused,
    onRead(value) {onRead = value;}, stale() {current = false;},
    get assetReads() {return assetReads;}, get closes() {return closes;}};
}

test('prepared Host routes the exact original image and original runtime/policies without a pathname read', async () => {
  const f = fixture(), moon = {}, capacity = {}, lookup = {};
  let selected = 0;
  const r = route({...f, readAsset: f.owner.readAsset, select(runtime, wire, actualCapacity, actualLookup) {
    selected++; assert.equal(runtime, moon); assert.equal(actualCapacity, capacity); assert.equal(actualLookup, lookup);
    assert.equal(wire, f.source.trimEnd()); return wire;
  }});
  assert.equal(await r.read(r.preparation, moon, capacity, lookup), f.source.trimEnd());
  assert.equal(selected, 1); assert.equal(f.assetReads, 1);
  assert.equal((await f.scope.close()).pending, false);
});

test('prepared Host has no pathname fallback when its original asset is unavailable', async () => {
  const failure = Object.freeze(Object.assign(new Error('OriginalAssetUnavailable'),
    {code: 'NodeInitialControlAssetUnavailable'}));
  let reads = 0, selections = 0;
  const r = route({readAsset() {reads++; throw failure;}, select() {selections++;}});
  await assert.rejects(r.read(r.preparation, {}, {}, {}), error => error === failure);
  assert.equal(reads, 1); assert.equal(selections, 0);
});

test('foreign or copied scope and each changed original refuse before environment selection', async () => {
  const f = fixture();
  const cases = [[{}, f.originals], [{...f.scope}, f.originals],
    ...Object.keys(f.originals).map(name => [f.scope, {...f.originals, [name]: {}}])];
  for (const [scope, originals] of cases) {
    const r = route({scope, originals, readAsset: f.owner.readAsset,
      select() {assert.fail('No selection of foreign originals');}});
    await assert.rejects(r.read(r.preparation, {}, {}, {}),
      {code: 'NodeInitialControlOriginalChanged'});
  }
  assert.equal(f.assetReads, 0);
  assert.equal((await f.scope.close()).pending, false);
});

test('current refusal after the original asset callback retains the same preparation custody', async () => {
  const f = fixture(), record = {}, duty = f.scope.retainPreparation(record);
  f.onRead(() => f.stale());
  const r = route({...f, readAsset: f.owner.readAsset,
    select() {assert.fail('No selection after original current refusal');}});
  await assert.rejects(r.read(r.preparation, {}, {}, {}), error => error === f.refused);
  assert.equal(f.assetReads, 1);
  assert.equal((await f.scope.close()).pending, true);
  assert.equal(f.closes, 0);
  duty.releaseReferences(record);
  assert.equal((await f.scope.close()).pending, false);
  assert.equal(f.closes, 1);
});

test('closing during the original read refuses handoff without acknowledging the remaining duty', async () => {
  const f = fixture(), record = {}, duty = f.scope.retainPreparation(record);
  let closing;
  f.onRead(() => {closing = f.scope.close();});
  const r = route({...f, readAsset: f.owner.readAsset,
    select() {assert.fail('No selection after reentrant close');}});
  await assert.rejects(r.read(r.preparation, {}, {}, {}),
    {code: 'NodeInitialControlOriginalChanged'});
  assert.equal((await closing).pending, true);
  assert.equal(f.closes, 0);
  duty.releaseReferences(record);
  assert.equal((await f.scope.close()).pending, false);
  assert.equal(f.closes, 1);
});

test('installed environment rejects an absent preparation owner before asset or pathname work', async () => {
  let assets = 0, selections = 0;
  const r = route({readAsset() {assets++;}, select() {selections++;}});
  await assert.rejects(r.read(undefined, {}, {}, {}), /InstalledRequestPreparationUnavailable/u);
  assert.equal(assets, 0); assert.equal(selections, 0);
});


test('Remote supplied Effect environment retains the original generic selector before publication composition', async () => {
  const f = fixture(), moon = {}, policy = {}, lookup = {}, selected = {};
  let selections = 0;
  const r = route({...f, readAsset: f.owner.readAsset,
    select() {assert.fail('A Remote Host must not replace published policy with Local row materialization');},
    selectRemote(runtime, wire, capacity, lookupPolicy) {
      selections++;
      assert.strictEqual(runtime, moon); assert.equal(wire, f.source.trimEnd());
      assert.strictEqual(capacity, policy); assert.strictEqual(lookupPolicy, lookup);
      return selected;
    }});
  assert.strictEqual(await r.read(r.preparation, moon, policy, lookup, 'remote', Object.freeze({environmentWire: 'original published Effect'})), selected);
  assert.equal(selections, 1); assert.equal(f.assetReads, 1);
  assert.equal((await f.scope.close()).pending, false);
});


test('Remote ordinary materialization retains its original Local selector without an independent Effect', async () => {
  const f = fixture(), moon = {}, policy = {}, lookup = {}, selected = {};
  let selections = 0;
  const r = route({...f, readAsset: f.owner.readAsset,
    select(runtime, wire, capacity, lookupPolicy) {
      selections++;
      assert.strictEqual(runtime, moon); assert.equal(wire, f.source.trimEnd());
      assert.strictEqual(capacity, policy); assert.strictEqual(lookupPolicy, lookup);
      return selected;
    }, selectRemote() {assert.fail('An ordinary Remote caller retains the installed Local materialization selector');}});
  assert.strictEqual(await r.read(r.preparation, moon, policy, lookup, 'remote'), selected);
  assert.equal(selections, 1); assert.equal(f.assetReads, 1);
  assert.equal((await f.scope.close()).pending, false);
});


test('profile-loaded Effects preserve their published generic policy on Local and Remote Hosts', async () => {
  for (const mode of ['local', 'remote']) {
    const f = fixture(), moon = {}, capacity = {}, lookup = {}, selected = {};
    let selections = 0;
    const r = route({...f, readAsset: f.owner.readAsset,
      select() {assert.fail('Loading a published Effect must not select a different Local row policy');},
      selectRemote(runtime, wire, originalCapacity, originalLookup) {
        selections++;
        assert.strictEqual(runtime, moon); assert.equal(wire, f.source.trimEnd());
        assert.strictEqual(originalCapacity, capacity); assert.strictEqual(originalLookup, lookup);
        return selected;
      }});
    assert.strictEqual(await r.read(r.preparation, moon, capacity, lookup, mode, undefined,
      Object.freeze(['/original-effect-profile.json'])), selected);
    assert.equal(selections, 1); assert.equal(f.assetReads, 1);
    assert.equal((await f.scope.close()).pending, false);
  }
});
