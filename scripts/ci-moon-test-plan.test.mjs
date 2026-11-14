import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {runInNewContext} from 'node:vm';
import {readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync, realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {parse} from 'yaml';
import {moonGraphCandidate, nonMoonRequirements, normalizeMoonGraph, planMoonTests,
  validateMoonTestPlan, readMoonTestPlan} from './ci-moon-test-plan.mjs';
import {selectTargets, validateSelection, gateJobRequired, deepProofRequired, verifyGate, gateJobs,
  maintenanceFiles, readChanges} from './ci-targets.mjs';
import {runMoonTests, nativeMoonPackages} from './ci-moon-tests.mjs';
import {nativeCoreTestSelection, nativeScopedTestFiles, portableMoonTestCount} from './native-core-test-selection.mjs';
import {runFocusedTests} from './test-execution.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url)).replace(/\/$/u, '');
// Complete tracked-source metadata exceeds Node's default 1 MiB. Keep the
// same finite Git transport bound as readMoonTestPlan; errors still propagate.
const git = args => execFileSync('git', args,
  {cwd:repository, encoding:'utf8', maxBuffer:32 * 1024 ** 2});
const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const hash = 'a'.repeat(40), other = 'b'.repeat(40);
test('repository Git metadata preserves command failure and argument exceptions', () => {
  assert.throws(() => git(['cat-file', '-e', '0'.repeat(40)]),
    error => error.status === 1 && error.signal === null);
  assert.throws(() => git(['rev-parse', '\0']), {code:'ERR_INVALID_ARG_VALUE'});
});
function fixture() {
  const names = ['a', 'b', 'c', 'unrelated', 'b/nested'];
  const graph = {version:2, status:'success', error:null, logs:[], root:names.map((_, i) => i),
    nodes:names.map(rel => ({module:'actql/actql', version:'0.0.1', rel,
      source:{kind:'local', path:repository}})), edges:[
      {from:1, to:0, alias:'a', kinds:['source']},
      {from:2, to:1, alias:'b', kinds:['blackbox-test', 'whitebox-test']},
      {from:1, to:2, alias:'cycle', kinds:['whitebox-test']},
    ]};
  const tree = names.flatMap(name => ['moon.pkg', 'code.mbt', 'case_wbtest.mbt'].map(file =>
    ({path:`src/${name}/${file}`, object:hash, mode:'100644'})));
  const normalized = normalizeMoonGraph(graph, tree, repository);
  return {graph, tree, normalized, plan:planMoonTests(['src/a/code.mbt'], normalized, tree)};
}

test('compiler reverse dependencies include source/test imports and cycles without unrelated/nested packages', () => {
  const {plan} = fixture();
  assert.deepEqual(plan.packages, ['src/a', 'src/b', 'src/c']);
  assert.equal(plan.files.length, 6);
  assert(!plan.files.some(path => path.includes('nested') || path.includes('unrelated')));
  assert.deepEqual(plan.changedPackages, ['actql/actql/a']);
  assert.equal(validateMoonTestPlan(plan), plan);
});

test('independent Moon edits compose by the union of reverse dependencies', () => {
  const {normalized, tree} = fixture();
  const plan = planMoonTests(['src/a/code.mbt', 'src/unrelated/code.mbt'], normalized, tree);
  assert.deepEqual(plan.packages, ['src/a', 'src/b', 'src/c', 'src/unrelated']);
  assert.equal(plan.files.length, 8);
});

test('compiler graph normalization is relocation independent and preserves every import kind', () => {
  const f = fixture(), moved = structuredClone(f.graph);
  for (const node of moved.nodes) node.source.path = '/another/checkout';
  const graph = normalizeMoonGraph(moved, f.tree, '/another/checkout');
  assert.equal(graph.digest, f.normalized.digest);
  assert.deepEqual(graph.edges, f.normalized.edges);
  moved.edges.pop();
  assert.notEqual(normalizeMoonGraph(moved, f.tree, '/another/checkout').digest, graph.digest);
});

test('partial, foreign, duplicate, diagnostic and future compiler graphs cannot narrow tests', () => {
  const mutations = [g => g.version++, g => g.root.pop(), g => g.root.push(g.root[0]),
    g => g.nodes[0].source.path = '/foreign', g => g.nodes[1].rel = g.nodes[0].rel,
    g => g.logs.push('warning'), g => g.edges[0].to = 1000,
    g => g.edges[0].kinds = ['unknown-target']];
  for (const mutate of mutations) {
    const {graph, tree} = fixture(); mutate(graph);
    assert.throws(() => normalizeMoonGraph(graph, tree, repository));
  }
});

test('missing/aliased sources, unknown packages and path escapes cannot become an execution plan', () => {
  for (const path of ['src/new/code.mbt', 'src/a/../code.mbt', 'src/a/moon.pkg', 'src/a/code.c']) {
    const {normalized, tree} = fixture();
    assert.throws(() => planMoonTests([path], normalized, tree), path);
  }
  const {normalized, tree} = fixture();
  tree.find(entry => entry.path === 'src/a/code.mbt').mode = '120000';
  assert.throws(() => planMoonTests(['src/a/code.mbt'], normalized, tree));
});

test('FFI, generator, JS bridge and proof inputs keep their explicit non-Moon owners', () => {
  for (const [path, owner] of [
    ['src/platform_native/sqlite/sqlite_stub.c', 'FFI/platform'],
    ['scripts/generate-credential-scope-binding.mjs', 'generator/build'],
    ['adapters/host-common/runtime-core.mjs', 'JS bridge/distribution'],
    ['packages/run-host-core/package.json', 'generator/build'],
    ['src/client_values_host_abi/entry.mbt', 'JS bridge/distribution'],
    ['proofs/relation-pipeline/inventory.mjs', 'proof snapshot'],
  ]) {
    assert(nonMoonRequirements([path]).some(row => row.name === owner), path);
    assert.equal(moonGraphCandidate(['src/a/code.mbt', path]), false, path);
    const selected = selectTargets(['src/a/code.mbt', path], {moonTests:fixture().plan});
    assert.equal(selected.profile, 'full'); assert.equal(selected.moonTests, undefined);
  }
});

test('a source-bound Moon plan narrows execution without omitting whole checks or Native/proof/product owners', () => {
  const {plan} = fixture();
  const selected = validateSelection(selectTargets(['src/a/code.mbt'], {moonTests:plan}));
  assert.equal(selected.moonTests, plan); assert.deepEqual(selected.targets, ['js', 'wasm', 'native']);
  for (const name of ['core', 'host', 'client', 'native', 'native-macos', 'python-wheels', 'session-evidence', 'session-controls', 'pipeline-evidence'])
    assert.equal(gateJobRequired(selected, name), true, name);
  assert.equal(deepProofRequired(selected), true);
  assert.equal(selectTargets(['src/a/code.mbt'], {moonTests:plan, targetSensitiveDiff:true}).moonTests, undefined);
  assert.equal(selectTargets(['src/a/code.mbt'], {moonTests:plan, event:'push'}).moonTests, undefined);
  assert.equal(selectTargets(['src/a/code.mbt'], {moonTests:plan, draft:true}).moonTests, undefined);
});

test('graph failure remains an explained full selection and never an empty/successful selection', () => {
  const selected = selectTargets(['src/a/code.mbt'], {moonGraphFailure:'compiler unavailable'});
  assert.equal(selected.profile, 'full'); assert.equal(selected.moonTests, undefined);
  assert.match(selected.reason, /compiler unavailable/u);
  const plan = fixture().plan; plan.files = [];
  assert.equal(selectTargets(['src/a/code.mbt'], {moonTests:plan}).moonTests, undefined);
});

test('the same final gate rejects every failed/cancelled/missing selected owner with a Moon plan', () => {
  const selection = selectTargets(['src/a/code.mbt'], {moonTests:fixture().plan});
  const outcomes = Object.fromEntries(gateJobs.map(name => [name, {result:gateJobRequired(selection, name) ? 'success' : 'skipped'}]));
  const envelope = {sourceRevision:hash, selection}, context = {sourceRevision:hash, event:'pull_request'};
  assert.doesNotThrow(() => verifyGate(envelope, outcomes, context));
  for (const name of gateJobs.filter(name => gateJobRequired(selection, name))) {
    for (const result of ['failure', 'cancelled', 'skipped', undefined]) {
      const changed = structuredClone(outcomes); changed[name].result = result;
      assert.throws(() => verifyGate(envelope, changed, context), name);
    }
  }
});

test('consumer rederives original graph/files before passing exact file arguments to the nonzero wrapper', () => {
  const selection = selectTargets(['src/a/code.mbt'], {moonTests:fixture().plan});
  const envelope = {sourceRevision:hash, selection};
  let invoked = 0;
  const options = {git:() => hash, discover(paths, base) {
    assert.deepEqual(paths, selection.paths); assert.equal(base, other); return structuredClone(selection.moonTests);
  }, count:() => 1, run(kind, args, {cwd}) {
    invoked++; assert.equal(kind, 'moon'); assert.equal(cwd, repository);
    assert.deepEqual(args.slice(0, 3), ['--target', 'js', '--deny-warn']);
    assert.deepEqual(args.slice(5), selection.moonTests.files); return 7;
  }, cwd:repository};
  assert.equal(runMoonTests(envelope, 'js', other, options), 7); assert.equal(invoked, 1);
  assert.throws(() => runMoonTests(envelope, 'native', other, options));
  assert.throws(() => runMoonTests(envelope, 'js', other, {...options, git:() => other}));
  assert.throws(() => runMoonTests(envelope, 'js', other, {...options, discover:() => ({...selection.moonTests, files:[]})}));
  for (const value of [undefined, NaN, -1, '1']) assert.throws(() => runMoonTests(envelope, 'js', other, {...options, count:() => value}));
  assert.equal(invoked, 1, 'Refused plans must never invoke a compiler/test');
});

test('a backend without runnable compiler cases retains its full nonzero suite', () => {
  const selection = selectTargets(['src/a/code.mbt'], {moonTests:fixture().plan});
  let invoked = 0;
  assert.equal(runMoonTests({sourceRevision:hash, selection}, 'wasm', other, {
    git:() => hash, discover:() => selection.moonTests, count:() => 0,
    run(kind, args) {
      invoked++; assert.equal(kind, 'moon');
      assert.deepEqual(args.slice(0, 3), ['--target', 'wasm', '--deny-warn']);
      assert.equal(args.length, 5, 'No selected path means the complete backend, never a zero-case pass');
      return 1;
    },
  }), 1);
  assert.equal(invoked, 1);
});

test('Native caller consumes the same checked package closure without changing its full entry classification', async () => {
  const selection = selectTargets(['src/a/code.mbt'], {moonTests:fixture().plan});
  const env = {CI_PLAN:JSON.stringify({sourceRevision:hash, selection}), GITHUB_EVENT_NAME:'pull_request', GITHUB_EVENT_PATH:'original-event'};
  let reads = 0;
  const options = {git:() => hash, discover:() => selection.moonTests,
    readEvent(path) {reads++;assert.equal(path, 'original-event');return {pull_request:{base:{sha:other}}};}};
  assert.deepEqual(nativeMoonPackages(env, options), selection.moonTests.packages); assert.equal(reads, 1);
  assert.equal(nativeMoonPackages({}, options), undefined);
  assert.equal(nativeMoonPackages({CI_PLAN:JSON.stringify({selection:{profile:'full'}})}, options), undefined);
  assert.throws(() => nativeMoonPackages({...env, GITHUB_EVENT_NAME:'push'}, options));
  assert.throws(() => nativeMoonPackages(env, {...options, git:() => other}));
  const source = readFileSync(new URL('./test-native-core.mjs', import.meta.url), 'utf8');
  assert.match(source, /const full = !\['focused', 'reporting'\]\.includes/u);
  assert.match(source, /full && \(process\.env\.CI_PLAN \|\| process\.env\.CI_PLAN_PATH\)/u);
  assert.match(source, /nativeMoonPackages\(\)/u);
  const start = source.indexOf('const selection = full ? nativeCoreTestSelection');
  const end = source.indexOf('if (selection?.executionScope)', start);
  assert(start > 0 && end > start);
  const packages = selection.moonTests.packages;
  const platformStart = source.indexOf('const platformPackages = full && platformScope');
  const platformEnd = source.indexOf('\nconst executionPackages', platformStart);
  assert(platformStart > 0 && platformEnd > platformStart);
  // This PR closure has no platform override. Evaluate the actual preceding
  // production binding rather than fabricating an empty Darwin package set.
  const platformPackages = await runInNewContext('(async () => {\n' +
    source.slice(platformStart, platformEnd) + '\nreturn platformPackages;})()', {
    full: true, platformScope: env.ACTQL_TEST_NATIVE_CORE_PLATFORM_SCOPE,
  });
  assert.equal(platformPackages, undefined);
  const linuxBinding = source.match(/^const linuxCommonImporters = [^\n]+;$/mu)?.[0];
  assert(linuxBinding, 'Retain the actual preceding platform binding in this extracted consumer');
  const linuxCommonImporters = runInNewContext(linuxBinding + '\nlinuxCommonImporters;',
    {platformScope: env.ACTQL_TEST_NATIVE_CORE_PLATFORM_SCOPE});
  assert.equal(linuxCommonImporters, false, 'This authenticated PR closure has no Linux platform override');
  for (const partition of [undefined, '1/2', '2/2', '1/4', '4/4', 'http', 'source', 'scoped']) {
    let calls = 0;
    runInNewContext(source.slice(start, end), {
      full: true, root: '/same/source', args: ['--release'], partition,
      executionPackages: packages, platformPackages, linuxCommonImporters, compilerEnvironment: {},
      nativeCoreTestSelection(root, args, options) {
        calls++;
        assert.equal(root, '/same/source');
        assert.equal(options.timeoutMs, 300_000);
        assert.equal(options.partitionProfiles, true);
        assert.equal(options.allowNestedFileInputs, false);
        assert.equal(options.ordinaryPartitions, partition?.endsWith('/4') ? 4 :
          Boolean(partition) && !['http', 'source', 'scoped'].includes(partition));
        assert.equal(options.executionPackages, ['http', 'source', 'scoped'].includes(partition) ? undefined : packages,
          'Physical profiles keep full originals; ordinary jobs use only the same authenticated closure');
      },
    });
    assert.equal(calls, 1);
  }
});

test('Native file transport retains the original compiler inventory and refuses changed evidence', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-native-ci-plan-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const path = join(root, 'plan.json');
  const selection = selectTargets(['src/a/code.mbt'], {moonTests: fixture().plan});
  writeFileSync(path, JSON.stringify({sourceRevision: hash, selection}));
  const environment = {CI_PLAN_PATH: path, GITHUB_EVENT_NAME: 'pull_request', GITHUB_EVENT_PATH: 'original-event'};
  const options = {git: () => hash, discover: () => selection.moonTests,
    readEvent: () => ({pull_request: {base: {sha: other}}})};
  assert.deepEqual(nativeMoonPackages(environment, options), selection.moonTests.packages);
  assert.throws(() => nativeMoonPackages(environment, {...options, git: () => other}), /Foreign/u);
  assert.throws(() => nativeMoonPackages(environment, {...options, discover: () => ({})}), /Changed/u);
  writeFileSync(path, '{');
  assert.throws(() => nativeMoonPackages(environment, options), SyntaxError);
  writeFileSync(path, 'null');
  assert.throws(() => nativeMoonPackages(environment, options), TypeError);
  assert.throws(() => nativeMoonPackages({...environment, CI_PLAN_PATH: '', CI_PLAN: 'null'}, options), TypeError);
});

