import assert from 'node:assert/strict';
import test from 'node:test';
import {referenceCid} from './evidence-reference.mjs';
import {compareInstructions, instructionCandidate, evaluationValueCid as cid} from './evaluate.mjs';

const target = 'classify_priority';
const candidates = [{id: 'A', target, instructions: 'Classify exact lowercase urgent.'},
  {id: 'B', target, instructions: 'Classify urgency without case sensitivity.'}];
const selectionCases = [{id: 'selection-upper', input: {id: 's1', text: 'URGENT'}, expected: 'high'}];
const finalCases = [{id: 'final-other', input: {id: 'f1', text: 'ordinary'}, expected: 'low'}];
const limits = {trials: 3, providerCalls: 3, evaluatorCalls: 3, retainedBytes: 3000,
  deadlineMs: 10000, finalTrials: 1, finalProviderCalls: 1, finalEvaluatorCalls: 1, finalRetainedBytes: 1000};

// Synthetic references only in this isolated driver unit test. Public
// acceptance must obtain original capture/Result references and current authorization.
function fixture(overrides = {}) {
  const calls = [], jobs = [], evidenceReads = [];
  const subjects = new Map();
  const config = {target, candidates, selectionCases, finalCases, limits,
    async executeTrial(trial) {
      calls.push(trial);
      assert.equal(Object.hasOwn(trial.case, 'expected'), false);
      assert.equal(Object.hasOwn(trial.case, 'role'), false);
      const subject = {runDefinitionCid: cid({trial: trial.trialId}), authorityScopeCid: cid('fixture-scope')};
      subjects.set(subject.runDefinitionCid, trial);
      return subject;
    },
    async readEvidence({subject}) {
      evidenceReads.push(subject);
      const trial = subjects.get(subject.runDefinitionCid);
      const attemptCid = cid({subject, attempt: 1});
      const policy = {kind: 'data_policy', wire: '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}'};
      policy.cid = referenceCid(JSON.parse(policy.wire));
      const references = Object.fromEntries(['typedInput', 'typedOutput', 'renderedInput', 'contextManifest', 'validation']
        .map(name => {
          const body = {version: 'evaluation-evidence-reference/0.1', kind: 'model_capture', part: name,
            subject, attemptCid, policy, original: {captureBundleCid: cid({subject, bundle: true}),
              modelCallSlotCid: cid({subject, slot: 0}), semanticRequestCid: cid(trial.case.input),
              modelTaskCid: cid(trial.candidate.instructions)},
            content: {cid: cid(name), sizeBytes: 100, truncated: false, expiresAt: '2099-01-01T00:00:00.000Z'}};
          return [name, {...body, evidenceRefCid: referenceCid(body)}];
        }));
      return {status: 'complete', target, subject, references, attemptCid, caseId: trial.case.id,
        instructionCid: trial.candidate.instructionCid, inputCid: cid(trial.case.input),
        programCid: cid(trial.case.input), modelTaskCid: cid(trial.candidate.instructions), providerBindingCid: cid('fixture-provider')};
    },
    async evaluate(job) {
      jobs.push(job);
      return {caseId: job.caseId, score: job.candidateId === 'A' ? 0 : 1,
        reason: job.candidateId === 'A' ? 'The uppercase urgency case was missed.' : 'The allowed instruction handles uppercase urgency.',
        evaluator: cid('independent-evaluator/1'), rubric: cid('exact-priority/1')};
    }, ...overrides};
  return {config, calls, jobs, subjects, evidenceReads};
}

test('aligned incorrect-answer scores select B, then freeze before a disjoint final case', async () => {
  const f = fixture();
  const result = await compareInstructions(f.config);
  assert.equal(result.status, 'scored');
  assert.equal(result.selectedCandidate, 'B');
  assert.deepEqual(result.records.map(({candidateId, caseId, role, score}) => ({candidateId, caseId, role, score})), [
    {candidateId: 'A', caseId: 'selection-upper', role: 'selection', score: 0},
    {candidateId: 'B', caseId: 'selection-upper', role: 'selection', score: 1},
    {candidateId: 'B', caseId: 'final-other', role: 'final_test', score: 1},
  ]);
  assert.equal(new Set(f.calls.map(call => call.trialId)).size, 3);
  assert.equal(f.jobs.length, 3);
});

test('missing Evidence stops comparison without a zero-score substitute or another execution', async () => {
  const f = fixture({readEvidence: async () => ({status: 'not_collected'})});
  const result = await compareInstructions(f.config);
  assert.equal(result.status, 'incomplete');
  assert.equal(result.reason, 'RequiredEvidenceUnavailable');
  assert.deepEqual(result.records, []);
  assert.equal(f.calls.length, 1);
  assert.equal(f.jobs.length, 0);
});

