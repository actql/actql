// Measure compilation separately without executing a second test campaign.
// Both Moon invocations retain the same arguments, environment and build tree.
import assert from 'node:assert/strict';
import {createCommandEvidence, redactCommandEvidence} from './packed-query-evidence.mjs';
import {runFocusedTests} from './test-execution.mjs';

export function runMeasuredNativeTests(args, options, {
  evidence = createCommandEvidence, execute = runFocusedTests,
  now = performance.now.bind(performance), report = value =>
    console.error('ACTQL_NATIVE_CI_PHASE ' + JSON.stringify(value)),
} = {}) {
  assert(args.includes('--target') && args[args.indexOf('--target') + 1] === 'native');
  assert(!args.includes('--build-only'));
  assert(Number.isSafeInteger(options.timeout) && options.timeout > 0);
  const deadline = now() + options.timeout;
  const remaining = () => Math.max(0, Math.floor(deadline - now()));
  const recorder = evidence({scratch: options.evidenceScratch,
    cwd: options.cwd ?? process.cwd(), env: options.env ?? process.env, prefix: 'native-compile-'});
  const start = now();
  if (remaining() <= 0) { recorder.finish('failed'); return 1; }
  const {result, writeFailure} = recorder.capture('moon', ['test', ...args, '--build-only'], {
    cwd: options.cwd, env: options.env, timeout: remaining(), killSignal: 'SIGKILL',
    maxBuffer: 64 * 1024 * 1024,
  });
  const compiled = !result.error && !result.signal && result.status === 0 && !writeFailure;
  for (const stream of ['stdout', 'stderr']) if (result[stream])
    process[stream].write(redactCommandEvidence(result[stream], options.env ?? process.env));
  recorder.finish(compiled ? 'passed' : 'failed');
  report({phase: 'compile', milliseconds: Math.round(now() - start), succeeded: compiled});
  if (!compiled) return result.status || 1;
  const budget = remaining();
  if (budget <= 0) return 1;
  const executeStart = now();
  // Moon rechecks its unchanged incremental graph, then executes the already
  // compiled tests. That graph-check overhead remains in the execution interval.
  const code = execute('moon', args, {...options, timeout: budget});
  report({phase: 'execute', milliseconds: Math.round(now() - executeStart), succeeded: code === 0});
  return code;
}
