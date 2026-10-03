// Local verification from the CI definition itself. `run <job>` executes the
// same `run:` commands as that locally supported job in .github/workflows/ci.yml,
// so a local check never drifts from CI; `changed` lists the narrow checks and
// the CI jobs that relate to the files changed since a base.
//
//   node scripts/local-checks.mjs test node|moon -- <test arguments>
//   node scripts/local-checks.mjs list
//   node scripts/local-checks.mjs changed [--base origin/main]
//   node scripts/local-checks.mjs run <job> [--target js|wasm|native] [--dry-run]
import {execFileSync} from 'node:child_process';
import {existsSync, readFileSync} from 'node:fs';
import {dirname, join, relative} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parse} from 'yaml';
import {checkBudget, durationSeconds, runLocalCheck} from './local-checks-guard.mjs';
import {ciOnlyPipelineJobs, classifyJob, classifyMoon} from './local-checks-policy.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const workflow = parse(readFileSync(join(root, '.github/workflows/ci.yml'),
  'utf8'));
// Jobs whose environment a developer machine does not provide.
const ciOnly = new Map([
  ['native-macos', 'runs on macOS arm64 runners'],
  ['native-separated-network', 'needs root network namespaces'],
  ['performance-matrix', 'registered performance runs'],
  ['check', 'aggregates the other jobs'],
  ['client', 'aggregates client-packages, client-distribution, client-packed and client-salesforce'],
  ...Object.entries(ciOnlyPipelineJobs),
]);
const jobs = Object.entries(workflow.jobs)
  .filter(([, job]) => Array.isArray(job.steps));

function fail(message) {
  console.error(message);
  process.exit(2);
}

function option(name, fallback) {
  const index = process.argv.indexOf(name);
  return index < 0 ? fallback : process.argv[index + 1];
}

// Steps that only prepare a runner: installs and records of versions. A
// developer's checkout keeps its own installed toolchain and dependencies.
const preparation = step => /^(npm ci|moon version|node scripts\/setup-moonbit)/u
  .test(step.run.trim()) || /^(Install|Record) /u.test(step.name ?? '');

// The commands of one job with its CI expressions resolved for this
// checkout. Runner preparation (`uses:` and install steps) is left to the
// developer's own installed toolchain. CI-only inspection keeps expressions raw.
function commands(name, target, raw = false) {
  const job = workflow.jobs[name];
  if (job === undefined || !Array.isArray(job.steps)) {
    fail(`Unknown job: ${name}`);
  }
  const scratch = join(root, '_build', 'local-checks', name);
  const resolve = text => raw ? String(text) : String(text)
    .replaceAll('${{ matrix.target }}', target)
    .replaceAll('${{ github.workspace }}', root.replace(/\/$/u, ''))
    .replaceAll('${{ runner.temp }}', scratch)
    .replaceAll('${{ github.sha }}', 'local');
  return job.steps.filter(step => typeof step.run === 'string' &&
    !preparation(step)).map(step => ({
    name: step.name ?? step.run.split('\n')[0],
    run: resolve(step.run),
    env: Object.fromEntries(Object.entries(step.env ?? {})
      .map(([key, value]) => [key, resolve(value)])),
    scratch,
  }));
}

function executionOptions(args) {
  const result = {};
  for (let index = 0; index < args.length; index++) {
    const name = args[index];
    if (name === '--allow-heavy' || name === '--dry-run') {
      if (result[name]) fail(`Duplicate option: ${name}`);
      result[name] = true;
    } else if (['--target', '--timeout-seconds', '--kill-grace-seconds'].includes(name)) {
      if (result[name] !== undefined || args[index + 1] === undefined) fail(`Invalid option: ${name}`);
      result[name] = args[++index];
    } else fail(`Unknown local execution option: ${name}`);
  }
  return result;
}

function requireHeavy(classification, options) {
  if (classification.classification === 'unknown') {
    fail(`${classification.reason}\nThis invocation is unclassified; use a supported focused selection or update the small classification explicitly.`);
  }
  if (classification.heavy && !options['--allow-heavy']) {
    fail(`${classification.reason}\n${classification.alternatives.join('\n')}\n` +
      'For a deliberate local run, supply --allow-heavy. It is friction, not human approval.');
  }
}

