import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {ensureAuthorizationRuntime} from './authorization-fixture.mjs';
import {createPrivateEvidenceKey, loadPrivateEvidenceKey,
  openContinuationEvidence} from './local-continuation-evidence.mjs';

ensureAuthorizationRuntime();
const moon = await import(new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
  import.meta.url).href);

test('a bounded evidence read refuses by recorded size before loading bytes',
  async t => {
    const state = await mkdtemp(join(tmpdir(), 'actql-evidence-bound-'));
    t.after(() => rm(state, {recursive: true, force: true}));
    await createPrivateEvidenceKey(state);
    const key = await loadPrivateEvidenceKey(state);
    const evidence = openContinuationEvidence({stateDirectory: state,
      ...key, contractControl: runtimeCore(moon).publicationControl,
      preparation: () => ({status: 'waiting_checkpoint'})});
    t.after(() => evidence.close());
    const small = JSON.stringify({kind: 'review', text: 'x'.repeat(100)});
    const large = JSON.stringify({kind: 'review', text: 'y'.repeat(20_000)});
    const [smallCid, largeCid] = await evidence.hold('attempt-1',
      `sha256:${'1'.repeat(64)}`, [
        {name: 'review_projection', wire: small},
        {name: 'captured_input', wire: large},
      ]);
    const opened = await evidence.open('attempt-1');
    assert.deepEqual(opened.held('review_projection'), [smallCid]);
    assert.deepEqual(opened.held('continuation_record'), []);
    // Within the bound: the exact bytes, verified against their CID.
    assert.equal((await opened.bytes('review_projection', smallCid,
      {maxBytes: 4096})).toString('utf8'), small);
    // The recorded envelope size already exceeds the bound: refused before
    // the object is consumed.
    await assert.rejects(opened.bytes('captured_input', largeCid,
      {maxBytes: 1024}), {code: 'EvidenceReadLimitExceeded'});
    // A plaintext just over the bound whose envelope fits the size
    // allowance is still refused after decryption, never returned.
    await assert.rejects(opened.bytes('review_projection', smallCid,
      {maxBytes: small.length - 1}), {code: 'EvidenceReadLimitExceeded'});
    for (const maxBytes of [0, -1, 1.5]) {
      await assert.rejects(opened.bytes('review_projection', smallCid,
        {maxBytes}), {code: 'InvalidEvidenceReadLimit'});
    }
    // Only an exact held reference is readable.
    await assert.rejects(opened.bytes('review_projection', largeCid,
      {maxBytes: 1_000_000}), {code: 'ContinuationEvidenceNotHeld'});
  });
