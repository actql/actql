import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const a = 'g'.repeat(256) + 'a';
const b = 'g'.repeat(256) + 'b';
const fields = ['item', 'position'];
const expected = [{item: a, position: 0}, {item: b, position: 0},
  {item: null, position: 1}, {item: null, position: 1}];

function program(id) {
  return {version: 'actql/0.1', id, stages: [
    {id: 'producer', inputs: {}, steps: [
      {values: {schema: {id: {type: 'object', nullable: false, fields: {
        p: {type: 'array', nullable: false, items: {type: 'string', nullable: true}},
      }}}, rows: [{id: {p: [a, null]}}, {id: {p: [b, null]}},
        {id: {p: [a, null]}}]}, as: 'seed'},
      {from: 'seed', distinct: true, as: 'unique'},
      {from: 'unique', derive: {items: {property: {value: {field: 'id'}, name: 'p'}}},
        as: 'arrays'},
      {from: 'arrays', unnest: {column: 'items', as: 'item',
        with_index: 'position', outer: false}, as: 'expanded'},
      {from: 'expanded', select: fields, as: 'projected'},
      {from: 'projected', sort: [{position: 'asc'}, {item: 'asc'}], as: 'out'},
    ], results: {r: {from: 'out', fields}}},
    ...['consumer_a', 'consumer_b'].map(name => ({id: name,
      inputs: {rows: {result: {stage: 'producer', result: 'r'}}},
      steps: [{select: name === 'consumer_a' ? fields : [...fields].reverse(),
        as: 'out'}], results: {r: {from: 'out', fields}},
    })),
  ], results: {
    published: {from: {stage: 'producer', result: 'r'}},
    consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
    consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
  }};
}

test('public retained DISTINCT scans nested values, publishes and cancels without redispatch',
  {timeout: 60_000}, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-public-distinct-values-'));
    const barrier = Promise.withResolvers();
    const released = Promise.withResolvers();
    let client;
    t.after(async () => {
      released.resolve();
      await client?.close();
      // Preserve Store custody if the actual owner cannot close.
      await rm(directory, {recursive: true, force: true});
    });
    let cancelAtComparison = false;
    let work = 0n;
    let advances = 0;
    let dispatches = 0;
    let completions = 0;
    let outputRepresentations;
    let childPhase = 0;
    const comparisonAdvances = [];
    const keys = generateKeyPairSync('ed25519');
    const authorization = {
      accountConfiguration: canonicalJson({
        version: 'actql-execution-account-config/0.1', account_id: 'public-distinct-values',
        entries: [{entry_id: 'write', outcome: 'allow', principal: {all: true},
          connection: {all: true}, resource: {all: true},
          operation: {any_of: ['write']}, exclusions: []}],
      }),
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer',
        principalId: userInfo().username,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({
        type: 'pkcs8', format: 'pem'})},
      async faultInjection(step, detail) {
        if (step === 'dispatch_reserved') dispatches++;
        if (step !== 'local_compute_advanced') return;
        advances++;
        if (!cancelAtComparison) return;
        comparisonAdvances.push({task: detail.task, work: detail.work, progress: detail.progress});
        // The ordinary Program is one fused producer task. The existing
        // chain reports Values completion, then one unit to start DISTINCT;
        // subsequent full advances are the certified child kernel quanta.
        assert.equal(detail.task, 0);
        if (childPhase === 0) {
          assert.equal(detail.progress, '3');
          assert.ok(BigInt(detail.work) > 0n);
          childPhase = 1;
          return;
        }
        if (childPhase === 1) {
          assert.equal(detail.work, '1');
          assert.equal(detail.progress, '0');
          childPhase = 2;
          return;
        }
        assert.equal(detail.work, '256');
        assert.equal(detail.progress, '0');
        work += BigInt(detail.work);
        if (work === 2304n) {
          // The matching kernel test certifies an actual UTF-16 scan here,
          // rather than measuring a delay or cancelling during value admission.
          assert.equal(detail.progress, '0');
          barrier.resolve();
          await released.promise;
        }
      },
      observe(step, detail) {
        if (step === 'computed') {
          completions++;
          outputRepresentations = detail.outputRepresentations;
          if (cancelAtComparison) barrier.reject(new Error(
            `DISTINCT completed before comparison barrier: ${inspect(comparisonAdvances)}`));
        }
      },
    };
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: true, authorization}});

    const source = JSON.stringify(program('public-distinct-values'));
    const options = {format: 'json', requestId: 'public-distinct-values'};
    const execution = await client.aql(source, options);
    const state = await execution.wait({signal: AbortSignal.timeout(45_000)});
    assert.equal(state.status, 'succeeded', inspect(state, {depth: 5}));
    for (const name of ['published', 'consumed_a', 'consumed_b']) {
      assert.deepEqual(await execution.result(name).all(), expected);
    }
    assert.ok(advances > 0);
    assert.equal(completions, 1);
    assert.ok(outputRepresentations?.some(value => value.representation === 'retained-file'));
    const successfulAdvances = advances;
    const repeated = await client.aql(source, options);
    assert.deepEqual(repeated.ref, execution.ref);
    assert.deepEqual(await repeated.result('published').all(), expected);
    assert.equal(dispatches, 1);
    assert.equal(advances, successfulAdvances);
    assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);

    cancelAtComparison = true;
    const cancelSource = JSON.stringify(program('public-distinct-values-cancel'));
    const cancelOptions = {format: 'json', requestId: 'public-distinct-values-cancel'};
    const cancelled = await client.aql(cancelSource, cancelOptions);
    await barrier.promise;
    const before = await readdir(join(directory, 'carrier-snapshots'));
    // The same-task Values input stays in the chain's completed-input owner,
    // not an invented intermediate Store lease. No output is sealed yet.
    assert.deepEqual(before, []);
    const advancedAtBarrier = advances;
    try {
      await cancelled.cancel();
      const waiting = await cancelled.status();
      assert.equal(waiting.control.cancellation_requested, true);
      assert.notEqual(waiting.control.physical_stop, 'confirmed');
      assert.notEqual(waiting.status, 'cancelled');
      assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), before);
      assert.equal(completions, 1);
    } finally { released.resolve(); }
    const stopped = await cancelled.wait({signal: AbortSignal.timeout(15_000)});
    assert.equal(stopped.status, 'cancelled', inspect(stopped, {depth: 5}));
    assert.equal(stopped.control.physical_stop, 'confirmed');
    for (const name of ['published', 'consumed_a', 'consumed_b']) {
      assert.equal(stopped.result_availability[name].state, 'unavailable');
      await assert.rejects(cancelled.result(name).all());
    }
    assert.equal(completions, 1);
    assert.equal(dispatches, 2);
    assert.equal(advances, advancedAtBarrier);
    assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);
    const cancelledAgain = await client.aql(cancelSource, cancelOptions);
    assert.deepEqual(cancelledAgain.ref, cancelled.ref);
    assert.equal((await cancelledAgain.status()).status, 'cancelled');
    assert.equal(dispatches, 2);
    assert.equal(advances, advancedAtBarrier);
  });
