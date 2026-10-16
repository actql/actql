// Private actual Common/Store/Host boundary. This is not GCS or funded byte
// acquisition acceptance: the new view borrows the original Reference only.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createGeneratedContentFixture} from './fixtures/generated-content.fixture.mjs';
import {openContentCommandHost} from './fixtures/content-command-host.fixture.mjs';

test('actual Content preparation borrows the original captured Command input and rejects copied or retired views', async t => {
  const scratch = await createOwnedScratch({
    parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'effect-content-original-', label: 'Original Content preparation projection',
  });
  const generated = await createGeneratedContentFixture(t);
  await generated.store.commitPhysicalHolding(generated.holding, [generated.physical.prepared]);
  await generated.issue();
  let borrowed;
  let preparations = 0;
  const host = await openContentCommandHost({scratch, generated,
    keys: generateKeyPairSync('ed25519'), entrance: 'Local',
    onPrepareContent({value, originalContent}) {
      preparations++;
      assert.equal(typeof originalContent, 'function');
      borrowed = originalContent('content');
      assert.equal(originalContent('content'), borrowed, 'one original view per row/input');
      assert.equal(borrowed.current(), true);
      assert.deepEqual(JSON.parse(borrowed.wire()), value.content);
      assert.equal(borrowed.wire(), generated.description.wire);
      const copied = {...borrowed.binding};
      assert.throws(() => checked(moon.clientProgramEffectCommandContentWire(copied)));
      moon.clientProgramEffectCommandContentRelease(copied);
      assert.equal(borrowed.current(), true, 'foreign retirement cannot retire the original view');
      assert.throws(() => originalContent('name'), 'a Text input cannot substitute for Content');
      assert.throws(() => originalContent('missing'), 'a caller name creates no original field');
      assert.equal(borrowed.current(), true);
    }});
  t.after(host.close);
  const run = await host.client.start(host.fixture.program);
  const state = await run.wait({signal: AbortSignal.timeout(15000)});
  assert.equal(state.status, 'waiting_checkpoint');
  assert.equal(preparations, 1);
  assert.equal(host.reads(), 1);
  assert.equal(host.sends(), 0, 'the Content projection does not issue a dispatch grant');
  await host.close();
  assert.equal(borrowed.current(), false);
  assert.throws(() => borrowed.wire());
  assert.equal(borrowed.release(), undefined, 'alias retirement is not a physical ACK');
  assert.equal(borrowed.release(), undefined);
  await generated.store.retirePhysicalHolding(generated.holding.holding_cid);
  scratch.passed();
});
