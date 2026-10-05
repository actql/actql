import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readFile, readdir, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const hash = value => `sha256:${createHash('sha256')
  .update(canonicalJson(value)).digest('hex')}`;
const longText = 'x'.repeat(4096);
const fixture = JSON.parse(await readFile(new URL(
  '../../scripts/fixtures/property-graph-presence.program.json', import.meta.url), 'utf8'));

function bindingProgram() {
  const document = structuredClone(fixture);
  document.id = 'public-long-binding-retention';
  const steps = document.stages[0].steps;
  steps[0].values.schema.p = {type: 'string', nullable: true};
  steps[0].values.rows[1].p = longText;
  steps.splice(5, steps.length - 5,
    {filter: {literal: true}, as: 'filtered'},
    {derive: {marker: {literal: 1}}, as: 'derived'},
    {select: ['id', 'labels', 'marker'], as: 'projected'});
  document.stages[0].results.out.fields = ['id', 'labels', 'marker'];
  for (const name of ['first', 'second']) document.stages.push({
    id: name, inputs: {rows: {result: {stage: 'source', result: 'out'}}},
    steps: [{select: name === 'first' ? ['id', 'marker'] : ['labels', 'marker'], as: 'out'}],
    results: {out: {from: 'out', fields: name === 'first'
      ? ['id', 'marker'] : ['labels', 'marker']}},
  });
  document.results = Object.fromEntries(['source', 'first', 'second'].map(stage =>
    [stage, {from: {stage, result: 'out'}}]));
  return document;
}

// Derive only the definition identity from authored declarations. The row
// order and all presence/value states below are independently specified.
function expectedBindingRows(document) {
  const steps = document.stages[0].steps;
  const constructor = structuredClone(steps[3].property_graph);
  let occurrence = 0;
  for (const family of ['nodes', 'edges']) for (const entry of constructor[family]) {
    delete entry.from;
    entry.input_occurrence = occurrence++;
  }
  const domain = hash({constructor,
    producer_definitions: steps.slice(0, 3).map(step =>
      ({body: {values: step.values}, dependencies: []})),
    version: 'actql-property-graph-definition/0.1'});
  const id = (definition, key, kinds) => ({definition, domain, key,
    key_types: kinds.map(kind => ({kind}))});
  const before = [
    {company_key: 3, id: id('M', [3], ['number']), labels: []},
    {id: id('N', [1, 'a'], ['number', 'string']), labels: ['Owner', 'Person'],
      p: longText, person_key: 1, tenant_key: 'a'},
    {id: id('N', [2, 'a'], ['number', 'string']), labels: ['Owner', 'Person'],
      p: null, person_key: 2, tenant_key: 'a'},
  ];
  assert.equal(Object.hasOwn(before[0], 'p'), false);
  assert.equal(before[1].p.length, 4096);
  assert.equal(before[2].p, null);
  return {before, derived: before.map(row => ({...row, marker: 1})),
    source: before.map(({id, labels}) => ({id, labels, marker: 1})),
    first: before.map(({id}) => ({id, marker: 1})),
    second: before.map(({labels}) => ({labels, marker: 1}))};
}

function authorization(observe, faultInjection) {
  const keys = generateKeyPairSync('ed25519');
  return {
    accountConfiguration: canonicalJson({version: 'actql-execution-account-config/0.1',
      account_id: 'public-binding-retention', entries: [{entry_id: 'allow',
        outcome: 'allow', principal: {all: true}, connection: {all: true},
        resource: {all: true}, operation: {all: true}, exclusions: []}]}),
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer',
      principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'host', privateKey: keys.privateKey.export({
      type: 'pkcs8', format: 'pem'})}, observe, faultInjection,
  };
}

function assertSnapshot(actual, task, rows) {
  const bytes = Buffer.byteLength(canonicalJson(rows));
  assert.deepEqual(actual.find(entry => entry.task === task), {
    task, cid: hash(rows), bytes, verifiedReadBytes: bytes, rows: rows.length,
    sourceReleased: true, sourceReadRejected: true, restored: true,
    temporaryBodyReclaimed: true,
  }, `task ${task} preserves exact sparse rows through the real Store`);
}