test('raw additions/deletions/renames/modes and omitted mixed changes refuse before graph discovery', () => {
  for (const status of ['A', 'D', 'R100', 'T']) {
    let compiler = 0;
    const fakeGit = args => args[0] === 'rev-parse' ? hash : args.includes('--name-only') ? 'src/a/code.mbt\0'
      : args.includes('--raw') ? `:100644 100644 ${hash} ${other} ${status}\0src/a/code.mbt\0` : '';
    assert.throws(() => readMoonTestPlan(['src/a/code.mbt'], other, {git:fakeGit,
      execute() {compiler++;throw new Error('must not discover');}}));
    assert.equal(compiler, 0);
  }
  assert.throws(() => readMoonTestPlan(['src/a/code.mbt'], other, {git:args => args[0] === 'rev-parse'
    ? hash : 'src/a/code.mbt\0toolchain.json\0'}), /omits/u);
});

test('reviewed real prose and independent JS edits omit product jobs but retain their lint/spec owners', () => {
  for (const path of ['CONTRIBUTING.md', 'docs/contributing/README.md', 'docs/ci-client.md',
    'scripts/operation-performance.mjs', 'scripts/operation-performance.test.mjs', 'scripts/operation-performance-policy.test.mjs']) {
    assert(maintenanceFiles.includes(path)); assert(readFileSync(new URL('../' + path, import.meta.url)).length > 0);
    const selected = selectTargets([path], {maintenanceChanges:[{path, before:{mode:'100644', object:hash}, after:{mode:'100644', object:other}}]});
    assert.equal(selected.profile, 'maintenance', path);
    for (const name of ['lint', 'spec']) assert.equal(gateJobRequired(selected, name), true);
    for (const name of ['core', 'host', 'client', 'native', 'python-wheels', 'session-evidence'])
      assert.equal(gateJobRequired(selected, name), false, path + ':' + name);
    assert.equal(selectTargets([path]).profile, 'full', 'Missing original modification identity stays full');
    assert.equal(selectTargets([path, 'toolchain.json']).profile, 'full');
  }
  const owned = workflow.jobs.lint.steps.find(step => step.name === 'Test ordinary operation performance policy oracles');
  assert.equal(owned.if, undefined, 'Small policy oracles must execute during Draft preparation too');
  for (const path of ['scripts/operation-performance.test.mjs', 'scripts/operation-performance-policy.test.mjs']) assert(owned.run.includes(path));
});

