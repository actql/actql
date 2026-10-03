import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parse} from 'yaml';
import {focusedPattern, focusedFixtureObjects, stableFocusedFiles, focusedPlan,
  eligibleFocusedChanges, checkFocusedSource, readFocusedTests, validateFocusedTests,
  runFocusedPlan} from './ci-focused-tests.mjs';
import {readChanges, selectTargets, validateSelection, verifyGate, gateJobs} from './ci-targets.mjs';
import {testExecutionResult} from './test-execution.mjs';
import {fullCheckpointJobs, policyPaths, resolveMainBaseline} from './ci-main-base.mjs';

const old = '1'.repeat(40), head = '2'.repeat(40), fresh = '3'.repeat(40), zero = '0'.repeat(40);
const current = stableFocusedFiles[0], added = 'src/query_integration/fixed_compute_zero_ports_wbtest.mbt';
const portable = `///|
test "native candidates preserve fixed ports" {
  let owner = zero_input_request_owner("[]")
  let capacity : @connector.FixedComputeCapacity = {
    contract_cid: "sha256:example", max_rows: 100, max_value_bytes: 10000, common_fragment: None,
  }
  let request = @connector.prepare_source_free_fixed_compute_request(owner, capacity).unwrap()
  assert_eq(@connector.fixed_compute_request_input_count(request), 0)
  assert_eq(@connector.fixed_compute_request_inputs(request).length(), 0)
  assert_true(@connector.fixed_compute_request_input(request, 0) is None)
  assert_false(@connector.fixed_compute_request_has_supplied_input(request))
}`;
const change = (path = current, addition = false) => ({path,
  before: {mode: addition ? '000000' : '100644', object: addition ? zero : old},
  after: {mode: '100644', object: fresh}});
function gitFixture({changes = [change()], sources = {}, badPin = false, extra = []} = {}) {
  const files = new Map(Object.entries(focusedFixtureObjects).map(([path, object]) => [path, {mode: '100644', object}]));
  for (const path of stableFocusedFiles) files.set(path, {mode: '100644', object: fresh});
  for (const entry of changes) if (entry.after.mode !== '000000') files.set(entry.path, entry.after);
  for (const [path, entry] of extra) files.set(path, entry);
  if (badPin) files.get('src/query_integration/moon.pkg').object = '9'.repeat(40);
  const commands = [];
  const git = args => {
    commands.push(args);
    if (args[0] === 'rev-parse') return head + '\n';
    if (args[0] === 'ls-tree') return [...files].map(([path, entry]) => `${entry.mode} blob ${entry.object}\t${path}\0`).join('');
    if (args[0] === 'show') {
      if (args[1] in sources) return sources[args[1]];
      if ([old, fresh].includes(args[1]) || args[1].includes(':')) return portable;
      return 'fn fixture_helper() { () }';
    }
    if (args.includes('--name-only')) return changes.map(entry => entry.path + '\0').join('');
    if (args.includes('--raw')) return changes.map(entry => `:${entry.before.mode} ${entry.after.mode} ${entry.before.object} ${entry.after.object} ${entry.before.mode === '000000' ? 'A' : entry.after.mode === '000000' ? 'D' : 'M'}\0${entry.path}\0`).join('');
    if (args.includes('--unified=0')) return '+test "native candidate sha256" { assert_true(true) }';
    throw new Error(`Unexpected git command: ${args.join(' ')}`);
  };
  return {git, commands};
}
function selection(changes = [change()], options = {}) {
  const paths = changes.map(entry => entry.path), {git} = gitFixture({changes});
  return selectTargets(paths, {focusedChanges: changes, focusedTests: readFocusedTests(paths, changes, git), ...options});
}
const results = value => Object.fromEntries(gateJobs.map(name => [name, {result:
  ['select-targets', 'preflight', 'lint', 'spec'].includes(name) || name === 'focused-tests' && value.profile === 'focused-tests'
    || name !== 'focused-tests' && value.profile === 'full' && (name !== 'native-macos' || value.macos) ? 'success' : 'skipped'}]));

