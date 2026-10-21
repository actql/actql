import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Execute the actual Host callbacks with explicit original preparation and
// installation ports. This is not ordinary installed Host/Account acceptance.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const nodes = [];
function visit(node) {
  if (node === null || typeof node !== 'object') return;
  if (node.type) nodes.push(node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(visit);
    else if (value !== null && typeof value === 'object') visit(value);
  }
}
visit(tree.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'openInstalledHost'));
function originalProperty(variable, property) {
  const matches = nodes.filter(node => node.type === 'VariableDeclarator' && node.id.name === variable);
  assert.equal(matches.length, 1, variable);
  const value = matches[0].init;
  const call = value.type === 'ConditionalExpression' ? value.alternate : value;
  const selected = call.arguments[0].properties.filter(node => node.key.name === property);
  assert.equal(selected.length, 1, property);
  return source.slice(selected[0].value.start, selected[0].value.end);
}
const admission = originalProperty('submissionService', 'admitPreparedSubmission');
const definition = originalProperty('effectRun', 'prepareDefinition');

function fixture({installed = true, acquisitionCount = 0, selection} = {}) {
  const prepared = {}, compilation = {}, descriptor = Object.freeze({}), calls = [];
  const originalInstallation = Object.freeze({effects: Object.freeze([{}])});
  const currentFailure = new Error('OriginalLocalHostRetired');
  const ownerFailure = new Error('ForeignOriginalLocalEffect');
  let current = true, ownerCurrent = true;
  const preparation = {admitEffectResultPublicationRun(value) {
    assert.strictEqual(this, preparation);
    assert.strictEqual(value, prepared);
    if (!current) throw currentFailure;
    calls.push('result-purpose');
  }};
  const inferSelections = new WeakMap();
  if (selection !== undefined) inferSelections.set(prepared, selection);
  const clientOperationError = code => Object.assign(new Error(code), {code});
  const values = {preparation, requestOf() {return {requested: {}, acquisitionCount, effectful: true};},
    inferSelections, mockEffectObservation: undefined,
    localFileEffectInstallation: installed ? originalInstallation : undefined, clientOperationError,
    installedEffectFor(inventory, descriptors) {
      assert.strictEqual(inventory, originalInstallation);
      assert.strictEqual(descriptors, descriptor);
      calls.push('same-installation');
      if (!ownerCurrent) throw ownerFailure;
      return {assertPrepared(facts) {
        assert.strictEqual(facts.prepared, prepared);
        assert.strictEqual(facts.compilation, compilation);
        calls.push('checked-owner');
      }};
    },
    installedRowEffectDescriptors(moon, actual, compiled) {
      assert.strictEqual(moon, values.moon);
      assert.strictEqual(actual, prepared);
      assert.strictEqual(compiled, compilation);
      calls.push('typed-descriptors'); return descriptor;
    },
    moon: {}, sourceProfile: new Proxy({}, {get() {assert.fail('ordinary Local must not acquire a Mock Source scope');}}),
    retainMockEffectRunOriginal() {assert.fail('ordinary Local must not create a Mock file original');},
    earlyMockEffectPlans: new WeakMap()};
  const make = text => new Function(...Object.keys(values), `return (${text});`)(...Object.values(values));
  return {admit: make(admission), define: make(definition), prepared, compilation, calls,
    currentFailure, ownerFailure, revoke() {current = false;}, foreignOwner() {ownerCurrent = false;}};
}

test('ordinary Local STORE admits its actual Result purpose without a Mock observation', () => {
  const f = fixture();
  assert.equal(typeof f.admit, 'function');
  assert.equal(f.admit({preparedProgram: f.prepared}), undefined);
  assert.deepEqual(f.calls, ['result-purpose']);
});

test('winning ordinary Local definition selects the same actual installation without a Mock Scope', () => {
  const f = fixture();
  assert.equal(typeof f.define, 'function');
  assert.equal(f.define({prepared: f.prepared, compilation: f.compilation}), undefined);
  assert.deepEqual(f.calls, ['result-purpose', 'typed-descriptors', 'same-installation', 'checked-owner']);
});

test('ordinary Local admission refuses a missing installation or a different Source or Model purpose', () => {
  for (const options of [{installed: false}, {acquisitionCount: 1}, {acquisitionCount: 2},
    {selection: {localMock: true}}, {selection: {localMock: false}}]) {
    const f = fixture(options);
    assert.throws(() => f.admit({preparedProgram: f.prepared}), {code: 'HostEffectRunPreparationUnavailable'});
    assert.deepEqual(f.calls, []);
  }
  assert.equal(fixture({installed: false}).define, undefined);
});

test('ordinary Local callbacks preserve the same Result service refusal before publication', () => {
  const f = fixture(); f.revoke();
  assert.throws(() => f.admit({preparedProgram: f.prepared}), cause => cause === f.currentFailure);
  assert.throws(() => f.define({prepared: f.prepared, compilation: f.compilation}), cause => cause === f.currentFailure);
  assert.deepEqual(f.calls, []);
});

test('ordinary Local definition cannot substitute another installation owner for its compiled commands', () => {
  const f = fixture(); f.foreignOwner();
  assert.throws(() => f.define({prepared: f.prepared, compilation: f.compilation}), cause => cause === f.ownerFailure);
  assert.deepEqual(f.calls, ['result-purpose', 'typed-descriptors', 'same-installation']);
});
