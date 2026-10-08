import assert from 'node:assert/strict';
import test from 'node:test';
import {compareSourceInstructions, sourceExperimentLimits, sourceEvaluationCases} from './compare-source-instructions.mjs';
import {evaluationValueCid as cid} from './evaluate.mjs';
import {referenceCid, evidenceParts} from './evidence-reference.mjs';

const candidates = [{id: 'A', target: 'first_assessment', instructions: 'A'},
  {id: 'B', target: 'first_assessment', instructions: 'B'}];
// Synthetic metadata only here; the public tests retrieve real original
// captures after terminating the Host, then invoke the external evaluator.
function fixture() {
  const submitted = [], evaluated = [];
  const config = {candidates,
    async executeTrial(trial) {
      assert.equal(Object.hasOwn(trial, 'expected'), false);
      submitted.push(trial);
      return {trial, subject: {runDefinitionCid: cid({trial: submitted.length}), authorityScopeCid: cid('scope')}};
    },
    async collectEvidence({subject, trial}) {
      return ['second_assessment', 'first_assessment'].flatMap(target => [2, 1].map(key => {
        const attemptCid = cid({subject, target, key});
        const policyWire = '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';
        const policy = {kind: 'data_policy', wire: policyWire, cid: referenceCid(JSON.parse(policyWire))};
        const references = Object.fromEntries(evidenceParts.map(part => {
          const body = {version: 'evaluation-evidence-reference/0.1', kind: 'model_capture', part,
            subject, attemptCid, policy, original: {captureBundleCid: cid({subject, target}),
              modelCallSlotCid: cid({subject, target, key}), semanticRequestCid: cid(key), modelTaskCid: cid(target)},
            content: {cid: cid(part), sizeBytes: 100, truncated: false, expiresAt: '2099-01-01T00:00:00.000Z'}};
          return [part, {...body, evidenceRefCid: referenceCid(body)}];
        }));
        return {target, key: [key], evidence: {status: 'complete', attemptCid, references}};
      }));
    },
    async evaluate({trial, item, job}) {
      evaluated.push(job);
      return {caseId: job.caseId, score: trial.trial.candidate.id === 'A' &&
        item.target === 'first_assessment' && item.key[0] === 1 ? 0 : 1,
        reason: 'Independent fixed rubric.', evaluator: cid('evaluator'), rubric: cid('rubric')};
    },
  };
  return {config, submitted, evaluated};
}
test('all four calls count before each fresh trial; the winner freezes before the reserved final trial', async () => {
  const f = fixture(), result = await compareSourceInstructions(f.config);
  assert.equal(result.status, 'scored'); assert.equal(result.selectedCandidate, 'B');
  assert.deepEqual(f.submitted.map(trial => [trial.candidate.id, trial.role]),
    [['A', 'selection'], ['B', 'selection'], ['B', 'final_test']]);
  assert.equal(result.records.length, 12);
  assert.deepEqual(result.used, {trials: 3, providerCalls: 12, evaluatorCalls: 12, retainedBytes: 6000});
  const inputs = entries => new Set(entries.map(entry => entry.text));
  assert(sourceEvaluationCases.final.every(entry => !inputs(sourceEvaluationCases.selection).has(entry.text)));
});
test('selection cannot spend the four provider calls reserved for final evaluation', async () => {
  const f = fixture(); f.config.limits = {...sourceExperimentLimits, providerCalls: 8};
  const result = await compareSourceInstructions(f.config);
  assert.equal(result.status, 'incomplete'); assert.equal(result.reason, 'EvaluationBudgetExceeded');
  assert.equal(f.submitted.length, 1); assert.equal(f.evaluated.length, 4);
});
test('a missing item is incomplete, not a zero score or a silently removed case', async () => {
  const f = fixture(), collect = f.config.collectEvidence;
  f.config.collectEvidence = async trial => (await collect(trial)).slice(1);
  const result = await compareSourceInstructions(f.config);
  assert.equal(result.status, 'incomplete'); assert.equal(result.reason, 'RequiredEvidenceUnavailable');
  assert.equal(f.submitted.length, 1); assert.equal(f.evaluated.length, 0); assert.deepEqual(result.records, []);
});
test('duplicate target/key association cannot replace a legitimate occurrence', async () => {
  const f = fixture(), collect = f.config.collectEvidence;
  f.config.collectEvidence = async trial => {const items = await collect(trial); items[3] = items[2]; return items;};
  const result = await compareSourceInstructions(f.config);
  assert.equal(result.status, 'incomplete'); assert.equal(result.reason, 'EvidenceSubjectMismatch');
  assert.equal(f.evaluated.length, 0);
});
test('the evaluator failing is a infrastructure error and never a score', async () => {
  const f = fixture(); f.config.evaluate = async () => {throw new Error('evaluator unavailable');};
  const result = await compareSourceInstructions(f.config);
  assert.equal(result.status, 'error'); assert.equal(result.reason, 'EvaluatorInfrastructureFailure');
  assert.equal(f.submitted.length, 1); assert.deepEqual(result.records, []);
});
test('response loss is not refunded or automatically retried', async () => {
  const f = fixture(); let sends = 0;
  f.config.executeTrial = async () => {sends++; throw Object.assign(new Error(), {code: 'SubmissionUnknown'});};
  const result = await compareSourceInstructions(f.config);
  assert.equal(result.status, 'error'); assert.equal(result.reason, 'SubmissionUnknown');
  assert.equal(sends, 1); assert.equal(result.used.providerCalls, 4);
});
test('late evaluator success cannot produce a score', async () => {
  const f = fixture(); let at = 0; f.config.now = () => at;
  const evaluate = f.config.evaluate;
  f.config.evaluate = async value => {at = sourceExperimentLimits.deadlineMs; return evaluate(value);};
  const result = await compareSourceInstructions(f.config);
  assert.equal(result.status, 'incomplete'); assert.equal(result.reason, 'EvaluationDeadlineExceeded');
  assert.deepEqual(result.records, []);
});
