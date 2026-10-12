// Public Program -> Source capture -> Command approval -> actual byte storage.
// The shared installed fixture also supports genuine separate-process recovery.
import assert from 'node:assert/strict';
import {generateKeyPairSync, sign} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {setTimeout as delay} from 'node:timers/promises';
import {inspect} from 'node:util';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createGeneratedContentFixture} from './fixtures/generated-content.fixture.mjs';
import {openContentCommandHost} from './fixtures/content-command-host.fixture.mjs';
import {resource} from './fixtures/file-listing-source.fixture.mjs';
import {contentCommandSource} from './fixtures/content-command.fixture.mjs';
for (const entrance of ['Local', 'HTTPS']) {
for (const format of ['program', 'sql', 'aql-text']) {
test(`public ${entrance} ${format} Content COMMAND waits for approval and physically stores the approved bytes`, async t => {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'content-command-', label: 'public physical Content Command'});
  // Reuse actual bounded common generation and finite physical Store. The
  // independent expected CSV is id\n, not encoder-produced expected bytes.
  const generated = await createGeneratedContentFixture(t);
  await generated.store.commitPhysicalHolding(generated.holding, [generated.physical.prepared]);
  await generated.issue();
  const keys = generateKeyPairSync('ed25519');
  const value = await openContentCommandHost({scratch, generated, keys, entrance});
  const {client, close, fixture, events, targetPath} = value;
  const source = format === 'program' ? fixture.program : contentCommandSource({format});
  const content = JSON.parse(generated.description.wire);
  const destination = resource('d');
  t.after(close);
  const checked = await client.check(source, format === 'program'
    ? {kind: 'program', scope: 'bound_input'} : {kind: 'text', format, scope: 'bound_input'});
  assert.equal(checked.outcome, 'completed');
  assert.equal(checked.report.verdict, 'verified', inspect(checked, {depth: 12}));
  assert.deepEqual(checked.report.coverage, {limits: [], unresolved: []});
  assert.equal(value.reads(), 0, 'advisory checking performs no Source I/O');
  assert.equal(value.sends(), 0, 'static Effect closure never dispatches');
  const run = await (format === 'program' ? client.start(source)
    : client.startSource(source, {format})).catch(error => {
    t.diagnostic(inspect({error, events}, {depth: 16}));
    throw error;
  });
  const waiting = await run.wait({signal: AbortSignal.timeout(15000)});
  assert.equal(waiting.status, 'waiting_checkpoint', inspect({waiting, events}, {depth: 12}));
  assert.equal(value.reads(), 1);
  assert.equal(value.sends(), 0);
  await assert.rejects(readFile(targetPath), {code: 'ENOENT'});
  const checkpoint = (await client.checkpoints()).items.find(item => item.kind === 'effect_set');
  assert.ok(checkpoint);
  const answer = await client.resolveCheckpoints([{checkpoint, decision: 'approved'}],
    {signer: {keyId: 'reviewer', reviewerId: 'reviewer', authorityScopeCid: run.ref.authorityScopeCid,
      sign: bytes => sign(null, bytes, keys.privateKey)}});
  assert.equal(answer.results[0].status, 'committed');
  const resumeSignal = AbortSignal.timeout(15000);
  const resumedAt = performance.now();
  let polls = 0;
  let final;
  try {
    do {
      final = await run.status({signal: resumeSignal});
      polls++;
      if (!['resuming', 'running', 'waiting_checkpoint'].includes(final.status)) break;
      await delay(20, undefined, {signal: resumeSignal});
    } while (true);
  } catch (error) {
    // Observe the same failed acceptance, never increase its budget or convert
    // eventual durable success into successful completion of this test.
    t.diagnostic(JSON.stringify({phase: 'resume', format, elapsedMs: performance.now() - resumedAt,
      polls, lastStatus: final?.status, reads: value.reads(), sends: value.sends(),
      events: events.slice(-32).map(item => item.event)}));
    throw error;
  }
  assert.equal(final.status, 'succeeded', inspect({final, events}, {depth: 12}));
  assert.deepEqual(await readFile(targetPath), Buffer.from('id\n'));
  assert.deepEqual(await run.result('r').all(), [{destination, name: 'approved.csv', content}]);
  assert.equal(value.sends(), 1);
  assert.equal(value.reads(), 1);
  await close();
  await generated.store.retirePhysicalHolding(generated.holding.holding_cid);
  scratch.passed();
});
}
}
