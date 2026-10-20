import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {scaffoldProject} from '../../packages/native-cli/lib/project-scaffold.mjs';

// Real source-checkout Host/Common/Journal/Store/Reviewer, not a packed public
// distribution or a live provider. Every attempt keeps its fresh original state.
test('actual Local Mock answers its original Checkpoint after reopen and applies the same Run once', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-local-checkpoint-answer-'));
  const project = scaffoldProject(join(directory, 'project'), 'churn-risk-mock');
  const cwd = process.cwd(), options = {mode: 'local', owner: 'local',
    installation: {directory: '.actql'}, profile: 'mock'};
  let client, primary, firstFailedStep, activeStep;
  const step = async (name, operation) => {
    activeStep = name;
    const result = await operation();
    t.diagnostic(JSON.stringify({step: name, status: 'passed'}));
    return result;
  };
  const target = async () => {
    const file = await stat('mock/data.json', {bigint: true});
    return {bytes: await readFile('mock/data.json', 'utf8'),
      dev: file.dev.toString(), ino: file.ino.toString(), mtimeNs: file.mtimeNs.toString()};
  };
  t.diagnostic(JSON.stringify({project: project.directory}));
  process.chdir(project.directory);
  try {
    client = await step('connect original Host', () => connectEmbeddedLocal(options));
    const before = await target(), source = await readFile('churn-risk.aql', 'utf8');
    const execution = await step('submit original README Effect', () =>
      client.startSource(source, {format: 'aql', stopBefore: 'commit'}));
    const state = await step('capture original Checkpoint', () => execution.wait());
    assert.equal(state.status, 'waiting_checkpoint');
    const ref = structuredClone(execution.ref);
    t.diagnostic(JSON.stringify({ref, checkpoint: state.checkpoint}));
    const page = await client.checkpoints({checkpointId: state.checkpoint.id});
    assert.equal(page.items.length, 1);
    const summary = page.items[0], review = await client.reviewCheckpoint(summary);
    const originalReview = Buffer.from(review.bytes);
    const reviewer = await readFile('.actql/mock-account/reviewer.pem');
    assert.deepEqual(await target(), before);
    await step('close captured Host', () => client.close()); client = undefined;

    client = await step('reopen same durable installation', () => connectEmbeddedLocal(options));
    const resumed = await client.attach(ref);
    assert.equal((await resumed.status()).status, 'waiting_checkpoint');
    assert.deepEqual(Buffer.from((await client.reviewCheckpoint(summary)).bytes), originalReview);
    assert.deepEqual(await readFile('.actql/mock-account/reviewer.pem'), reviewer);
    assert.deepEqual(await target(), before);
    const answer = await step('explicit original Local approval', () => client.approve(summary.checkpointId));
    assert.equal(answer.results.length, 1); assert.equal(answer.results[0].status, 'committed');
    assert.equal(answer.signed.length, 1);
    const resolution = JSON.parse(answer.signed[0].resolutionWire);
    assert.equal(resolution.decision, 'approved');
    assert.equal(resolution.checkpoint_cid, summary.checkpointCid);
    assert.equal(resolution.run_id, state.run_id);
    const completed = await step('same original Run UPDATE', () => resumed.wait());
    assert.equal(completed.status, 'succeeded'); assert.equal(completed.run_id, state.run_id);
    const rows = await step('read original Named Result', () => resumed.result('updates').all());
    assert.deepEqual(rows.map(row => row.id).sort(), ['001Acme', '001Globex']);
    for (const row of rows) {
      assert.equal(row.risk.outcome, 'ok'); assert.equal(row.risk.value.level, 'high');
    }
    const after = await target(); assert.notEqual(after.bytes, before.bytes);
    assert.deepEqual(await readFile('.actql/mock-account/reviewer.pem'), reviewer);
    await step('close approved Host', () => client.close()); client = undefined;
    client = await step('reopen completed original Run', () => connectEmbeddedLocal(options));
    const recovered = await client.attach(ref);
    assert.equal((await recovered.status()).status, 'succeeded');
    assert.deepEqual(await recovered.result('updates').all(), rows);
    assert.deepEqual(await target(), after, 'completed recovery must not replace the target again');
    assert.deepEqual(await readFile('.actql/mock-account/reviewer.pem'), reviewer);
  } catch (cause) {
    primary = cause; firstFailedStep = activeStep;
    t.diagnostic(JSON.stringify({firstFailedStep, code: cause.code, message: cause.message,
      cause: cause.cause?.message}));
  } finally {
    try {await client?.close();}
    catch (cause) {primary = primary === undefined ? cause :
      new AggregateError([primary, cause], 'Original Checkpoint answer and Host cleanup failed');}
    finally {process.chdir(cwd);}
  }
  if (primary !== undefined) throw primary;
});
