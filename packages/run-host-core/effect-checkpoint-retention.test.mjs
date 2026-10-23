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
  'effectReviewCheckpointBindingFacts', 'effectReviewCheckpointWaitingState', 'effectProjectionArray'];
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
  let waitingFailure;
  const fields = [fixed('a'), '{"original":"checkpoint"}', 'run', 'unit',
    fixed('b'), fixed('c'), fixed('d'), fixed('e')];
  let refusal = false, malformed = false;
  const owner = {
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
    bodies + '\nreturn {effectReviewCheckpointBinding, effectReviewCheckpointBindingFacts, effectReviewCheckpointWaitingState};')(
    owner, allowedRuns, definitions, retained, value => value?.$tag === 1,
    value => value?.$tag === 0, (value, index) => value[`_${index}`]);
  return {api, counts, artifacts, retained, allowed, definition, fields, waitingCalls,
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
