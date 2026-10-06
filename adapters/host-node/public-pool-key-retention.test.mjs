import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {inspect} from 'node:util';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const prefix = 'g'.repeat(512);
const fields = ['group', 'embedding', 'member_count'];
const names = ['published', 'consumed_a', 'consumed_b'];
const expected = ['a', 'b'].map(suffix => ({
  group: prefix + suffix, embedding: [1, 2], member_count: 1,
}));

function program(id, direct = false, outputScan = false, identityScan = false) {
  const dimensions = outputScan ? 257 : 2;
  const schema = {
    id: {type: 'number', nullable: false},
    group: {type: outputScan ? 'number' : 'string', nullable: false},
    embedding: {type: 'vector', dimensions, nullable: false},
    ...(direct ? {zz_unused: {type: 'array', nullable: false, max_items: 129,
      items: {type: 'number', nullable: false}}} : {}),
  };
  return {version: 'actql/0.1', id, stages: [
    {id: 'values', inputs: {}, steps: [{values: {schema,
      rows: (outputScan || identityScan ? ['a'] : ['b', 'a']).map((suffix, index) => ({
      id: index + 1, group: outputScan ? 1 : identityScan ? 'g'.repeat(8096) : prefix + suffix,
      embedding: outputScan ? Array.from({length: dimensions}, () => 1) : [1, 2],
      ...(direct ? {zz_unused: Array.from({length: 129}, () => 1)} : {}),
    }))}, as: 'out'}, ...(direct ? [
      {from: 'out', assert_rows: {unique_by: ['id']}, as: 'keyed'},
    ] : [])], results: {r: {from: direct ? 'keyed' : 'out',
      fields: Object.keys(schema)}}},
    {id: 'bridge', inputs: {rows: {result: {stage: 'values', result: 'r'}}},
      steps: direct ? [
        {pool_vectors: {vector: 'embedding', by: ['group'], method: 'sum'}, as: 'pooled'},
        {from: 'pooled', vectors: true, as: 'out'},
      ] : [{to_vectors: {id: 'id', vector: 'embedding'}, as: 'source'},
        {from: 'source', pool_vectors: {by: ['group'], method: 'sum'}, as: 'pooled'},
        {from: 'pooled', vectors: true, as: 'out'}],
      results: {r: {from: 'out', fields}}},
    ...['consumer_a', 'consumer_b'].map(name => ({id: name,
      inputs: {rows: {result: {stage: 'bridge', result: 'r'}}},
      steps: [{select: fields, as: 'out'}], results: {r: {from: 'out', fields}},
    })),
  ], results: {
    published: {from: {stage: 'bridge', result: 'r'}},
    consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
    consumed_b: {from: {stage: 'consumer_b', result: 'r'}},
  }};
}

async function runPublicPoolBarrier(t, {direct = false, outputScan = false,
  identityScan = false} = {}) {
    const directory = await mkdtemp(join(tmpdir(), 'actql-public-pool-key-'));
    const barrier = Promise.withResolvers();
    const released = Promise.withResolvers();
    let client;
    t.after(async () => {
      released.resolve();
      await client?.close();
      // Failed close leaves the real Store custody available for retry.
      await rm(directory, {recursive: true, force: true});
    });
    let cancelling = false;
    let advances = 0;
    let dispatches = 0;
    let completions = 0;
    let representations;
    const fixtureId = identityScan ? 'public-pool-identity' : outputScan ? 'public-pool-output' :
      direct ? 'public-pool-input' : 'public-pool-key';
    const expectedRows = identityScan ? [{group: 'g'.repeat(8096), embedding: [1, 2],
      member_count: 1}] : outputScan ? [{group: 1,
      embedding: Array.from({length: 257}, () => 1), member_count: 1}] : expected;
    const trace = [];
    let prefixComplete = false;
    let poolWork = 0;
    let poolProgress = 0;
    const keys = generateKeyPairSync('ed25519');
    const authorization = {
      accountConfiguration: canonicalJson({
        version: 'actql-execution-account-config/0.1', account_id: 'pool-key',
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
        if (!cancelling || detail.task !== 1) return;
        if (!direct && !prefixComplete) {
          assert.equal(detail.progress, outputScan || identityScan ? '1' : '2');
          assert.equal(detail.work, outputScan || identityScan ? '4' : '8');
          prefixComplete = true;
          return;
        }
        if (outputScan || identityScan) {
          // One 257-dimensional member needs >1,000 control steps before
          // output, then >257 wire polls. 1280 lies inside the output vector;
          // the kernel fixture independently fixes that shared cursor boundary.
          poolWork += Number(detail.work);
          poolProgress += Number(detail.progress);
          assert.ok(Number(detail.work) <= 256);
          // The matching kernel derives 8,192 inside canonical identity
          // hashing for the 8,096-unit group, before record emission.
          const boundary = identityScan ? 8192 : 1280;
          if (poolWork < boundary) return;
          assert.equal(poolWork, boundary);
          assert.equal(poolProgress, 1);
          barrier.resolve();
          await released.promise;
          return;
        }
        // Carrier mode stops in long group validation after the bridge.
        // Relation mode has an unused array requiring 261 recheck polls;
        // other field/control units leave fewer than 256 for that array.
        // Neither first quantum can commit a Pool record or output group.
        assert.equal(detail.work, '256');
        assert.equal(detail.progress, '0');
        barrier.resolve();
        await released.promise;
      },
      observe(step, detail) {
        if (step !== 'computed') return;
        completions++;
        representations = detail.outputRepresentations;
        if (cancelling) barrier.reject(new Error(`Pool passed its scan barrier: ${inspect(trace)}`));
      },
    };
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: true, authorization}});
    const source = JSON.stringify(program(fixtureId, direct, outputScan, identityScan));
    const options = {format: 'json', requestId: fixtureId};
    const execution = await client.aql(source, options);
    const state = await execution.wait({signal: AbortSignal.timeout(30_000)});
    assert.equal(state.status, 'succeeded', inspect(state, {depth: 6}));
    for (const name of names) assert.deepEqual(await execution.result(name).all(), expectedRows);
    assert.deepEqual(Object.keys(state.result_availability).sort(), names.toSorted());
    assert.equal(completions, 1);
    assert.ok(representations?.some(item => item.representation === 'retained-file'));
    const finishedAdvances = advances;
    const repeat = await client.aql(source, options);
    assert.deepEqual(repeat.ref, execution.ref);
    assert.deepEqual(await repeat.result('published').all(), expectedRows);
    assert.equal(advances, finishedAdvances);
    assert.equal(dispatches, 1);
    assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);

    cancelling = true;
    const cancel = await client.aql(JSON.stringify(program(fixtureId + '-cancel', direct, outputScan, identityScan)),
      {format: 'json', requestId: fixtureId + '-cancel'});
    await barrier.promise;
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

test('public retained Pool publishes and cancels inside long group validation',
  {timeout: 45_000}, t => runPublicPoolBarrier(t));

test('public retained Pool admits Relation input and cancels inside unused array',
  {timeout: 45_000}, t => runPublicPoolBarrier(t, {direct: true}));

test('public retained Pool publishes and cancels inside output Vector encoding',
  {timeout: 45_000}, t => runPublicPoolBarrier(t, {outputScan: true}));

test('public retained Pool publishes and cancels inside output identity hashing',
  {timeout: 45_000}, t => runPublicPoolBarrier(t, {identityScan: true}));
