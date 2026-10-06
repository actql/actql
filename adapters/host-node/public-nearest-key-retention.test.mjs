import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const fields = ['candidate_id', 'query_id', 'rank', 'score'];
const names = ['published', 'consumed_a', 'consumed_b'];
const expectedRows = prefix => ['a', 'b'].flatMap(query => ['a', 'b'].map((candidate, index) => ({
  candidate_id: prefix + candidate, query_id: prefix + query,
  rank: index + 1, score: 5,
})));

function program(id, prefix, direct = false) {
  const schema = {
    id: {type: 'string', nullable: false},
    embedding: {type: 'vector', dimensions: 2, nullable: false},
    ...(direct ? {zz_unused: {type: 'array', nullable: false, max_items: 129,
      items: {type: 'number', nullable: false}}} : {}),
  };
  return {version: 'actql/0.1', id, stages: [
    ...['candidates', 'queries'].map(name => ({id: name, inputs: {},
      steps: [{values: {schema, rows: ['b', 'a'].map(suffix => ({
        id: prefix + suffix, embedding: [1, 2],
        ...(direct ? {zz_unused: Array.from({length: 129}, () => 1)} : {}),
      }))}, as: 'out'}], results: {r: {from: 'out', fields: Object.keys(schema)}},
    })),
    {id: 'nearest', inputs: {
      queries: {result: {stage: 'queries', result: 'r'}},
      candidates: {result: {stage: 'candidates', result: 'r'}},
    }, steps: direct ? [
      {from: 'candidates', nearest: {queries: 'queries', metric: 'dot', k: 2,
        candidate_id: 'id', candidate_vector: 'embedding',
        query_id: 'id', query_vector: 'embedding'}, as: 'out'},
    ] : [
      {from: 'candidates', to_vectors: {id: 'id', vector: 'embedding'}, as: 'cv'},
      {from: 'queries', to_vectors: {id: 'id', vector: 'embedding'}, as: 'qv'},
      {from: 'cv', nearest: {queries: 'qv', metric: 'dot', k: 2}, as: 'out'},
    ], results: {r: {from: 'out', fields}}},
    ...['consumer_a', 'consumer_b'].map(name => ({id: name,
      inputs: {rows: {result: {stage: 'nearest', result: 'r'}}},
      steps: [{select: fields, as: 'out'}], results: {r: {from: 'out', fields}},
    })),
  ], results: {
    published: {from: {stage: 'nearest', result: 'r'}},
    consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
    consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
  }};
}

async function runPublicNearestBarrier(t, {
  prefixLength, barrierWork, barrierProgress, direct = false,
}) {
    const prefix = 'x'.repeat(prefixLength);
    const expected = expectedRows(prefix);
    const directory = await mkdtemp(join(tmpdir(), 'actql-public-nearest-key-'));
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
    let bridges = 0;
    let nearestWork = 0;
    let representations;
    const fixtureId = direct ? 'public-nearest-input' : 'public-nearest-key';
    const trace = [];
    const keys = generateKeyPairSync('ed25519');
    const authorization = {
      accountConfiguration: canonicalJson({
        version: 'actql-execution-account-config/0.1', account_id: 'nearest-key',
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
        if (!direct && bridges < 2) {
          assert.equal(detail.progress, '2');
          // Each bridge reads two fields and commits one record, twice.
          assert.equal(detail.work, '6');
          bridges++;
          return;
        }
        // The existing Carrier cases retain both bridges in the fused task.
        // Direct Relation input: two field rechecks finish before zz_unused;
        // fewer than 256 polls remain for its 261-poll array walk, so this
        // boundary cannot finish the first input. No sleep selects the phase.
        assert.equal(detail.work, '256');
        nearestWork += Number(detail.work);
        if (nearestWork < barrierWork) {
          assert.equal(detail.progress, '0');
          return;
        }
        assert.equal(nearestWork, barrierWork);
        assert.equal(detail.progress, String(barrierProgress));
        barrier.resolve();
        await released.promise;
      },
      observe(step, detail) {
        if (step !== 'computed') return;
        completions++;
        representations = detail.outputRepresentations;
        if (cancelling) barrier.reject(new Error('nearest passed its bounded barrier'));
      },
    };
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: true, authorization}});
    const source = JSON.stringify(program(fixtureId, prefix, direct));
    const options = {format: 'json', requestId: fixtureId};
    const execution = await client.aql(source, options);
    const state = await execution.wait({signal: AbortSignal.timeout(30_000)});
    assert.equal(state.status, 'succeeded', inspect(state, {depth: 6}));
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
    const cancel = await client.aql(JSON.stringify(program(fixtureId + '-cancel', prefix, direct)),
      {format: 'json', requestId: fixtureId + '-cancel'});
    await Promise.race([barrier.promise,
      cancel.wait({signal: AbortSignal.timeout(10_000)}).then(state => {
        throw new Error(`nearest missed bounded barrier: ${inspect({state, trace}, {depth: 6})}`);
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

test('public retained nearest publishes and cancels inside long identity validation',
  {timeout: 45_000}, t => runPublicNearestBarrier(t, {
    prefixLength: 512, barrierWork: 256, barrierProgress: 0,
  }));

test('public retained nearest cancels output after its first committed row',
  {timeout: 45_000}, t => runPublicNearestBarrier(t, {
    prefixLength: 660, barrierWork: 6144, barrierProgress: 1,
  }));

test('public retained nearest admits Relation inputs and cancels inside unused array',
  {timeout: 45_000}, t => runPublicNearestBarrier(t, {
    prefixLength: 1, barrierWork: 256, barrierProgress: 0, direct: true,
  }));
