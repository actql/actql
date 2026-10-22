import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Execute the actual Host closure with explicit service ports. This establishes
// optional capability ordering, not an initialized Host or a physical signature.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
let initializer;
function visit(value) {
  if (value === null || typeof value !== 'object') return;
  if (value.type === 'VariableDeclarator' && value.id.name === 'answerLocalCheckpoint') {
    assert.equal(initializer, undefined);
    initializer = source.slice(value.init.start, value.init.end);
  }
  for (const child of Object.values(value)) {
    if (Array.isArray(child)) child.forEach(visit);
    else if (child !== null && typeof child === 'object') visit(child);
  }
}
visit(tree);
assert.equal(typeof initializer, 'string');
const instantiate = new Function('ports', `
  const {assertProjectRuntime, mode, mockAccount, clientOperationError, preparation,
    runtimeCore, moon, createLocalCheckpointAnswer, checkpoints, store,
    authorityScopeCid, principalId} = ports;
  let localCheckpointAnswer, localSigningMetadata;
  return (${initializer});
`);
function fixture({reviewer = true, checkpoints = true, currentFailure} = {}) {
  const calls = [], moon = {}, store = {}, metadata = {}, checkpointOwner = {};
  const account = Object.freeze(reviewer ? {reviewer: Object.freeze({resource: 'original-reviewer'})} : {});
  const answer = (summary, decision, signal) => ({summary, decision, signal});
  return {calls, answer: instantiate({mode: 'local', mockAccount: account,
    checkpoints: checkpoints ? checkpointOwner : undefined, store, moon,
    authorityScopeCid: 'original-authority', principalId: 'original-principal',
    assertProjectRuntime() {calls.push('current'); if (currentFailure) throw currentFailure;},
    clientOperationError: code => Object.assign(new Error(code), {code}),
    preparation: {assertResultPublicationCurrent() {calls.push('publication-current');}},
    runtimeCore(actual) {assert.strictEqual(actual, moon); return {localSigningMetadata() {calls.push('metadata'); return metadata;}};},
    createLocalCheckpointAnswer(options) {
      calls.push('create-answer');
      assert.strictEqual(options.mockAccount, account);
      assert.strictEqual(options.checkpoints, checkpointOwner);
      assert.strictEqual(options.store, store);
      assert.strictEqual(options.metadata, metadata);
      return answer;
    },
  })};
}
test('Account-only Host refuses explicit checkpoint answer before signing preparation', () => {
  const f = fixture({reviewer: false, checkpoints: false});
  assert.throws(() => f.answer({}, 'approved'), {code: 'CheckpointSignerUnavailable'});
  assert.deepEqual(f.calls, ['current']);
});
test('Checkpoint service cannot substitute for an absent actual Local Reviewer', () => {
  const f = fixture({reviewer: false});
  assert.throws(() => f.answer({}, 'rejected'), {code: 'CheckpointSignerUnavailable'});
  assert.deepEqual(f.calls, ['current']);
});
test('Local checkpoint answer retains the original available signer service', () => {
  const f = fixture(), summary = {}, signal = new AbortController().signal;
  assert.deepEqual(f.answer(summary, 'approved', signal), {summary, decision: 'approved', signal});
  assert.deepEqual(f.answer(summary, 'rejected', signal), {summary, decision: 'rejected', signal});
  assert.equal(f.calls.filter(value => value === 'create-answer').length, 1);
  assert.equal(f.calls.filter(value => value === 'metadata').length, 1);
});
test('Original Host current refusal precedes optional signing capability selection', () => {
  const failure = new Error('OriginalHostChanged');
  const f = fixture({reviewer: false, checkpoints: false, currentFailure: failure});
  assert.throws(() => f.answer({}, 'approved'), error => error === failure);
  assert.deepEqual(f.calls, ['current']);
});
