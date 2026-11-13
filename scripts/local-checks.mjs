// Local verification from the CI definition itself. `run <job>` executes the
// same `run:` commands as that locally supported job in .github/workflows/ci.yml,
// so a local check never drifts from CI; `changed` lists the narrow checks and
// related CI jobs for inspection, not a complete reverse-dependency closure.
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
  ['native-http-macos', 'runs on macOS arm64 runners'],
  ['native-separated-network', 'needs root network namespaces'],
  ['performance-matrix', 'registered performance runs'],
  ['check', 'aggregates the other jobs'],
  ['client', 'aggregates all required Client producers and consumers'],
  ['core-common', 'uses the hosted Core matrix; select the complete local core entrance'],
  ['core-darwin', 'uses the hosted Darwin matrix; select the complete local core entrance'],
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
  const job = workflow.jobs[name === 'core' && !raw && workflow.jobs['core-common'] ? 'core-common'
    : name === 'native' && !raw && workflow.jobs['native-workloads'] ? 'native-workloads' : name];
  if (job === undefined || !Array.isArray(job.steps)) {
    fail(`Unknown job: ${name}`);
  }
  const scratch = join(root, '_build', 'local-checks', name);
  let steps = job.steps;
  if (name === 'native' && !raw && workflow.jobs['native-workloads']) {
    const plan = JSON.parse(readFileSync(join(root, 'scripts/ci-native-background-groups.json'), 'utf8')).native;
    const prepare = steps.findIndex(step => step.id === 'native-preparation');
    const http = workflow.jobs['native-http']?.steps.find(step => step.id === 'native-http');
    const retained = steps.find(step => step.name === 'Verify registered Native retained product path');
    if (prepare < 0 || !http) fail('Incomplete local Native composition; retain all original consumers');
    const environment = {
      ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION: join(scratch, 'native-scoped-preparation'),
      ACTQL_TEST_NATIVE_HTTP_COMPONENT_RECEIPT: join(scratch, 'native-scoped-preparation/http/component/build.json'),
    };
    // Hosted background bookkeeping is not needed locally. Keep every original
    // case serially in this same process tree, with one original preparation.
    steps = [...steps.slice(0, prepare + 1), http,
      ...steps.slice(prepare + 1).filter(step => step !== retained &&
        !['native-background-start', 'native-background'].includes(step.id)),
      ...plan.flatMap(group => group.steps.map(step => ({...step, 'timeout-minutes': step.timeoutMinutes}))),
      ...(retained ? [retained] : [])];
    steps = steps.map(step => ({...step, env: {...environment, ...step.env}}));
  }
  if (name === 'session-evidence' && !raw && workflow.jobs['session-controls']) {
    // Preserve the original complete local route without a second setup or
    // collector. Hosted jobs run controls independently on another runner.
    const controls = workflow.jobs['session-controls'].steps.filter(step =>
      typeof step.run === 'string' && !preparation(step));
    const index = steps.findIndex(step => step.run === 'node proofs/ci-evidence/collect.mjs init');
    if (index < 0 || controls.length !== 1) fail('Incomplete local Session controls composition');
    steps = [...steps.slice(0, index), ...controls, ...steps.slice(index)];
  }
  const resolve = text => raw ? String(text) : String(text)
    .replaceAll('${{ matrix.target }}', target)
    // Hosted portable shards do not narrow the existing full local command.
    .replaceAll('${{ matrix.query-part }}', name === 'client-packed' ? 'portable' : '${{ matrix.query-part }}')
    // A local full Core invocation remains unpartitioned. Hosted-only Linux
    // partitions cannot silently narrow this existing diagnostic entrance.
    .replaceAll('${{ matrix.partition }}', name === 'core' ? '' : '${{ matrix.partition }}')
    .replaceAll('${{ needs.select-targets.outputs.moon_test_selection }}', 'false')
    .replaceAll('${{ github.workspace }}', root.replace(/\/$/u, ''))
    .replaceAll('${{ runner.temp }}', scratch)
    .replaceAll('${{ github.sha }}', 'local');
  const environment = ([key, value]) => {
    if (!raw && name === 'core' && key === 'CI_PLAN') {
      if (value !== '${{ needs.select-targets.outputs.plan }}') {
        fail('Unsupported Core selection expression; local CI must retain complete coverage');
      }
      // Local job execution has no authenticated PR plan. Keep full coverage,
      // including when the developer's parent shell contains a CI_PLAN value.
      return [key, ''];
    }
    if (!raw && name === 'core' && key === 'CI_PLAN_PATH') {
      if (value !== '${{ runner.temp }}/actql-ci-plan.json') {
        fail('Unsupported Core selection path; local CI must retain complete coverage');
      }
      return [key, ''];
    }
    if (!raw && name === 'core' && key === 'ACTQL_TEST_NATIVE_CORE_PARTITION') {
      if (!["${{ matrix.target == 'native' && matrix.partition || '' }}",
        "${{ matrix.target == 'native' && !startsWith(matrix.partition, 'linux-common-') && matrix.partition || '' }}"].includes(value)) {
        fail('Unsupported Native Core partition expression; local CI must retain complete coverage');
      }
      // One local runner keeps the complete original campaign, rather than
      // silently selecting only one hosted partition or physical profile.
      return [key, ''];
    }
    if (!raw && name === 'core' && key === 'ACTQL_TEST_NATIVE_CORE_SCOPED_JOBS') {
      if (value !== "${{ matrix.target == 'native' && matrix.partition == 'scoped' && '2' || '1' }}") {
        fail('Unsupported Native Core scheduling expression; local CI must retain the serial scoped profile');
      }
      return [key, '1'];
    }
    if (!raw && name === 'core' && key === 'ACTQL_TEST_NATIVE_CORE_PLATFORM_SCOPE') {
      if (value !== "${{ matrix.target == 'native' && !startsWith(matrix.partition, 'linux-common-') && 'darwin-differences' || '' }}") {
        fail('Unsupported Native Core platform scope; local CI must retain complete coverage');
      }
      return [key, ''];
    }
    return [key, resolve(value)];
  };
  return steps.filter(step => typeof step.run === 'string' &&
    !preparation(step)).map(step => ({
    name: step.name ?? step.run.split('\n')[0],
    run: resolve(step.run),
    env: Object.fromEntries(Object.entries(step.env ?? {}).map(environment)),
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

// Resolve only the workflow's literal two-branch Native matrix budget. This
// is not an Actions expression evaluator; unfamiliar expressions require an
// explicit local budget, just like missing/non-numeric workflow values.
function workflowMinutes(name, target) {
  const value = workflow.jobs[name === 'core' && workflow.jobs['core-common'] ? 'core-common'
    : name === 'native' && workflow.jobs['native-workloads'] ? 'native-workloads' : name]?.['timeout-minutes'];
  if (typeof value === 'number') return value;
  if (name !== 'core' || typeof value !== 'string' || target === undefined) return undefined;
  const match = /^\$\{\{\s*matrix\.target\s*==\s*'native'\s*&&\s*([1-9][0-9]*)\s*\|\|\s*([1-9][0-9]*)\s*\}\}$/u.exec(value);
  if (!match) return undefined;
  const minutes = Number(match[target === 'native' ? 1 : 2]);
  return Number.isSafeInteger(minutes) ? minutes : undefined;
}

// A missing target uses Moon's ordinary non-Native default. Ambiguous or
// unsupported target selections cannot infer one matrix row's time budget.
function selectedMoonTarget(args) {
  let target = null;
  for (let index = 0; index < args.length; index++) {
    const arg = args[index];
    if (arg === '--') break;
    if (arg === '--target' || arg.startsWith('--target=')) {
      if (target !== null) return undefined;
      target = arg === '--target' ? args[++index] : arg.slice('--target='.length);
      if (!['js', 'wasm', 'native'].includes(target)) return undefined;
    }
  }
  return target;
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
    env: {RUNNER_TEMP: step.scratch, ...(name === 'core' ? {CI_PLAN: '', CI_PLAN_PATH: ''} : {}), ...step.env},
  })), classification, options, workflowMinutes(name, target));
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
    workflowMinutes(kind === 'moon' ? 'core' : 'lint', kind === 'moon' ? selectedMoonTarget(selected) : null);
  // Reuse the existing summary/evidence guard unchanged, in an owned child so
  // its synchronous test capture cannot block timeout or parent-death handling.
  const step = command === 'test' ? {name: `selected ${kind} tests`, command: process.execPath,
    args: ['--input-type=module', '-e',
      "import {runFocusedTests} from './scripts/test-execution.mjs'; process.exitCode = runFocusedTests(process.argv[1], process.argv.slice(2), {cwd: process.cwd()});",
      kind, ...selected]} : {name: 'selected MoonBit build', command: 'moon', args: ['build', ...selected]};
  return execute([step], classification, options, defaultMinutes);
}