test('public binding rows retain absent NULL and long Text through Store and two consumers',
  {timeout: 120_000}, async t => {
    const directory = await mkdtemp(join(tmpdir(), 'actql-public-binding-'));
    t.after(() => rm(directory, {recursive: true, force: true}));
    let computed;
    const auth = authorization((name, detail) => {
      if (name === 'computed') computed = detail;
    });
    const open = () => connectEmbeddedLocal({mode: 'local', owner: 'local',
      installation: {directory, retainedRelationOutput: true, authorization: auth}});
    let client = await open();
    t.after(() => client.close());
    const document = bindingProgram();
    const expected = expectedBindingRows(document);
    const wire = canonicalJson(document);
    const run = await client.aql(wire, {format: 'json', requestId: 'binding-success'});
    const state = await run.wait({signal: AbortSignal.timeout(90_000)});
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    for (const name of ['source', 'first', 'second']) {
      assert.deepEqual(await run.result(name).all(), expected[name]);
    }
    assert.ok(computed.outputRepresentations.some(entry =>
      entry.representation === 'retained-file'));
    assertSnapshot(computed.relationSnapshots, 4, expected.before);
    assertSnapshot(computed.relationSnapshots, 5, expected.before);
    assertSnapshot(computed.relationSnapshots, 6, expected.derived);
    assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);
    const ref = run.ref;
    await client.close();
    client = await open();
    const attached = await client.attach(ref);
    for (const name of ['source', 'first', 'second']) {
      assert.deepEqual(await attached.result(name).all(), expected[name]);
    }
    const resent = await client.aql(wire, {format: 'json', requestId: 'binding-success'});
    assert.deepEqual(resent.ref, ref);
    assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);
  });

for (const task of [5, 6]) {
  test(`public binding task ${task} cancels after positive progress without partial publication`,
    {timeout: 120_000}, async t => {
      const directory = await mkdtemp(join(tmpdir(), 'actql-public-binding-cancel-'));
      t.after(() => rm(directory, {recursive: true, force: true}));
      let reached, release;
      const advanced = new Promise(resolve => { reached = resolve; });
      const paused = new Promise(resolve => { release = resolve; });
      t.after(() => release());
      let held = false, computed = 0, advances = 0;
      const auth = authorization(name => { if (name === 'computed') computed++; },
        (name, detail) => {
          if (name === 'local_compute_advanced') advances++;
          if (name === 'local_compute_advanced' && detail.task === task &&
              BigInt(detail.progress) > 0n && !held) {
            held = true;
            reached(detail);
            return paused;
          }
        });
      const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
        installation: {directory, retainedRelationOutput: true, authorization: auth}});
      t.after(() => client.close());
      const wire = canonicalJson(bindingProgram());
      const requestId = `binding-cancel-${task}`;
      const run = await client.aql(wire, {format: 'json', requestId});
      const first = await Promise.race([
        advanced.then(detail => ({kind: 'advance', detail})),
        run.wait({signal: AbortSignal.timeout(90_000)})
          .then(state => ({kind: 'terminal', state})),
      ]);
      assert.equal(first.kind, 'advance', JSON.stringify(first));
      assert.ok(BigInt(first.detail.work) > 0n);
      assert.ok(BigInt(first.detail.progress) > 0n);
      assert.equal(computed, 0);
      await client.cancelRequest(requestId);
      release();
      const state = await run.wait({signal: AbortSignal.timeout(30_000)});
      assert.equal(state.status, 'cancelled', JSON.stringify(state));
      assert.equal(state.control.physical_stop, 'confirmed');
      assert.equal(state.result_available, false);
      for (const name of ['source', 'first', 'second']) {
        await assert.rejects(run.result(name).all(), {code: 'ResultAccessDenied'});
      }
      assert.equal(computed, 0);
      assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);
      const stoppedAdvances = advances;
      const resent = await client.aql(wire, {format: 'json', requestId});
      assert.deepEqual(resent.ref, run.ref);
      assert.equal((await resent.wait()).status, 'cancelled');
      assert.equal(advances, stoppedAdvances);
      assert.deepEqual(await readdir(join(directory, 'carrier-snapshots')), []);
    });
}
