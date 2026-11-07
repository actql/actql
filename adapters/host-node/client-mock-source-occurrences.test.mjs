import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {open} from '../../packages/node/index.mjs';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {scaffoldProject} from '../../packages/native-cli/lib/project-scaffold.mjs';

const accounts = [
  {id: '001Acme', name: 'Acme Corp'},
  {id: '001Globex', name: 'Globex Inc'},
];

// The installed catalogue is larger than each query's capture inventory.
// Each case uses a real Host and fresh owned state, never pre-read fixture rows.
async function withMockClient(run) {
  const previous = process.cwd();
  const directory = await mkdtemp(join(tmpdir(), 'actql-mock-occurrences-'));
  const project = join(directory, 'project');
  scaffoldProject(project, 'churn-risk-mock');
  process.chdir(project);
  let client, closed = false;
  try {
    client = await open({stateDir: join(project, '.actql'), profile: 'mock'});
    await run(client);
  } finally {
    try { if (client) await client.close(); closed = true; }
    finally {
      process.chdir(previous);
      if (closed) await rm(directory, {recursive: true, force: true});
    }
  }
}

async function rows(client, text, requestId) {
  const check = await client.check(text, {
    kind: 'text', scope: 'bound_input', format: 'aql-text',
  });
  assert.equal(check.report.verdict, 'verified');
  const run = await client.startSource(text, {format: 'aql-text', requestId});
  assert.equal((await run.wait({signal: AbortSignal.timeout(10000)})).status, 'succeeded');
  return {run, rows: await run.result('main').all()};
}

test('one Mock Salesforce occurrence retains its original submission', async () => {
  await withMockClient(async client => {
    const text = 'SELECT id, name FROM salesforce.accounts ORDER BY id';
    const original = await rows(client, text, 'single-salesforce');
    assert.deepEqual(original.rows, accounts);
    const submission = getSubmissionOutcome(original.run);
    assert.equal(submission.kind, 'ready');
    const found = await client.lookupSubmission(submission.submissionRef);
    assert.equal(found.kind, 'ready');
    assert.deepEqual(found.admission.ref, original.run.ref);
    const replay = await rows(client, text, 'single-salesforce');
    assert.deepEqual(replay.run.ref, original.run.ref);
    assert.deepEqual(replay.rows, accounts);
    const unordered = await rows(client, 'SELECT id, name FROM salesforce.accounts', 'unordered-salesforce');
    assert.deepEqual(unordered.rows.sort((a, b) => a.id.localeCompare(b.id)), accounts);
  });
});

test('one Mock Snowflake occurrence does not use its catalogue ordinal', async () => {
  await withMockClient(async client => {
    const result = await rows(client,
      'SELECT account_id, active_users FROM snowflake.usage_30d ORDER BY account_id',
      'single-snowflake');
    assert.deepEqual(result.rows, [
      {account_id: '001Acme', active_users: '4'},
      {account_id: '001Globex', active_users: '12'},
    ]);
  });
});

test('Mock JOIN occurrences follow checked order, not installed catalogue order', async () => {
  await withMockClient(async client => {
    for (const [name, text] of [
      ['forward', 'SELECT a.id AS id, a.name AS name FROM salesforce.accounts AS a JOIN snowflake.usage_30d AS u ON a.id = u.account_id ORDER BY id'],
      ['reverse', 'SELECT a.id AS id, a.name AS name FROM snowflake.usage_30d AS u JOIN salesforce.accounts AS a ON u.account_id = a.id ORDER BY id'],
    ]) {
      assert.deepEqual((await rows(client, text, name)).rows, accounts);
    }
  });
});

test('repeated Mock Source occurrences keep separate read custody', async () => {
  await withMockClient(async client => {
    const result = await rows(client,
      'SELECT a.id AS id, b.name AS name FROM salesforce.accounts AS a JOIN salesforce.accounts AS b ON a.id = b.id ORDER BY id',
      'repeated-salesforce');
    assert.deepEqual(result.rows, accounts);
  });
});