test('workflow prepares graph tools only for candidates and retains full checks and unchanged Native command', () => {
  const select = workflow.jobs['select-targets'];
  assert.equal(select.steps.find(step => step.id === 'moon-candidate').run, 'node scripts/ci-targets.mjs moon-graph-candidate');
  assert.equal(select.steps.find(step => step.name?.startsWith('Install pinned Moon only')).if,
    "steps.moon-candidate.outputs.required == 'true'");
  const core = workflow.jobs['core-common'].steps;
  assert.equal(core.find(step => step.name === 'Check common core').run, 'moon check --target "${{ matrix.target }}" --deny-warn');
  const run = core.find(step => step.name === 'Test common core');
  assert.match(run.run, /node scripts\/ci-moon-tests\.mjs "\$\{\{ matrix\.target \}\}"/u);
  assert.match(run.run, /MOONBIT_NEW_NATIVE=0 node scripts\/test-native-core\.mjs --deny-warn --release --strip -j 2 --no-parallelize --verbose/u);
  assert.equal(run.env.CI_PLAN_PATH, '${{ runner.temp }}/actql-ci-plan.json');
  assert(workflow.jobs.lint.steps.some(step => step.run === 'node --test scripts/ci-moon-test-plan.test.mjs'));
});

test('the actual pinned compiler graph narrows a real Gmail source change and retains its host importer', () => {
  const tree = git(['ls-tree', '-rz', 'HEAD', '--', 'src']).slice(0, -1).split('\0').map(line => {
    const [, mode, object, path] = /^(\d{6}) blob ([a-f0-9]{40})\t(.+)$/u.exec(line);
    return {mode, object, path};
  });
  const raw = JSON.parse(execFileSync('moon', ['tree', '--package', '--json'],
    {cwd:repository, encoding:'utf8', timeout:60000, maxBuffer:16 * 1024 ** 2}));
  const graph = normalizeMoonGraph(raw, tree, repository);
  const path = 'src/connectors/gmail/catalog/message_date.mbt';
  const plan = planMoonTests([path], graph, tree);
  assert(plan.packages.includes('src/connectors/gmail/catalog'));
  assert(plan.packages.includes('src/connectors/gmail/host_node'));
  assert(plan.packages.length < graph.packages.length);
  assert(!plan.files.some(path => path.startsWith('src/platform_native/')));
  const selection = validateSelection(selectTargets([path], {moonTests:plan}));
  assert.equal(selection.moonTests, plan);
  assert.equal(gateJobRequired(selection, 'client-readme-packed'), true,
    'Compiler-selected Core edits must still run the normal packed README consumers');
  const sourceRevision = git(['rev-parse', 'HEAD']).trim();
  const results = Object.fromEntries(gateJobs.map(name => [name,
    {result: gateJobRequired(selection, name) ? 'success' : 'skipped'}]));
  const context = {event: 'pull_request', sourceRevision, draft: false};
  verifyGate({sourceRevision, selection}, results, context);
  assert.throws(() => verifyGate({sourceRevision, selection},
    {...results, 'client-readme-packed': {result: 'skipped'}}, context), /client-readme-packed/u);
  for (const target of ['js', 'wasm']) {
    assert(portableMoonTestCount(repository, ['--deny-warn', ...plan.files], target) > 0,
      'The real ordinary input must contain runnable compiler cases, not permanent full fallback');
  }
});

