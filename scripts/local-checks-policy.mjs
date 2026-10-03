// A small cost/scope policy shared by the execution wrapper and optional hook.
// This is not a shell parser or an authorization boundary. A focused selection
// still needs an execution budget: its dependencies can be expensive to build.
import {posix} from 'node:path';

export const heavyJobs = Object.freeze([
  'core', 'host', 'native', 'session-evidence',
  'client-packages', 'client-distribution', 'client-packed', 'client-salesforce',
  'workers', 'connector-addition', 'duckdb-node', 'spec',
]);

// These workflow wrappers require hosted Actions provenance, not just a cost
// override. The underlying proof campaigns remain ordinary heavy work; this
// registry does not classify or intercept their raw commands.
export const ciOnlyPipelineJobs = Object.freeze({
  'pipeline-mutations': 'requires real GitHub source/run/attempt/output metadata for producer begin, stage and seal',
  'pipeline-capacity': 'requires real GitHub source/run/attempt/output metadata for producer begin, stage and seal',
  'pipeline-evidence': 'requires sealed exact-artifact producer inputs from the same GitHub run and attempt',
});

const commonFlags = new Set([
  '-g', '--debug', '--release', '--strip', '--no-strip', '--enable-coverage',
  '--sort-input', '--output-wat', '-d', '--deny-warn', '--no-render',
  '--output-json', '--frozen', '-q', '--quiet', '-v', '--verbose', '--trace',
]);
const commonValues = new Set([
  '--target', '-j', '--jobs', '--warn-list', '--render-no-loc',
  '--diagnostic-limit', '--target-dir',
]);
const testFlags = new Set([
  '-u', '--update', '--build-only', '--profile', '--no-parallelize',
  '--outline', '--test-failure-json', '--include-skipped',
]);
const testValues = new Set([
  '-i', '--index', '--doc-index', '-l', '--limit', '--wasm-policy',
  '--patch-file', '-f', '--filter',
]);

function moonAlternatives(kind) {
  return kind === 'test' ? [
    'node scripts/local-checks.mjs changed',
    'node scripts/local-checks.mjs test moon -- --target js -p <package>',
    'node scripts/local-checks.mjs test moon -- --target js <test-file.mbt>',
  ] : [
    'node scripts/local-checks.mjs changed',
    'moon check --target js <package-directory>',
    'node scripts/local-checks.mjs build moon -- --target js <package-directory>',
  ];
}

function concreteScope(value) {
  if (!value || /[\s*?\[\]{}$`]/u.test(value)) return false;
  const normalized = posix.normalize(value).replace(/\/$/u, '') || '/';
  return !['.', '..', '/', 'src'].includes(normalized);
}

// Unknown options are conservative in the wrapper: they do not turn a value
// into a positional package path. Consumers must inspect classification when
// they need to distinguish a known full run from an unclassified invocation.
export function classifyMoon(kind, args) {
  const alternatives = moonAlternatives(kind);
  const result = (classification, reason) => ({
    heavy: !['focused', 'reporting'].includes(classification),
    classification, reason, alternatives,
  });
  if (!['test', 'build'].includes(kind) || !Array.isArray(args) ||
      args.some(arg => typeof arg !== 'string')) {
    return result('unknown', 'Unsupported Moon command or arguments');
  }
  let focused = false;
  let broad = false;
  let reporting = false;
  let positional = false;
  for (let index = 0; index < args.length; index++) {
    const arg = args[index];
    if (positional || !arg.startsWith('-')) {
      if (concreteScope(arg)) focused = true;
      else broad = true;
      continue;
    }
    if (arg === '--') { positional = true; continue; }
    if (['-h', '--help', '--dry-run'].includes(arg)) {
      reporting = true;
      continue;
    }
    if (commonFlags.has(arg) || (kind === 'test' && testFlags.has(arg)) ||
        (kind === 'build' && ['-w', '--watch'].includes(arg))) continue;
    const equals = arg.indexOf('=');
    const option = equals < 0 ? arg : arg.slice(0, equals);
    const isPackage = kind === 'test' && ['-p', '--package'].includes(option);
    if (!isPackage && !commonValues.has(option) &&
        !(kind === 'test' && testValues.has(option))) {
      return result('unknown', `Unclassified Moon option: ${option}`);
    }
    const value = equals < 0 ? args[++index] : arg.slice(equals + 1);
    if (value === undefined || value === '' ||
        (value.startsWith('-') && option !== '--warn-list')) {
      return result('unknown', `Missing or unsupported value for ${option}`);
    }
    if (isPackage) {
      if (concreteScope(value)) focused = true;
      else broad = true;
    }
  }
  if (reporting) return result('reporting', 'Help or dry-run does not execute the gate');
  if (focused && !broad) {
    return result('focused', 'An explicit package or file/path is selected');
  }
  return result('full', `Unscoped moon ${kind}; target, jobs and test-name filters do not limit build scope`);
}

// Keep this reviewed alongside .github/workflows/ci.yml. Workflow timeouts are
// execution budgets, not evidence that an unfamiliar job is cheap or heavy.
export function classifyJob(name) {
  const alternatives = ['node scripts/local-checks.mjs changed',
    'node scripts/local-checks.mjs run <job> --dry-run'];
  if (Object.hasOwn(ciOnlyPipelineJobs, name)) return {
    heavy: true, classification: 'ci-only',
    reason: `${name} is CI only: ${ciOnlyPipelineJobs[name]}`,
    alternatives: ['node scripts/local-checks.mjs list',
      `node scripts/local-checks.mjs run ${name} --dry-run`],
  };
  if (heavyJobs.includes(name)) return {
    heavy: true, classification: 'heavy',
    reason: `CI job ${name} runs a complete suite or build`, alternatives,
  };
  if (name === 'lint') return {
    heavy: false, classification: 'light',
    reason: 'The lint job is intentionally available without a heavy override', alternatives,
  };
  return {heavy: true, classification: 'unknown',
    reason: `No local cost classification for job: ${name}`, alternatives};
}
