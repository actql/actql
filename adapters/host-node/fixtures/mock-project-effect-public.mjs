// Public Mock lifecycle consumer. Each phase runs in a separate process from
// the same Project and ordinary installed @actql/node package namespace.
// No internal Host port, application signer or replacement submission is used.
import assert from 'node:assert/strict';
import {readFile, writeFile, stat} from 'node:fs/promises';
import {connect} from '@actql/node';

const [phase, handoffPath, template = 'churn-risk-mock', variant = 'readme'] = process.argv.slice(2);
assert.ok(['capture', 'approve', 'recover'].includes(phase));
assert.equal(typeof handoffPath, 'string');
assert.ok(['churn-risk-mock', 'deal-review-mock'].includes(template));
const dealReview = template === 'deal-review-mock';
assert.ok(variant === 'readme' || variant === 'two-models' && dealReview);
const twoModels = variant === 'two-models';
const C = /^sha256:[0-9a-f]{64}$/u;
const expected = Object.freeze(dealReview ? {
  '006Acme': {changed: true, stage: 'Negotiation', next_step: 'Send revised pricing by Friday'},
  '006Globex': {changed: true, stage: 'Closed Lost', next_step: 'Revisit next fiscal year'},
} : {
  '001Acme': {level: 'high', reason: 'falling usage and a competitor evaluation'},
  '001Globex': {level: 'high', reason: 'support tickets about pricing'},
});
const originalRisk = Object.freeze({'001Acme': 'low', '001Globex': 'medium'});
const originalDeal = Object.freeze({
  '006Acme': {StageName: 'Proposal', NextStep: null},
  '006Globex': {StageName: 'Negotiation', NextStep: 'Legal review'},
});
let client, firstFailedStep, activeStep, primary, failed = false;
async function step(name, operation) {
  activeStep = name;
  try {
    const result = await operation();
    console.log(JSON.stringify({phase, step: name, status: 'passed'}));
    return result;
  } catch (cause) {
    firstFailedStep ??= name;
    throw cause;
  }
}
const snapshot = info => ({dev: String(info.dev), ino: String(info.ino),
  size: String(info.size), mtimeNs: String(info.mtimeNs)});
const dataPath = 'mock/data.json';
const targetState = async () => ({bytes: await readFile(dataPath, 'utf8'),
  file: snapshot(await stat(dataPath, {bigint: true}))});
const save = (path, value) => writeFile(path, JSON.stringify(value) + '\n',
  {encoding: 'utf8', mode: 0o600, flag: 'wx'});

