import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const fields = ['id', 'q', 'rank', 'score', 'segment'];
const names = ['published', 'consumed_a', 'consumed_b'];
// Two [1,...] literals of 129 entries total 518 canonical bytes, below the
// unchanged 1,000-byte nested Values policy, and require 261 recheck polls.
const unusedItems = 129;
const expectedRows = prefix => [1, 2].map(id => ({
  id, q: null, rank: id, score: id === 1 ? 1 : 2 / 3, segment: prefix + 's',
}));

function program(id, prefix, unused = false) {
  const schema = {
    q: {type: 'number', nullable: true},
    segment: {type: 'string', nullable: true},
    id: {type: 'number', nullable: false},
    rank: {type: 'number', nullable: false},
  };
  if (unused) schema.zz_unused = {type: 'array', nullable: false,
    items: {type: 'number', nullable: false}, max_items: unusedItems};
  return {version: 'actql/0.1', id, stages: [
    ...['left', 'right'].map(name => ({id: name, inputs: {},
      steps: [{values: {schema, rows: [2, 1].map(id => ({
        q: null, segment: prefix + 's', id, rank: id,
        ...(unused ? {zz_unused: Array.from({length: unusedItems}, () => 1)} : {}),
      }))}, as: 'out'}], results: {r: {from: 'out', fields: Object.keys(schema)}},
    })),
    {id: 'ranking', inputs: {
      left: {result: {stage: 'left', result: 'r'}},
      right: {result: {stage: 'right', result: 'r'}},
    }, steps: [{from: 'left', merge_rankings: {
      with: ['right'], by: ['q', 'segment'], candidate: 'id', rank: 'rank',
      k: 3, score_policy: {rrf: {rank_constant: 1, weights: [1, 1], rank_window: 2}},
    }, as: 'out'}], results: {r: {from: 'out', fields}}},
    ...['consumer_a', 'consumer_b'].map(name => ({id: name,
      inputs: {rows: {result: {stage: 'ranking', result: 'r'}}},
      steps: [{select: fields, as: 'out'}], results: {r: {from: 'out', fields}},
    })),
  ], results: {
    published: {from: {stage: 'ranking', result: 'r'}},
    consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
    consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
  }};
}

async function runPublicRankingBarrier(t, {unused = false} = {}) {
    const prefix = 'x'.repeat(512);
    const fixtureId = unused ? 'public-ranking-input' : 'public-ranking-key';
    const expected = expectedRows(prefix);
    const directory = await mkdtemp(join(tmpdir(), 'actql-public-ranking-key-'));
    const barrier = Promise.withResolvers();
    const released = Promise.withResolvers();
    let client;
    t.after(async () => {
      released.resolve();
      await client?.close();
      await rm(directory, {recursive: true, force: true});
    });
    let cancelling = false;
    let advances = 0;
    let dispatches = 0;
    let completions = 0;
    let representations;
    const trace = [];
    const keys = generateKeyPairSync('ed25519');
    const authorization = {
      accountConfiguration: canonicalJson({
        version: 'actql-execution-account-config/0.1', account_id: 'ranking-key',
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
        if (cancelling) trace.push({...detail});
        if (!cancelling || detail.task !== 2) return;
        // Ordinary keys: quantum 256 ends inside the first group comparison.
        // With zz_unused, initialization and id/q/rank/segment cost 23,
        // then the array read costs one. Its 232 recheck polls at this
        // boundary cannot exhaust a 129-element array (261 polls).
        // Neither fixture can commit an output row at this boundary.
        assert.equal(detail.work, '256');
        assert.equal(detail.progress, '0');
        barrier.resolve();
        await released.promise;
      },
      observe(step, detail) {
        if (step !== 'computed') return;
        completions++;
        representations = detail.outputRepresentations;
        if (cancelling) barrier.reject(new Error('ranking passed its bounded barrier'));
      },
    };
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: true, authorization}});
    const source = JSON.stringify(program(fixtureId, prefix, unused));
    const options = {format: 'json', requestId: fixtureId};
    const execution = await client.aql(source, options).catch(error => {
      assert.fail(inspect(error, {depth: 8}));
    });
    const state = await execution.wait({signal: AbortSignal.timeout(30_000)});
    assert.equal(state.status, 'succeeded', inspect(state, {depth: 6}));
    assert.deepEqual(Object.keys(state.result_availability).sort(), [...names].sort());
    for (const name of names) assert.deepEqual(await execution.result(name).all(), expected);
    assert.equal(completions, 1);
    assert.ok(representations?.some(item => item.representation === 'retained-file'));
    const finishedAdvances = advances;
    const repeat = await client.aql(source, options);
    assert.deepEqual(repeat.ref, execution.ref);
    assert.deepEqual(await repeat.result('published').all(), expected);
    assert.equal(advances, finishedAdvances);
    assert.equal(dispatches, 1);
    assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);

    cancelling = true;
    const cancel = await client.aql(JSON.stringify(program(fixtureId + '-cancel', prefix, unused)),
      {format: 'json', requestId: fixtureId + '-cancel'});
    await Promise.race([barrier.promise,
      cancel.wait({signal: AbortSignal.timeout(10_000)}).then(state => {
        throw new Error(`ranking missed bounded barrier: ${inspect({state, trace}, {depth: 6})}`);
      })]);
    const atBarrier = advances;
    const retainedAtBarrier = await readdir(join(directory, 'carrier-snapshots'));
    try {
      await cancel.cancel();
      const pending = await cancel.status();
      assert.equal(pending.control.cancellation_requested, true);
      assert.notEqual(pending.control.physical_stop, 'confirmed');
      assert.notEqual(pending.status, 'cancelled');
      assert.equal(completions, 1);
      assert.equal(advances, atBarrier);
      assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), retainedAtBarrier);
    } finally { released.resolve(); }
    const stopped = await cancel.wait({signal: AbortSignal.timeout(10_000)});
    assert.equal(stopped.status, 'cancelled', inspect(stopped, {depth: 6}));
    assert.equal(stopped.control.physical_stop, 'confirmed');
    for (const name of names) {
      assert.equal(stopped.result_availability[name].state, 'unavailable');
      await assert.rejects(cancel.result(name).all());
    }
    assert.equal(completions, 1);
    assert.equal(advances, atBarrier);
    assert.equal(dispatches, 2);
    assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);
}

test('public retained ranking publishes and cancels inside long group comparison',
  {timeout: 45_000}, t => runPublicRankingBarrier(t));

test('public retained ranking publishes and cancels inside unused array recheck',
  {timeout: 45_000}, t => runPublicRankingBarrier(t, {unused: true}));
