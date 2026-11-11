import test from 'node:test';
import assert from 'node:assert/strict';
import {tmpdir} from 'node:os';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {open} from '../../packages/node/index.mjs';

// A large policy ceiling must not reserve its theoretical maximum before
// this tiny actual result. Runtime growth remains under the same finite policy.
test('large metadata row policy permits a two-row result and preserves its original Run', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(),
    prefix: 'actql-metadata-large-policy-', label: 'large metadata policy original'});
  let db;
  try {
    db = await open({stateDir: scratch.path, installation: {valuesMaxRows: 10000000}});
    const submissionRef = db.newSubmission({nonce: 'metadata-large-policy'});
    const run = await db.startSource('SELECT x FROM UNNEST([1, 2]) AS x', {
      format: 'sql', readOnly: true, submissionRef, signal: AbortSignal.timeout(20000),
    });
    assert.equal((await run.wait({signal: AbortSignal.timeout(20000)})).status, 'succeeded');
    const result = run.result('main');
    assert.deepEqual(result.ref, {run: run.ref, resultName: 'main'});
    assert.deepEqual(await result.all(), [{x: 1}, {x: 2}]);
    const first = await db.lookupSubmission(submissionRef);
    const second = await db.lookupSubmission(submissionRef);
    assert.deepEqual(first, second);
    assert.deepEqual(first.submissionRef, submissionRef);
    assert.equal(first.kind, 'ready');
    assert.deepEqual(first.admission.ref, run.ref);
    assert.deepEqual(await db.sql('SELECT 7 AS x').all(), [{x: 7}]);
    await db.close();
    db = await open({stateDir: scratch.path});
    const reopened = await db.lookupSubmission(submissionRef);
    assert.equal(reopened.kind, 'ready');
    assert.deepEqual(reopened.submissionRef, submissionRef);
    assert.deepEqual(reopened.admission.ref, run.ref);
    const attached = await db.attach(reopened.admission.ref);
    assert.deepEqual(attached.ref, run.ref);
    assert.equal((await attached.wait({signal: AbortSignal.timeout(20000)})).status, 'succeeded');
    assert.deepEqual(attached.result('main').ref, result.ref);
    assert.deepEqual(await attached.result('main').all(), [{x: 1}, {x: 2}]);
    assert.deepEqual(await db.sql('SELECT 8 AS x').all(), [{x: 8}]);
  } finally {
    await db?.close();
  }
  scratch.passed();
});

test('metadata quote normal and empty result controls retain their semantics', async () => {
  const scratch = await createOwnedScratch({parent: tmpdir(),
    prefix: 'actql-metadata-controls-', label: 'metadata quote normal controls'});
  let db;
  try {
    db = await open({stateDir: scratch.path});
    assert.deepEqual(await db.sql('SELECT x FROM UNNEST([1, 2]) AS x').all(), [{x: 1}, {x: 2}]);
    assert.deepEqual(await db.sql('SELECT x FROM UNNEST([1, 2]) AS x WHERE FALSE').all(), []);
    assert.deepEqual(await db.sql('SELECT 7 AS x').all(), [{x: 7}]);
  } finally {
    await db?.close();
  }
  scratch.passed();
});
