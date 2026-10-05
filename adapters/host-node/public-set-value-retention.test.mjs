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
const schema = {items: {type: 'array', nullable: false, max_items: 2,
  items: {type: 'string', nullable: true}},
  marker: {type: 'number', nullable: false}};

function retainedSetProgram(id, operation, duplicates) {
  return {version: 'actql/0.1', id, stages: [
    {id: 'producer', inputs: {}, steps: [
      {values: {schema, rows: [{items: [a, null], marker: 1},
        {items: [a, null], marker: 1}, {items: [b, null], marker: 2}]}, as: 'l'},
      {from: 'l', filter: 'marker = 1', as: 'r'},
      {from: 'l', [operation]: {with: 'r', duplicates}, as: 'survivors'},
      {from: 'survivors', unnest: {column: 'items', as: 'item',
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

function retainedSetAuthorization(accountId, hooks) {
  const keys = generateKeyPairSync('ed25519');
  return {
    accountConfiguration: canonicalJson({
      version: 'actql-execution-account-config/0.1', account_id: accountId,
      entries: [{entry_id: 'write', outcome: 'allow', principal: {all: true},
        connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []}],
    }),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer',
      principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({
      type: 'pkcs8', format: 'pem'})},
    ...hooks,
  };
}

test('public retained Set compares nested values before scalar publication',
  {timeout: 60_000}, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-public-set-values-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    let advances = 0;
    let completions = 0;
    let outputRepresentations;
    const observations = [];
    const authorization = retainedSetAuthorization('public-set-values', {
      faultInjection(step) {
        if (step === 'local_compute_advanced') advances++;
      },
      observe(step, detail) {
        observations.push({step, detail});
        if (step === 'computed') {
          completions++;
          outputRepresentations = detail.outputRepresentations;
        }
      },
    });
    const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: true, authorization}});
    t.after(() => client.close());
    for (const [operation, duplicates, expected] of [
      ['except', 'all', [
        {item: b, position: 0}, {item: null, position: 1},
      ]],
      ['except', 'distinct', [
        {item: b, position: 0}, {item: null, position: 1},
      ]],
      ['intersect', 'all', [
        {item: a, position: 0}, {item: a, position: 0},
        {item: null, position: 1}, {item: null, position: 1},
      ]],
      ['intersect', 'distinct', [
        {item: a, position: 0}, {item: null, position: 1},
      ]],
    ]) {
      const id = `public-set-${operation}-${duplicates}`;
      const program = retainedSetProgram(id, operation, duplicates);
      const source = JSON.stringify(program);
      const options = {format: 'json', requestId: id};
      const execution = await client.aql(source, options).catch(error => {
        assert.fail(inspect(error, {depth: 8}));
      });
      const state = await execution.wait({signal: AbortSignal.timeout(45_000)});
      assert.equal(state.status, 'succeeded', inspect({state, observations}, {depth: 8}));
      for (const name of ['published', 'consumed_a', 'consumed_b']) {
        assert.deepEqual(await execution.result(name).all(), expected, `${id}/${name}`);
      }
      assert.ok(outputRepresentations?.some(value =>
        value.representation === 'retained-file'));
      const savedAdvances = advances;
      const savedCompletions = completions;
      const repeated = await client.aql(source, options);
      assert.deepEqual(repeated.ref, execution.ref);
      assert.deepEqual(await repeated.result('published').all(), expected);
      assert.equal(advances, savedAdvances);
      assert.equal(completions, savedCompletions);
    }
    assert.ok(advances > 0);
    assert.equal(completions, 4);
    assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);
  });

test('public retained Set cancellation interrupts a confirmed nested Text scan',
  {timeout: 30_000}, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-public-set-cancel-'));
    const reached = Promise.withResolvers();
    const released = Promise.withResolvers();
    let client;
    t.after(async () => {
      released.resolve();
      await client?.close();
      // Do not delete Store custody if closing the actual owner fails.
      await rm(directory, {recursive: true, force: true});
    });
    let setWork = 0n;
    let advanced = 0;
    let completions = 0;
    let dispatches = 0;
    let sealed = 0;
    const observations = [];
    const authorization = retainedSetAuthorization('public-set-cancel', {
      async faultInjection(step, detail) {
        if (step === 'dispatch_reserved') dispatches++;
        if (step === 'local_retained_output_sealed') sealed++;
        if (step !== 'local_compute_advanced') return;
        advanced++;
        if (detail.task !== 2) return;
        setWork += BigInt(detail.work);
        if (setWork === 2048n) {
          // The matching kernel fixture fixes this barrier inside Text scan,
          // after input admission, with no output row or completion yet.
          assert.equal(detail.progress, '0');
          reached.resolve();
          await released.promise;
        }
      },
      observe(step, detail) {
        observations.push({step, detail});
        if (step === 'computed') completions++;
      },
    });
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: true, authorization}});
    const source = JSON.stringify(retainedSetProgram('public-set-cancel', 'except', 'all'));
    const options = {format: 'json', requestId: 'public-set-cancel'};
    const execution = await client.aql(source, options);
    await reached.promise;
    assert.equal(setWork, 2048n);
    assert.equal(sealed, 2);
    const before = await readdir(join(directory, 'carrier-snapshots'));
    assert.equal(before.length, 2);
    const advancedBefore = advanced;
    try {
      await execution.cancel();
      const waiting = await execution.status();
      assert.equal(waiting.control.cancellation_requested, true);
      assert.notEqual(waiting.control.physical_stop, 'confirmed');
      assert.notEqual(waiting.status, 'cancelled');
      assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), before);
      assert.equal(completions, 0);
    } finally { released.resolve(); }
    const stopped = await execution.wait({signal: AbortSignal.timeout(15_000)});
    assert.equal(stopped.status, 'cancelled', inspect({stopped, observations}, {depth: 5}));
    assert.equal(stopped.control.physical_stop, 'confirmed');
    for (const name of ['published', 'consumed_a', 'consumed_b']) {
      assert.equal(stopped.result_availability[name].state, 'unavailable');
      await assert.rejects(execution.result(name).all());
    }
    assert.equal(completions, 0);
    assert.equal(advanced, advancedBefore);
    assert.equal(sealed, 2);
    assert.equal(dispatches, 1);
    assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);
    const repeated = await client.aql(source, options);
    assert.deepEqual(repeated.ref, execution.ref);
    assert.equal((await repeated.status()).status, 'cancelled');
    assert.equal(dispatches, 1);
    assert.equal(advanced, advancedBefore);
  });