test('registered family includes existing siblings and NEW fixed-compute/join tests', () => {
  for (const path of [current, stableFocusedFiles[1], added, 'src/query_integration/fixed_join_ordered_ports_wbtest.mbt']) {
    assert(focusedPattern.test(path));
    const value = selection([change(path, path !== current)]);
    assert.equal(value.profile, 'focused-tests');
    assert.deepEqual(value.focusedTests.files, [...new Set([path, ...stableFocusedFiles])].sort());
    validateSelection(value);
  }
});
test('words in strings/comments and abstract native candidate names do not mean native execution', () => {
  assert.equal(checkFocusedSource(portable + '\n// @env native-stub #cfg extern unsafe'), 1);
  assert.equal(checkFocusedSource('test "native" { let native_candidate = "@native_host.read()"; assert_eq(native_candidate, "sha256:capacity") }'), 1);
});
test('actual target/FFI/environment/import boundaries fail closed', () => {
  for (const body of ['@env.get_env_var("KEY")', '@native_host.open()', '@salesforce_host.open()', 'extern "C" fn secret() = "secret"',
    '#cfg(target="native") assert_true(true)', 'unsafe { assert_true(true) }', 'Unreviewed::call()', 'fn callback() { () }']) {
    assert.throws(() => checkFocusedSource(`test "case" { ${body} }`), undefined, body);
  }
  assert.throws(() => checkFocusedSource('test "case" { let value = "\\{@env.get_env_var(\"X\")}" }'));
});
test('unknown direct and callback helper references do not gain portability from suffix', () => {
  assert.throws(() => checkFocusedSource('test "case" { native_http_fixture() }'));
  assert.throws(() => checkFocusedSource('test "case" { [1].map(native_http_fixture) }', ['native_http_fixture']));
  assert.throws(() => checkFocusedSource('test "case" { let transport : NativeTransport = {} }', ['NativeTransport']));
});
test('new shared helpers or non-test declarations cannot affect other package tests', () => {
  for (const source of ['', '// none', 'fn fake() { () }', 'let shared = 1', portable + '\nfn helper() { () }',
    '#skip\n' + portable, 'test "broken" {']) assert.throws(() => checkFocusedSource(source));
});
test('only exact A/M regular-file identities qualify; deleted/renamed/mode/symlink/mixed paths are full', () => {
  const modified = change(), good = [modified];
  assert(eligibleFocusedChanges([current], good));
  assert(eligibleFocusedChanges([added], [change(added, true)]));
  for (const entry of [
    {...modified, after: {mode: '000000', object: zero}},
    {...modified, before: {mode: '120000', object: old}},
    {...modified, after: {mode: '100755', object: fresh}},
    {...modified, after: modified.before}, {...modified, extra: true},
    {...modified, before: {mode: '000000', object: old}},
  ]) assert.equal(eligibleFocusedChanges([current], [entry]), false);
  for (const path of ['src/query_integration/native_http_wbtest.mbt', 'src/connector_sdk/api.mbt',
    'src/query_integration/moon.pkg', 'src/query_integration/../fixed_compute_bad_wbtest.mbt']) {
    assert.equal(selection([change(), change(path)]).profile, 'full');
  }
  const deleted = {...change(), after: {mode: '000000', object: zero}};
  assert.equal(selection([deleted, change(added, true)]).profile, 'full');
});
test('fixture, import-manifest or missing stable-family drift falls back to full', () => {
  const changes = [change()], paths = [current];
  assert.equal(readFocusedTests(paths, changes, gitFixture({badPin: true}).git), null);
  const absent = gitFixture().git;
  assert.equal(readFocusedTests(paths, changes, args => args[0] === 'ls-tree'
    ? absent(args).split('\0').filter(line => !line.endsWith(stableFocusedFiles[1])).join('\0') : absent(args)), null);
  assert.equal(readFocusedTests(paths, changes, gitFixture({sources: {[fresh]: 'test "bad" { @env.get_env_var("X") }'}}).git), null);
  assert.equal(readFocusedTests(paths, changes, gitFixture({sources: {[old]: 'fn changed_shared_helper() { () }'}}).git), null);
});
test('removing or renaming an existing test case falls back even when other tests still pass', () => {
  const changes = [change()], paths = [current];
  const before = portable + '\ntest "retained sibling" { assert_true(true) }';
  assert.equal(readFocusedTests(paths, changes, gitFixture({sources: {[old]: before}}).git), null);
  assert.equal(readFocusedTests(paths, changes, gitFixture({sources: {[fresh]: portable.replace('native candidates preserve fixed ports', 'renamed')}}).git), null);
  const additions = portable + '\ntest "new ports" { assert_eq(0, 0) }';
  assert(readFocusedTests(paths, changes, gitFixture({sources: {[fresh]: additions}}).git));
  assert.equal(readFocusedTests(paths, changes, gitFixture({sources: {[fresh]: portable + '\n' + portable}}).git), null);
});
test('selection uses complete actual base-to-tested-tree Git inventory, including additions', () => {
  const changes = [change(), change(added, true)], {git, commands} = gitFixture({changes});
  const read = readChanges({pull_request: {base: {sha: old}}}, git);
  assert.deepEqual(read.focusedChanges, changes);
  assert.equal(selectTargets(read.paths, read).profile, 'focused-tests');
  for (const args of commands.filter(args => args[0] === 'diff')) {
    assert(args.includes('--no-renames'));
    assert(args.includes(old) && args.includes(head));
  }
});
test('cumulative main delta selects full when earlier source obligations remain', () => {
  const earlier = '8'.repeat(40), changes = [change(), change('src/connector_sdk/api.mbt')];
  const {git, commands} = gitFixture({changes});
  const read = readChanges({}, git, {baseRevision: earlier});
  assert.equal(selectTargets(read.paths, read).profile, 'full');
  assert(commands.filter(args => args[0] === 'diff').every(args => args.includes(earlier)));
  assert.equal(selection([change()], {event: 'push'}).profile, 'full');
});
test('malformed/truncated raw inventory cannot enable focused selection', () => {
  const {git} = gitFixture();
  assert.throws(() => readChanges({pull_request: {base: {sha: old}}}, args => args.includes('--raw') ? git(args).slice(0, -1) : git(args)));
  assert.throws(() => readChanges({pull_request: {base: {sha: old}}}, args => args.includes('--name-only') ? git(args).slice(0, -1) : git(args)));
});
test('stable family cannot be removed from or forged into the plan', () => {
  const changes = [change()], value = focusedPlan([current]);
  validateFocusedTests([current], changes, value);
  for (const plan of [{...value, files: [current]}, {...value, family: 'all-tests'}, {...value, package: 'src'},
    {...value, files: [...value.files, 'src/platform_native/test.mbt']}]) assert.throws(() => validateFocusedTests([current], changes, plan));
});
test('runner checks only owning JS package and executes every selected file separately', () => {
  const calls = [], plan = focusedPlan([added]);
  runFocusedPlan(plan, {cwd: '/selected', check: (...args) => calls.push(args), run: (...args) => {calls.push(args); return 0;}});
  assert.deepEqual(calls[0].slice(0, 2), ['moon', ['check', '--target', 'js', '--deny-warn', 'src/query_integration']]);
  assert.deepEqual(calls.slice(1).map(call => call[1].at(-1)), plan.files);
  assert(calls.slice(1).every(call => call[0] === 'moon' && call[1].slice(0, 3).join(' ') === '--target js --deny-warn'));
});
test('zero/missing/skipped-only file results fail despite other passing family tests', () => {
  const plan = focusedPlan([added]);
  for (const output of ['', 'Total tests: 0, passed: 0, failed: 0.']) {
    const status = testExecutionResult('moon', 'moon', ['test', added], {status: 0, stdout: output}).status;
    assert.notEqual(status, 0);
    assert.throws(() => runFocusedPlan(plan, {check() {}, run: (_kind, args) => args.at(-1) === added ? status : 0}));
  }
});
test('aggregate requires focused success and legitimate explicit skips, bound to checkout/event', () => {
  const value = selection(), envelope = {sourceRevision: head, selection: value}, context = {sourceRevision: head, event: 'pull_request'};
  assert.equal(verifyGate(envelope, results(value), context).length, gateJobs.length);
  for (const name of gateJobs) for (const bad of ['failure', 'cancelled', undefined]) {
    const needs = results(value); needs[name] = {result: bad};
    assert.throws(() => verifyGate(envelope, needs, context));
  }
  for (const name of ['focused-tests', 'preflight', 'spec', 'lint']) {
    const needs = results(value); needs[name].result = 'skipped'; assert.throws(() => verifyGate(envelope, needs, context));
  }
  assert.throws(() => verifyGate(envelope, results(value), {...context, sourceRevision: old}));
});
test('workflow selects focused job only for this profile and retains mandatory gates', () => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const job = workflow.jobs['focused-tests'];
  assert.deepEqual(job.needs, ['select-targets', 'preflight']);
  assert.match(job.if, /profile == 'focused-tests'/u);
  assert(job.steps.some(step => step.run === 'node scripts/ci-focused-tests.mjs'));
  assert.deepEqual(workflow.jobs.check.needs, gateJobs);
  assert(workflow.jobs.lint.steps.some(step => step.run === 'node --test scripts/ci-focused-tests.test.mjs'));
});
test('focused runner installs only Node and MoonBit while preserving upstream artifact preflight', () => {
  const {jobs} = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const focused = jobs['focused-tests'].steps;
  assert(!focused.some(step => step.uses === './.github/actions/setup-toolchain'));
  assert(!focused.some(step => /npm ci|duckdb\/node/u.test(step.run ?? '')));
  assert(focused.some(step => step.run?.includes('node scripts/setup-moonbit.mjs')));
  const artifact = 'node --test proofs/relation-pipeline/ci-artifacts.test.mjs';
  assert.equal(jobs.preflight.steps.filter(step => step.run === artifact).length, 1);
  assert(jobs['pipeline-validation'].steps.some(step => step.run?.includes('if [[ "$test" != proofs/relation-pipeline/ci-artifacts.test.mjs ]]')));
});

