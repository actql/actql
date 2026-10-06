import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

// Independent JSON Programs also provide controls for Frontend REPLACE and
// LENGTH spelling acceptance. No prepared handle or internal state is forged.
function program(id, rows, search = 'ana', replacement = 'X') {
  return {version: 'actql/0.1', id, stages: [{
    id: 'source', inputs: {}, steps: [
      {values: {schema: {id: {type: 'number', nullable: false},
        payload: {type: 'string', nullable: true}}, rows}, as: 'seed'},
      {derive: {replaced: {replace: [{field: 'payload'}, {literal: search},
        {literal: replacement}]}, length: {len: {field: 'payload'}}}, as: 'derived'},
      {select: ['id', 'replaced', 'length'], as: 'out'},
    ], results: {out: {from: 'out', fields: ['id', 'replaced', 'length']}},
  }], results: {answer: {from: {stage: 'source', result: 'out'}}}};
}

function authority(observe, faultInjection) {
  const keys = generateKeyPairSync('ed25519');
  return {accountConfiguration: canonicalJson({
    version: 'actql-execution-account-config/0.1', account_id: 'text-functions',
    entries: [{entry_id: 'allow', outcome: 'allow', principal: {all: true},
      connection: {all: true}, resource: {all: true}, operation: {all: true},
      exclusions: []}],
  }), hostKey: {keyId: 'host', privateKey: keys.privateKey.export({
    type: 'pkcs8', format: 'pem'})},
  reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer',
    principalId: userInfo().username,
    publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
  observe, faultInjection};
}

test('public retained REPLACE and LENGTH publish independent Unicode and NULL rows',
  {timeout: 60_000}, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-text-functions-'));
    let client;
    let dispatches = 0;
    let advances = 0;
    let computed;
    t.after(async () => {
      await client?.close();
      await rm(directory, {recursive: true, force: true});
    });
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: true,
        authorization: authority((name, detail) => {
          if (name === 'computed') computed = detail;
        }, name => {
          if (name === 'dispatch_reserved') dispatches++;
          if (name === 'local_compute_advanced') advances++;
        })}});
    for (const [id, rows, search, replacement, expected] of [
      ['literal', [{id: 3, payload: null}, {id: 1, payload: 'banana'},
        {id: 2, payload: ''}], 'ana', 'X',
      // VALUES has explicit occurrence order; these functions do not sort it.
      [{id: 3, replaced: null, length: null}, {id: 1, replaced: 'bXna', length: 6},
        {id: 2, replaced: '', length: 0}]],
      ['unicode', [{id: 1, payload: '😀é😀\r\n'}], '😀', 'é',
      [{id: 1, replaced: 'ééé\r\n', length: 6}]],
      ['empty', [], 'a', 'bb', []],
      ['long', [{id: 1, payload: 'a'.repeat(256)}], 'a', 'bb',
      [{id: 1, replaced: 'b'.repeat(512), length: 256}]],
    ]) {
      const source = JSON.stringify(program(id, rows, search, replacement));
      const priorAdvances = advances;
      const options = {format: 'json', requestId: 'text-' + id};
      const run = await client.aql(source, options);
      const state = await run.wait({signal: AbortSignal.timeout(45_000)});
      assert.equal(state.status, 'succeeded', JSON.stringify(state));
      assert.deepEqual(await run.result('answer').all(), expected);
      assert.deepEqual((await run.result('answer').describe()).columns,
        [{name: 'id', contract: {type: 'number', nullable: false}},
          {name: 'replaced', contract: {type: 'string', nullable: true}},
          {name: 'length', contract: {type: 'number', nullable: true}}]);
      assert.ok(computed.outputRepresentations.some(entry =>
        entry.representation === 'retained-file'));
      assert.ok(advances > priorAdvances, 'ordinary Program used bounded Local dispatch');
      const before = dispatches;
      assert.deepEqual((await client.aql(source, options)).ref, run.ref);
      assert.deepEqual(await (await client.attach(run.ref)).result('answer').all(), expected);
      assert.equal(dispatches, before);
    }
  });

test('public Text call cancellation is delivered after charged progress',
  {timeout: 60_000}, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-text-call-cancel-'));
    const reached = Promise.withResolvers();
    const resume = Promise.withResolvers();
    let client;
    let advances = 0;
    let dispatches = 0;
    let completions = 0;
    t.after(async () => {
      resume.resolve();
      await client?.close();
      await rm(directory, {recursive: true, force: true});
    });
    client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: true,
        authorization: authority(name => {
          if (name === 'computed') {
            completions++;
            reached.reject(new Error('Text call completed before progress barrier'));
          }
        }, async (name, detail) => {
          if (name === 'dispatch_reserved') dispatches++;
          if (name !== 'local_compute_advanced' || BigInt(detail.work) === 0n) return;
          if (++advances === 10) {
            reached.resolve();
            await resume.promise;
          }
        })}});
    const source = JSON.stringify(program('cancel', [{id: 1, payload: 'a'.repeat(4096)}], 'a', 'bb'));
    const options = {format: 'json', requestId: 'text-cancel'};
    const run = await client.aql(source, options);
    await reached.promise;
    const before = advances;
    try {
      await run.cancel();
      const pending = await run.status();
      assert.equal(pending.control.cancellation_requested, true);
      assert.notEqual(pending.control.physical_stop, 'confirmed');
      assert.notEqual(pending.status, 'cancelled');
      assert.equal(completions, 0);
    } finally { resume.resolve(); }
    const stopped = await run.wait({signal: AbortSignal.timeout(15_000)});
    assert.equal(stopped.status, 'cancelled', JSON.stringify(stopped));
    assert.equal(stopped.control.physical_stop, 'confirmed');
    assert.equal(stopped.result_availability.answer.state, 'unavailable');
    await assert.rejects(run.result('answer').all());
    assert.equal(completions, 0);
    assert.equal(advances, before);
    assert.equal(dispatches, 1);
    assert.deepEqual((await client.aql(source, options)).ref, run.ref);
    assert.equal(dispatches, 1);
  });
