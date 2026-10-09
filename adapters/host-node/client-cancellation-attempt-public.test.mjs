import assert from 'node:assert/strict';
import test from 'node:test';
import {fixture} from './client-cancel-response-loss.fixture.mjs';

// Reuse the existing real journal and installed ingress fixture. Its separate
// SQLite connection observes committed facts independently of the public DTO.
for (const transport of ['in-process', 'https']) {
  test(`${transport}: Refused is invocation-local and does not consume cancellation custody`, async t => {
    const f = await fixture(t, transport);
    const options = f.cancelOptions();
    f.authorizeCancel(false);
    const refused = await f.execution.cancel({...options, attemptId: 'refused-before'});
    assert.deepEqual(refused, {kind: 'refused', reason: 'authorization',
      guarantee: 'attempt_uncommitted_unconsumed',
      attemptRef: {operation: 'cancel', attemptId: 'refused-before'}});
    assert.deepEqual(f.stored(), f.before);
    f.authorizeCancel(true);
    const accepted = await f.execution.cancel({...options, attemptId: 'accepted-invocation'});
    assert.equal(accepted.kind, 'accepted');
    assert.deepEqual(accepted.attemptRef, {operation: 'cancel', attemptId: 'accepted-invocation'});
    const committed = [{...f.before[0], cancellation_requested: 1,
      revision: f.before[0].revision + 1}];
    assert.deepEqual(f.stored(), committed);
    f.authorizeCancel(false);
    const laterRefusal = await f.execution.cancel({...options, attemptId: 'refused-after'});
    assert.equal(laterRefusal.kind, 'refused');
    assert.deepEqual(f.stored(), committed);
    f.authorizeCancel(true);
    const found = await f.execution.lookupCancellation(accepted.cancellation.cancelRef);
    assert.deepEqual(found, {kind: 'found', cancellation: accepted.cancellation});
    assert.deepEqual(f.counts(), {cancelCalls: 3, submits: 0});
    assert.deepEqual(f.stored(), committed);
  });

  test(`${transport}: stale relevant revision returns a correlated Conflict without a write`, async t => {
    const f = await fixture(t, transport);
    const options = {...f.cancelOptions(), expectedRevision: f.before[0].revision - 1,
      attemptId: 'stale-invocation'};
    const answer = await f.execution.cancel(options);
    assert.deepEqual(answer, {kind: 'conflict', reason: 'control_revision',
      attemptRef: {operation: 'cancel', attemptId: 'stale-invocation'},
      cancelRef: {...f.execution.ref, cancelId: options.cancelId,
        expectedRevision: options.expectedRevision}});
    assert.deepEqual(f.stored(), f.before);
    assert.deepEqual(f.counts(), {cancelCalls: 1, submits: 0});
  });

  for (const phase of ['before-dispatch', 'after-commit']) {
    test(`${transport}: ${phase} response loss retains the original operation and invocation`, async t => {
      const f = await fixture(t, transport, phase);
      const options = {...f.cancelOptions(), attemptId: 'lost-invocation'};
      let failure;
      await assert.rejects(f.execution.cancel(options), error => {
        failure = error;
        assert.equal(error.code, 'CancellationUnknown');
        assert.deepEqual(error.attemptRef, {operation: 'cancel', attemptId: 'lost-invocation'});
        assert.deepEqual(error.cancelRef, {...f.execution.ref, cancelId: options.cancelId,
          expectedRevision: options.expectedRevision});
        return true;
      });
      const committed = phase === 'after-commit';
      const expected = [{...f.before[0], cancellation_requested: committed ? 1 : 0,
        revision: f.before[0].revision + (committed ? 1 : 0)}];
      assert.deepEqual(f.stored(), expected);
      for (let iteration = 0; iteration < 2; iteration++) {
        const found = await f.execution.lookupCancellation(failure.cancelRef);
        assert.equal(found.kind, committed ? 'found' : 'unknown');
        if (committed) assert.equal(found.cancellation.kind, 'accepted');
        assert.deepEqual(f.stored(), expected);
      }
      assert.deepEqual(f.counts(), {cancelCalls: committed ? 1 : 0, submits: 0});
      assert.equal(f.operations.filter(operation => operation === 'cancel').length, 1);
    });
  }
}
