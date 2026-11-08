// Consume the same source-bound compiler graph as selection. No package build,
// artifact reuse or product gate is substituted for these selected tests.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {availableParallelism} from 'node:os';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {readMoonTestPlan} from './ci-moon-test-plan.mjs';
import {validateSelection} from './ci-targets.mjs';
import {runFocusedTests} from './test-execution.mjs';

export function runMoonTests(plan, target, base, {cwd = process.cwd(),
  git = args => execFileSync('git', args, {cwd, encoding:'utf8'}),
  discover = readMoonTestPlan,
  preview = args => execFileSync('moon', args, {cwd, encoding:'utf8', timeout:60000, maxBuffer:16 * 1024 ** 2}),
  run = runFocusedTests} = {}) {
  assert(['js', 'wasm'].includes(target), 'Native retains its full original physical profiles');
  assert.equal(git(['rev-parse', 'HEAD']).trim(), plan?.sourceRevision, 'Foreign test selection');
  const selection = validateSelection(plan.selection);
  assert(selection.moonTests, 'Missing compiler-owned test plan');
  assert.deepEqual(discover(selection.paths, base, {repository:cwd}), selection.moonTests,
    'Changed compiler graph or selected source inventory');
  const args = ['--target', target, '--deny-warn', '-j', String(availableParallelism())];
  const commands = preview(['test', ...args, ...selection.moonTests.files, '--dry-run']);
  assert.equal(typeof commands, 'string', 'Missing compiler test plan');
  // A JS-only package may have no Wasm driver. Keep that backend's complete
  // nonzero suite, rather than invent successful execution for zero tests.
  if (!commands.split('\n').some(line => /(?:^|\/)moon generate-test-driver /u.test(line.trim()))) {
    console.log(`Moon ${target}: no applicable selected compiler driver; retaining the full backend suite`);
    return run('moon', args, {cwd});
  }
  return run('moon', [...args, ...selection.moonTests.files], {cwd});
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.env.GITHUB_EVENT_NAME, 'pull_request');
  const payload = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  process.exitCode = runMoonTests(JSON.parse(process.env.CI_PLAN), process.argv[2], payload.pull_request.base.sha);
}
