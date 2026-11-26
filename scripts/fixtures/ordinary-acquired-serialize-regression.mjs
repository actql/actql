// Run this fixture from an ordinary installed Node consumer with its fixture
// dependencies staged. The default assertion is the functional #3644 gate.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';
import {connect, open} from '@actql/node';
import {mockProjectFiles} from './salesforce-approval/mock-project.mjs';
import {workflowWorkObservation} from '../../adapters/host-node/fixtures/work-observation.fixture.mjs';

// The installed Local connector binds two distinct directories, following the
// Project-owned JOIN acceptance fixture. Both source rows contribute to output.
const joinInput = 'SELECT a.path AS left_path, a.size_bytes AS left_bytes, ' +
  'b.path AS right_path, b.size_bytes AS right_bytes ' +
  'FROM LIST_FILES(left_source) AS a JOIN LIST_FILES(right_source) AS b ON a.media_type = b.media_type';
const joinRows = [{left_path: 'left.txt', left_bytes: 3, right_path: 'right.txt', right_bytes: 7}];
const joinFiles = {
  'actql.config.json': JSON.stringify({version: 'actql-config/0.1', connectors: 'connectors.json'}),
  'connectors.json': JSON.stringify({version: 'actql-connectors/0.1', connections: {
    left_source: {connector: 'local', root: './left-data', tables: {}},
    right_source: {connector: 'local', root: './right-data', tables: {}},
  }}),
  'left-data/left.txt': 'abc',
  'right-data/right.txt': '1234567',
  'right-data/unmatched.json': '{}',
};
const accountConfiguration = JSON.stringify({version: 'actql-execution-account-config/0.1',
  account_id: 'acquired-serialize-operator', entries: [{entry_id: 'owned-fixture',
    outcome: 'allow', principal: {all: true}, connection: {all: true},
    resource: {all: true}, operation: {all: true}, exclusions: []}]});
const cases = {
  single: {
    query: "FROM salesforce.accounts |> SELECT Id, Name " +
      "|> SERIALIZE FORMAT JSONL ORDER BY Id OPTIONS (name = 'accounts.jsonl', max_rows = 2, max_bytes = 512) |> RESULT file",
    bytes: Buffer.from('{"Id":"001MockUntouched","Name":"Untouched control"}\n' +
      '{"Id":"001Serialize","Name":"Original name"}\n'),
    rowCount: 2, sourceStarts: 1, name: 'accounts.jsonl',
    files: mockProjectFiles({recordId: '001Serialize', previousName: 'Original name', nextName: 'Not an input'}),
  },
  join: {
    query: joinInput + ' |> ASSERT UNIQUE BY (left_path, right_path) |> SERIALIZE FORMAT JSONL ORDER BY left_path, left_bytes, right_path, right_bytes ' +
      "OPTIONS (name = 'join.jsonl', max_rows = 2, max_bytes = 512) |> RESULT file",
    bytes: Buffer.from('{"left_path":"left.txt","left_bytes":3,"right_path":"right.txt","right_bytes":7}\n'),
    rowCount: 1, sourceStarts: 2, name: 'join.jsonl', files: joinFiles,
  },
};
const originalFile = 'original-run.json';

async function readOriginal(client, ref, root, fixture) {
  const hash = createHash('sha256').update(fixture.bytes).digest('hex');
  const run = await client.attach(ref);
  assert.deepEqual(run.ref, ref);
  assert.equal((await run.status()).status, 'succeeded');
  const [row, extra] = await run.result('file').all();
  assert.equal(extra, undefined);
  assert.equal(row.name, fixture.name);
  assert.equal(row.media_type, 'application/x-ndjson');
  assert.equal(row.content.$actql_ref, 'content');
  assert.equal(row.content.metadata.size_bytes, fixture.bytes.byteLength);
  assert.equal(row.content.metadata.truncated, false);
  assert.equal(row.row_count, fixture.rowCount);
  assert.equal(row.size_bytes, fixture.bytes.byteLength);
  assert.equal(row.content.metadata.content_cid, 'sha256:' + hash);
  assert.deepEqual(await readFile(join(root, 'state', 'publication', 'objects', hash)), fixture.bytes);
}

function openObserved(root, variant, observer) {
  const directory = join(root, 'state'), observation = observer.connection;
  if (variant === 'join') {
    return open({stateDir: directory, installation: {observation, authorization: {accountConfiguration}}});
  }
  return connect({mode: 'local', profile: 'mock', installation: {directory, observation}});
}

