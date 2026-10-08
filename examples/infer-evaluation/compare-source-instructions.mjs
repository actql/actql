// A bounded user-owned example. Execution and Evidence retrieval remain with
// the normal Client and the original authorized sink, respectively.
import {instructionCandidate, evaluationValueCid} from './evaluate.mjs';
import {checkEvidenceReference, evidenceParts} from './evidence-reference.mjs';

const fail = code => {throw Object.assign(new Error(code), {code});};
const unavailable = new Set(['RequiredEvidenceUnavailable', 'EvidenceExpired',
  'EvidenceReadDenied', 'EvidenceExternalSendDenied', 'EvidenceOriginalMissing',
  'EvidenceSubjectMismatch', 'InvalidEvidenceReference', 'InvalidEvidencePolicy',
  'EvaluationBudgetExceeded', 'EvaluationDeadlineExceeded']);
export const sourceExperimentLimits = Object.freeze({trials: 3, providerCalls: 12,
  evaluatorCalls: 12, retainedBytes: 3145728, deadlineMs: 180000,
  finalTrials: 1, finalProviderCalls: 4, finalEvaluatorCalls: 4, finalRetainedBytes: 1048576});
export const sourceEvaluationCases = Object.freeze({
  selection: Object.freeze([
    Object.freeze({id: 'selection-upper', key: 1, text: 'URGENT', first: 'high', second: 'low'}),
    Object.freeze({id: 'selection-ordinary', key: 2, text: 'ordinary', first: 'low', second: 'low'}),
  ]),
  final: Object.freeze([
    Object.freeze({id: 'final-lower', key: 1, text: 'urgent', first: 'high', second: 'low'}),
    Object.freeze({id: 'final-negated', key: 2, text: 'not urgent', first: 'low', second: 'low'}),
  ]),
});