test('the actual repository Native compiler retains full profiles and partitions for oversized reverse dependencies', () => {
  const tree = git(['ls-tree', '-rz', 'HEAD', '--', 'src']).slice(0, -1).split('\0').map(line => {
    const [, mode, object, path] = /^(\d{6}) blob ([a-f0-9]{40})\t(.+)$/u.exec(line);
    return {mode, object, path};
  });
  const raw = JSON.parse(execFileSync('moon', ['tree', '--package', '--json'],
    {cwd:repository, encoding:'utf8', timeout:60000, maxBuffer:16 * 1024 ** 2}));
  const graph = normalizeMoonGraph(raw, tree, repository);
  const paths = ['src/bounded_graph_diff/apply_before.mbt'];
  // This real reverse closure outgrew the finite file argv. The selector must
  // retain the complete backend, not raise the bound or truncate its inventory.
  let moonGraphFailure;
  assert.throws(() => planMoonTests(paths, graph, tree), error => {
    assert.equal(error.code, 'ERR_ASSERTION');
    assert.equal(error.message, 'Selected argv exceeds its finite bound');
    moonGraphFailure = error.message;
    return true;
  });
  const selection = validateSelection(selectTargets(paths, {moonGraphFailure}));
  assert.equal(selection.profile, 'full');
  assert.equal(selection.moonTests, undefined);
  assert.deepEqual(selection.targets, ['js', 'wasm', 'native']);
  assert(selection.reason.includes(moonGraphFailure));
  assert.equal(selection.event, 'pull_request');
  assert.equal(gateJobRequired(selection, 'main-performance'), true, 'Ready full input must retain positive performance acceptance');
  for (const name of gateJobs) assert.equal(gateJobRequired(selection, name),
    !['focused-tests', 'health-quick'].includes(name), name);
  const executionPackages = nativeMoonPackages({CI_PLAN:JSON.stringify({sourceRevision:hash, selection})});
  assert.equal(executionPackages, undefined, 'Full fallback must not narrow the original Native entrance');
  const selected = nativeCoreTestSelection(repository, ['--deny-warn', '--release', '--strip', '-j', '2', '--no-parallelize'],
    {env:{...process.env, MOONBIT_NEW_NATIVE:'0'}, partitionProfiles:true, ordinaryPartitions:true,
      timeoutMs:5 * 60_000, executionPackages});
  assert.equal(selected.executionScope, undefined);
  const profiles = selected.profiles;
  assert.equal(profiles.uniqueCases, selected.cases);
  assert.equal(profiles.ordinary.cases + profiles.http.cases + profiles.source.cases +
    profiles.physicalCases + (profiles.benchmarkDeclarations ?? 0), selected.cases);
  for (const name of ['ordinary', 'http', 'source', 'scoped']) assert(profiles[name].cases > 0, name);
  assert.equal(profiles.scoped.cases, profiles.physicalCases + profiles.repeatedGeometryCases);
  assert.equal(profiles.scoped.tests.length, profiles.scoped.cases);
  assert.equal(profiles.ordinary.partitions.length, 2);
  assert(profiles.ordinary.partitions.every(part => part.cases > 0));
  assert.equal(profiles.ordinary.partitions.reduce((sum, part) => sum + part.cases, 0), profiles.ordinary.cases);
});

