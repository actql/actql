// A user-owned experiment adapter, not an execution or recovery owner.
// Each trial submits one whole Program through the supplied ordinary Client.
import {createHash, randomUUID} from 'node:crypto';
import {canonicalJson as sdkCanonicalJson} from '../../packages/sdk/host-port.mjs';
import {checkEvidenceReference, evidenceParts} from './evidence-reference.mjs';

const canonicalJson = value => sdkCanonicalJson(value, {dataKeys: true});

const digest = value => `sha256:${createHash('sha256').update(canonicalJson(value)).digest('hex')}`;
const fail = code => {throw Object.assign(new Error(code), {code});};
const plain = value => value !== null && typeof value === 'object' &&
  Object.getPrototypeOf(value) === Object.prototype;
const keys = (value, expected) => plain(value) &&
  Object.keys(value).sort().join(',') === [...expected].sort().join(',');
const positive = value => Number.isSafeInteger(value) && value > 0;
const cid = value => typeof value === 'string' && /^sha256:[a-f0-9]{64}$/u.test(value);

// Candidate proposals cannot carry new authority, schema, Model, Effect,
// assertion, context-selector or budget fields. Canonical binding is still
// performed by the normal checker and Host when executeTrial submits it.
export function instructionCandidate(proposal, target) {
  if (!keys(proposal, ['id', 'target', 'instructions']) ||
      typeof proposal.id !== 'string' || !proposal.id || proposal.id.length > 128 ||
      proposal.target !== target || typeof proposal.instructions !== 'string' ||
      !proposal.instructions || proposal.instructions.length > 4096 ||
      Buffer.byteLength(proposal.instructions) > 4096) fail('ForbiddenEvaluationEdit');
  return Object.freeze({...proposal, instructionCid: digest(proposal.instructions)});
}

function snapshot(value) {
  const pending = [{value, depth: 0}];
  const seen = new Set();
  let nodes = 0, bytes = 0;
  while (pending.length) {
    const {value: current, depth, exit} = pending.pop();
    if (exit) {seen.delete(current); continue;}
    if (++nodes > 4096 || depth > 32) fail('EvaluationBudgetExceeded');
    if (typeof current === 'string') {
      if (current.length > 65536) fail('EvaluationBudgetExceeded');
      bytes += Buffer.byteLength(current) * 6 + 2;
    } else if (current === null || typeof current === 'boolean' ||
      typeof current === 'number' && Number.isFinite(current)) bytes += 32;
    else {
      if ((!Array.isArray(current) && !plain(current)) || seen.has(current)) fail('InvalidEvaluationCases');
      seen.add(current);
      pending.push({value: current, exit: true});
      const entries = Object.entries(current);
      if (entries.length > 4096 - nodes) fail('EvaluationBudgetExceeded');
      for (const [key, child] of entries) {
        if (key.length > 65536) fail('EvaluationBudgetExceeded');
        bytes += Buffer.byteLength(key) * 6 + 3;
        pending.push({value: child, depth: depth + 1});
      }
    }
    if (bytes > 65536) fail('EvaluationBudgetExceeded');
  }
  const copied = JSON.parse(canonicalJson(value));
  const freeze = value => {
    if (value !== null && typeof value === 'object') {
      for (const child of Object.values(value)) freeze(child);
      Object.freeze(value);
    }
    return value;
  };
  return freeze(copied);
}

function casesFor(value, role) {
  if (!Array.isArray(value) || value.length === 0 || value.length > 64) fail('InvalidEvaluationCases');
  const ids = new Set();
  return value.map(entry => {
    if (!keys(entry, ['id', 'input', 'expected']) || typeof entry.id !== 'string' ||
        !entry.id || ids.has(entry.id)) fail('InvalidEvaluationCases');
    ids.add(entry.id);
    // Values keep their original Unicode/newlines. Evaluator-only labels
    // never enter executeTrial's input object.
    return Object.freeze({id: entry.id, role,
      input: snapshot(entry.input),
      expected: snapshot(entry.expected)});
  });
}

