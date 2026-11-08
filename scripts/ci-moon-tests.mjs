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
import {portableMoonTestCount} from './native-core-test-selection.mjs';

export function originalMoonTestPlan(plan, base, {cwd = process.cwd(),
  git = args => execFileSync('git', args, {cwd, encoding:'utf8'}),
  discover = readMoonTestPlan} = {}) {
  assert.equal(git(['rev-parse', 'HEAD']).trim(), plan?.sourceRevision, 'Foreign test selection');
  const selection = validateSelection(plan.selection);
  assert(selection.moonTests, 'Missing compiler-owned test plan');
  assert.deepEqual(discover(selection.paths, base, {repository:cwd}), selection.moonTests,
    'Changed compiler graph or selected source inventory');
  return selection.moonTests;
}

export function nativeMoonPackages(environment = process.env, {cwd = process.cwd(),
  readEvent = path => JSON.parse(readFileSync(path, 'utf8')), ...options} = {}) {
  if (!environment.CI_PLAN) return undefined;
  const plan = JSON.parse(environment.CI_PLAN);
  if (!plan.selection?.moonTests) return undefined;
  assert.equal(environment.GITHUB_EVENT_NAME, 'pull_request');
  const base = readEvent(environment.GITHUB_EVENT_PATH).pull_request.base.sha;
  return originalMoonTestPlan(plan, base, {cwd, ...options}).packages;
}

export function runMoonTests(plan, target, base, {cwd = process.cwd(), git, discover,
  count = (args, backend) => portableMoonTestCount(cwd, args, backend),
  run = runFocusedTests} = {}) {
  assert(['js', 'wasm'].includes(target), 'Native uses its original compiler/profile entrance');
  const scope = originalMoonTestPlan(plan, base, {cwd, git, discover});
  const args = ['--target', target, '--deny-warn', '-j', String(availableParallelism())];
  const runnable = count([...args.slice(2), ...scope.files], target);
  assert(Number.isSafeInteger(runnable) && runnable >= 0, 'Missing compiler runnable test count');
  // JS-only, testless and benchmark-only packages retain this backend's
  // complete nonzero suite, rather than claiming a zero-test success.
  if (runnable === 0) {
    console.log(`Moon ${target}: no runnable selected compiler cases; retaining the full backend suite`);
    return run('moon', args, {cwd});
  }
  return run('moon', [...args, ...scope.files], {cwd});
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.env.GITHUB_EVENT_NAME, 'pull_request');
  const payload = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  process.exitCode = runMoonTests(JSON.parse(process.env.CI_PLAN), process.argv[2], payload.pull_request.base.sha);
}