function checkRows(rows) {
  assert.equal(rows.length, 2);
  assert.deepEqual(rows.map(row => row.id).sort(), Object.keys(expected).sort());
  for (const row of rows) {
    if (dealReview) {
      assert.equal(row.review.outcome, 'ok');
      assert.deepEqual(row.review.value, expected[row.id]);
      assert.equal(row.StageName, originalDeal[row.id].StageName);
      assert.equal(row.NextStep, originalDeal[row.id].NextStep);
      if (twoModels) {
        assert.equal(row.confirmation.outcome, 'ok');
        assert.deepEqual(row.confirmation.value, {confirmed: true,
          stage: expected[row.id].stage, next_step: expected[row.id].next_step});
      }
    } else {
      assert.equal(row.risk.outcome, 'ok');
      assert.deepEqual(row.risk.value, expected[row.id]);
      assert.equal(row.active_users, row.id === '001Acme' ? '4' : '12');
    }
  }
}
function checkReview(review, summary, ref) {
  assert.deepEqual(Object.keys(review).sort(), ['version', 'review_projection_cid',
    'effect_preview_cid', 'authority_scope_cid', 'approval_claims', 'authoring_context_cid',
    'redaction_policy_cid', 'sensitivity', 'retention_class', 'encryption_required',
    'displayed_scope', 'displayed_permissions', 'displayed_rows',
    'displayed_authoring_context'].sort());
  assert.equal(review.version, 'actql-review-projection/0.1');
  assert.equal(review.review_projection_cid, summary.reviewProjectionCid);
  assert.equal(review.effect_preview_cid, summary.requiredArtifact.cid);
  assert.equal(review.authority_scope_cid, ref.authorityScopeCid);
  assert.deepEqual(review.approval_claims, summary.requirements);
  assert.equal(review.sensitivity, 'restricted');
  assert.equal(review.retention_class, 'approval-evidence');
  assert.equal(review.encryption_required, true);
  assert.deepEqual(review.displayed_scope.effects.map(({kind, target, count}) =>
    ({kind, target, count})), [{kind: 'update', target: dealReview
      ? 'connector://salesforce/Opportunity' : 'connector://salesforce/Account', count: 2}]);
  assert.equal(review.displayed_rows.length, 2);
  assert.deepEqual(review.displayed_rows.map(row => row.target_row_identity).sort(),
    Object.keys(expected).sort());
  for (const row of review.displayed_rows) {
    const id = row.target_row_identity, answer = expected[id];
    assert.match(row.row_preview_cid, C);
    assert.equal(row.preview_strength, 'full_diff');
    assert.equal(row.target_guard.state, 'version');
    assert.match(row.target_guard.version_cid, C);
    assert.equal(row.before.state, 'present');
    assert.equal(row.before.value.id, id);
    if (dealReview) {
      assert.equal(row.before.value.StageName, originalDeal[id].StageName);
      assert.equal(row.before.value.NextStep, originalDeal[id].NextStep);
      const changes = {StageName: answer.stage, NextStep: answer.next_step};
      assert.deepEqual(row.intended_changes, {state: 'present', value: changes});
      assert.deepEqual(row.after, {state: 'present', value: changes});
    } else {
      assert.equal(row.before.value.Churn_Risk__c, originalRisk[id]);
      assert.equal(row.before.value.Risk_Reason__c, null);
      assert.deepEqual(row.intended_changes, {state: 'present', value: {
        Churn_Risk__c: answer.level, Risk_Reason__c: answer.reason}});
      // The original full-diff after/change omits unchanged fields. The sealed
      // review preserves that original value rather than expanding the row.
      assert.deepEqual(row.after, {state: 'present', value: {
        Churn_Risk__c: answer.level, Risk_Reason__c: answer.reason}});
    }
  }
}
function expectedBytes(before) {
  if (dealReview) {
    // Select each edit in the original authored bytes. Acme's new stage is
    // Globex's old stage; a sequential search in changed bytes would edit it twice.
    const edits = [];
    for (const id of Object.keys(expected)) {
      for (const [field, value] of Object.entries({StageName: expected[id].stage,
        NextStep: expected[id].next_step})) {
        const prior = JSON.stringify(field) + ': ' + JSON.stringify(originalDeal[id][field]);
        assert.equal(before.split(prior).length, 2);
        edits.push({start: before.indexOf(prior), length: prior.length,
          next: JSON.stringify(field) + ': ' + JSON.stringify(value)});
      }
    }
    return edits.sort((a, b) => b.start - a.start).reduce((bytes, edit) =>
      bytes.slice(0, edit.start) + edit.next + bytes.slice(edit.start + edit.length), before);
  }
  let result = before;
  for (const id of Object.keys(expected)) {
    const prior = `"Churn_Risk__c": "${originalRisk[id]}"`;
    assert.equal(result.split(prior).length, 2);
    result = result.replace(prior, '"Churn_Risk__c": "high"');
    const reason = '"Risk_Reason__c": null';
    assert.ok(result.includes(reason));
    result = result.replace(reason, '"Risk_Reason__c": ' + JSON.stringify(expected[id].reason));
  }
  return result;
}