function limitsFor(value) {
  const fields = ['trials', 'providerCalls', 'evaluatorCalls', 'retainedBytes',
    'deadlineMs', 'finalTrials', 'finalProviderCalls', 'finalEvaluatorCalls', 'finalRetainedBytes'];
  if (!keys(value, fields) || fields.some(name => !positive(value[name])) ||
      value.deadlineMs > 300000 || value.retainedBytes > 16777216 ||
      value.finalTrials > value.trials || value.finalProviderCalls > value.providerCalls ||
      value.finalEvaluatorCalls > value.evaluatorCalls ||
      value.finalRetainedBytes > value.retainedBytes) fail('InvalidEvaluationBudget');
  return Object.freeze({...value});
}

function evidenceFor(value, subject, candidate, item, target, maxBytes) {
  if (!plain(value) || value.status !== 'complete') fail('RequiredEvidenceUnavailable');
  if (value.target !== target || value.subject?.runDefinitionCid !== subject.runDefinitionCid ||
      value.subject?.authorityScopeCid !== subject.authorityScopeCid ||
      value.instructionCid !== candidate.instructionCid || value.caseId !== item.id ||
      value.inputCid !== digest(item.input) || !cid(value.programCid) ||
      !cid(value.modelTaskCid) || !cid(value.providerBindingCid)) fail('EvidenceSubjectMismatch');
  if (!cid(value.attemptCid) || !keys(value.references, evidenceParts)) fail('RequiredEvidenceUnavailable');
  let bytes = 0;
  for (const name of evidenceParts) {
    const ref = checkEvidenceReference(value.references[name], subject, value.attemptCid);
    if (ref.part !== name) fail('EvidenceSubjectMismatch');
    bytes += ref.content.sizeBytes;
  }
  if (!Number.isSafeInteger(bytes) || bytes > maxBytes) fail('EvaluationBudgetExceeded');
  return {value, bytes};
}

