// One bounded, independent evaluator process. No Client, execution Owner,
// provider credential or automatic execution retry is supplied to the child.
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {checkResolvedEvidence} from './evidence-reference.mjs';

const fail = code => Object.assign(new Error(code), {code});
const evaluator = fileURLToPath(new URL('./evaluator-worker.mjs', import.meta.url));

export async function runEvaluatorProcess({job, resolvedEvidence, deadline,
  onProcess = () => {}, signal}) {
  const remaining = deadline - Date.now();
  if (!Number.isFinite(remaining) || remaining <= 0 || remaining > 300000) throw fail('EvaluationDeadlineExceeded');
  checkResolvedEvidence(job, resolvedEvidence);
  const payload = canonicalJson({job, resolvedEvidence});
  if (payload.length > 1048576 || Buffer.byteLength(payload) > 1048576) throw fail('EvaluationBudgetExceeded');
  signal?.throwIfAborted();
  const child = spawn(process.execPath, [evaluator], {stdio: ['pipe', 'pipe', 'pipe'],
    env: {PATH: process.env.PATH}, shell: false});
  let code, stderrBytes = 0, outputBytes = 0;
  const stdout = [], stderr = [];
  const stop = problem => {code ??= problem; child.kill('SIGTERM');};
  const abort = () => stop('EvaluatorInfrastructureFailure');
  signal?.addEventListener('abort', abort, {once: true});
  // A deadline does not report settlement: keep ownership until close.
  const timer = setTimeout(() => stop('EvaluationDeadlineExceeded'), remaining);
  let hardStop;
  child.stdout.on('data', bytes => {
    outputBytes += bytes.length;
    if (outputBytes > 16384) stop('EvaluatorInfrastructureFailure');
    else stdout.push(bytes);
  });
  child.stderr.on('data', bytes => {stderrBytes += bytes.length; if (stderrBytes > 4096) stop('EvaluatorInfrastructureFailure'); else stderr.push(bytes);});
  child.stdin.on('error', () => stop('EvaluatorInfrastructureFailure'));
  const closed = new Promise((resolve, reject) => {
    child.once('error', () => {code ??= 'EvaluatorInfrastructureFailure';});
    child.once('close', (exit, killed) => {
      clearTimeout(timer); clearTimeout(hardStop); signal?.removeEventListener('abort', abort);
      if (code || exit !== 0 || killed) {
        const reason = Buffer.concat(stderr, Math.min(stderrBytes, 4096)).toString('utf8');
        const unavailable = ['RequiredEvidenceUnavailable', 'EvidenceExpired', 'EvidenceSubjectMismatch',
          'InvalidEvidenceReference', 'InvalidEvidencePolicy', 'EvaluationBudgetExceeded'];
        return reject(fail(code ?? (unavailable.includes(reason) ? reason : 'EvaluatorInfrastructureFailure')));
      }
      try {resolve(JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(stdout, outputBytes))));} catch {reject(fail('InvalidEvaluatorReply'));}
    });
  });
  // Only the fixed local evaluator is executed. The PID is caller-scoped
  // measurement, not execution authority or an ActQL identity.
  try {onProcess(child.pid); child.stdin.end(payload);}
  catch {stop('EvaluatorInfrastructureFailure');}
  // Terminate a child which ignores TERM without claiming successful work.
  hardStop = setTimeout(() => {code ??= 'EvaluationDeadlineExceeded'; child.kill('SIGKILL');}, remaining + 1000);
  return closed;
}