async function execute(steps, classification, options, defaultMinutes) {
  const timeoutSeconds = checkBudget(options['--timeout-seconds'], defaultMinutes);
  const graceSeconds = options['--kill-grace-seconds'] === undefined ? 5 :
    durationSeconds(options['--kill-grace-seconds'], 'kill-grace-seconds');
  return runLocalCheck({root, steps, heavy: classification.heavy, timeoutSeconds, graceSeconds});
}

async function runJob(name, args) {
  const classification = classifyJob(name);
  // Keep the existing CI-only routes closed. Pipeline wrappers additionally
  // support inspection of the literal CI commands, without fake CI context.
  if (ciOnly.has(name) && classification.classification !== 'ci-only') {
    fail(`${name} is CI only: ${ciOnly.get(name)}`);
  }
  const options = executionOptions(args);
  const target = options['--target'] ?? 'js';
  if (!['js', 'wasm', 'native'].includes(target)) fail('--target must be js, wasm or native');
  if (classification.classification === 'ci-only' && !options['--dry-run']) {
    fail(`${classification.reason}\n--allow-heavy cannot enable this job locally; use hosted CI.\n` +
      classification.alternatives.join('\n'));
  }
  const selected = commands(name, target, classification.classification === 'ci-only');
  if (options['--dry-run']) {
    if (classification.classification === 'ci-only') {
      console.log(`${classification.reason}\nLiteral workflow commands for inspection only:`);
    }
    for (const step of selected) console.log(`\n== ${name}: ${step.name}\n${step.run}`);
    return 0;
  }
  requireHeavy(classification, options);
  return execute(selected.map(step => ({name: `${name}: ${step.name}`,
    command: 'bash', args: ['-eo', 'pipefail', '-c', step.run], scratch: step.scratch,
    env: {RUNNER_TEMP: step.scratch, ...step.env},
  })), classification, options, workflow.jobs[name]['timeout-minutes']);
}

async function runSelected(command, kind, args) {
  const delimiter = args.indexOf('--');
  if (delimiter < 0) fail('Selected commands require -- before test/build arguments');
  const options = executionOptions(args.slice(0, delimiter));
  if (options['--target'] !== undefined || options['--dry-run']) fail('Pass target after --; dry-run is only for jobs');
  const selected = args.slice(delimiter + 1);
  const classification = kind === 'moon' ? classifyMoon(command, selected) :
    {heavy: false, classification: 'focused'};
  requireHeavy(classification, options);
  const defaultMinutes = classification.heavy ? undefined :
    workflow.jobs[kind === 'moon' ? 'core' : 'lint']?.['timeout-minutes'];
  // Reuse the existing summary/evidence guard unchanged, in an owned child so
  // its synchronous test capture cannot block timeout or parent-death handling.
  const step = command === 'test' ? {name: `selected ${kind} tests`, command: process.execPath,
    args: ['--input-type=module', '-e',
      "import {runFocusedTests} from './scripts/test-execution.mjs'; process.exitCode = runFocusedTests(process.argv[1], process.argv.slice(2), {cwd: process.cwd()});",
      kind, ...selected]} : {name: 'selected MoonBit build', command: 'moon', args: ['build', ...selected]};
  return execute([step], classification, options, defaultMinutes);
}

