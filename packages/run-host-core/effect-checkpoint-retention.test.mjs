import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Execute the actual facade bodies with explicit compiler ports. The Common
// reader/fields tests qualify their implementations separately; this fixture
// neither issues persistence nor represents an installed runtime operation.
const source = readFileSync(new URL('./index.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const names = ['checked', 'requireHandle', 'effectReviewCheckpointBinding',
  'effectReviewCheckpointBindingFacts', 'effectReviewCheckpointWaitingState', 'effectReviewCheckpointReconciliationState', 'effectReviewCheckpointCancelledState', 'effectProjectionArray'];
const bodies = names.map(name => {
  const declaration = ast.body.map(node => node.declaration ?? node)
    .find(node => node.type === 'FunctionDeclaration' && node.id.name === name);
  assert(declaration, name);
  return source.slice(declaration.start, declaration.end);
}).join('\n');
const fixed = value => 'sha256:' + value.repeat(64);

function fixture() {
  const counts = {admit: 0, fields: 0}, artifacts = [], retained = new WeakMap();
  const allowedRuns = new WeakMap(), definitions = new WeakMap(), waitingCalls = [];
  let waitingFailure, reconciliationFailure, cancelledFailure;
  const cancelledCalls = [];
  const reconciliationCalls = [];
  const fields = [fixed('a'), '{"original":"checkpoint"}', 'run', 'unit',
    fixed('b'), fixed('c'), fixed('d'), fixed('e')];
  let refusal = false, malformed = false;
  const owner = {
    clientValuesHostEffectCheckpointCancelledState(original, allowed, definition, ...data) {
      assert(artifacts.includes(original));
      assert.strictEqual(allowed, allowedValue); assert.strictEqual(definition, definitionValue);
      cancelledCalls.push({original, data});
      return cancelledFailure === undefined ? {$tag: 1, _0: 'original-cancelled-wire'}
        : {$tag: 0, _0: cancelledFailure};
    },
    clientValuesHostEffectCheckpointReconciliationState(original, allowed, definition, ...data) {
      assert(artifacts.includes(original));
      assert.strictEqual(allowed, allowedValue); assert.strictEqual(definition, definitionValue);
      reconciliationCalls.push({original, data});
      return reconciliationFailure === undefined ? {$tag: 1, _0: 'original-reconciliation-wire'}
        : {$tag: 0, _0: reconciliationFailure};
    },
    clientValuesHostEffectCheckpointWaitingState(original, storedWire, updatedAt, results) {
      assert(artifacts.includes(original));
      waitingCalls.push({original, storedWire, updatedAt, results});
      return waitingFailure === undefined ? {$tag: 1, _0: 'original-waiting-wire'} : {$tag: 0, _0: waitingFailure};
    },
    clientValuesHostAdmitEffectCheckpointBinding(allowed, definition, wire) {
      counts.admit++;
      assert.strictEqual(allowed, allowedValue);
      assert.strictEqual(definition, definitionValue);
      assert.equal(wire, fields[1]);
      if (refusal) return {$tag: 0, _0: 'original admission failure'};
      const artifact = Object.freeze({nominal: artifacts.length});
      artifacts.push(artifact); return {$tag: 1, _0: artifact};
    },
    clientValuesHostEffectCheckpointBindingFields(artifact) {
      counts.fields++; assert(artifacts.includes(artifact));
      return {$tag: 1, _0: malformed ? fields.slice(0, 7) : fields};
    },
  };
  const allowedValue = Object.freeze({allowed: 'original'});
  const definitionValue = Object.freeze({definition: 'original'});
  const allowed = Object.freeze({kind: 'allowed'}), definition = Object.freeze({kind: 'definition'});
  allowedRuns.set(allowed, {value: allowedValue}); definitions.set(definition, definitionValue);
  const api = new Function('owner', 'effectAllowedRuns', 'definitions',
    'effectCheckpointBindings', 'runtimeIsOk', 'runtimeIsError', 'runtimeField',
    bodies + '\nreturn {effectReviewCheckpointBinding, effectReviewCheckpointBindingFacts, effectReviewCheckpointWaitingState, effectReviewCheckpointReconciliationState, effectReviewCheckpointCancelledState};')(
    owner, allowedRuns, definitions, retained, value => value?.$tag === 1,
    value => value?.$tag === 0, (value, index) => value[`_${index}`]);
  return {api, counts, artifacts, retained, allowed, definition, fields, waitingCalls, reconciliationCalls, cancelledCalls,
    rejectCancelled(issue) {cancelledFailure = issue;},
    rejectReconciliation(issue) {reconciliationFailure = issue;},
    rejectWaiting(issue) {waitingFailure = issue;},
    refuse() {refusal = true;}, malformed() {malformed = true;}};
}

test('same-original binding retains one nominal Checkpoint across pure reads and await', async () => {
  const f = fixture();
  const binding = f.api.effectReviewCheckpointBinding(f.allowed, f.definition, f.fields[1]);
  assert(Object.isFrozen(binding));
  assert.deepEqual(Object.values(binding), f.fields);
  assert.strictEqual(f.retained.get(binding).original, f.artifacts[0]);
  for (let index = 0; index < 4; index++) {
    await Promise.resolve();
    assert.strictEqual(f.api.effectReviewCheckpointBindingFacts(binding,
      f.allowed, f.definition), binding);
  }
  assert.deepEqual(f.counts, {admit: 1, fields: 1});
});

test('copies foreign bindings and changed original roots cannot borrow retained facts', () => {
  const f = fixture(), other = fixture();
  const binding = f.api.effectReviewCheckpointBinding(f.allowed, f.definition, f.fields[1]);
  const foreign = other.api.effectReviewCheckpointBinding(other.allowed, other.definition, other.fields[1]);
  for (const value of [{...binding}, foreign, {}, null]) {
    assert.throws(() => f.api.effectReviewCheckpointBindingFacts(value,
      f.allowed, f.definition), /ForeignRunHostCheckpointBinding/);
  }
  for (const [allowed, definition] of [[other.allowed, f.definition],
    [f.allowed, other.definition], [{...f.allowed}, f.definition]]) {
    assert.throws(() => f.api.effectReviewCheckpointBindingFacts(binding,
      allowed, definition), /ForeignRunHostCheckpointBinding/);
  }
  assert.deepEqual(f.counts, {admit: 1, fields: 1});
});

test('equal visible metadata keeps separate originals and admission failures stay failures', () => {
  const f = fixture();
  const first = f.api.effectReviewCheckpointBinding(f.allowed, f.definition, f.fields[1]);
  const second = f.api.effectReviewCheckpointBinding(f.allowed, f.definition, f.fields[1]);
  assert.deepEqual(first, second); assert.notStrictEqual(first, second);
  assert.notStrictEqual(f.retained.get(first).original, f.retained.get(second).original);
  f.refuse();
  assert.throws(() => f.api.effectReviewCheckpointBinding(f.allowed,
    f.definition, f.fields[1]), {code: 'RunHostEffectCheckpointBindingRejected'});
  assert.deepEqual(f.counts, {admit: 3, fields: 2});
  const bad = fixture(); bad.malformed();
  assert.throws(() => bad.api.effectReviewCheckpointBinding(bad.allowed,
    bad.definition, bad.fields[1]), /InvalidRunHostCheckpointBinding/);
});


test('waiting projection forwards the same nominal original and one results snapshot', async () => {
  const f = fixture();
  const binding = f.api.effectReviewCheckpointBinding(f.allowed, f.definition, f.fields[1]);
  let reads = 0;
  const declared = [];
  Object.defineProperty(declared, 0, {get() {reads++; return 'main';}});
  for (const name of ['map', 'slice', 'some', Symbol.iterator]) {
    Object.defineProperty(declared, name, {value() {throw new Error('caller-owned traversal');}});
  }
  await Promise.resolve();
  assert.equal(f.api.effectReviewCheckpointWaitingState(binding, f.allowed,
    f.definition, f.fields[1], '2026-10-09T03:00:00.000Z', declared), 'original-waiting-wire');
  assert.deepEqual(f.counts, {admit: 1, fields: 1});
  assert.equal(reads, 1); assert.equal(f.waitingCalls.length, 1);
  const call = f.waitingCalls[0];
  assert.strictEqual(call.original, f.artifacts[0]);
  assert.equal(call.storedWire, f.fields[1]);
  assert.equal(call.updatedAt, '2026-10-09T03:00:00.000Z');
  assert.deepEqual(call.results, ['main']); assert.notStrictEqual(call.results, declared);
});

test('waiting projection keeps foreign-root and typed owner failures distinct', () => {
  const f = fixture(), other = fixture();
  const binding = f.api.effectReviewCheckpointBinding(f.allowed, f.definition, f.fields[1]);
  for (const [value, allowed, definition] of [[{...binding}, f.allowed, f.definition],
    [binding, other.allowed, f.definition], [binding, f.allowed, other.definition]]) {
    assert.throws(() => f.api.effectReviewCheckpointWaitingState(value, allowed,
      definition, f.fields[1], 'time', []), /ForeignRunHostCheckpointBinding/);
  }
  assert.equal(f.waitingCalls.length, 0);
  const issue = Object.freeze({kind: 'Checkpoint', issue: 'PersistedWireMismatch'});
  f.rejectWaiting(issue);
  assert.throws(() => f.api.effectReviewCheckpointWaitingState(binding, f.allowed,
    f.definition, f.fields[1] + ' ', 'time', []), error =>
    error.code === 'RunHostEffectCheckpointWaitingRejected' && error.cause === issue);
  assert.strictEqual(f.waitingCalls[0].original, f.artifacts[0]);
  assert.deepEqual(f.counts, {admit: 1, fields: 1});
});

test('waiting projection bounds caller snapshots before Common emission', () => {
  const f = fixture();
  const binding = f.api.effectReviewCheckpointBinding(f.allowed, f.definition, f.fields[1]);
  for (const results of [[42], Array(1), Array(65537), ['x'.repeat(1048577)]]) {
    assert.throws(() => f.api.effectReviewCheckpointWaitingState(binding, f.allowed,
      f.definition, f.fields[1], 'time', results), TypeError);
  }
  for (const [wire, time] of [[null, 'time'], [f.fields[1], null]]) {
    assert.throws(() => f.api.effectReviewCheckpointWaitingState(binding, f.allowed,
      f.definition, wire, time, []), TypeError);
  }
  assert.equal(f.waitingCalls.length, 0);
  assert.deepEqual(f.counts, {admit: 1, fields: 1});
});


test('original Checkpoint reconciliation forwards same nominal roots and snapshots receipt DATA', () => {
  const f = fixture(), binding = f.api.effectReviewCheckpointBinding(f.allowed, f.definition, f.fields[1]);
  const members = ['member'], names = ['published'];
  assert.equal(f.api.effectReviewCheckpointReconciliationState(binding, f.allowed, f.definition,
    f.fields[1], 'preview', 'invocation', 'set', members, 'time', names), 'original-reconciliation-wire');
  const call = f.reconciliationCalls[0];
  assert.strictEqual(call.original, f.artifacts[0]);
  assert.deepEqual(call.data, [f.fields[1], 'preview', 'invocation', 'set', members, 'time', names]);
  assert.notStrictEqual(call.data[4], members); assert.notStrictEqual(call.data[6], names);
  members[0] = 'changed'; names[0] = 'other';
  assert.deepEqual(call.data[4], ['member']); assert.deepEqual(call.data[6], ['published']);
  assert.deepEqual(f.counts, {admit: 1, fields: 1});
});

test('original Checkpoint reconciliation rejects foreign roots invalid DATA and original Core refusal', () => {
  const f = fixture(), other = fixture();
  const binding = f.api.effectReviewCheckpointBinding(f.allowed, f.definition, f.fields[1]);
  const project = (candidate = binding, allowed = f.allowed, definition = f.definition,
    members = ['member'], names = []) => f.api.effectReviewCheckpointReconciliationState(
    candidate, allowed, definition, f.fields[1], 'preview', 'invocation', 'set', members, 'time', names);
  assert.throws(() => project({...binding}), /ForeignRunHostCheckpointBinding/u);
  assert.throws(() => project(binding, other.allowed), /ForeignRunHostCheckpointBinding/u);
  assert.throws(() => project(binding, f.allowed, other.definition), /ForeignRunHostCheckpointBinding/u);
  let getters = 0;
  const accessor = []; Object.defineProperty(accessor, '0', {get() {getters++; return 'member';}});
  for (const input of [accessor, new Array(1), [1], new Array(65537)]) {
    assert.throws(() => project(binding, f.allowed, f.definition, input), /InvalidRunHostCheckpointReconciliationInput/u);
  }
  assert.equal(getters, 0); assert.equal(f.reconciliationCalls.length, 0);
  assert.throws(() => project(binding, f.allowed, f.definition, ['x'.repeat(1048576)]),
    /InvalidRunHostCheckpointReconciliationInput/u);
  f.rejectReconciliation('original receipt refusal');
  assert.throws(() => project(), {code: 'RunHostEffectCheckpointReconciliationRejected'});
  assert.equal(f.reconciliationCalls.length, 1);
});


test('original Checkpoint cancelled DATA forwards same originals without a scalar authority input', () => {
  const f = fixture(), binding = f.api.effectReviewCheckpointBinding(f.allowed, f.definition, f.fields[1]);
  const names = ['published'];
  assert.equal(f.api.effectReviewCheckpointCancelledState(binding, f.allowed, f.definition,
    f.fields[1], 'time', names), 'original-cancelled-wire');
  assert.strictEqual(f.cancelledCalls[0].original, f.artifacts[0]);
  assert.deepEqual(f.cancelledCalls[0].data, [f.fields[1], 'time', names]);
  assert.notStrictEqual(f.cancelledCalls[0].data[2], names);
  names[0] = 'other'; assert.deepEqual(f.cancelledCalls[0].data[2], ['published']);
  assert.deepEqual(f.counts, {admit: 1, fields: 1});
});

test('original Checkpoint cancelled DATA refuses copied foreign and invalid inputs before Core', () => {
  const f = fixture(), other = fixture();
  const binding = f.api.effectReviewCheckpointBinding(f.allowed, f.definition, f.fields[1]);
  const project = (candidate = binding, allowed = f.allowed, definition = f.definition,
    stored = f.fields[1], names = []) => f.api.effectReviewCheckpointCancelledState(
    candidate, allowed, definition, stored, 'time', names);
  assert.throws(() => project({...binding}), /ForeignRunHostCheckpointBinding/u);
  assert.throws(() => project(binding, other.allowed), /ForeignRunHostCheckpointBinding/u);
  assert.throws(() => project(binding, f.allowed, other.definition), /ForeignRunHostCheckpointBinding/u);
  assert.throws(() => project(binding, f.allowed, f.definition, true), /InvalidRunHostCheckpointCancelledInput/u);
  let reads = 0;
  const accessor = []; Object.defineProperty(accessor, '0', {get() {reads++; return 'published';}});
  for (const input of [accessor, new Array(1), [false], new Array(65537), ['x'.repeat(1048577)]]) {
    assert.throws(() => project(binding, f.allowed, f.definition, f.fields[1], input), /InvalidRunHostCheckpointCancelledInput/u);
  }
  assert.equal(reads, 0); assert.equal(f.cancelledCalls.length, 0);
  f.rejectCancelled('original typed refusal');
  assert.throws(() => project(), {code: 'RunHostEffectCheckpointCancelledRejected'});
  assert.equal(f.cancelledCalls.length, 1);
});


test('receipt facades retain one bounded array extent across reentry', () => {
  const changing = value => {
    let lengthReads = 0, descriptors = 0;
    const input = new Proxy([value], {
      get(target, key, receiver) {
        if (key === 'length') return ++lengthReads === 1 ? 1 : 65537;
        return Reflect.get(target, key, receiver);
      },
      getOwnPropertyDescriptor(target, key) {
        if (/^(?:0|[1-9][0-9]*)$/u.test(key)) {
          descriptors++;
          return {value, writable: true, enumerable: true, configurable: true};
        }
        return Reflect.getOwnPropertyDescriptor(target, key);
      },
    });
    return {input, counts: () => ({lengthReads, descriptors})};
  };
  const f = fixture(), binding = f.api.effectReviewCheckpointBinding(f.allowed, f.definition, f.fields[1]);
  const members = changing('member');
  assert.equal(f.api.effectReviewCheckpointReconciliationState(binding, f.allowed, f.definition,
    f.fields[1], 'preview', 'invocation', 'set', members.input, 'time', []), 'original-reconciliation-wire');
  assert.equal(f.reconciliationCalls[0].data[4].length, 1);
  assert.deepEqual(f.reconciliationCalls[0].data[4], ['member']);
  assert.deepEqual(members.counts(), {lengthReads: 1, descriptors: 1});
  const names = changing('published');
  assert.equal(f.api.effectReviewCheckpointCancelledState(binding, f.allowed, f.definition,
    f.fields[1], 'time', names.input), 'original-cancelled-wire');
  assert.equal(f.cancelledCalls[0].data[2].length, 1);
  assert.deepEqual(f.cancelledCalls[0].data[2], ['published']);
  assert.deepEqual(names.counts(), {lengthReads: 1, descriptors: 1});
});
