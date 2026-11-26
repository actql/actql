// Measure compilation separately without executing a second test campaign.
// Both Moon invocations retain the same arguments, environment and build tree.
import assert from 'node:assert/strict';
import {basename, dirname, join, resolve} from 'node:path';
import {createCommandEvidence, redactCommandEvidence} from './packed-query-evidence.mjs';
import {runFocusedTests} from './test-execution.mjs';

type NativeTestOptions = NonNullable<Parameters<typeof runFocusedTests>[2]> & {
  timeout: number;
  evidenceScratch: string;
};
type CompileCapture = Pick<NativeTestOptions, 'cwd' | 'env' | 'timeout' | 'killSignal' | 'maxBuffer'>;
type CompileResult = {
  status: number | null;
  stdout?: string | null;
  stderr?: string | null;
  signal?: NodeJS.Signals | null;
  error?: unknown;
};
type CompileRecorder = {
  capture(command: string, args: readonly string[], options: CompileCapture):
    {result: CompileResult; writeFailure?: unknown};
  finish(outcome: 'passed' | 'failed'): void;
};
type NativePhase = {phase: 'compile' | 'execute' | 'start-claim'; milliseconds: number; succeeded: boolean};
type NativeTestCallbacks = {
  evidence?: (options: Parameters<typeof createCommandEvidence>[0]) => CompileRecorder;
  execute?: (kind: string, args: readonly string[], options: NativeTestOptions) => number;
  now?: () => number;
  report?: (value: NativePhase) => void;
};

export function selectsNativeStartClaim(args: readonly string[]) {
  return args.includes('src/platform_native/remote_journal') ||
    args.includes('src/platform_native/remote_journal/journal_native_wbtest.mbt');
}

function startClaimArtifacts(stdout: string, cwd: string) {
  const artifacts = stdout.split(/\r?\n/u)
    .filter(line => line.startsWith('{"artifacts_path":'))
    .flatMap(line => (JSON.parse(line) as {artifacts_path: string[]}).artifacts_path);
  const selected = artifacts.filter(path => basename(path) === 'remote_journal.whitebox_test.exe');
  assert.equal(selected.length, 1, 'Moon must report one Native Remote Journal whitebox executable');
  const binary = resolve(cwd, selected[0]);
  // The pinned Moon whitebox driver writes this companion beside its reported executable.
  return {
    ACTQL_TEST_NATIVE_START_CLAIM_EXECUTABLE: binary,
    ACTQL_TEST_NATIVE_START_CLAIM_METADATA: join(dirname(binary), '__whitebox_test_info.json'),
  };
}

export function runMeasuredNativeTests(args: readonly string[], options: NativeTestOptions, {
  evidence = createCommandEvidence, execute = runFocusedTests,
  now = performance.now.bind(performance), report = value =>
    console.error('ACTQL_NATIVE_CI_PHASE ' + JSON.stringify(value)),
}: NativeTestCallbacks = {}) {
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
  for (const stream of ['stdout', 'stderr'] as const) if (result[stream])
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
  if (code !== 0 || !selectsNativeStartClaim(args)) return code;
  const raceBudget = Math.min(remaining(), 45_000);
  if (raceBudget <= 0) return 1;
  const raceStart = now();
  const artifacts = startClaimArtifacts(result.stdout!, options.cwd ?? process.cwd());
  const raceCode = execute('node', ['scripts/test-native-start-claim-process.test.mjs'], {
    ...options, timeout: raceBudget, expectedTests: 1, requireAllPassed: true,
    env: {...(options.env ?? process.env), ...artifacts},
  });
  report({phase: 'start-claim', milliseconds: Math.round(now() - raceStart), succeeded: raceCode === 0});
  return raceCode;
}