// executeTrial submits one complete Program, then stops its Host process.
// collectEvidence returns all four original call references; evaluate resolves
// them using current permission and invokes a separate evaluator process.
export async function compareSourceInstructions({candidates, executeTrial,
  collectEvidence, evaluate, limits = sourceExperimentLimits, now = Date.now}) {
  if (!Array.isArray(candidates) || candidates.length !== 2 ||
      [executeTrial, collectEvidence, evaluate, now].some(fn => typeof fn !== 'function')) fail('InvalidEvaluationExperiment');
  const proposals = candidates.map(candidate => instructionCandidate(candidate, 'first_assessment'));
  if (proposals[0].id === proposals[1].id) fail('DuplicateEvaluationCandidate');
  if (Object.keys(limits).sort().join(',') !== Object.keys(sourceExperimentLimits).sort().join(',') ||
      Object.values(limits).some(value => !Number.isSafeInteger(value) || value <= 0) ||
      limits.deadlineMs > 300000 || limits.retainedBytes > 16777216 ||
      limits.finalTrials !== 1 || limits.finalProviderCalls !== 4 || limits.finalEvaluatorCalls !== 4 ||
      limits.finalRetainedBytes > limits.retainedBytes) fail('InvalidEvaluationBudget');
  let lastObserved = now();
  if (!Number.isFinite(lastObserved)) fail('InvalidEvaluationClock');
  const deadline = lastObserved + limits.deadlineMs;
  const records = [], subjects = new Set();
  const used = {trials: 0, providerCalls: 0, evaluatorCalls: 0, retainedBytes: 0};
  const datasetCid = evaluationValueCid(sourceEvaluationCases);
  let selectedCandidate;
  const result = (status, reason) => ({status, ...(reason === undefined ? {} : {reason}),
    datasetCid, selectedCandidate, records: [...records], used: {...used}});
  const checkDeadline = () => {
    const at = now();
    if (!Number.isFinite(at) || at < lastObserved) fail('InvalidEvaluationClock');
    lastObserved = at;
    if (at >= deadline) fail('EvaluationDeadlineExceeded');
  };
  async function trial(candidate, role) {
    const selection = role === 'selection';
    checkDeadline();
    for (const [name, charge] of [['trials', 1], ['providerCalls', 4], ['evaluatorCalls', 4]]) {
      const ceiling = limits[name] - (selection ? limits['final' + name[0].toUpperCase() + name.slice(1)] : 0);
      if (used[name] + charge > ceiling) fail('EvaluationBudgetExceeded');
    }
    // Unknown send outcomes do not refund calls or trigger a retry.
    used.trials++; used.providerCalls += 4;
    const trialValue = await executeTrial({candidate, role, deadline});
    checkDeadline();
    const identity = evaluationValueCid(trialValue.subject);
    if (subjects.has(identity)) fail('ReusedEvaluationRun');
    subjects.add(identity);
    const items = await collectEvidence(trialValue);
    checkDeadline();
    if (!Array.isArray(items) || items.length !== 4) fail('RequiredEvidenceUnavailable');
    let bytes = 0;
    const expected = sourceEvaluationCases[selection ? 'selection' : 'final'];
    const seen = new Set();
    for (const item of items) {
      if (!['first_assessment', 'second_assessment'].includes(item.target) ||
          !Array.isArray(item.key) || item.key.length !== 1 ||
          !expected.some(entry => entry.key === item.key[0])) fail('EvidenceSubjectMismatch');
      const association = `${item.target}:${item.key[0]}`;
      if (seen.has(association)) fail('EvidenceSubjectMismatch');
      seen.add(association);
      if (item.evidence?.status !== 'complete' || !item.evidence.references) fail('RequiredEvidenceUnavailable');
      for (const part of evidenceParts) {
        const ref = checkEvidenceReference(item.evidence.references[part], trialValue.subject, item.evidence.attemptCid);
        if (ref.part !== part) fail('EvidenceSubjectMismatch');
        bytes += ref.content.sizeBytes;
      }
    }
    const remaining = limits.retainedBytes - used.retainedBytes - (selection ? limits.finalRetainedBytes : 0);
    if (!Number.isSafeInteger(bytes) || bytes > remaining) fail('EvaluationBudgetExceeded');
    used.retainedBytes += bytes;
    // Each item is evaluated even when another item scores zero. Missing items
    // and process failures stop with a reason, never synthetic zero scores.
    for (const item of items) {
      checkDeadline(); used.evaluatorCalls++;
      const entry = expected.find(entry => entry.key === item.key[0]);
      const job = {subject: trialValue.subject, evidence: item.evidence,
        caseId: `${entry.id}:${item.target}`, role, deadline,
        expected: item.target === 'first_assessment' ? entry.first : entry.second};
      const scored = await evaluate({trial: trialValue, item, job});
      checkDeadline();
      if (scored?.caseId !== job.caseId || !Number.isFinite(scored.score) ||
          scored.score < 0 || scored.score > 1 || typeof scored.reason !== 'string' ||
          scored.reason.length > 4096 || !/^sha256:[a-f0-9]{64}$/u.test(scored.evaluator) ||
          !/^sha256:[a-f0-9]{64}$/u.test(scored.rubric)) fail('InvalidEvaluatorReply');
      records.push({candidateId: candidate.id, target: item.target, key: item.key,
        role, subject: trialValue.subject, attemptCid: item.evidence.attemptCid, ...scored});
    }
  }
  try {
    for (const candidate of proposals) await trial(candidate, 'selection');
    const total = candidate => records.filter(record => record.candidateId === candidate.id &&
      record.target === 'first_assessment').reduce((sum, record) => sum + record.score, 0);
    const winner = total(proposals[1]) > total(proposals[0]) ? proposals[1] : proposals[0];
    selectedCandidate = winner.id; // Frozen before the final trial is submitted.
    await trial(winner, 'final_test');
    return result('scored');
  } catch (error) {
    const reason = error?.code ?? 'EvaluatorInfrastructureFailure';
    return result(unavailable.has(reason) ? 'incomplete' : 'error', reason);
  }
}