test('full success checkpoint accepts focused-only job skipped but requires every full family', async () => {
  const fullJobs = fullCheckpointJobs(gateJobs.filter(name => name !== 'focused-tests'));
  assert(!fullJobs.includes('focused-tests'));
  for (const name of ['core (js)', 'core (wasm)', 'core (native)', 'host', 'client', 'native',
    'session-evidence', 'pipeline-evidence', 'native-macos', 'workers', 'duckdb-node']) assert(fullJobs.includes(name));
  const run = {id: 101, run_attempt: 1, workflow_id: 7, path: '.github/workflows/ci.yml',
    event: 'push', head_branch: 'main', repository: {id: 12, full_name: 'actql/actql'},
    head_repository: {id: 12}, head_sha: old, status: 'completed', conclusion: 'success'};
  const jobs = [...fullJobs.map(name => ({name, run_id: 101, run_attempt: 1, head_sha: old,
    status: 'completed', conclusion: 'success'})), {name: 'focused-tests', run_id: 101,
    run_attempt: 1, head_sha: old, status: 'completed', conclusion: 'skipped'}];
  const options = {testedSha: head, repository: 'actql/actql', repositoryId: 12, requiredJobs: fullJobs,
    git: args => args[0] === 'replace' ? '' : args[0] === 'rev-list' ? `${head}\n${old}\n`
      : args[1] === 'HEAD' ? head : args[1] === '--is-shallow-repository' ? 'false'
        : args[1] === '--git-path' ? '/tmp/actql-focused-no-grafts' : fresh,
    request: async path => path === '/actions/workflows/ci.yml'
      ? {id: 7, path: '.github/workflows/ci.yml', state: 'active'}
      : path.includes('/runs?') ? {workflow_runs: [run]}
        : path.includes('/jobs?') ? {total_count: jobs.length, jobs} : run};
  const checkpoint = await resolveMainBaseline(options);
  assert.equal(checkpoint.baseSha, old);
  assert.deepEqual(checkpoint.policy.map(entry => entry.path), policyPaths);
  assert(policyPaths.includes('scripts/ci-focused-tests.mjs'));
  const focused = selection([change()], {event: 'push', mainBaseline: checkpoint});
  assert.equal(validateSelection(focused).profile, 'focused-tests');
  verifyGate({selection: focused, sourceRevision: head}, results(focused), {event: 'push', sourceRevision: head});
  jobs.find(job => job.name === 'core (native)').conclusion = 'skipped';
  assert.equal((await resolveMainBaseline(options)).baseSha, null);
});