test('Evaluator infrastructure failure is error, never an incorrect-answer score', async () => {
  const f = fixture({evaluate: async () => {throw new Error('fixture evaluator died');}});
  const result = await compareInstructions(f.config);
  assert.equal(result.status, 'error');
  assert.equal(result.reason, 'EvaluatorInfrastructureFailure');
  assert.deepEqual(result.records, []);
  assert.equal(f.calls.length, 1);
});

test('late evaluator success is incomplete and cannot become a score', async () => {
  let at = 0;
  const f = fixture({now: () => at});
  const evaluate = f.config.evaluate;
  f.config.evaluate = async job => {at = limits.deadlineMs; return evaluate(job);};
  const result = await compareInstructions(f.config);
  assert.equal(result.status, 'incomplete');
  assert.equal(result.reason, 'EvaluationDeadlineExceeded');
  assert.deepEqual(result.records, []);
  assert.equal(f.calls.length, 1);
});

test('a backwards clock cannot renew the experiment allowance', async () => {
  let at = 1;
  const f = fixture({now: () => at});
  const execute = f.config.executeTrial;
  f.config.executeTrial = async trial => {at = 0; return execute(trial);};
  const result = await compareInstructions(f.config);
  assert.equal(result.status, 'error');
  assert.equal(result.reason, 'InvalidEvaluationClock');
  assert.deepEqual(result.records, []);
  assert.equal(f.calls.length, 1);
});

for (const property of ['authority', 'model', 'schema', 'effectTarget', 'approval', 'assertions', 'budget', 'contextSelector']) {
  test(`instruction-only candidate refuses forbidden ${property}`, () => {
    assert.throws(() => instructionCandidate({...candidates[0], [property]: {}}, target), {code: 'ForbiddenEvaluationEdit'});
  });
}

test('final-test input reuse is rejected before any provider or evaluator call', async () => {
  const f = fixture({finalCases: [{id: 'copied-final', input: selectionCases[0].input, expected: 'high'}]});
  await assert.rejects(compareInstructions(f.config), {code: 'EvaluationSplitLeakage'});
  assert.equal(f.calls.length, 0);
  assert.equal(f.jobs.length, 0);
});

test('reserved final-test trial allowance cannot be spent by selection', async () => {
  const f = fixture({limits: {...limits, trials: 2}});
  const result = await compareInstructions(f.config);
  assert.equal(result.status, 'incomplete');
  assert.equal(result.reason, 'EvaluationBudgetExceeded');
  assert.equal(f.calls.length, 1);
  assert.equal(result.selectedCandidate, undefined);
});

test('lost original execution response is never automatically retried', async () => {
  let calls = 0;
  const f = fixture({executeTrial: async () => {calls++; throw Object.assign(new Error('unknown original'), {code: 'SubmissionUnknown'});}});
  const result = await compareInstructions(f.config);
  assert.equal(result.status, 'error');
  assert.equal(result.reason, 'SubmissionUnknown');
  assert.equal(calls, 1);
  assert.equal(f.jobs.length, 0);
});

test('a changed INFER instruction cannot be evaluated with the previous candidate Evidence', async () => {
  const f = fixture();
  const read = f.config.readEvidence;
  let first;
  f.config.readEvidence = async request => {
    const current = await read(request);
    if (first === undefined) {first = current; return current;}
    return {...current, instructionCid: first.instructionCid};
  };
  const result = await compareInstructions(f.config);
  assert.equal(result.status, 'incomplete');
  assert.equal(result.reason, 'EvidenceSubjectMismatch');
  assert.equal(f.calls.length, 2);
  assert.equal(f.jobs.length, 1);
});

test('original exact Unicode and newlines survive case and instruction identity', async () => {
  const variants = ['e\u0301', 'é', '\r', '\n', '\r\n'];
  assert.equal(new Set(variants.map(cid)).size, variants.length);
  for (const value of variants) {
    const candidate = instructionCandidate({...candidates[0], instructions: value}, target);
    assert.equal(candidate.instructions, value);
  }
});

test('data member identity and submitted case snapshots preserve exact nested keys', async () => {
  assert.notEqual(cid({'e\u0301': 1}), cid({'é': 1}));
  assert.notEqual(cid({'line\r': 1}), cid({'line\n': 1}));
  const f = fixture({selectionCases: [{id: 'selection-keys', expected: 'high', input: {
    id: 's1', text: 'URGENT', metadata: {'e\u0301': {'line\r': 'CR\r', 'line\n': 'LF\n'}, 'é': 'CRLF\r\n'},
  }}], limits: {...limits, retainedBytes: 30000, finalRetainedBytes: 10000}});
  const result = await compareInstructions(f.config);
  assert.equal(result.status, 'scored');
  assert.deepEqual(f.calls[0].case.input, {id: 's1', text: 'URGENT',
    metadata: {'e\u0301': {'line\r': 'CR\r', 'line\n': 'LF\n'}, 'é': 'CRLF\r\n'}});
});