async function control(client, variant, root) {
  if (variant === 'join') {
    const run = await client.startSource(joinInput + ' |> RESULT joined', {format: 'sql'});
    assert.equal((await run.wait()).status, 'succeeded');
    assert.deepEqual(await run.result('joined').all(), joinRows);
  }
  const run = await client.startSource(
    "SELECT 1 AS id |> SERIALIZE FORMAT JSONL ORDER BY id OPTIONS (name = 'control.jsonl') |> RESULT file",
    {format: 'aql'});
  assert.equal((await run.wait()).status, 'succeeded');
  await readOriginal(client, run.ref, root, {bytes: Buffer.from('{"id":1}\n'), rowCount: 1, name: 'control.jsonl'});
}

async function runCase(variant, mode) {
  const fixture = cases[variant];
  const root = await mkdtemp(join(tmpdir(), 'actql-acquired-serialize-'));
  const previous = process.cwd();
  try {
    for (const [name, body] of Object.entries(fixture.files)) {
      const path = join(root, name);
      await mkdir(dirname(path), {recursive: true});
      await writeFile(path, body);
    }
    process.chdir(root);
    const observer = workflowWorkObservation({trackOriginal: true});
    let originalRef;
    const client = await openObserved(root, variant, observer);
    try {
      if (variant === 'single' && mode !== '--control-only') {
        const localPlan = await client.plan('SELECT 1 AS n', {format: 'sql'});
        assert.equal(localPlan.version, 'actql-plan-view/0.1');
        const acquiredPlan = await client.plan('SELECT Id, Name FROM salesforce.accounts', {format: 'sql'});
        assert.equal(acquiredPlan.version, 'actql-plan-view/0.1');
        assert.match(acquiredPlan.compiled_plan_cid, /^sha256:[0-9a-f]{64}$/u);
        assert.equal(observer.snapshot().sourceAcquisitionStarts, 0);
        assert.equal(observer.snapshot().modelCallStarts, 0);
        assert.equal(observer.snapshot().effectReplacementReturns, 0);
        assert.equal(await readFile(join(root, 'mock/data.json'), 'utf8'), fixture.files['mock/data.json']);
      }
      await control(client, variant, root);
      const afterControl = observer.snapshot().sourceAcquisitionStarts;
      assert.equal(afterControl, variant === 'join' ? 2 : 0);
      if (mode === '--control-only') return;
      const input = {format: variant === 'join' ? 'sql' : 'aql', requestId: 'ordinary-acquired-serialize-' + variant};
      const original = await client.startSource(fixture.query, input);
      assert.equal((await original.wait()).status, 'succeeded');
      await readOriginal(client, original.ref, root, fixture);
      assert.equal(observer.snapshot().sourceAcquisitionStarts - afterControl, fixture.sourceStarts);
      originalRef = original.ref;
      await writeFile(originalFile, JSON.stringify(originalRef));
    } finally {await client.close();}
    const originalWork = observer.forOriginal(originalRef);
    assert.equal(originalWork.complete, true, 'Incomplete diagnostics cannot establish the acquisition count');
    assert.equal(originalWork.sourceAcquisitionStarts, fixture.sourceStarts);
    // Prove the cold JOIN Result is retained rather than computed afresh: the
    // two installed source directories still exist but neither input file does.
    if (variant === 'join') {
      await rm(join(root, 'left-data', 'left.txt'));
      await rm(join(root, 'right-data', 'right.txt'));
      await rm(join(root, 'right-data', 'unmatched.json'));
    }
    await promisify(execFile)(process.execPath, [fileURLToPath(import.meta.url), '--restore', variant], {cwd: root});
  } finally {
    process.chdir(previous);
    await rm(root, {recursive: true, force: true});
  }
}

const [mode, variant] = process.argv.slice(2);
if (variant !== undefined) assert(Object.hasOwn(cases, variant));
if (mode === '--restore') {
  assert(variant !== undefined);
  const root = process.cwd();
  const observer = workflowWorkObservation();
  const client = await openObserved(root, variant, observer);
  try {
    await readOriginal(client, JSON.parse(await readFile(originalFile, 'utf8')), root, cases[variant]);
  } finally {await client.close();}
  const restoredWork = observer.snapshot();
  assert.equal(restoredWork.complete, true, 'Incomplete diagnostics cannot establish zero cold work');
  assert.equal(restoredWork.sourceAcquisitionStarts, 0);
} else {
  assert([undefined, '--control-only', '--run'].includes(mode));
  for (const key of variant === undefined ? Object.keys(cases) : [variant]) await runCase(key, mode);
}
