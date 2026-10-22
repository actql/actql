import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, stat, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {scaffoldProject} from '../../packages/native-cli/lib/project-scaffold.mjs';

// Real source-checkout Host/Common/SQLite/Store/Reviewer. Each case owns a new
// project; no retained failed Run, private signing port or native-sign double.
async function originalCheckpoint(t, operation) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-local-checkpoint-authority-'));
  const project = scaffoldProject(join(directory, 'project'), 'churn-risk-mock');
  const cwd = process.cwd();
  let client, primary;
  process.chdir(project.directory);
  t.diagnostic(JSON.stringify({project: project.directory}));
  const connect = async () => client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
    installation: {directory: '.actql'}, profile: 'mock'});
  const close = async () => {await client.close(); client = undefined;};
  const target = async () => {
    const original = await stat('mock/data.json', {bigint: true});
    return {bytes: await readFile('mock/data.json', 'utf8'),
      dev: original.dev.toString(), ino: original.ino.toString(),
      mtimeNs: original.mtimeNs.toString()};
  };
  const signingRecords = () => {
    assert.equal(client, undefined, 'Inspect original DB only after actual Host close');
    const database = new DatabaseSync('.actql/checkpoints/journal/checkpoint-journal.sqlite3',
      {open: false, readOnly: true});
    const closeDatabase = database.close;
    try {
      database.open();
      return database.prepare("SELECT value FROM journal_metadata WHERE key LIKE 'local-signing/%'")
        .all().map(row => JSON.parse(row.value));
    } finally {if (database.isOpen) Reflect.apply(closeDatabase, database, []);}
  };
  try {
    await connect();
    const before = await target();
    const execution = await client.startSource(await readFile('churn-risk.aql', 'utf8'),
      {format: 'aql', stopBefore: 'commit'});
    const waiting = await execution.wait();
    assert.equal(waiting.status, 'waiting_checkpoint');
    const page = await client.checkpoints({checkpointId: waiting.checkpoint.id});
    assert.equal(page.items.length, 1);
    const summary = page.items[0];
    const key = await readFile('.actql/mock-account/reviewer.pem');
    const review = Buffer.from((await client.reviewCheckpoint(summary)).bytes);
    assert.deepEqual(await target(), before);
    await operation({connect, close, target, signingRecords, before, key, review,
      ref: structuredClone(execution.ref), summary, runId: waiting.run_id,
      current: () => client});
  } catch (cause) {primary = cause;}
  finally {
    try {if (client !== undefined) await close();}
    catch (cause) {primary = primary === undefined ? cause :
      new AggregateError([primary, cause], 'Original authority counter and Host cleanup failed');}
    finally {process.chdir(cwd);}
  }
  if (primary !== undefined) throw primary;
}

test('actual Local rejection stays cancelled across reopen without target writes or a replacement approval', async t => {
  await originalCheckpoint(t, async f => {
    const response = await f.current().reject(f.summary.checkpointId);
    assert.equal(response.results.length, 1);
    assert.equal(response.results[0].status, 'committed');
    const resolution = JSON.parse(response.signed[0].resolutionWire);
    assert.equal(resolution.decision, 'rejected');
    assert.equal(resolution.run_id, f.runId);
    assert.equal(resolution.checkpoint_cid, f.summary.checkpointCid);
    assert.equal(response.signed[0].approvalEvidenceWire, '');
    const execution = await f.current().attach(f.ref);
    assert.equal((await execution.wait()).status, 'cancelled');
    assert.deepEqual(await f.target(), f.before);
    await f.close();
    const records = f.signingRecords();
    assert.equal(records.length, 1);
    assert.equal(records[0].decision, 'rejected');
    assert.deepEqual(Object.keys(records[0].signatures), ['resolution']);
    assert.equal(records[0].signatures.resolution.state, 'saved');
    await f.connect();
    assert.equal((await (await f.current().attach(f.ref)).status()).status, 'cancelled');
    await assert.rejects(f.current().approve(f.summary.checkpointId), {code: 'CheckpointUnavailable'});
    assert.deepEqual(await f.target(), f.before);
    assert.deepEqual(await readFile('.actql/mock-account/reviewer.pem'), f.key);
    await f.close();
    assert.deepEqual(f.signingRecords(), records, 'No replacement signing operation on rejected recovery');
  });
});

test('actual Local current Account Deny blocks signing after reopen without a claim or target write', async t => {
  await originalCheckpoint(t, async f => {
    await f.close();
    const path = '.actql/mock-account/account.json';
    const account = JSON.parse(await readFile(path, 'utf8'));
    const sign = account.entries.filter(entry => entry.operation?.any_of?.includes('sign'));
    assert.equal(sign.length, 1, 'Restrict the actual existing signing rule only');
    sign[0].outcome = 'deny';
    const wire = JSON.stringify(account);
    await writeFile(path, wire, {mode: 0o600});
    await f.connect();
    assert.equal(await readFile(path, 'utf8'), wire, 'Reopen must not overwrite operator Deny');
    assert.deepEqual(Buffer.from((await f.current().reviewCheckpoint(f.summary)).bytes), f.review);
    await assert.rejects(f.current().approve(f.summary.checkpointId), cause => {
      assert.equal(cause.code, 'ExecutionAuthorizationDenied');
      assert.equal(cause.authorization?.action, 'deny');
      assert.equal(cause.authorization?.tuple?.operation, 'sign');
      return true;
    });
    assert.equal((await (await f.current().attach(f.ref)).status()).status, 'waiting_checkpoint');
    assert.equal((await f.current().checkpoints({checkpointId: f.summary.checkpointId})).items.length, 1);
    assert.deepEqual(await f.target(), f.before);
    assert.deepEqual(await readFile('.actql/mock-account/reviewer.pem'), f.key);
    await f.close();
    assert.deepEqual(f.signingRecords(), [], 'Current Deny precedes the original physical signing claim');
  });
});
