// Failure workaround for the selected Darwin Core row, not another test gate.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {runFocusedTests} from './test-execution.mjs';

export function runNativeCoreTestSequence(args, options, {
  build = spawnSync, test = runFocusedTests, now = () => performance.now(),
  platform = process.platform,
} = {}) {
  const {serialBuild = false, timeout, env = process.env, cwd = process.cwd(),
    ...rest} = options;
  if (!serialBuild) return test('moon', args, {timeout, env, cwd, ...rest});
  assert.equal(platform, 'darwin', 'Serial Core preparation is selected only on Darwin');
  assert.equal(args[0], '--target');
  assert.equal(args[1], 'native');
  assert(!args.includes('--build-only') && !args.includes('--no-parallelize'));
  assert(Number.isFinite(timeout) && timeout > 0);
  const buildArgs = [];
  for (let index = 0; index < args.length; index++) {
    const arg = args[index];
    if (arg === '-j' || arg === '--jobs') {
      assert(/^[1-9][0-9]*$/u.test(args[++index] ?? ''));
    } else if (!/^(?:-j[1-9][0-9]*|--jobs=[1-9][0-9]*)$/u.test(arg)) buildArgs.push(arg);
  }
  // The same source, cwd, environment, flags and output tree yield the same
  // Moon action identities. --build-only stops after preparing test artifacts;
  // -j changes scheduling, not the compiler/driver action command lines.
  const started = now();
  console.log('Native compiler preparation: serial build-only; no tests executed');
  const result = build('moon', ['test', ...buildArgs, '--build-only', '-j', '1'],
    {env, cwd, stdio: 'inherit', timeout, killSignal: 'SIGKILL'});
  if (result.error || result.signal || result.status !== 0) {
    console.error('Native compiler preparation failed');
    return result.status || 1;
  }
  const remaining = timeout - Math.ceil(now() - started);
  if (remaining <= 0) {
    console.error('Native Core test budget exhausted during compiler preparation');
    return 1;
  }
  // Keep the exact original test selection, -j and nonzero-execution guard.
  // Never convert a build-only success into an executed-test result.
  return test('moon', args, {timeout: remaining, env, cwd, ...rest});
}
