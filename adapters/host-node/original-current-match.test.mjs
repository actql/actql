// Actual compiled private bridge with explicit synthetic original allowances,
// not a normal physical profile, journal receipt/COMMIT or public Model Run.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {currentResourceFixture} from './model-current-resource.fixture.mjs';

const limits = {
  parse: {max_input_bytes: 10000, max_nodes: 1000, max_depth: 20},
  tree: {max_nodes: 1000, max_depth: 20, max_string_bytes: 10000, max_total_string_bytes: 10000},
  maxWork: 20000,
};
async function fixture(id) {
  let original;
  // Test-only observation of the actual existing caller's arguments. No new
  // product getter, record, callback, Ledger or Execution exposure is added.
  const observed = {...moon, clientProgramStartInferOriginalCurrentStateComparison(...args) {
    original = {active: args[0], scope: args[1]};
    return moon.clientProgramStartInferOriginalCurrentStateComparison(...args);
  }};
  const f = await currentResourceFixture(observed, runtimeCore(moon).publicationControl, id);
  const park = f.operation.parkOriginalResourcesForStateWrite();
  const writer = f.operation.prepareOriginalCurrentStateWriter(park,
    {maxWireBytes: 10000, maxNodes: 1000, maxDepth: 20});
  assert.equal(f.operation.advanceOriginalCurrentStateWriter(park, writer, 19).kind, 'complete');
  const wire = f.operation.finishOriginalCurrentStateWriter(park, writer);
  const decoder = f.operation.startOriginalCurrentStateDecode(park, `{"resource_state":${wire}}`, limits);
  let document;
  for (let i = 0; i < 20000; i++) {
    const poll = f.operation.advanceOriginalCurrentStateDecode(park, decoder, 10000);
    if (poll.kind === 'complete') { document = poll.document; break; }
    assert.equal(poll.kind, 'continue');
  }
  assert.notEqual(document, undefined);
  const cursor = f.operation.startOriginalCurrentStateComparison(park, document, 5);
  return {...f, park, document, cursor, ...original};
}
const advance = (f, quantum) => moon.clientProgramInferOriginalCurrentStateMatchPoll(checked(
  moon.clientProgramAdvanceInferOriginalCurrentStateComparisonWithMatch(
    f.active, f.scope, f.park, f.cursor, quantum)));
const current = (f, value) => moon.clientProgramInferOriginalCurrentStateMatchCurrent(
  f.active, f.scope, f.park, value);

test('actual compiled matched comparison only exposes its opaque borrow after all five original work units', async () => {
  const f = await fixture('matched-five');
  const partial = advance(f, 1);
  assert.equal(partial._0, 'continue');
  assert.equal(partial._1, 1);
  assert.equal(partial._3, undefined);
  const complete = advance(f, 4);
  assert.equal(complete._0, 'complete');
  assert.equal(complete._1, 4);
  assert.equal(complete._2, undefined);
  const matched = complete._3;
  assert.notEqual(matched, undefined);
  assert.strictEqual(current(f, matched), matched);
  assert.throws(() => advance(f, 1), {code: 'MoonBitHostFailure'});
  moon.clientProgramRetireInferOriginalCurrentStateMatch(matched);
  assert.equal(current(f, matched), undefined);
  assert.strictEqual(f.operation.originalResourceParkCurrent(f.park), f.park);
  f.operation.retireOriginalCurrentStateDocument(f.document);
  assert.equal(f.sends(), 0);
  // No actual journal invalidation exists. Closing cannot fabricate it.
  await assert.rejects(f.operation.close(), {code: 'MoonBitHostFailure'});
  assert.equal(f.operation.cleanupPending(), true);
});

test('actual compiled matched borrow refuses foreign Model Scope and retired original document', async () => {
  const f = await fixture('matched-original');
  const foreign = await fixture('matched-foreign');
  const matched = advance(f, 5)._3;
  assert.strictEqual(current(f, matched), matched);
  assert.equal(moon.clientProgramInferOriginalCurrentStateMatchCurrent(
    foreign.active, foreign.scope, f.park, matched), undefined);
  f.operation.retireOriginalCurrentStateDocument(f.document);
  assert.equal(current(f, matched), undefined);
  moon.clientProgramRetireInferOriginalCurrentStateMatch(matched);
  foreign.operation.cancelOriginalCurrentStateComparison(foreign.cursor);
  foreign.operation.retireOriginalCurrentStateDocument(foreign.document);
  assert.equal(f.sends(), 0);
  assert.equal(foreign.sends(), 0);
  await assert.rejects(f.operation.close(), {code: 'MoonBitHostFailure'});
  await assert.rejects(foreign.operation.close(), {code: 'MoonBitHostFailure'});
});