test('actual approval Core and Native Host edits retain the scoped call-count owner and required Native job', () => {
  const counter = 'src/cmd/native_client/local_project_mock_physical_scoped_wbtest.mbt';
  assert(nativeScopedTestFiles.includes(counter));
  const tree = git(['ls-tree', '-rz', 'HEAD', '--', 'src']).slice(0, -1).split('\0').map(line => {
    const [, mode, object, path] = /^(\d{6}) blob ([a-f0-9]{40})\t(.+)$/u.exec(line);
    return {mode, object, path};
  });
  const raw = JSON.parse(execFileSync('moon', ['tree', '--package', '--json'],
    {cwd:repository, encoding:'utf8', timeout:60000, maxBuffer:16 * 1024 ** 2}));
  const graph = normalizeMoonGraph(raw, tree, repository);
  const paths = ['src/execution_authorization/decision.mbt'];
  let moonTests, moonGraphFailure;
  try {moonTests = planMoonTests(paths, graph, tree);}
  catch (error) {
    // Preserve the existing complete fallback if this real reverse closure
    // exceeds the original finite argv; never narrow by losing the importer.
    assert.equal(error.code, 'ERR_ASSERTION');
    assert.equal(error.message, 'Selected argv exceeds its finite bound');
    moonGraphFailure = error.message;
  }
  const selected = validateSelection(selectTargets(paths, {moonTests, moonGraphFailure}));
  assert.equal(gateJobRequired(selected, 'native'), true);
  if (selected.moonTests) {
    assert(selected.moonTests.packages.includes('src/cmd/native_client'));
    assert(selected.moonTests.files.includes(counter));
  } else assert.equal(selected.profile, 'full');
  for (const path of [counter, 'src/platform_native/client_host/local_installation_original.mbt']) {
    assert(tree.some(entry => entry.path === path), 'Select an actual tracked Native owner input');
    const native = validateSelection(selectTargets([path], {draft: false}));
    assert.equal(gateJobRequired(native, 'native'), true);
    assert.equal(native.moonTests, undefined, 'Native Host edits retain complete original Native profiles');
  }
});