// CI jobs that cover a changed path. The narrow checks come first; the jobs
// are advisory references, not a requirement to run full jobs locally.
const areas = [
  [/^proofs\/relation-pipeline\//u, Object.keys(ciOnlyPipelineJobs)],
  [/^scripts\/packed-client-packages/u, ['client-packages', 'client-distribution', 'client-packed', 'client-packed-composition']],
  [/^scripts\/(build-runtime-packages|test-runtime-package-build|build-local-node|build-run-host-core|build-remote-(coordinator|transfer)-package)|^packages\/(run-host-core|coordinator-core|transfer-core)\//u, ['host']],
  [/^\.github\/|^scripts\/local-checks(?:[-.])/u, ['lint']],
  [/^src\//u, ['lint', 'core']],
  [/^(spec|docs)\/|\.md$/u, ['spec']],
  [/^adapters\/connectors\/salesforce\//u, ['client-distribution', 'client-packed', 'client-packed-composition', 'client-salesforce']],
  [/^adapters\/connectors\/duckdb\/node\//u, ['duckdb-node']],
  [/^adapters\/workers\/|workers/u, ['workers']],
  [/^packages\/(sdk|client-wire|node|local-node)\/|^scripts\/test-(packed(?!-resident-materials)|node-client|native-client)/u,
    ['client-distribution', 'client-packed', 'client-packed-composition', 'client-salesforce']],
  [/^adapters\/host-node\/(client|embedded-local|remote|captured|installed)/u,
    ['client-distribution', 'client-packed', 'client-packed-composition', 'client-salesforce', 'host']],
  [/^adapters\/(host-common|host-node|store-local|site-node|local-node)\//u,
    ['host']],
  [/^(src\/cmd|src\/platform_native)\/|^scripts\/test-native|^scripts\/test-packed-resident-materials/u, ['native']],
  [/^benchmarks\//u, ['host', 'native']],
  [/^scripts\/.*(connector|duckdb-environment)/u, ['connector-addition']],
];

// One known admission-fixture edge, not a general reverse-dependency map.
// Keep these direct inputs and the output aligned with infer-host-fixtures.mjs;
// the registry path is the current actql-aoa.json pipeline_registry_file.
const inferAdmissionPaths = new Set([
  'scripts/infer-host-fixtures.mjs',
  'scripts/check-canonical-json.mjs',
  'spec/contracts/actql-aoa.json',
  'spec/dependencies/aoa-pipeline-registry.json',
  'spec/local-check-environment.json',
  'src/stage_results/infer_program_test.mbt',
  'src/run_publication_host/client_infer_prefix_wbtest.mbt',
  'src/client_infer_host/fixture.generated_wbtest.mbt',
]);

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
  const inferAdmissionChanged = unique.some(file => inferAdmissionPaths.has(file));
  if (inferAdmissionChanged) {
    narrow.add('node scripts/infer-host-fixtures.mjs');
    narrow.add('node scripts/local-checks.mjs test moon -- --target js -p client_infer_host');
  }
  if (packages.size > 0) {
    narrow.add('moon fmt --check');
    for (const directory of [...packages].sort()) {
      narrow.add(`moon check --target js ${directory}`);
      narrow.add(`node scripts/local-checks.mjs test moon -- --target js -p ${relative('src', directory)}`);
    }
  }
  console.log(`Changed since ${base}: ${unique.length} files\n`);
  console.log('Candidate narrow checks (inspect affected callers and validators too):');
  for (const command of narrow) console.log(`  ${command}`);
  if (inferAdmissionChanged) {
    console.log('\nKnown INFER admission dependency (advisory, incomplete):');
    console.log('  The existing read-only freshness check requires the pinned MOON_HOME.');
    console.log('  Inspect the generated admission fixture and affected caller tests; no checks were executed.');
  }
  console.log('\nRelated CI jobs (advisory inspection; not required local execution):');
  for (const name of [...related].sort()) {
    const note = ciOnly.has(name) ? `  # CI only: ${ciOnly.get(name)}`
      : name === 'core' ? '  # select matching-target diagnostics for native-only or FFI changes'
        : '';
    const classification = classifyJob(name);
    const deliberate = classification.classification === 'ci-only' ? ' --dry-run'
      : classification.heavy ? ' --allow-heavy' : '';
    console.log(`  node scripts/local-checks.mjs run ${name}${deliberate}${note}`);
  }
  console.log('\nThese path-based candidates are not complete reverse-dependent coverage.');
  console.log('Follow .agents/skills/actql-local-verification/SKILL.md; broad suites are not local defaults.');
  console.log('After an authorized push, read exact-SHA CI; report executed and unverified coverage separately.');
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