// CI jobs that cover a changed path. The narrow checks come first; the jobs
// are what to run before pushing, and Linux CI remains the full check.
const areas = [
  [/^proofs\/relation-pipeline\//u, Object.keys(ciOnlyPipelineJobs)],
  [/^scripts\/packed-client-packages/u, ['client-packages', 'client-distribution', 'client-packed']],
  [/^scripts\/(build-runtime-packages|test-runtime-package-build|build-local-node|build-run-host-core|build-remote-(coordinator|transfer)-package)|^packages\/(run-host-core|coordinator-core|transfer-core)\//u, ['host']],
  [/^\.github\/|^scripts\/local-checks(?:[-.])/u, ['lint']],
  [/^src\//u, ['lint', 'core']],
  [/^(spec|docs)\/|\.md$/u, ['spec']],
  [/^adapters\/connectors\/salesforce\//u, ['client-distribution', 'client-packed', 'client-salesforce']],
  [/^adapters\/connectors\/duckdb\/node\//u, ['duckdb-node']],
  [/^adapters\/workers\/|workers/u, ['workers']],
  [/^packages\/(sdk|client-wire|node|local-node)\/|^scripts\/test-(packed(?!-resident-materials)|node-client|native-client)/u,
    ['client-distribution', 'client-packed', 'client-salesforce']],
  [/^adapters\/host-node\/(client|embedded-local|remote|captured|installed)/u,
    ['client-distribution', 'client-packed', 'client-salesforce', 'host']],
  [/^adapters\/(host-common|host-node|store-local|site-node|local-node)\//u,
    ['host']],
  [/^(src\/cmd|src\/platform_native)\/|^scripts\/test-native|^scripts\/test-packed-resident-materials/u, ['native']],
  [/^benchmarks\//u, ['host', 'native']],
  [/^scripts\/.*(connector|duckdb-environment)/u, ['connector-addition']],
];

function changed() {
  const base = option('--base', 'origin/main');
  const git = (...args) => execFileSync('git', args,
    {cwd: root, encoding: 'utf8'}).split('\n');
  const files = [...git('diff', '--name-only', `${base}...HEAD`),
    ...git('diff', '--name-only', 'HEAD'),
    ...git('ls-files', '--others', '--exclude-standard')].filter(Boolean);
  const unique = [...new Set(files)];
  if (unique.length === 0) {
    console.log(`No changes since ${base}.`);
    return;
  }
  const narrow = new Set(['git diff --check']);
  const packages = new Set();
  const related = new Set();
  for (const file of unique) {
    if (/\.(mbt|mbti)$|(^|\/)moon\.pkg$/u.test(file) && file.startsWith('src/')) {
      packages.add(dirname(file));
    }
    if (/\.test\.mjs$/u.test(file) && existsSync(join(root, file))) {
      narrow.add(`node scripts/local-checks.mjs test node -- ${file}`);
    } else if (/\.mjs$/u.test(file) && existsSync(join(root, file))) {
      narrow.add(`node --check ${file}`);
      const test = file.replace(/\.mjs$/u, '.test.mjs');
      if (existsSync(join(root, test))) narrow.add(`node scripts/local-checks.mjs test node -- ${test}`);
    }
    for (const [pattern, names] of areas) {
      if (pattern.test(file)) names.forEach(name => related.add(name));
    }
  }
  if (packages.size > 0) {
    narrow.add('moon fmt --check');
    for (const directory of [...packages].sort()) {
      narrow.add(`moon check --target js ${directory}`);
      narrow.add(`node scripts/local-checks.mjs test moon -- --target js -p ${relative('src', directory)}`);
    }
  }
  console.log(`Changed since ${base}: ${unique.length} files\n`);
  console.log('Narrow checks (while editing and before commit):');
  for (const command of narrow) console.log(`  ${command}`);
  console.log('\nCI jobs for these areas (before push):');
  for (const name of [...related].sort()) {
    const note = ciOnly.has(name) ? `  # CI only: ${ciOnly.get(name)}`
      : name === 'core' ? '  # add --target wasm / native when shared core changed'
        : '';
    const classification = classifyJob(name);
    const deliberate = classification.classification === 'ci-only' ? ' --dry-run'
      : classification.heavy ? ' --allow-heavy' : '';
    console.log(`  node scripts/local-checks.mjs run ${name}${deliberate}${note}`);
  }
  console.log('\nThen push and let Linux CI verify the whole SHA.');
}

const [command, argument] = process.argv.slice(2);
if (command === 'list') {
  for (const [name, job] of jobs) {
    const note = ciOnly.has(name) ? ` (CI only: ${ciOnly.get(name)})` : '';
    console.log(`${name}${note}`);
    for (const step of job.steps.filter(item => item.run !== undefined &&
      !preparation(item))) {
      console.log(`  - ${step.name ?? step.run.split('\n')[0]}`);
    }
  }
} else if ((command === 'test' && ['node', 'moon'].includes(argument)) ||
    (command === 'build' && argument === 'moon')) {
  try { process.exitCode = await runSelected(command, argument, process.argv.slice(4)); }
  catch (error) { fail(error.message); }
} else if (command === 'changed') {
  changed();
} else if (command === 'run' && argument) {
  try { process.exitCode = await runJob(argument, process.argv.slice(4)); }
  catch (error) { fail(error.message); }
} else {
  fail('Usage: local-checks.mjs test node|moon [--allow-heavy] [--timeout-seconds N] -- <test arguments> | ' +
    'build moon [--allow-heavy] [--timeout-seconds N] -- <build arguments> | list | changed [--base <ref>] | ' +
    'run <job> [--target js|wasm|native] [--allow-heavy] [--timeout-seconds N] [--dry-run]');
}
