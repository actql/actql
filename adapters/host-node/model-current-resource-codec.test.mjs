// Actual compiled Node/Model/Resource boundary with synthetic layout funding.
// No real Provider, Store ACK or public acceptance is inferred.
import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {currentResourceFixture} from './model-current-resource.fixture.mjs';

test('actual Node original current Writer decoder and comparison keep one park and no send', async () => {
  const f = await currentResourceFixture(moon, runtimeCore(moon).publicationControl);
  assert.notEqual(f.preparedCallSet, undefined);
  const park = f.operation.parkOriginalResourcesForStateWrite();
  const value = f.operation.prepareOriginalCurrentStateWriter(park, {maxWireBytes: 10000, maxNodes: 1000, maxDepth: 20});
  assert.throws(() => f.operation.finishOriginalCurrentStateWriter(park, value), {code: 'MoonBitHostFailure'});
  let writerWork = 0;
  for (let i = 0; i < 100; i++) {
    const poll = f.operation.advanceOriginalCurrentStateWriter(park, value, 1);
    writerWork += poll.work;
    if (poll.kind === 'complete') break;
    assert.equal(poll.kind, 'continue');
  }
  // One original read, handed-off Model capacity and one reserved attempt.
  assert.equal(writerWork, 19);
  const state = f.operation.finishOriginalCurrentStateWriter(park, value);
  const wire = `{"resource_state":${state}}`;
  const decoder = f.operation.startOriginalCurrentStateDecode(park, wire, {
    parse: {max_input_bytes: 10000, max_nodes: 1000, max_depth: 20},
    tree: {max_nodes: 1000, max_depth: 20, max_string_bytes: 10000, max_total_string_bytes: 10000}, maxWork: 20000});
  let document;
  for (let i = 0; i < 20000; i++) {
    const poll = f.operation.advanceOriginalCurrentStateDecode(park, decoder, 1);
    assert.ok(poll.work >= 0 && poll.work <= 1);
    if (poll.kind === 'complete') {document = poll.document; break;}
    assert.equal(poll.kind, 'continue');
  }
  assert.notEqual(document, undefined);
  const comparison = f.operation.startOriginalCurrentStateComparison(park, document, 5);
  assert.deepEqual(f.operation.advanceOriginalCurrentStateComparison(park, comparison, 5),
    {kind: 'complete', work: 5, issue: undefined});
  f.operation.retireOriginalCurrentStateDocument(document);
  assert.strictEqual(f.operation.originalResourceParkCurrent(park), park);
  assert.equal(f.sends(), 0);
  // No journal COMMIT exists in this case, so retaining park/cleanup pending
  // is the correct outcome; never use a caller Bool to release this custody.
  // advance reports the existing typed ResourceParked cause through checked(),
  // before stop can reach the generic Node pending branch. Do not replace it.
  await assert.rejects(f.operation.close(), error => error.code === 'MoonBitHostFailure' && error.cause !== undefined);
  assert.equal(f.operation.cleanupPending(), true);
  assert.equal(f.operation.physicalStopped(), false);
  assert.strictEqual(f.operation.originalResourceParkCurrent(park), park);
  assert.equal(f.sends(), 0);
});

test('actual Node codec rejects unsafe limits before FFI and keeps cancelled bounded custody', async () => {
  const f = await currentResourceFixture(moon, runtimeCore(moon).publicationControl, 'current-resource-bounds');
  const park = f.operation.parkOriginalResourcesForStateWrite();
  const limits = {
    parse: {max_input_bytes: 10000, max_nodes: 1000, max_depth: 20},
    tree: {max_nodes: 1000, max_depth: 20, max_string_bytes: 10000, max_total_string_bytes: 10000},
    maxWork: 20000,
  };
  // An undefined park would fail inside Core. These exact TypeErrors instead
  // prove that unsafe/missing bounds do not cross the Int FFI boundary.
  for (const bad of [undefined, null, {...limits, maxWork: 2147483648},
    {...limits, maxWork: Number.MAX_SAFE_INTEGER + 1}, {...limits, maxWork: 0},
    {...limits, parse: {...limits.parse, max_nodes: -1}},
    {...limits, parse: {...limits.parse, max_nodes: 1.5}},
    {...limits, tree: {...limits.tree, max_string_bytes: undefined}},
    {...limits, tree: {...limits.tree, extra: 0}}]) {
    assert.throws(() => f.operation.startOriginalCurrentStateDecode(undefined, '{}', bad),
      {name: 'TypeError', message: 'InvalidInferOriginalCurrentDecodeLimits'});
  }
  for (const bad of [0, -1, 1.5, 2147483648, undefined]) {
    assert.throws(() => f.operation.advanceOriginalCurrentStateDecode(undefined, undefined, bad),
      {name: 'TypeError', message: 'InvalidInferOriginalCurrentDecodeQuantum'});
    assert.throws(() => f.operation.startOriginalCurrentStateComparison(undefined, undefined, bad),
      {name: 'TypeError', message: 'InvalidInferOriginalCurrentComparisonWork'});
    assert.throws(() => f.operation.advanceOriginalCurrentStateComparison(undefined, undefined, bad),
      {name: 'TypeError', message: 'InvalidInferOriginalCurrentComparisonQuantum'});
  }
  // The whole parent wire, not just resource_state, is bounded before parsing.
  const tooLarge = f.operation.startOriginalCurrentStateDecode(park, '{}',
    {...limits, parse: {...limits.parse, max_input_bytes: 1}});
  // The existing bounded UTF-8 scan spends one unit per character; the
  // second byte crosses the limit, rather than being inspected for free.
  assert.equal(f.operation.advanceOriginalCurrentStateDecode(park, tooLarge, 1).kind, 'continue');
  const excess = f.operation.advanceOriginalCurrentStateDecode(park, tooLarge, 1);
  assert.equal(excess.kind, 'failed');
  assert.equal(excess.work, 1);
  f.operation.cancelOriginalCurrentStateDecode(tooLarge);
  const decoder = f.operation.startOriginalCurrentStateDecode(park, '{"resource_state":[]}', limits);
  assert.equal(f.operation.advanceOriginalCurrentStateDecode(park, decoder, 1).kind, 'continue');
  f.operation.cancelOriginalCurrentStateDecode(decoder);
  f.operation.cancelOriginalCurrentStateDecode(decoder);
  const retired = f.operation.advanceOriginalCurrentStateDecode(park, decoder, 1);
  assert.equal(retired.kind, 'failed');
  assert.equal(retired.work, 0);
  assert.strictEqual(f.operation.originalResourceParkCurrent(park), park);
  assert.equal(f.sends(), 0);
  await assert.rejects(f.operation.close(), error => error.code === 'MoonBitHostFailure');
  assert.equal(f.operation.cleanupPending(), true);
  assert.equal(f.sends(), 0);
});
