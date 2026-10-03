// Optional personal PreToolUse adapter. No tests, subprocesses, or validation
// gates run here. The shared policy and bounded wrapper do the actual work.
import {readFileSync} from 'node:fs';
import {isAbsolute, relative, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {classifyJob, classifyMoon} from './local-checks-policy.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));

// Deliberately only one unquoted literal command. Unsupported shell syntax is
// unclassified, not safe. In particular, never search a compound command for
// an override flag that could belong to a different command.
export function classifyCommand(command) {
  if (typeof command !== 'string' ||
      !/^[ \t]*[A-Za-z0-9_./:@%+=,-]+(?:[ \t]+[A-Za-z0-9_./:@%+=,-]+)*[ \t]*$/u.test(command)) {
    return {recognized: false, classification: 'unknown'};
  }
  const words = command.trim().split(/[ \t]+/u);
  if (words[0] === 'moon' && ['test', 'build'].includes(words[1])) {
    return {recognized: true, ...classifyMoon(words[1], words.slice(2)),
      route: `${words[1]} moon`, moonArgs: words.slice(2), explicitOverride: false};
  }
  if (words[0] !== 'node' ||
      !['scripts/local-checks.mjs', './scripts/local-checks.mjs'].includes(words[1])) {
    return {recognized: false, classification: 'unknown'};
  }
  const [action, subject] = words.slice(2);
  if (['list', 'changed'].includes(action)) {
    return {recognized: true, heavy: false, classification: 'reporting'};
  }
  if (!['test', 'build', 'run'].includes(action) || !subject) {
    return {recognized: false, classification: 'unknown'};
  }
  if (action !== 'run' && subject !== 'moon') {
    return {recognized: false, classification: 'unknown'};
  }
  const rest = words.slice(4);
  const delimiter = rest.indexOf('--');
  if (action !== 'run' && delimiter < 0) {
    return {recognized: false, classification: 'unknown'};
  }
  const options = action === 'run' ? rest : rest.slice(0, delimiter);
  let explicitOverride = false;
  let dryRun = false;
  const jobArgs = [];
  for (let index = 0; index < options.length; index++) {
    if (options[index] === '--allow-heavy') { explicitOverride = true; continue; }
    if (options[index] === '--dry-run' && action === 'run') { dryRun = true; continue; }
    if (['--timeout-seconds', '--kill-grace-seconds'].includes(options[index])) {
      const value = options[++index];
      if (!/^\d+(?:\.\d+)?$/u.test(value ?? '') || !(Number(value) > 0) ||
          Number(value) * 1000 > 2147483647) {
        return {recognized: false, classification: 'unknown'};
      }
      continue;
    }
    if (options[index] === '--target' && action === 'run' &&
        ['js', 'wasm', 'native'].includes(options[++index])) {
      jobArgs.push('--target', options[index]);
      continue;
    }
    return {recognized: false, classification: 'unknown'};
  }
  const policy = action === 'run' ? classifyJob(subject)
    : classifyMoon(action, rest.slice(delimiter + 1));
  // Unknown jobs follow the wrapper's normal validation. Do not manufacture a
  // deny based on a nonexistent or as-yet-unclassified workflow job.
  if (action === 'run' && policy.classification === 'unknown') {
    return {recognized: false, classification: 'unknown'};
  }
  return {recognized: true, ...policy, explicitOverride,
    ...(dryRun ? {heavy: false, classification: 'reporting'} : {}),
    route: `${action} ${subject}`,
    ...(action === 'run' ? {jobArgs} : {moonArgs: rest.slice(delimiter + 1)})};
}

function inCheckout(cwd, checkout) {
  if (typeof cwd !== 'string' || !isAbsolute(cwd)) return false;
  const path = relative(checkout, cwd);
  return path !== '..' && !path.startsWith(`..${sep}`) && !isAbsolute(path);
}

export function hookDecision(payload, {checkout = root} = {}) {
  if (payload?.hook_event_name !== 'PreToolUse' || payload.tool_name !== 'Bash' ||
      !inCheckout(payload.cwd, checkout)) return null;
  const result = classifyCommand(payload.tool_input?.command);
  if (!result.recognized || !result.heavy || result.explicitOverride) return null;
  const rerun = `node scripts/local-checks.mjs ${result.route} --allow-heavy` +
    (result.moonArgs ? ` --timeout-seconds <seconds> --${result.moonArgs.length ? ' ' + result.moonArgs.join(' ') : ''}`
      : `${result.jobArgs.length ? ' ' + result.jobArgs.join(' ') : ''} [--timeout-seconds <seconds>]`);
  return `${result.reason}. From the checkout root, prefer a focused check: ` +
    `${result.alternatives.join('; ')}. Leave the complete check to CI. ` +
    (result.classification === 'unknown'
      ? 'The wrapper rejects unclassified arguments; add reviewed policy support before using this form. '
      : `If this full local run is deliberate, use from the checkout root: ${rerun}. `) +
    '--allow-heavy is deliberate friction, not user approval or a permission grant.';
}

export function runHookAdapter(moduleUrl, respond, label) {
  if (!process.argv[1] || resolve(process.argv[1]) !== fileURLToPath(moduleUrl)) return;
  try {
    const result = respond(JSON.parse(readFileSync(0, 'utf8')));
    if (result) process.stdout.write(JSON.stringify(result) + '\n');
  } catch {
    // An invalid event is outside this adapter's contract. Do not output an
    // unsupported "ask" or allow decision, and do not claim a hook failure blocks.
    process.stderr.write(`${label} local checks hook: invalid input; no decision was made\n`);
  }
}
