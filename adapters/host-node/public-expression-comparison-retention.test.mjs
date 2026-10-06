import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const text = 'g'.repeat(256);
const names = ['published', 'consumed_a', 'consumed_b'];

function program(id) {
  return {version: 'actql/0.1', id, stages: [
    {id: 'producer', inputs: {}, steps: [
      {values: {schema: {id: {type: 'number', nullable: false},
        tag: {type: 'string', nullable: true}}, rows: [{id: 1, tag: text}]}, as: 'seed'},
      {from: 'seed', filter: {eq: [{field: 'tag'}, {literal: text}]}, as: 'matched'},
      {from: 'matched', select: ['id'], as: 'out'},
    ], results: {r: {from: 'out', fields: ['id']}}},
    ...['consumer_a', 'consumer_b'].map(name => ({id: name,
      inputs: {rows: {result: {stage: 'producer', result: 'r'}}},
      steps: [{select: ['id'], as: 'out'}],
      results: {r: {from: 'out', fields: ['id']}},
    })),
  ], results: {
    published: {from: {stage: 'producer', result: 'r'}},
    consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
    consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
  }};
}

test('public retained expression comparison publishes and stops inside its Text scan',
  {timeout: 45_000}, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-public-expression-comparison-'));
    const barrier = Promise.withResolvers();
    const released = Promise.withResolvers();
    let client;
    t.after(async () => {
      released.resolve();
      await client?.close();
      // Keep Store custody if the real owner cannot finish close.
      await rm(directory, {recursive: true, force: true});
    });
    let cancelling = false;
    let phase = 0;
    let childQuanta = 0;
    let advances = 0;
    let dispatches = 0;
    let completions = 0;
    let representations;
    const trace = [];
    const keys = generateKeyPairSync('ed25519');
    const authorization = {
      accountConfiguration: canonicalJson({
        version: 'actql-execution-account-config/0.1', account_id: 'public-expression-comparison',
        entries: [{entry_id: 'write', outcome: 'allow', principal: {all: true},
          connection: {all: true}, resource: {all: true},
          operation: {any_of: ['write']}, exclusions: []}],
      }),
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({
        type: 'pkcs8', format: 'pem'})},
      async faultInjection(step, detail) {
        if (step === 'dispatch_reserved') dispatches++;
        if (step !== 'local_compute_advanced') return;
        advances++;
        if (!cancelling) return;
        trace.push({task: detail.task, work: detail.work, progress: detail.progress});
        assert.equal(detail.task, 0);
        if (phase === 0) {
          assert.equal(detail.progress, '1');
          assert.ok(BigInt(detail.work) > 0n);
          phase = 1;
          return;
        }
        if (phase === 1) {
          assert.equal(detail.work, '1');
          assert.equal(detail.progress, '0');
          phase = 2;
          return;
        }
        assert.equal(detail.work, '256');
        assert.equal(detail.progress, '0');
        childQuanta++;
        if (childQuanta === 3) {
          // The matching bounded-filter fixture certifies a CompareBinary
          // UTF-16 scan, after operand charging, at this exact child quantum.
          barrier.resolve();
          await released.promise;
        }
      },
      observe(step, detail) {
        if (step !== 'computed') return;
        completions++;
        representations = detail.outputRepresentations;
        if (cancelling) barrier.reject(new Error(
          `filter completed before comparison barrier: ${inspect(trace)}`));
      },
    };
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: true, authorization}});
    const source = JSON.stringify(program('public-expression-comparison'));
    const options = {format: 'json', requestId: 'public-expression-comparison'};
    const execution = await client.aql(source, options);
    const state = await execution.wait({signal: AbortSignal.timeout(30_000)});
    assert.equal(state.status, 'succeeded', inspect(state, {depth: 6}));
    for (const name of names) assert.deepEqual(await execution.result(name).all(), [{id: 1}]);
    assert.equal(completions, 1);
    assert.ok(representations?.some(item => item.representation === 'retained-file'));
    const successfulAdvances = advances;
    const repeat = await client.aql(source, options);
    assert.deepEqual(repeat.ref, execution.ref);
    assert.deepEqual(await repeat.result('published').all(), [{id: 1}]);
    assert.equal(advances, successfulAdvances);
    assert.equal(dispatches, 1);
    assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);

    cancelling = true;
    const cancelSource = JSON.stringify(program('public-expression-comparison-cancel'));
    const cancelOptions = {format: 'json', requestId: 'public-expression-comparison-cancel'};
    const cancel = await client.aql(cancelSource, cancelOptions);
    await barrier.promise;
    const advancedAtBarrier = advances;
    try {
      await cancel.cancel();
      const pending = await cancel.status();
      assert.equal(pending.control.cancellation_requested, true);
      assert.notEqual(pending.control.physical_stop, 'confirmed');
      assert.notEqual(pending.status, 'cancelled');
      assert.equal(completions, 1);
      assert.equal(advances, advancedAtBarrier);
      // The fused input remains in the completed-input owner. Its actual
      // root/workspace retention is checked by the matching core fixture.
      assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);
    } finally { released.resolve(); }
    const stopped = await cancel.wait({signal: AbortSignal.timeout(10_000)});
    assert.equal(stopped.status, 'cancelled', inspect(stopped, {depth: 6}));
    assert.equal(stopped.control.physical_stop, 'confirmed');
    for (const name of names) {
      assert.equal(stopped.result_availability[name].state, 'unavailable');
      await assert.rejects(cancel.result(name).all());
    }
    assert.equal(completions, 1);
    assert.equal(advances, advancedAtBarrier);
    assert.equal(dispatches, 2);
    assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);
    const repeatedCancel = await client.aql(cancelSource, cancelOptions);
    assert.deepEqual(repeatedCancel.ref, cancel.ref);
    assert.equal((await repeatedCancel.status()).status, 'cancelled');
    assert.equal(advances, advancedAtBarrier);
    assert.equal(dispatches, 2);
  });
