import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const column = 'x'.repeat(1024);
const names = ['published', 'consumed_a', 'consumed_b'];
const expected = [{id: 1}, {id: 2}];

function program(id) {
  return {version: 'actql/0.1', id, stages: [
    ...['left', 'right'].map((stage, index) => ({id: stage, inputs: {},
      steps: [{values: {schema: {[column]: {type: 'number', nullable: false}},
        rows: [{[column]: index + 1}]}, as: 'out'}],
      results: {rows: {from: 'out', fields: [column]}}})),
    {id: 'producer', inputs: {left: {result: {stage: 'left', result: 'rows'}},
      right: {result: {stage: 'right', result: 'rows'}}}, steps: [
      {from: 'left', append: {with: 'right'}, as: 'appended'},
      {from: 'appended', select: [{id: column}], as: 'out'},
    ], results: {rows: {from: 'out', fields: ['id']}}},
    ...['consumer_a', 'consumer_b'].map(stage => ({id: stage,
      inputs: {rows: {result: {stage: 'producer', result: 'rows'}}},
      steps: [{select: ['id'], as: 'out'}],
      results: {rows: {from: 'out', fields: ['id']}}})),
  ], results: Object.fromEntries(['producer', 'consumer_a', 'consumer_b']
    .map((stage, index) => [names[index], {from: {stage, result: 'rows'}}]))};
}

test('public retained chain prepares long producer names before child start and cancellation',
  {timeout: 90_000}, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-producer-metadata-'));
    const reached = Promise.withResolvers();
    const release = Promise.withResolvers();
    let client;
    t.after(async () => { release.resolve(); await client?.close();
      await rm(directory, {recursive: true, force: true}); });
    let cancelling = false, afterAppend = false, appendProgress = 0n, preparation = 0;
    let dispatches = 0, advances = 0, completions = 0;
    const keys = generateKeyPairSync('ed25519');
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: true, authorization: {
        accountConfiguration: canonicalJson({version: 'actql-execution-account-config/0.1',
          account_id: 'metadata', entries: [{entry_id: 'allow', outcome: 'allow',
            principal: {all: true}, connection: {all: true}, resource: {all: true},
            operation: {all: true}, exclusions: []}]}),
        hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
        reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
          publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
        observe(name, detail) {
          if (name === 'computed') {
            completions++;
            assert.ok(detail.outputRepresentations.some(entry => entry.representation === 'retained-file'));
            if (cancelling) reached.reject(new Error('chain completed before metadata barrier'));
          }
        },
        async faultInjection(name, detail) {
          if (name === 'dispatch_reserved') dispatches++;
          if (name !== 'local_compute_advanced') return;
          advances++;
          if (!cancelling || detail.task !== 2) return;
          if (!afterAppend) {
            appendProgress += BigInt(detail.progress);
            if (appendProgress === 2n) afterAppend = true;
            return;
          }
          // The existing Append may still report its final tail after its two
          // rows. A run of eight unit-work, zero-row polls reaches the first
          // name fragments: setup/port/probe/field precede sixteen fragments.
          // The lower-level fixture fixes the exact shared cursor transition.
          if (preparation === 0 && (detail.work !== '1' || detail.progress !== '0')) return;
          assert.equal(detail.work, '1');
          assert.equal(detail.progress, '0');
          if (++preparation === 8) { reached.resolve(); await release.promise; }
        },
      }}});
    const source = JSON.stringify(program('metadata-success'));
    const run = await client.aql(source, {format: 'json', requestId: 'metadata-success'});
    const state = await run.wait({signal: AbortSignal.timeout(60_000)});
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    assert.deepEqual(Object.keys(state.result_availability).sort(), names.toSorted());
    for (const name of names) assert.deepEqual(await run.result(name).all(), expected);
    const before = dispatches;
    assert.deepEqual((await client.aql(source, {format: 'json', requestId: 'metadata-success'})).ref, run.ref);
    assert.equal(dispatches, before);
    cancelling = true;
    const stopped = await client.aql(JSON.stringify(program('metadata-cancel')),
      {format: 'json', requestId: 'metadata-cancel'});
    await Promise.race([reached.promise,
      stopped.wait({signal: AbortSignal.timeout(20_000)}).then(state => {
        throw new Error(`metadata barrier not reached: ${JSON.stringify(state)}`);
      })]);
    const beforeStop = advances;
    const held = await readdir(join(directory, 'carrier-snapshots'));
    try {
      await stopped.cancel();
      const pending = await stopped.status();
      assert.equal(pending.control.cancellation_requested, true);
      assert.notEqual(pending.control.physical_stop, 'confirmed');
      assert.notEqual(pending.status, 'cancelled');
      assert.equal(completions, 1);
      assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), held);
    } finally { release.resolve(); }
    const final = await stopped.wait({signal: AbortSignal.timeout(20_000)});
    assert.equal(final.status, 'cancelled', JSON.stringify(final));
    assert.equal(final.control.physical_stop, 'confirmed');
    for (const name of names) { assert.equal(final.result_availability[name].state, 'unavailable');
      await assert.rejects(stopped.result(name).all()); }
    assert.equal(completions, 1);
    assert.equal(advances, beforeStop);
    assert.equal(dispatches, 2);
    assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);
  });
