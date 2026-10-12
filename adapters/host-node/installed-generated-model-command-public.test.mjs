// Real public composition on the rebuilt runtime. No authored Ref envelope,
// pure-Program substitution, paid provider or physical send double is used.
import assert from 'node:assert/strict';
import {generateKeyPairSync, sign} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {inspect} from 'node:util';
import {setTimeout as delay} from 'node:timers/promises';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {createGeneratedContentFixture} from './fixtures/generated-content.fixture.mjs';
import {generatedContentModelCommandProgram} from './fixtures/content-command.fixture.mjs';
import {openContentCommandHost} from './fixtures/content-command-host.fixture.mjs';
import {mediaInstallation, generatedContentModelProviders} from
  './fixtures/generated-model-installation.fixture.mjs';

for (const entrance of ['Local', 'HTTPS']) {
  test(`public ${entrance} original SERIALIZE INFER COMMAND preserves both families through approval`, async t => {
    const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
      prefix: 'generated-model-command-', label: 'Content Model Command public composition'});
    const source = await createGeneratedContentFixture(t);
    await source.store.commitPhysicalHolding(source.holding, [source.physical.prepared]);
    await source.issue();
    const media = await mediaInstallation({requestBytes: 4096});
    const keys = generateKeyPairSync('ed25519');
    const events = [];
    const startedAt = performance.now();
    let calls = 0, generations = 0, physicalIssue;
    const expected = Buffer.from('name\n"approved.csv"\n');
    const host = await openContentCommandHost({scratch, generated: source, keys, entrance,
      generatedCommand: true, modelInstallation: media.installation,
      hostCapacityPolicy: media.hostCapacityPolicy,
      registerModelProviders: generatedContentModelProviders({root: scratch.path,
        task: media.task, expected, sourceWire: source.description.wire,
        onSend: () => calls++, onFailure: error => { physicalIssue = error; }}),
      faultInjection(event, facts) {
        events.push({event, elapsedMs: Math.round(performance.now() - startedAt), facts});
        if (event === 'effect_content_generation_retained') generations++;
      }});
    t.after(host.close);
    const program = generatedContentModelCommandProgram();
    const report = await host.client.check(program, {kind: 'program', scope: 'bound_input'});
    assert.equal(report.report.verdict, 'verified', inspect(report, {depth: 16}));
    assert.deepEqual([host.reads(), calls, host.sends()], [0, 0, 0]);
    const run = await host.client.start(program).catch(error => {
      t.diagnostic(inspect({error, events, observations: host.events}, {depth: 20}));
      throw error;
    });
    const status = await run.wait({signal: AbortSignal.timeout(15000)}).catch(async error => {
      t.diagnostic(inspect({error, status: await run.status(), events,
        observations: host.events, physicalIssue, reads: host.reads(),
        calls, generations, sends: host.sends()}, {depth: 20}));
      throw error;
    });
    const details = () => inspect({status, events, observations: host.events,
      physicalIssue, reads: host.reads(), calls, generations, sends: host.sends()}, {depth: 16});
    assert.equal(status.status, 'waiting_checkpoint', details());
    assert.deepEqual([host.reads(), generations, calls, host.sends()], [1, 1, 1, 0]);
    const completion = events.find(value => value.event === 'effect_content_generation_retained')
      ?.facts.completion;
    assert.ok(completion, 'original Content producer completion is retained before Model approval');
    const descriptor = JSON.parse(completion.descriptorWire);
    assert.equal(descriptor.version, 'actql-host-model-input-completion/0.1');
    assert.equal(descriptor.rows, 1);
    assert.equal(descriptor.columns, 5);
    assert.equal(completion.rows.length, 1);
    const savedProducer = JSON.parse(completion.rows[0]);
    assert.deepEqual(Object.keys(savedProducer), ['content', 'media_type', 'name', 'row_count', 'size_bytes']);
    assert.equal(savedProducer.name, 'approved.csv');
    assert.equal(savedProducer.media_type, 'text/csv');
    assert.equal(savedProducer.row_count, 1);
    assert.equal(savedProducer.size_bytes, expected.byteLength);
    assert.equal(savedProducer.content.metadata.content_cid,
      'sha256:11af3859185fd4b8e2cef2ba824fdddf63b8a6fbfa26aea783660fefda5459de');
    const binding = JSON.parse(completion.binding);
    assert.equal(binding[0], 'actql-host-content-producer-completion/0.1');
    assert.equal(binding.length, 6);
    assert.equal(binding[5], descriptor.output_step);
    await assert.rejects(readFile(host.targetPath), {code: 'ENOENT'});
    const {items} = await host.client.checkpoints();
    const approvals = items.filter(item => item.kind === 'effect_set');
    assert.equal(approvals.length, 1);
    const resolution = await host.client.resolveCheckpoints([{checkpoint: approvals[0], decision: 'approved'}],
      {signer: {keyId: 'reviewer', reviewerId: 'reviewer', authorityScopeCid: run.ref.authorityScopeCid,
        sign: bytes => sign(null, bytes, keys.privateKey)}});
    assert.equal(resolution.results[0].status, 'committed');
    let final;
    const signal = AbortSignal.timeout(15000);
    do {
      final = await run.status({signal});
      if (!['resuming', 'running', 'waiting_checkpoint'].includes(final.status)) break;
      await delay(20, undefined, {signal});
    } while (true);
    assert.equal(final.status, 'succeeded', inspect({final, events, observations: host.events}, {depth: 16}));
    assert.deepEqual(await readFile(host.targetPath), expected);
    const rows = await run.result('r').all();
    assert.equal(rows.length, 1);
    assert.equal(rows[0].name, 'approved.csv');
    assert.deepEqual(savedProducer.content, rows[0].content,
      'the authentic producer reference survives Model KEEP and public projection');
    assert.equal(rows[0].content.metadata.content_cid,
      'sha256:11af3859185fd4b8e2cef2ba824fdddf63b8a6fbfa26aea783660fefda5459de');
    assert.deepEqual([host.reads(), generations, calls, host.sends()], [1, 1, 1, 1]);
    await host.close();
    await source.store.retirePhysicalHolding(source.holding.holding_cid);
    scratch.passed();
  });
}
