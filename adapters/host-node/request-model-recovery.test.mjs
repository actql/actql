import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Execute the actual recovery/material/binding methods with explicit Core
// ports. Real nominal reservation/current/cleanup controls live in the paired
// Core WB; these ports cannot grant Model IO or a saved Run.
const source = readFileSync(new URL('./ordinary-source-managed.mjs', import.meta.url), 'utf8');
const names = ['restoreModelOriginal', 'prepareModelMaterials', 'prepareModelBinding'];
const selected = [];
function visit(value) {
  if (value === null || typeof value !== 'object') return;
  if (value.type === 'Property' && value.method && names.includes(value.key.name)) selected.push(value);
  for (const child of Object.values(value)) {
    if (Array.isArray(child)) child.forEach(visit); else if (child && typeof child === 'object') visit(child);
  }
}
visit(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
assert.equal(selected.length, names.length);
const helpers = source.slice(source.indexOf('  function constructRequestDomain('),
  source.indexOf('  function registerRequestRun('));
const methods = selected.map(node => source.slice(node.start, node.end)).join(',');
const fail = code => {throw Object.assign(new Error(code), {code});};
function fixture({reserveFailure, constructFailure} = {}) {
  const request = {}, identity = {}, definition = {wire: 'definition'}, parent = {}, receipt = {};
  const restored = {prepared: {}, compiled: {}, graph: {}, runDefinition: definition};
  const original = {materialsWire: 'saved', resultPolicyOriginal: {wire: 'policy'}};
  const calls = [], binding = {}, bindings = [];
  let active = true;
  const state = {parent, context: {}, recovery: {request: identity, definition, assertCurrent() {
    calls.push('original current'); if (!active) fail('OriginalRecoveryRetired');
  }}};
  const producer = {receipt, request, preparation: state};
  const control = {
    reserveCheckedClientRequestModelRecoveryMaterials(p, input, r, d, count, wireAt, containers) {
      assert.equal(this, control); assert.deepEqual([p, input, r, d], [parent, receipt, identity, definition]);
      calls.push({reserve: Array.from({length: count}, (_, i) => wireAt(i)), containers});
      if (reserveFailure !== undefined) throw reserveFailure;
    },
  };
  const moon = state.context.runtime = {
    clientProgramModelProviderBinding(id, installation, contract, configuration) {
      const value = bindings.length === 0 ? binding : {};
      bindings.push(value);
      calls.push({binding: [id, installation, contract, configuration]}); return value;
    },
  };
  const api = Function('current', 'producerForRequest', 'fail', 'checked', 'runtimeCore',
    helpers + `return ({${methods}});`)(() => {}, actual => {
      assert.equal(actual, request); return producer;
    }, fail, value => value, actual => {
      assert.equal(actual, moon); return {publicationControl: control};
    });
  let constructed = 0;
  const restore = () => api.restoreModelOriginal(request, original, definition, identity, () => {
    constructed++; calls.push('original reader'); if (constructFailure !== undefined) throw constructFailure;
    return restored;
  });
  return {api, restore, calls, state, producer, request, identity, definition, restored, binding, bindings,
    constructed: () => constructed, revoke: () => {active = false;}};
}
test('saved original and both material constructors reserve on one restoration parent without fresh compilation', () => {
  const f = fixture();
  assert.equal(f.restore(), f.restored);
  assert.equal(f.state.prepared, f.restored.prepared);
  f.api.prepareModelMaterials(f.restored.prepared, f.request, 2, i => ['prompt', 'retry'][i], 4);
  assert.equal(f.api.prepareModelBinding(f.restored.prepared, f.request,
    'provider', 'installation', 'contract', 'configuration'), f.binding);
  assert.deepEqual(f.calls.filter(value => typeof value === 'object'), [
    {reserve: ['saved', 'policy', 'definition'], containers: 3},
    {reserve: ['prompt', 'retry'], containers: 4},
    {reserve: ['installation', 'contract', 'configuration'], containers: 3},
    {binding: ['provider', 'installation', 'contract', 'configuration']},
  ]);
  assert.equal(f.constructed(), 1);
  assert.throws(f.restore, {code: 'ForeignInstalledSourceProducer'});
  assert.throws(() => f.api.prepareModelMaterials({}, f.request, 0, () => '', 0),
    {code: 'ForeignInstalledSourceProducer'});
  assert.throws(() => f.api.prepareModelBinding({}, f.request,
    'provider', 'installation', 'contract', 'configuration'), {code: 'ForeignInstalledSourceProducer'});
});
test('restored Model occurrences retain distinct bindings funded by the same original recovery', () => {
  const f = fixture(); f.restore();
  const first = f.api.prepareModelBinding(f.restored.prepared, f.request,
    'first', 'installation-1', 'contract-1', 'configuration-1');
  const second = f.api.prepareModelBinding(f.restored.prepared, f.request,
    'second', 'installation-2', 'contract-2', 'configuration-2');
  assert.notEqual(first, second);
  assert.deepEqual(f.bindings, [first, second]);
  assert.deepEqual(f.calls.filter(value => typeof value === 'object'), [
    {reserve: ['saved', 'policy', 'definition'], containers: 3},
    {reserve: ['installation-1', 'contract-1', 'configuration-1'], containers: 3},
    {binding: ['first', 'installation-1', 'contract-1', 'configuration-1']},
    {reserve: ['installation-2', 'contract-2', 'configuration-2'], containers: 3},
    {binding: ['second', 'installation-2', 'contract-2', 'configuration-2']},
  ]);
  assert.equal(f.state.prepared, f.restored.prepared);
  assert.equal(f.state.recovery.restored, f.restored);
  assert.equal(f.constructed(), 1);
});
test('a later restored binding preserves current refusal and the already returned original', () => {
  const f = fixture(); f.restore();
  const first = f.api.prepareModelBinding(f.restored.prepared, f.request,
    'first', 'installation-1', 'contract-1', 'configuration-1');
  f.revoke();
  const next = () => f.api.prepareModelBinding(f.restored.prepared, f.request,
    'second', 'installation-2', 'contract-2', 'configuration-2');
  assert.throws(next, {code: 'OriginalRecoveryRetired'});
  assert.throws(next, {code: 'OriginalRecoveryRetired'});
  assert.deepEqual(f.bindings, [first]);
  assert.equal(f.state.modelProviderBinding, first);
  assert.equal(f.state.recovery.restored, f.restored);
});
test('original reservation and reader failures latch without a second constructor or substituted preparation', () => {
  for (const kind of ['reserveFailure', 'constructFailure']) {
    const primary = new Error('same original ' + kind), f = fixture({[kind]: primary});
    assert.throws(f.restore, cause => cause === primary);
    assert.throws(f.restore, cause => cause === primary);
    assert.equal(f.constructed(), kind === 'reserveFailure' ? 0 : 1);
    assert.equal(f.state.prepared, undefined);
  }
});
test('restoration current refusal stops later binding without replacing the restored original', () => {
  const f = fixture(); f.restore(); f.revoke();
  assert.throws(() => f.api.prepareModelMaterials(f.restored.prepared, f.request, 1, () => 'prompt', 1),
    {code: 'OriginalRecoveryRetired'});
  assert.throws(() => f.api.prepareModelBinding(f.restored.prepared, f.request,
    'provider', 'installation', 'contract', 'configuration'), {code: 'OriginalRecoveryRetired'});
  assert.equal(f.state.recovery.restored, f.restored);
  assert.equal(f.calls.filter(value => value?.binding).length, 0);
});

test('the same current callback cannot revive a retired restoration or replace its alias', () => {
  for (const retire of [f => {f.producer.finished = true;}, f => {f.state.recovery = undefined;}]) {
    const f = fixture(); f.restore();
    f.state.recovery.assertCurrent = () => retire(f);
    assert.throws(() => f.api.prepareModelMaterials(f.restored.prepared, f.request, 1, () => 'prompt', 1),
      {code: 'ForeignInstalledSourceProducer'});
    assert.equal(f.constructed(), 1);
    assert.equal(f.calls.filter(value => value?.binding).length, 0);
  }
});

test('same recovery finish waits for its actual dispatch reclamation before original Request abort', () => {
  const begin = source.indexOf('    finishSourceProducer(');
  const end = source.indexOf('    beforeResultRead()', begin);
  assert(begin >= 0 && end > begin);
  const receipt = {}, state = {recovery: {childrenPending: () => pending}};
  const producer = {receipt, preparation: state, liveRuns: 0};
  const producers = new Set([producer]), calls = [];
  let pending = true;
  const api = Function('producerFor', 'fail', 'cleanupRequestInput', 'retireInitialPreparation',
    'producers', 'releaseFinishedProducer', `return ({${source.slice(begin, end).trim().replace(/,$/u, '')}});`)(
    actual => {assert.equal(actual, receipt); return producer;}, fail,
    actual => {assert.equal(actual, state); calls.push('same original abort');},
    () => assert.fail('A saved preparation is not a fresh Pure issuer'), producers,
    actual => {assert.equal(actual, producer); calls.push('original release');});
  assert.throws(() => api.finishSourceProducer(receipt, 'failed'), {code: 'InstalledSourceRunCleanupPending'});
  assert.equal(producer.preparation, state); assert(producers.has(producer));
  assert.deepEqual(calls, []);
  pending = false;
  api.finishSourceProducer(receipt, 'failed');
  assert.deepEqual(calls, ['same original abort', 'original release']);
  assert.equal(producer.preparation, undefined); assert(!producers.has(producer));
});
