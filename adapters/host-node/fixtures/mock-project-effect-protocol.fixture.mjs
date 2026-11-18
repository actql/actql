// Authored public Mock fixture protocol. Importing this module performs no
// connection, source preparation, submission, publication or cleanup.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';

export async function mockProjectWorkflowChecks({template = 'churn-risk-mock', variant = 'readme'} = {}) {
  assert.ok(['churn-risk-mock', 'deal-review-mock'].includes(template));
  const dealReview = template === 'deal-review-mock', multipleTargets = variant === 'multiple-targets';
  assert.ok(variant === 'readme' || multipleTargets && !dealReview ||
    ['two-models', 'two-models-whole', 'two-models-joined-whole', 'two-models-joined-inputs'].includes(variant) && dealReview);
  const twoModels = variant !== 'readme' && !multipleTargets;
  const {checkMultipleTargetMockRows, checkMultipleTargetMockReview, multipleTargetMockExpectedBytes} = multipleTargets
    ? await import('./mock-multiple-targets.fixture.mjs') : {};
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
  function checkRows(rows) {
    if (multipleTargets) return checkMultipleTargetMockRows(rows);
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

  // Independent authored oracle for the separately named joined-Unit fixture.
  // Version goldens bind the literal physical row and its declared revision.
  // Opaque authority CIDs are checked as nominal DATA, never recreated as grants.

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
    if (multipleTargets) return checkMultipleTargetMockReview(review);
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
    if (multipleTargets) return multipleTargetMockExpectedBytes(before);
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
  return {expected, checkRows, checkReview, expectedBytes};
}

// Keep the original returned reference before any wait, review or close.
// Explicit filesystem/SDK ports qualify this fixture boundary without running
// a business workflow in its source-only controls.
export async function startMockProjectSource({client, template, variant, handoffPath, step,
  readProgram = readFile, writeHandoff = writeFile, save}) {
  const dealReview = template === 'deal-review-mock', multipleTargets = variant === 'multiple-targets';
  const twoModels = variant !== 'readme' && !multipleTargets;
  const source = await step('read original README program', () =>
    readProgram(multipleTargets ? 'multiple-targets.program.json' : twoModels ? 'deal-review.program.json' : dealReview ? 'deal-review.aql' : 'churn-risk.aql', 'utf8'));
  const execution = await step('README startSource', () =>
    client.startSource(source, {format: twoModels || multipleTargets ? 'json' : 'aql', stopBefore: 'commit'}));
  const retain = save ?? ((path, value) => writeHandoff(path, JSON.stringify(value) + '\n',
    {encoding: 'utf8', mode: 0o600, flag: 'wx'}));
  await step('retain original accepted reference before wait', () =>
    retain(handoffPath + '.started', {ref: execution.ref, template, variant}));
  return execution;
}
