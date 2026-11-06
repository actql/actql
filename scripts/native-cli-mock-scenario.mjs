// Public README/Quickstart commands only. The installed runner supplies a new
// exited process for every invocation. Unit doubles validate these assertions,
// not Native execution, signatures, custody or an installed package.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile, stat, unlink} from 'node:fs/promises';
import {join} from 'node:path';

export const mockTemplates = Object.freeze(['deal-review-mock', 'churn-risk-mock']);

const expectedChanges = Object.freeze({
  'deal-review-mock': {
    resource: 'Opportunity', model: 'review', answers: [
      {changed: true, stage: 'Negotiation', next_step: 'Send revised pricing by Friday'},
      {changed: true, stage: 'Closed Lost', next_step: 'Revisit next fiscal year'},
    ],
    rows: [
      {id: '006Acme', StageName: 'Negotiation', NextStep: 'Send revised pricing by Friday'},
      {id: '006Globex', StageName: 'Closed Lost', NextStep: 'Revisit next fiscal year'},
    ],
  },
  'churn-risk-mock': {
    resource: 'Account', model: 'risk', answers: [
      {level: 'high', reason: 'falling usage and a competitor evaluation'},
      {level: 'high', reason: 'support tickets about pricing'},
    ],
    rows: [
      {id: '001Acme', Churn_Risk__c: 'high', Risk_Reason__c: 'falling usage and a competitor evaluation'},
      {id: '001Globex', Churn_Risk__c: 'high', Risk_Reason__c: 'support tickets about pricing'},
    ],
  },
});

async function targetSnapshot(file) {
  const bytes = await readFile(file);
  const info = await stat(file, {bigint: true});
  // atime is deliberately excluded: a metadata/Result read may inspect DATA,
  // but must not rewrite it, even with identical bytes or a replacement inode.
  return {sha256: createHash('sha256').update(bytes).digest('hex'),
    bytes: bytes.toString('utf8'), device: String(info.dev), inode: String(info.ino),
    size: String(info.size), mtimeNs: String(info.mtimeNs), ctimeNs: String(info.ctimeNs)};
}

function runState(record, expectedStatus, runId) {
  const value = JSON.parse(record.stdout);
  assert.equal(value.version, 'actql-run-state/0.1', 'A command receipt is not a Run state');
  assert.equal(value.status, expectedStatus);
  assert.equal(typeof value.run_id, 'string');
  assert(value.run_id.length > 0, 'The original Run identity must be present');
  if (runId !== undefined) assert.equal(value.run_id, runId, 'Recovery must retain the original Run');
  return value;
}

function checkpointId(state) {
  assert.equal(typeof state.checkpoint?.checkpoint_id, 'string');
  assert(state.checkpoint.checkpoint_id.length > 0);
  assert.equal(typeof state.checkpoint.checkpoint_cid, 'string');
  assert.match(state.checkpoint.checkpoint_cid, /^sha256:[0-9a-f]{64}$/u);
  return state.checkpoint.checkpoint_id;
}

export async function runNativeCliMockScenario({root, template, run}) {
  assert(mockTemplates.includes(template), 'Unknown Native mock acceptance template');
  assert.equal(typeof run, 'function');
  const project = join(root, template), file = join(project, 'mock/data.json');
  const commands = [];
  async function invoke(args, cwd = project) {
    const record = await run(args, cwd);
    commands.push({args, cwd, ...record});
    assert.equal(record.signal, null, `${args[0]} terminated by signal`);
    assert.equal(record.code, 0, `${args.join(' ')} failed: ${record.stderr}`);
    return record;
  }
  await invoke(['init', '--template', template, project], root);
  const before = await targetSnapshot(file);
  const original = runState(await invoke(['run', `${template.slice(0, -5)}.aql`,
    '--stop-before', 'commit', '--json']), 'waiting_checkpoint');
  const runId = original.run_id, checkpoint = checkpointId(original);
  // Resume must consume retained preparation, never recompile the input file.
  await unlink(join(project, `${template.slice(0, -5)}.aql`));
  // The waiting checkpoint already retains its Model outcome. Approval and
  // Result recovery must not need the original answer supplier again.
  await unlink(join(project, 'mock', `${template.slice(0, -5)}.v1.answers.yaml`));
  assert.deepEqual(await targetSnapshot(file), before, 'Run must not write before approval');

  // All commands have exited. The next command must find the same durable
  // Run/Checkpoint, not prepare another program or reconstruct a new preview.
  const pending = runState(await invoke(['status', runId, '--json']), 'waiting_checkpoint', runId);
  assert.equal(checkpointId(pending), checkpoint);
  assert.equal(pending.checkpoint.checkpoint_cid, original.checkpoint.checkpoint_cid);
  assert.deepEqual(await targetSnapshot(file), before, 'Pending status must not write');

  await invoke(['approve', checkpoint, '--wait', '--json']);
  const after = await targetSnapshot(file);
  const actual = JSON.parse(after.bytes), expected = JSON.parse(before.bytes);
  const change = expectedChanges[template];
  for (const update of change.rows) {
    const row = expected.salesforce[change.resource].rows.find(value => value.id === update.id);
    assert(row, 'Independent fixture target must exist');
    Object.assign(row, update);
  }
  assert.deepEqual(actual, expected, 'Only the independently expected target fields may change');
  assert.notEqual(after.sha256, before.sha256, 'Approval must perform the mock write');
  runState(await invoke(['status', runId, '--json']), 'succeeded', runId);
  assert.deepEqual(await targetSnapshot(file), after, 'Completed status must not rewrite the target');

  const resultArguments = ['result', runId, '--result', 'updates', '--format', 'jsonl'];
  const first = await invoke(resultArguments);
  const rows = first.stdout.trim().split('\n').map(line => JSON.parse(line));
  assert.equal(rows.length, 2, 'Both independently expected updates must be retained');
  assert.deepEqual(rows.map(value => value.id).sort(), change.rows.map(value => value.id).sort());
  const originalRows = JSON.parse(before.bytes).salesforce[change.resource].rows;
  for (const [index, update] of change.rows.entries()) {
    const row = rows.find(value => value.id === update.id);
    assert.equal(row[change.model]?.outcome, 'ok', 'The retained mock Model outcome must be present');
    assert.deepEqual(row[change.model].value, change.answers[index]);
    if (template === 'deal-review-mock') {
      const originalRow = originalRows.find(value => value.id === update.id);
      assert.equal(row.StageName, originalRow.StageName, 'Result must retain the pre-write Source');
      assert.equal(row.NextStep, originalRow.NextStep, 'Result must retain the pre-write Source');
    }
  }
  assert.deepEqual(await targetSnapshot(file), after, 'Reading Result must not replay the Effect');
  runState(await invoke(['status', runId, '--json']), 'succeeded', runId);
  const reread = await invoke(resultArguments);
  assert.equal(reread.stdout, first.stdout, 'Fresh-process Result must retain original bytes');
  assert.deepEqual(await targetSnapshot(file), after, 'Saved Run/Result reread must not rewrite the target');
  return {template, runId, checkpointId: checkpoint, checkpointCid: original.checkpoint.checkpoint_cid,
    beforeSha256: before.sha256, afterSha256: after.sha256, resultRows: rows.length,
    resultSha256: createHash('sha256').update(first.stdout).digest('hex'), commands};
}
