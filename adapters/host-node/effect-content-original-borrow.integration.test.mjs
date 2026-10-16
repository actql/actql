// Private actual Common/Store/Host boundary. This is not GCS or funded byte
// acquisition acceptance: the new view borrows the original Reference only.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeOptionalField, runtimeTag} from '../host-common/compiler-binding.generated.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createGeneratedContentFixture} from './fixtures/generated-content.fixture.mjs';
import {openContentCommandHost} from './fixtures/content-command-host.fixture.mjs';
import {setImmediate as turn} from 'node:timers/promises';

test('actual Content preparation borrows the original captured Command input and rejects copied or retired views', async t => {
  const scratch = await createOwnedScratch({
    parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'effect-content-original-', label: 'Original Content preparation projection',
  });
  const generated = await createGeneratedContentFixture(t);
  await generated.store.commitPhysicalHolding(generated.holding, [generated.physical.prepared]);
  await generated.issue();
  let borrowed;
  let preparationFailure;
  let preparations = 0;
  const host = await openContentCommandHost({scratch, generated,
    keys: generateKeyPairSync('ed25519'), entrance: 'Local',
    onPrepareContent({value, originalContent}) {
      try {
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
      } catch (error) {
        preparationFailure = error;
        throw error;
      }
    }});
  t.after(host.close);
  const run = await host.client.start(host.fixture.program);
  const state = await run.wait({signal: AbortSignal.timeout(15000)});
  // Preserve the actual same-run public observation and bounded closed
  // diagnostic tags before asserting; never print keys, wire or body values.
  const tag = value => typeof value === 'string' && /^[A-Za-z][A-Za-z0-9_:]*$/u.test(value)
    ? value.slice(0, 128) : undefined;
  const issueTag = value => typeof value === 'number' ? value : runtimeTag(value);
  const issue = preparationFailure?.cause;
  const facts = {state, preparations, reads: host.reads(), sends: host.sends(),
    preparationIssue: {tag: issueTag(issue),
      nested: issueTag(runtimeOptionalField(issue, 0))},
    events: host.events.map(({event, detail}) => ({event: tag(event),
      code: tag(detail?.code), issueTag: detail?.issueTag,
      nestedIssueTag: detail?.nestedIssueTag}))};
  await writeFile(scratch.path + '/projection-observation.json', JSON.stringify(facts) + '\n');
  if (preparationFailure !== undefined) {
    console.error(JSON.stringify({fixture: 'original-content-preparation', facts}));
    throw preparationFailure;
  }
  assert.equal(state.status, 'waiting_checkpoint', JSON.stringify(facts));
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

test('actual Content capture keeps the same original parent through an async preparation child', async t => {
  const scratch = await createOwnedScratch({
    parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'effect-content-child-', label: 'Original Content async child',
  });
  const generated = await createGeneratedContentFixture(t);
  await generated.store.commitPhysicalHolding(generated.holding, [generated.physical.prepared]);
  await generated.issue();
  let borrowed, preparations = 0, closes = 0, pending = true;
  const closeObserved = Promise.withResolvers();
  const closeAcknowledged = Promise.withResolvers();
  const host = await openContentCommandHost({scratch, generated,
    keys: generateKeyPairSync('ed25519'), entrance: 'Local',
    onPrepareContent() { assert.fail('The async child must not start a second synchronous preparation'); },
    prepareContentChild({originalContent, value, preparedRequest}) {
      const release = async () => {
        closes++;
        closeObserved.resolve();
        await closeAcknowledged.promise;
        pending = false;
        return true;
      };
      return Object.freeze({async prepare() {
        preparations++;
        borrowed = originalContent('content');
        assert.equal(borrowed.current(), true);
        await turn();
        assert.equal(borrowed.current(), true);
        assert.strictEqual(originalContent('content'), borrowed);
        assert.deepEqual(JSON.parse(borrowed.wire()), value.content);
        return preparedRequest;
      }, release, retry: release, status: () => ({pending})});
    }});
  t.after(async () => { closeAcknowledged.resolve(); await host.close(); });
  const run = await host.client.start(host.fixture.program);
  await closeObserved.promise;
  assert.equal(closes, 1);
  assert.equal(pending, true);
  assert.equal(borrowed.current(), true,
    'The actual still-pending original child retains the source/pin');
  closeAcknowledged.resolve();
  const state = await run.wait({signal: AbortSignal.timeout(15000)});
  assert.equal(state.status, 'waiting_checkpoint');
  assert.equal(preparations, 1);
  assert.equal(host.reads(), 1);
  assert.equal(host.sends(), 0);
  assert.equal(closes, 1);
  assert.equal(borrowed.current(), false,
    'The same Owner may retire inputs once the last original child actually acknowledges');
  await host.close();
  assert.equal(closes, 1);
  assert.equal(pending, false);
  assert.equal(borrowed.current(), false);
  assert.throws(() => borrowed.wire());
  await generated.store.retirePhysicalHolding(generated.holding.holding_cid);
  scratch.passed();
});
