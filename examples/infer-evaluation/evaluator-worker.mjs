// A deterministic external rubric proves the Evidence connection, not real
// model quality improvement. Labels arrive here, never in provider inputs.
import {createHash} from 'node:crypto';
import {canonicalJson as sdkCanonicalJson} from '../../packages/sdk/host-port.mjs';
import {checkResolvedEvidence, checkModelCaptureCorrespondence} from './evidence-reference.mjs';
const canonicalJson = value => sdkCanonicalJson(value, {dataKeys: true});
const cid = value => `sha256:${createHash('sha256').update(canonicalJson(value)).digest('hex')}`;
const fail = code => {throw Object.assign(new Error(code), {code});};
let size = 0;
const chunks = [];
try {
  for await (const chunk of process.stdin) {
    size += chunk.length;
    if (size > 1048576) fail('EvaluationBudgetExceeded');
    chunks.push(chunk);
  }
  const {job, resolvedEvidence} = JSON.parse(Buffer.concat(chunks, size).toString('utf8'));
  if (!job || typeof job.caseId !== 'string' || !['high', 'low'].includes(job.expected) ||
      !['selection', 'final_test'].includes(job.role)) fail('InvalidEvaluatorInput');
  const values = checkModelCaptureCorrespondence(job, checkResolvedEvidence(job, resolvedEvidence));
  if (values.validation.outcome !== 'accepted' || values.typedOutput.outcome !== 'ok' ||
      typeof values.typedOutput.value?.risk !== 'string') fail('RequiredEvidenceUnavailable');
  const actual = values.typedOutput.value.risk;
  const score = actual === job.expected ? 1 : 0;
  process.stdout.write(canonicalJson({caseId: job.caseId, score,
    reason: score === 1 ? 'The instruction matches the independent priority label.' :
      'The submitted instruction missed the independent priority label; handle input case explicitly.',
    evaluator: cid({implementation: 'deterministic-priority-evaluator', revision: 1}),
    rubric: cid({objective: 'exact-priority', scale: [0, 1], direction: 'maximize', revision: 1})}));
} catch (error) {
  // Failure is a process error, never a synthetic score. Do not disclose raw
  // artifact content, labels, provider inputs or credential-bearing errors.
  process.stderr.write(typeof error?.code === 'string' ? error.code : 'EvaluatorInfrastructureFailure');
  process.exitCode = 1;
}