try {
  client = await step('connect', () => connect({mode: 'local',
    installation: {directory: '.actql'}, profile: 'mock'}));
  if (phase === 'capture') {
    const before = await step('read authored target before submission', targetState);
    const source = await step('read original README program', () =>
      readFile(dealReview ? 'deal-review.aql' : 'churn-risk.aql', 'utf8'));
    const execution = await step('README startSource', () =>
      client.startSource(source, {format: 'aql', stopBefore: 'commit'}));
    const state = await step('wait for original Checkpoint', async () => {
      const state = await execution.wait();
      assert.equal(state.status, 'waiting_checkpoint');
      assert.ok(state.checkpoint);
      assert.equal(state.checkpoint.id, state.checkpoint.checkpoint_id);
      return state;
    });
    const summary = await step('exact Checkpoint lookup', async () => {
      const page = await client.checkpoints({checkpointId: state.checkpoint.id});
      assert.equal(page.items.length, 1);
      assert.equal(page.items[0].checkpointCid, state.checkpoint.checkpoint_cid);
      return page.items[0];
    });
    const review = await step('read original sealed review', async () => {
      const review = await client.reviewCheckpoint(summary);
      await writeFile(handoffPath + '.review', review.bytes, {mode: 0o600, flag: 'wx'});
      checkReview(JSON.parse(Buffer.from(review.bytes).toString('utf8')), summary, execution.ref);
      return review;
    });
    await step('no write before approval', async () => assert.deepEqual(await targetState(), before));
    await step('retain original recovery reference', () => save(handoffPath,
      {ref: execution.ref, runId: state.run_id,
      checkpointId: state.checkpoint.id, summary,
      reviewBase64: Buffer.from(review.bytes).toString('base64'), before,
      expectedBytes: expectedBytes(before.bytes), ...(dealReview ? {template} : {}), ...(twoModels ? {variant} : {})}));
  } else {
    const captured = await step('read original public recovery reference', async () => {
      const captured = JSON.parse(await readFile(handoffPath, 'utf8'));
      assert.equal(captured.template ?? 'churn-risk-mock', template);
      assert.equal(captured.variant ?? 'readme', variant);
      return captured;
    });
    const execution = await step('attach same original Run', async () => {
      const execution = await client.attach(captured.ref);
      assert.deepEqual(execution.ref, captured.ref);
      return execution;
    });
    if (phase === 'approve') {
      await step('recover original Checkpoint', async () => {
        const state = await execution.status();
        assert.equal(state.run_id, captured.runId);
        assert.equal(state.status, 'waiting_checkpoint');
        assert.ok(state.checkpoint);
        assert.equal(state.checkpoint.id, captured.checkpointId);
      });
      await step('recover identical sealed review', async () => {
        const review = await client.reviewCheckpoint(captured.summary);
        assert.equal(Buffer.from(review.bytes).toString('base64'), captured.reviewBase64);
      });
      await step('still no write before approval', async () =>
        assert.deepEqual(await targetState(), captured.before));
      await step('explicit default-Local approval', async () => {
        const answer = await client.approve(captured.checkpointId);
        assert.equal(answer.results.length, 1);
        assert.equal(answer.results[0].status, 'committed');
        assert.equal(answer.signed.length, 1);
        const resolution = JSON.parse(answer.signed[0].resolutionWire);
        assert.equal(resolution.decision, 'approved');
        assert.equal(resolution.run_id, captured.runId);
        assert.equal(resolution.run_definition_cid, captured.ref.runDefinitionCid);
        assert.equal(resolution.checkpoint_cid, captured.summary.checkpointCid);
        assert.equal(resolution.review_projection_cid, captured.summary.reviewProjectionCid);
      });
      const terminal = await step('same Run explicit UPDATE completion', async () => {
        const state = await execution.wait();
        assert.equal(state.status, 'succeeded');
        assert.equal(state.run_id, captured.runId);
        return state;
      });
      const rows = await step('original Named Result', async () => {
        const rows = await execution.result('updates').all();
        checkRows(rows); return rows;
      });
      const after = await step('exact conditional target bytes', async () => {
        const after = await targetState();
        assert.equal(after.bytes, captured.expectedBytes); return after;
      });
      await step('retain approved recovery reference', () => save(handoffPath + '.approved.json',
        {ref: execution.ref, runId: terminal.run_id, rows, after, ...(dealReview ? {template} : {}), ...(twoModels ? {variant} : {})}));
    } else {
      const approved = await step('read approved public recovery reference', async () => {
        const approved = JSON.parse(await readFile(handoffPath + '.approved.json', 'utf8'));
        assert.equal(approved.template ?? 'churn-risk-mock', template);
        assert.equal(approved.variant ?? 'readme', variant);
        assert.deepEqual(execution.ref, approved.ref);
        return approved;
      });
      await step('recover completed same Run', async () => {
        const state = await execution.status();
        assert.equal(state.status, 'succeeded');
        assert.equal(state.run_id, approved.runId);
      });
      await step('recover original Named Result', async () => {
        const rows = await execution.result('updates').all();
        checkRows(rows); assert.deepEqual(rows, approved.rows);
      });
      // Same bytes and physical inode/mtime show that completed recovery did
      // not replace this target again. This does not count Source acquisitions.
      await step('no repeated target replacement on recovery', async () =>
        assert.deepEqual(await targetState(), approved.after));
    }
  }
} catch (cause) {failed = true; primary = cause; firstFailedStep ??= activeStep;}
let closeFailure, closeFailed = false;
if (client !== undefined) {
  try {await client.close();}
  catch (cause) {closeFailure = cause; closeFailed = true; firstFailedStep ??= 'close';}
}
console.log(JSON.stringify({phase, firstFailedStep: firstFailedStep ?? null,
  status: failed || closeFailed ? 'failed' : 'passed',
  code: primary?.code, cleanupCode: closeFailure?.code}));
if (failed) throw primary;
if (closeFailed) throw closeFailure;