test('Mock JOIN and INFER retain their original two-Source profile', async () => {
  await withMockClient(async client => {
    const result = await rows(client,
      'SELECT a.id AS id, a.description AS notes, u.active_users, u.trend ' +
      'FROM salesforce.accounts AS a JOIN snowflake.usage_30d AS u ON a.id = u.account_id ' +
      '|> WHERE active_users < 10 ' +
      '|> INFER `model-task:churn-risk.v1` INPUT (notes, active_users, trend) AS risk ' +
      '|> SELECT id, risk', 'mock-infer-control');
    assert.deepEqual(result.rows, [{id: '001Acme', risk: {
      input_key: {id: '001Acme'}, outcome: 'ok',
      value: {level: 'high', reason: 'falling usage and a competitor evaluation'},
    }}]);
  });
});


// Actual installed Mock preparation method; Core and raw physical ports remain
// explicit. These controls do not issue a real read, admission or cleanup ACK.
function mockPlannedReadFixture({requestOwned = true} = {}) {
  const source = readFileSync(new URL('../local-node/installed-project-mock.mjs', import.meta.url), 'utf8');
  const nodes = [];
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Property' && node.method && node.key.name === 'prepareSourceRead') nodes.push(node);
    for (const value of Object.values(node)) if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === 'object') visit(value);
  })(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.equal(nodes.length, 1);
  const prepared = {}, declaration = {}, parent = {}, oldParent = {}, read = {}, calls = [];
  const run = {value: parent, original: oldParent, requestOwned, reads: [], closed: false};
  const originalReads = new WeakMap();
  const raw = {close() {}, readOriginalBytes() {}};
  const fail = code => {throw Object.assign(new Error(code), {code});};
  const moon = {clientProgramAcquisitionCount: () => 2,
    clientProgramInstalledManagedRunSourceReadAt(value, stage, input, task) {
      assert.equal(requestOwned, false, 'the retained Plan already opened this exact occurrence');
      assert.strictEqual(value, parent); assert.deepEqual([stage, input, task], [0, 0, 0]);
      calls.push('begin'); return {$tag: 1, _0: read};
    }};
  const ports = {sameRun(value) {assert.strictEqual(value, prepared); return run;}, moon,
    effectRuns: new WeakMap(), originalReads, effectReads: new Set(), index: 1, declaration, fail,
    sourceManaged: {prepareRead(value, selected, original, occurrence) {
      assert.strictEqual(value, prepared); assert.strictEqual(selected, declaration);
      assert.strictEqual(original, requestOwned ? parent : oldParent);
      assert.deepEqual(occurrence, {stage: 0, input: 0, task: 0}); calls.push('raw'); return raw;
    }, assertCurrent() {calls.push('current');}},
    checked: result => {assert.equal(result.$tag, 1); return result._0;},
    releaseEffectSourceAliases() {assert.fail('this Model control has no Effect release');}};
  const actual = new Function(...Object.keys(ports), 'return ({' + source.slice(nodes[0].start, nodes[0].end) + '}).prepareSourceRead;')(...Object.values(ports));
  const facts = {checkedOwner: prepared, effectful: false, declaration,
    occurrence: {stage: 0, input: 0, task: 0},
    ...(requestOwned ? {managedRun: parent, originalRead: read} : {})};
  return {actual, facts, run, read, raw, originalReads, calls};
}

test('Mock planned Model Source keeps its original read without reopening the same occurrence', () => {
  const f = mockPlannedReadFixture();
  assert.strictEqual(f.actual(f.facts), f.read);
  assert.deepEqual(f.calls, ['raw', 'current']);
  assert.strictEqual(f.run.reads[0].raw, f.raw);
  assert.strictEqual(f.originalReads.get(f.read).run, f.run);
  assert.throws(() => f.actual(f.facts), {code: 'InstalledSourcePreparationMismatch'});
  assert.deepEqual(f.calls, ['raw', 'current'], 'duplicate occurrence creates no second raw child');
});

test('Mock planned Model Source refuses a foreign parent or missing original before raw preparation', () => {
  for (const change of [{managedRun: {}}, {originalRead: undefined}]) {
    const f = mockPlannedReadFixture();
    assert.throws(() => f.actual({...f.facts, ...change}), {code: 'InstalledSourcePreparationMismatch'});
    assert.deepEqual(f.calls, []); assert.deepEqual(f.run.reads, []);
  }
});

test('Mock legacy Source still opens its one original occurrence under the existing raw parent', () => {
  const f = mockPlannedReadFixture({requestOwned: false});
  assert.strictEqual(f.actual(f.facts), f.read);
  assert.deepEqual(f.calls, ['raw', 'current', 'begin']);
});