test('executed documentation Quickstart changes retain product owners while pure prose stays maintenance', () => {
  const path = 'docs/development.md';
  const original = readFileSync(new URL('../' + path, import.meta.url), 'utf8');
  const inspect = after => {
    const sourceGit = args => args[0] === 'rev-parse' ? hash : args.includes('--name-only') ? path + '\0'
      : args.includes('--raw') ? `:100644 100644 ${hash} ${other} M\0${path}\0`
        : args[0] === 'show' ? args[1] === hash ? original : after : '+Changed prose\n';
    const changed = readChanges({pull_request:{base:{sha:hash}}}, sourceGit);
    return selectTargets(changed.paths, changed);
  };
  assert.equal(inspect(original + '\nProse-only addition.\n').profile, 'maintenance');
  const changedCommand = original.replace('node quickstart.mjs\ncat answer.jsonl', 'node changed.mjs\ncat answer.jsonl');
  assert.notEqual(changedCommand, original);
  for (const body of [changedCommand, original.split('## Quickstart\n')[0]]) {
    const selected = inspect(body);
    assert.equal(selected.profile, 'full'); assert.equal(gateJobRequired(selected, 'client'), true);
  }
});

test('actual compiler and Git endpoints execute only selected backend tests while retaining complete checks', t => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'actql-moon-ci-graph-')));
  t.after(() => rmSync(root, {recursive:true, force:true}));
  const write = (path, value) => {mkdirSync(dirname(join(root, path)), {recursive:true});writeFileSync(join(root, path), value);};
  const cleanEnv = {...Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_'))),
    MOONBIT_NEW_NATIVE:'0'};
  const originalGit = args => execFileSync('git', args, {cwd:root, env:cleanEnv, encoding:'utf8', timeout:15000});
  write('.gitignore', '_build/\n.moon/\n');
  write('moon.mod', 'name = "actql/actql"\nsource = "src"\npreferred_target = "js"\nsupported_targets = "+js+wasm+native"\n');
  write('src/moon.pkg', '');
  for (const name of ['base', 'consumer', 'caller', 'unrelated']) write(`src/${name}/moon.pkg`, '');
  write('src/base/value.mbt', 'pub fn value() -> Int { 7 }\n');
  write('src/base/value_wbtest.mbt', 'test "base" { assert_eq(value(), 7) }\n');
  write('src/consumer/moon.pkg', 'import { "actql/actql/base" @base, }\n');
  write('src/consumer/value.mbt', 'pub fn value() -> Int { @base.value() }\n');
  write('src/consumer/value_wbtest.mbt', 'test "consumer" { assert_eq(value(), 7) }\n');
  write('src/caller/moon.pkg', 'import { "actql/actql/consumer" @consumer, } for "wbtest"\n');
  write('src/caller/value_wbtest.mbt', 'test "caller" { assert_eq(@consumer.value(), 7) }\n');
  write('src/unrelated/fail_wbtest.mbt', 'test "unselected runtime sentinel" { assert_true(false) }\n');
  originalGit(['init', '--quiet']);
  const commit = message => {
    originalGit(['add', '.']); originalGit(['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
      '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', message]);
  };
  execFileSync('moon', ['info', '--target', 'js,wasm,native'], {cwd:root, env:cleanEnv, encoding:'utf8', timeout:60000});
  commit('Original input'); const base = originalGit(['rev-parse', 'HEAD']).trim();
  write('src/base/value.mbt', 'pub fn value() -> Int { 7 }\n// body-only change\n'); commit('Changed input');
  const paths = ['src/base/value.mbt'];
  const scope = readMoonTestPlan(paths, base, {repository:root, git:originalGit});
  assert.deepEqual(scope.packages, ['src/base', 'src/caller', 'src/consumer']);
  const plan = {sourceRevision:originalGit(['rev-parse', 'HEAD']).trim(), selection:selectTargets(paths, {moonTests:scope})};
  const event = join(root, '_build/event.json'), output = join(root, '_build/outputs');
  writeFileSync(event, JSON.stringify({action:'synchronize', pull_request:{draft:false, base:{sha:base}}}));
  writeFileSync(output, '');
  const environment = {...cleanEnv, GITHUB_EVENT_NAME:'pull_request', GITHUB_EVENT_PATH:event,
    GITHUB_OUTPUT:output, GITHUB_SHA:plan.sourceRevision};
  const selector = fileURLToPath(new URL('./ci-targets.mjs', import.meta.url));
  execFileSync(process.execPath, [selector, 'moon-graph-candidate'], {cwd:root, env:environment, encoding:'utf8', timeout:60000});
  assert.match(readFileSync(output, 'utf8'), /^required=true$/mu);
  execFileSync(process.execPath, [selector], {cwd:root, env:environment, encoding:'utf8', timeout:60000});
  const emitted = readFileSync(output, 'utf8').split('\n').find(line => line.startsWith('plan='));
  assert.deepEqual(JSON.parse(emitted.slice(5)), plan);
  for (const target of ['js', 'wasm']) {
    execFileSync('moon', ['check', '--target', target, '--deny-warn'], {cwd:root, env:cleanEnv, encoding:'utf8', timeout:60000});
    assert.equal(runMoonTests(plan, target, base, {cwd:root, git:originalGit}), 0);
  }
  const executionPackages = nativeMoonPackages({...environment, CI_PLAN:JSON.stringify(plan)}, {cwd:root});
  const native = nativeCoreTestSelection(root, ['--deny-warn', '--release', '--strip', '-j', '1', '--no-parallelize'],
    {env:cleanEnv, partitionProfiles:true, ordinaryPartitions:true, executionPackages});
  assert.equal(native.executionScope.mode, 'subset');
  assert.equal(native.executionScope.originalCases, 4); assert.equal(native.cases, 3);
  assert.equal(native.profiles.ordinary.partitions.reduce((sum, part) => sum + part.cases, 0), 3);
  for (const part of native.profiles.ordinary.partitions) assert.equal(runFocusedTests('moon',
    ['--target', 'native', ...part.args], {cwd:root, env:cleanEnv, expectedTests:part.cases}), 0);

  write('src/unrelated/fail_wbtest.mbt', 'test "unselected runtime sentinel" { assert_true(true) }\n');
  write('src/testless/moon.pkg', '');
  write('src/testless/value.mbt', 'pub fn value() -> Int { 7 }\n');
  write('src/bench_only/moon.pkg', 'import { "moonbitlang/core/bench" } for "wbtest"\n');
  write('src/bench_only/value_wbtest.mbt',
    'test "benchmark only" (it : @bench.T) { it.bench(fn() { it.keep(7) }) }\n');
  execFileSync('moon', ['info', '--target', 'js,wasm,native'], {cwd:root, env:cleanEnv, encoding:'utf8', timeout:60000});
  commit('Original zero-case inputs');
  for (const file of ['src/testless/value.mbt', 'src/bench_only/value_wbtest.mbt']) {
    const before = originalGit(['rev-parse', 'HEAD']).trim();
    write(file, readFileSync(join(root, file), 'utf8') + '// body-only zero-case change\n');
    commit('Changed zero-case input');
    const zeroScope = readMoonTestPlan([file], before, {repository:root, git:originalGit});
    assert.deepEqual(zeroScope.packages, [dirname(file)]);
    const zeroPlan = {sourceRevision:originalGit(['rev-parse', 'HEAD']).trim(),
      selection:selectTargets([file], {moonTests:zeroScope})};
    for (const target of ['js', 'wasm']) {
      assert.equal(portableMoonTestCount(root, ['--deny-warn', ...zeroScope.files], target), 0);
      assert.equal(runMoonTests(zeroPlan, target, before, {cwd:root, git:originalGit,
        run(kind, args, options) {
          assert.equal(args.length, 5, 'Zero-case selection must run the complete backend');
          return runFocusedTests(kind, args, {...options, expectedTests:4});
        }}), 0);
    }
  }
});