// readEvidence must use the original kind's current authorized resolver;
// a CID, copied metadata or a remembered allow does not grant retrieval.
// evaluate is external work and has no Client or execution-control handle.
export async function compareInstructions({target, candidates, selectionCases,
  finalCases, limits, executeTrial, readEvidence, evaluate, now = Date.now}) {
  if (typeof target !== 'string' || !target || !Array.isArray(candidates) ||
      candidates.length !== 2 || [executeTrial, readEvidence, evaluate, now]
        .some(fn => typeof fn !== 'function')) fail('InvalidEvaluationExperiment');
  const proposals = candidates.map(value => instructionCandidate(value, target));
  if (proposals[0].id === proposals[1].id) fail('DuplicateEvaluationCandidate');
  const budget = limitsFor(limits);
  const selection = casesFor(selectionCases, 'selection');
  const final = casesFor(finalCases, 'final_test');
  if (final.some(item => selection.some(other => other.id === item.id ||
      digest(other.input) === digest(item.input)))) fail('EvaluationSplitLeakage');
  const startedAt = now();
  if (!Number.isFinite(startedAt)) fail('InvalidEvaluationClock');
  const deadline = startedAt + budget.deadlineMs;
  let lastObservedAt = startedAt;
  const checkDeadline = () => {
    const at = now();
    if (!Number.isFinite(at) || at < lastObservedAt) fail('InvalidEvaluationClock');
    lastObservedAt = at;
    if (at >= deadline) fail('EvaluationDeadlineExceeded');
  };
  const datasetCid = digest({selection: selection.map(item => ({id: item.id, input: item.input, expected: item.expected})),
    final: final.map(item => ({id: item.id, input: item.input, expected: item.expected}))});
  const fixedBytes = Buffer.byteLength(canonicalJson({proposals, selection, final}));
  if (fixedBytes > budget.retainedBytes - budget.finalRetainedBytes) fail('EvaluationBudgetExceeded');
  const used = {trials: 0, providerCalls: 0, evaluatorCalls: 0, retainedBytes: fixedBytes};
  const records = [];
  const subjects = new Set();
  let frozen;
  const result = (status, reason) => Object.freeze({status, reason, target,
    datasetCid, records: Object.freeze([...records]), used: Object.freeze({...used}),
    ...(frozen === undefined ? {} : {selectedCandidate: frozen.id})});
  async function trial(candidate, item) {
    const reserve = item.role === 'selection';
    for (const name of ['trials', 'providerCalls', 'evaluatorCalls', 'retainedBytes']) {
      const ceiling = budget[name] - (reserve ? budget[`final${name[0].toUpperCase()}${name.slice(1)}`] : 0);
      if (used[name] >= ceiling) fail('EvaluationBudgetExceeded');
    }
    checkDeadline();
    // Charge before invoking user code. Response loss does not refund a
    // trial or call, and the adapter never retries executeTrial.
    used.trials++; used.providerCalls++;
    const trialId = randomUUID();
    const subject = await executeTrial({trialId, target, candidate,
      case: {id: item.id, input: item.input}});
    checkDeadline();
    if (!plain(subject) || !cid(subject.runDefinitionCid) ||
        !cid(subject.authorityScopeCid)) fail('InvalidEvaluationSubject');
    const subjectIdentity = canonicalJson(subject);
    if (subjects.has(subjectIdentity)) fail('ReusedEvaluationRun');
    subjects.add(subjectIdentity);
    const remaining = budget.retainedBytes - used.retainedBytes -
      (reserve ? budget.finalRetainedBytes : 0);
    const evidence = evidenceFor(await readEvidence({subject, target, trialId}),
      subject, candidate, item, target, remaining);
    used.retainedBytes += evidence.bytes;
    checkDeadline();
    used.evaluatorCalls++;
    const scored = await evaluate({trialId, target, candidateId: candidate.id,
      caseId: item.id, role: item.role, subject, evidence: evidence.value,
      expected: item.expected, deadline});
    checkDeadline();
    if (!keys(scored, ['caseId', 'score', 'reason', 'evaluator', 'rubric']) ||
        scored.caseId !== item.id || !Number.isFinite(scored.score) ||
        scored.score < 0 || scored.score > 1 || typeof scored.reason !== 'string' ||
        scored.reason.length > 4096 || !cid(scored.evaluator) || !cid(scored.rubric)) fail('InvalidEvaluatorReply');
    records.push(Object.freeze({status: 'scored', trialId, candidateId: candidate.id,
      datasetCid, caseId: item.id, role: item.role, subject, instructionCid: candidate.instructionCid,
      scale: Object.freeze({minimum: 0, maximum: 1, direction: 'maximize'}),
      programCid: evidence.value.programCid, modelTaskCid: evidence.value.modelTaskCid,
      providerBindingCid: evidence.value.providerBindingCid,
      references: evidence.value.references,
      attemptCid: evidence.value.attemptCid,
      ...scored}));
  }
  try {
    for (const candidate of proposals) for (const item of selection) await trial(candidate, item);
    const total = candidate => records.filter(record => record.candidateId === candidate.id)
      .reduce((sum, record) => sum + record.score, 0);
    // Freeze before any final-test input/label is given to execution or
    // evaluation. A tie keeps A; no optimizer or final-test feedback loop.
    frozen = total(proposals[1]) > total(proposals[0]) ? proposals[1] : proposals[0];
    for (const item of final) await trial(frozen, item);
    return result('scored');
  } catch (error) {
    const reason = error?.code ?? 'EvaluatorInfrastructureFailure';
    return result(['RequiredEvidenceUnavailable', 'EvidenceSubjectMismatch',
      'EvaluationBudgetExceeded', 'EvaluationDeadlineExceeded', 'EvidenceExpired',
      'EvidenceReadDenied', 'EvidenceExternalSendDenied', 'EvidenceOriginalMissing',
      'InvalidEvidenceReference', 'InvalidEvidencePolicy'].includes(reason)
      ? 'incomplete' : 'error', reason);
  }
}

export const evaluationValueCid = digest;
