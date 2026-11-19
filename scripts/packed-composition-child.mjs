import {spawn} from 'node:child_process';

const scripts = ['publish.mjs', 'read.mjs', 'publish-effect.mjs', 'effect-run.mjs'];
const sources = ['publication', 'target-read', 'source', 'two-source', 'read-approval',
  'infer', 'infer-model-approval', 'infer-text', 'infer-graph-node', 'infer-graph-edge',
  'optional-effect'];
const phases = ['identity', 'submit', 'answer', 'resume', 'recheck', 'target-answer',
  'target-resume', 'source-answer', 'source-resume', 'model-answer', 'model-resume',
  'rce-empty', 'rce-unsupported', 'rce-submit', 'rce-submit-pending', 'rce-resume',
  'admission-original', 'admission-foreign-actor', 'admission-replay',
  'admission-without-source', 'admission-conflict', 'admission-corrupt',
  'policy-refusal', 'assertion-refusal'];
const label = (allowed, value) => allowed.includes(value) ? value : 'unclassified';

// The original packed composition child seam, with closed diagnostic labels.
// Ports let its close/timer behavior be tested without a product process or wait.
export function runPackedCompositionChild({script, cwd, env, args = [], expectedExit = 0,
  source = 'publication', protocol = 'local'}, {
  spawnChild = spawn, setTimer = setTimeout, clearTimer = clearTimeout,
  report = line => console.error(line),
} = {}) {
  return new Promise((resolve, reject) => {
    const boundary = {script: label(scripts, script), source: label(sources, source),
      protocol: label(['local', 'https'], protocol),
      phase: args.length === 0 ? 'default' : label(phases, args[0])};
    report('packed child start ' + JSON.stringify(boundary));
    const child = spawnChild(process.execPath, [script, ...args], {cwd, env});
    let stdout = '';
    let stderr = '';
    let timerFired = false;
    let killReturned = null;
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    const timer = setTimer(() => {
      timerFired = true;
      killReturned = child.kill('SIGKILL');
    }, 120000);
    child.on('error', reject);
    child.on('close', (code, signal) => {
      clearTimer(timer);
      if (code === expectedExit) resolve(stdout);
      else reject(new Error(`${script} failed:\n${stdout}\n${stderr}\n` +
        'packed child close ' + JSON.stringify({...boundary, code, signal,
          timerFired, killReturned})));
    });
  });
}
