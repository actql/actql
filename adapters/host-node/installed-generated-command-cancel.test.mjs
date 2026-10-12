// Cancel after actual Store I/O in the original Content child. This is not
// cancellation of a substituted pure Program or a preissued Source Ref.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, readdir} from 'node:fs/promises';
import {join} from 'node:path';
import {inspect} from 'node:util';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createGeneratedContentFixture} from './fixtures/generated-content.fixture.mjs';
import {generatedContentCommandProgram} from './fixtures/content-command.fixture.mjs';
import {openContentCommandHost} from './fixtures/content-command-host.fixture.mjs';

for (const entrance of ['Local', 'HTTPS']) {
for (const failure of ['cancel', 'append_reply_lost']) {
  test(`public ${entrance} original generated COMMAND ${failure} after physical Content append`, async t => {
    const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
      prefix: 'generated-command-cancel-', label: 'Generated Command physical cancellation'});
    const sourceContent = await createGeneratedContentFixture(t);
    await sourceContent.store.commitPhysicalHolding(sourceContent.holding, [sourceContent.physical.prepared]);
    await sourceContent.issue();
    let entered;
    const appended = new Promise(resolve => { entered = resolve; });
    const events = [];
    const host = await openContentCommandHost({scratch, generated: sourceContent,
      keys: generateKeyPairSync('ed25519'), entrance, generatedCommand: true,
      faultInjection: async (event, facts) => {
        events.push(event);
        if (event !== 'effect_content_piece_appended') return;
        assert.ok(facts.byteCount > 0, 'the existing Store actually appended a positive piece');
        entered();
        if (failure === 'append_reply_lost') throw new Error('FixtureContentAppendReplyLost');
        if (!facts.signal.aborted) await new Promise(resolve =>
          facts.signal.addEventListener('abort', resolve, {once: true}));
        facts.signal.throwIfAborted();
      }});
    t.after(host.close);
    const run = await host.client.start(generatedContentCommandProgram());
    const timeout = AbortSignal.timeout(15000);
    await Promise.race([appended, new Promise((_, reject) =>
      timeout.addEventListener('abort', () => reject(timeout.reason), {once: true}))]);
    if (failure === 'cancel') await run.cancel();
    const status = await run.wait({signal: timeout});
    assert.equal(status.status, failure === 'cancel' ? 'cancelled' : 'failed',
      inspect({status, events, observations: host.events}, {depth: 12}));
    assert.equal(status.result_availability.r.state, 'unavailable');
    assert.equal(status.result_availability.r.reason, 'not_published');
    assert.equal(host.reads(), 1);
    assert.equal(host.sends(), 0);
    assert.equal(host.writeGrants(), 0);
    assert.ok(!events.includes('effect_content_generation_retained'));
    await assert.rejects(readFile(host.targetPath), {code: 'ENOENT'});
    await host.close();
    const released = host.events.filter(item => item.event === 'effect_computation_cleanup_completed').at(-1);
    assert.ok(released, inspect(host.events, {depth: 12}));
    // Holdings counts issued allocation serials, not live allocations: the
    // original Source task completed once. Cleanup must not refund that count.
    assert.equal(released.detail.resourceUsage.holdings, '1');
    for (const field of ['heldBytes', 'reservedTransferBytes',
      'reservedRetentionBytes', 'reservedExecutionBytes', 'uncertainTransferBytes']) {
      assert.equal(released.detail.resourceUsage[field], '0', field);
    }
    assert.deepEqual(await readdir(join(scratch.path, 'host', 'publication', 'staging')), [],
      'the original prepared writer is reclaimed after confirmed stop');
    await sourceContent.store.retirePhysicalHolding(sourceContent.holding.holding_cid);
    scratch.passed();
  });
}
}
