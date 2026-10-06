import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const names = ['published', 'consumed_a', 'consumed_b'];
const dimensions = 256;
const unused = Array.from({length: 129}, () => 1);
const vector = Array.from({length: dimensions}, () => 1);

function program(id, score) {
  const schema = {
    id: {type: 'number', nullable: false},
    embedding: {type: 'vector', dimensions, nullable: false},
    zz_unused: {type: 'array', nullable: false, max_items: 129,
      items: {type: 'number', nullable: false}},
  };
  const fields = [...Object.keys(schema), ...(score ? ['score'] : [])];
  return {version: 'actql/0.1', id, stages: [
    {id: 'values', inputs: {}, steps: [{values: {schema,
      rows: [{id: 1, embedding: vector, zz_unused: unused}]}, as: 'out'}],
    results: {r: {from: 'out', fields: Object.keys(schema)}}},
    {id: 'bridge', inputs: {rows: {result: {stage: 'values', result: 'r'}}}, steps: [
      {to_vectors: {id: 'id', vector: 'embedding'}, as: 'source'},
      {from: 'source', ...(score ? {score_vectors: {query: vector, metric: 'dot'}} :
        {normalize_vectors: true}), as: 'computed'},
      {from: 'computed', vectors: true, as: 'out'},
    ], results: {r: {from: 'out', fields}}},
    ...['consumer_a', 'consumer_b'].map(id => ({id,
      inputs: {rows: {result: {stage: 'bridge', result: 'r'}}},
      steps: [{select: fields, as: 'out'}], results: {r: {from: 'out', fields}},
    })),
  ], results: {
    published: {from: {stage: 'bridge', result: 'r'}},
    consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
    consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
  }};
}

async function runVectorRecordBoundary(t, score) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-public-vector-record-'));
  const barrier = Promise.withResolvers();
  const released = Promise.withResolvers();
  let client;
  t.after(async () => {
    released.resolve();
    await client?.close();
    await rm(directory, {recursive: true, force: true});
  });
  let cancelling = false;
  let prefixComplete = false;
  let work = 0;
  let dispatches = 0;
  let advances = 0;
  let completions = 0;
  let representations;
  const trace = [];
  const keys = generateKeyPairSync('ed25519');
  const authorization = {
    accountConfiguration: canonicalJson({
      version: 'actql-execution-account-config/0.1', account_id: 'vector-record',
      entries: [{entry_id: 'write', outcome: 'allow', principal: {all: true},
        connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []}],
    }),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
    async faultInjection(step, detail) {
      if (step === 'dispatch_reserved') dispatches++;
      if (step !== 'local_compute_advanced') return;
      advances++;
      if (!cancelling || detail.task !== 1) return;
      trace.push({...detail});
      if (!prefixComplete) {
        // Three input fields and one commit complete the existing bridge.
        assert.equal(detail.work, '4');
        assert.equal(detail.progress, '1');
        prefixComplete = true;
        return;
      }
      assert.equal(detail.work, '256');
      work += Number(detail.work);
      if (work < 768) return;
      assert.equal(work, 768);
      // Kernel computation finishes before 768; the shared append cannot
      // finish its 256-component Vector and 129-item Array at this boundary.
      assert.equal(detail.progress, score ? '1' : '0');
      barrier.resolve();
      await released.promise;
    },
    observe(step, detail) {
      if (step !== 'computed') return;
      completions++;
      representations = detail.outputRepresentations;
      if (cancelling) throw new Error('unfinished vector record was published');
    },
  };
  client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
    installation: {directory, retainedRelationOutput: true, authorization}});
  const fixtureId = score ? 'public-score-record' : 'public-normalize-record';
  const expected = [{id: 1, embedding: score ? vector : vector.map(() => 0.0625),
    zz_unused: unused, ...(score ? {score: 256} : {})}];
  const source = JSON.stringify(program(fixtureId, score));
  const options = {format: 'json', requestId: fixtureId};
  const execution = await client.aql(source, options);
  const state = await execution.wait({signal: AbortSignal.timeout(30_000)});
  assert.equal(state.status, 'succeeded', inspect(state, {depth: 6}));
  assert.deepEqual(Object.keys(state.result_availability).sort(), [...names].sort());
  for (const name of names) assert.deepEqual(await execution.result(name).all(), expected);
  assert.equal(completions, 1);
  assert.ok(representations?.some(item => item.representation === 'retained-file'));
  const completedAdvances = advances;
  const repeated = await client.aql(source, options);
  assert.deepEqual(repeated.ref, execution.ref);
  assert.deepEqual(await repeated.result('published').all(), expected);
  assert.equal(advances, completedAdvances);
  assert.equal(dispatches, 1);
  assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);

  cancelling = true;
  const cancel = await client.aql(JSON.stringify(program(fixtureId + '-cancel', score)),
    {format: 'json', requestId: fixtureId + '-cancel'});
  await Promise.race([barrier.promise,
    cancel.wait({signal: AbortSignal.timeout(10_000)}).then(state => {
      throw new Error(`record append missed bounded barrier: ${inspect({state, trace}, {depth: 6})}`);
    })]);
  const atBarrier = advances;
  const retained = await readdir(join(directory, 'carrier-snapshots'));
  try {
    await cancel.cancel();
    const pending = await cancel.status();
    assert.equal(pending.control.cancellation_requested, true);
    assert.notEqual(pending.control.physical_stop, 'confirmed');
    assert.notEqual(pending.status, 'cancelled');
    assert.equal(completions, 1);
    assert.equal(advances, atBarrier);
    assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), retained);
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

test('public retained Normalize publishes and cancels inside provisional record emission',
  {timeout: 45_000}, t => runVectorRecordBoundary(t, false));
test('public retained Score publishes and cancels inside provisional record emission',
  {timeout: 45_000}, t => runVectorRecordBoundary(t, true));
