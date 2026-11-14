import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {appendFileSync, chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {runInNewContext} from 'node:vm';
import {parse} from 'yaml';
import {parse as parseJavaScript} from 'acorn';
import {nativeCoreCCachePin} from './native-core-c-compiler.mjs';
import {gateJobs, gateJobRequired, selectTargets} from './ci-targets.mjs';
import {validateGroups} from './ci-native-background-groups.mjs';
import {nativeCoreCiPartitions} from './ci-core-partitions.mjs';
import {nativeCoreLinuxCommonPartitions} from './test-native-core-linux-common.mjs';
import {spawnSync} from 'node:child_process';

const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const original = JSON.parse(readFileSync(new URL('./fixtures/ci-native-obligations.json', import.meta.url), 'utf8'));
const background = JSON.parse(readFileSync(new URL('./ci-native-background-groups.json', import.meta.url)));

test('scarce Mac admission waits for lint and the original JS row while Native Mac remains early', () => {
  const js = workflow.jobs['core-js'], common = workflow.jobs['core-common'], darwin = workflow.jobs['core-darwin'];
  assert(js, 'The existing JS row needs its own status boundary');
  assert.deepEqual(js.needs, ['select-targets']);
  assert.deepEqual(js.strategy.matrix, {target: ['js'], partition: ['1/4']});
  assert.equal(js.name, common.name);
  assert.equal(js.steps, common.steps); assert.equal(js.steps, darwin.steps);
  assert.equal(darwin.strategy['max-parallel'], 3);
  assert.deepEqual(darwin.strategy.matrix.partition.slice(0, 2), ['scoped', 'source']);
  for (const job of [darwin, workflow.jobs['python-wheels']])
    assert.deepEqual(job.needs, ['select-targets', 'lint', 'core-js']);
  assert.deepEqual(workflow.jobs['native-macos-workloads'].needs, ['select-targets']);
  const evaluate = (job, targets, lint, result, stopped = false, profile = 'full') =>
    runInNewContext(job.if.slice(3, -2).replaceAll('needs.select-targets', "needs['select-targets']")
      .replaceAll('needs.core-js', "needs['core-js']"), {
      github: {event: {repository: {visibility: 'public', private: false}}}, inputs: {},
      needs: {'select-targets': {outputs: {profile, targets: JSON.stringify(targets), python_wheels: 'true'}},
        lint: {result: lint}, 'core-js': {result}},
      toJSON: JSON.stringify, fromJSON: JSON.parse, contains: (values, value) => values.includes(value),
      always: () => true, cancelled: () => stopped,
    });
  for (const targets of [['js'], ['wasm'], ['native'], ['js', 'wasm'], ['js', 'native'], ['wasm', 'native'], ['js', 'wasm', 'native']]) {
    const actual = [];
    if (evaluate(js, targets, 'success', targets.includes('js') ? 'success' : 'skipped')) actual.push({target: 'js', partition: '1/4'});
    if (evaluate(common, targets, 'success', targets.includes('js') ? 'success' : 'skipped')) for (const target of targets) for (const partition of common.strategy.matrix.partition)
      if (!common.strategy.matrix.exclude.some(row => row.target === target && row.partition === partition)) actual.push({target, partition});
    if (evaluate(darwin, targets, 'success', targets.includes('js') ? 'success' : 'skipped')) for (const partition of darwin.strategy.matrix.partition) actual.push({target: 'native', partition});
    const expected = [
      ...(targets.includes('js') ? [{target: 'js', partition: '1/4'}] : []),
      ...(targets.includes('wasm') ? [{target: 'wasm', partition: '1/4'}] : []),
      ...(targets.includes('native') ? [...nativeCoreLinuxCommonPartitions, '1/2', '2/2', 'source', 'scoped']
        .map(partition => ({target: 'native', partition})) : []),
    ];
    assert.deepEqual(actual.map(row => JSON.stringify(row)).sort(), expected.map(row => JSON.stringify(row)).sort());
    for (const lint of ['success', 'failure', 'cancelled', 'skipped', undefined])
      for (const result of ['success', 'failure', 'cancelled', 'skipped', undefined]) for (const stopped of [false, true]) {
        const admitted = !stopped && lint === 'success' && result === (targets.includes('js') ? 'success' : 'skipped');
        assert.equal(evaluate(darwin, targets, lint, result, stopped), admitted && targets.includes('native'));
        assert.equal(evaluate(workflow.jobs['python-wheels'], targets, lint, result, stopped), admitted);
      }
  }
  // Targeted Draft wheel acceptance does not select full Core. Its absent JS
  // row is legitimate only when the original full-only predicate omits it.
  for (const profile of ['draft', 'draft-focused']) for (const lint of ['success', 'failure', 'cancelled', 'skipped', undefined])
    for (const result of ['success', 'failure', 'cancelled', 'skipped', undefined]) for (const stopped of [false, true]) {
      assert.equal(evaluate(js, ['js'], lint, result, stopped, profile), false);
      assert.equal(evaluate(common, ['js'], lint, result, stopped, profile), false);
      assert.equal(evaluate(darwin, ['js'], lint, result, stopped, profile), false);
      assert.equal(evaluate(workflow.jobs['python-wheels'], ['js'], lint, result, stopped, profile),
        !stopped && lint === 'success' && result === 'skipped');
    }
});

test('Core runner split caps only Darwin and retains the complete original matrix union', () => {
  const js = workflow.jobs['core-js'], common = workflow.jobs['core-common'], darwin = workflow.jobs['core-darwin'];
  assert(js && common && darwin);
  assert.equal(common['runs-on'], 'ubuntu-24.04');
  assert.equal(common.strategy['max-parallel'], undefined);
  assert.equal(darwin['runs-on'], 'macos-15');
  assert.equal(darwin.strategy['max-parallel'], 3);
  assert.deepEqual({...darwin.strategy.matrix, partition: [...darwin.strategy.matrix.partition].sort()},
    {target: ['native'], partition: [...nativeCoreCiPartitions].sort()});
  assert.deepEqual(darwin.strategy.matrix.partition,
    ['scoped', 'source', '1/2', '2/2']);
  assert.equal(common.strategy.matrix.target, '${{ fromJSON(needs.select-targets.outputs.targets) }}');
  assert.deepEqual(common.strategy.matrix.partition, ['1/4', ...nativeCoreLinuxCommonPartitions]);
  const rows = job => ['js', 'wasm', 'native'].flatMap(target => job.strategy.matrix.partition.map(partition => ({target, partition})))
    .filter(row => !job.strategy.matrix.exclude.some(x => x.target === row.target && x.partition === row.partition));
  const selected = [{target: 'js', partition: '1/4'}, ...rows(common), ...nativeCoreCiPartitions.map(partition => ({target: 'native', partition}))];
  assert.equal(selected.length, 14);
  assert.equal(new Set(selected.map(row => JSON.stringify(row))).size, 14);
  assert.deepEqual(selected, [{target: 'js', partition: '1/4'}, {target: 'wasm', partition: '1/4'},
    ...nativeCoreLinuxCommonPartitions.map(partition => ({target: 'native', partition})),
    ...nativeCoreCiPartitions.map(partition => ({target: 'native', partition}))]);
  assert.equal(common.steps, darwin.steps, 'One YAML-anchored step owner preserves all original commands and environments');
  assert.deepEqual(js.needs, ['select-targets']);
  assert.deepEqual(common.needs, ['select-targets']);
  assert.deepEqual(darwin.needs, ['select-targets', 'lint', 'core-js']);
  for (const job of [js, common, darwin]) {
    assert.equal(job.strategy['fail-fast'], false);
    assert.equal(job['timeout-minutes'], "${{ matrix.target == 'native' && 90 || 30 }}");
  }
  assert(darwin.if.includes("contains(fromJSON(needs.select-targets.outputs.targets), 'native')"));
});

test('Core runner aggregate requires every selected matrix and refuses missing failed or skipped work', () => {
  const core = workflow.jobs.core;
  assert.deepEqual(core.needs, ['select-targets', 'core-js', 'core-common', 'core-darwin']);
  assert.equal(core['runs-on'], 'ubuntu-24.04');
  assert(core.if.includes('always()'));
  assert.equal(core['timeout-minutes'], 5);
  const step = core.steps[0];
  assert.deepEqual(step.env, {CORE_TARGETS: '${{ needs.select-targets.outputs.targets }}',
    JS_RESULT: '${{ needs.core-js.result }}', COMMON_RESULT: '${{ needs.core-common.result }}', DARWIN_RESULT: '${{ needs.core-darwin.result }}'});
  const run = values => spawnSync('bash', ['-eo', 'pipefail', '-c', step.run], {
    encoding: 'utf8', timeout: 5000, env: {...process.env, ...values},
  });
  for (const targets of [['js'], ['wasm'], ['native'], ['js', 'wasm'], ['js', 'native'], ['wasm', 'native'], ['js', 'wasm', 'native']]) {
    const success = {CORE_TARGETS: JSON.stringify(targets),
      JS_RESULT: targets.includes('js') ? 'success' : 'skipped',
      COMMON_RESULT: targets.some(target => target === 'wasm' || target === 'native') ? 'success' : 'skipped',
      DARWIN_RESULT: targets.includes('native') ? 'success' : 'skipped'};
    assert.equal(run(success).status, 0);
    for (const key of ['JS_RESULT', 'COMMON_RESULT', 'DARWIN_RESULT'])
      for (const value of ['success', 'failure', 'cancelled', 'skipped', ''])
        if (value !== success[key]) assert.notEqual(run({...success, [key]: value}).status, 0);
  }
  for (const targets of ['', '[]', 'null', '["other"]', '["native","native"]', 'invalid'])
    assert.notEqual(run({CORE_TARGETS: targets, JS_RESULT: 'success', COMMON_RESULT: 'success', DARWIN_RESULT: 'success'}).status, 0);
});

test('normal Native object caching selects ordinary and Scoped jobs and retains their complete Core command', () => {
  assert.equal(workflow.on.workflow_dispatch.inputs.ordinary_native_c_cache, undefined);
  const steps = workflow.jobs['core-darwin'].steps;
  const prepare = steps.find(step => step.id === 'native-c-object-cache');
  const restore = steps.find(step => step.id === 'native-c-object-cache-restore');
  const mark = steps.find(step => step.name === 'Mark current-job Native C compiler diagnostics');
  const save = steps.find(step => step.name === 'Save ordinary Native C objects');
  assert(prepare && restore && mark && save);
  const evaluate = (target, partition) => runInNewContext(
    prepare.if.replace(/^\$\{\{\s*|\s*\}\}$/gu, ''), {
      matrix: {target, partition},
      contains: (values, value) => values.includes(value), fromJSON: JSON.parse,
    });
  for (const target of ['js', 'wasm', 'native'])
    for (const partition of ['1/2', '2/2', 'source', 'scoped'])
      assert.equal(evaluate(target, partition), target === 'native' && ['1/2', '2/2', 'scoped'].includes(partition));
  const action = 'actions/cache/';
  const pin = '@caa296126883cff596d87d8935842f9db880ef25';
  assert.equal(restore.uses, action + 'restore' + pin);
  assert.equal(save.uses, action + 'save' + pin);
  assert.equal(restore.if, "${{ steps.native-c-object-cache.outcome == 'success' }}");
  assert.equal(mark.if, restore.if);
  assert(save.if.includes('success()') && save.if.includes("outputs.cache-hit != 'true'"));
  assert.equal(restore.with.key, '${{ steps.native-c-object-cache.outputs.key-prefix }}${{ github.sha }}');
  assert.equal(restore.with['restore-keys'], '${{ steps.native-c-object-cache.outputs.key-prefix }}');
  assert.equal(save.with.key, '${{ steps.native-c-object-cache-restore.outputs.cache-primary-key }}');
  assert.equal(restore.with.path, save.with.path);
  assert.equal(restore.with.path.trim(), [
    '${{ runner.temp }}/actql-core-ordinary-c-cache',
    '!${{ runner.temp }}/actql-core-ordinary-c-cache/tmp',
    '!${{ runner.temp }}/actql-core-ordinary-c-cache/compiler.log',
  ].join('\n'));
  assert(prepare.run.includes('nativeCoreCCachePin'));
  assert(prepare.run.includes('pin.archiveSha256') && prepare.run.includes('pin.binarySha256'));
  assert(prepare.run.includes('SDKSettings.json') === false, 'actual compiler/SDK checking belongs to the wrapper');
  assert(prepare.run.includes('--strip-components=1'));
  assert(prepare.run.includes('ACTQL_TEST_NATIVE_CORE_CCACHE=') &&
    prepare.run.includes('ACTQL_TEST_NATIVE_CORE_CCACHE_DIR='));
  assert(prepare.run.includes('process.env.ImageVersion') && prepare.run.includes('toolchain.json'));
  const compile = steps.findIndex(step => step.name === 'Test common core');
  assert(steps.indexOf(prepare) < steps.indexOf(restore) && steps.indexOf(restore) < compile);
  assert(steps.indexOf(restore) < steps.indexOf(mark));
  assert(steps.indexOf(mark) < steps.findIndex(step => step.name === 'Check common core'));
  assert(steps.indexOf(save) > compile);
  const source = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
  assert.equal(source.split('ACTQL_TEST_NATIVE_CORE_CCACHE=').length - 1, 1);
  assert(steps[compile].run.includes('MOONBIT_NEW_NATIVE=0 node scripts/test-native-core.mjs --deny-warn --release --strip -j 2 --no-parallelize --verbose'));
  assert.equal(workflow.jobs['core-darwin']['timeout-minutes'], "${{ matrix.target == 'native' && 90 || 30 }}");
});

test('actual Native cache preparation admits only selected halves and Scoped while preserving both digest guards', t => {
  const prepare = workflow.jobs['core-darwin'].steps.find(step => step.id === 'native-c-object-cache');
  const match = /^node --input-type=module <<'NODE'\n([\s\S]+)\nNODE\s*$/u.exec(prepare.run);
  assert(match, 'Execute the real workflow Node entry');
  const body = parseJavaScript(match[1], {ecmaVersion: 'latest', sourceType: 'module'}).body
    .filter(node => node.type !== 'ImportDeclaration').map(node => match[1].slice(node.start, node.end)).join('\n');
  const parent = mkdtempSync(join(tmpdir(), 'actql-cache-admission-'));
  t.after(() => rmSync(parent, {recursive: true, force: true}));
  const archive = Buffer.from('independent test-only original ccache archive');
  const binary = Buffer.from('independent test-only original ccache executable');
  const hash = bytes => createHash('sha256').update(bytes).digest('hex');
  const pin = {...nativeCoreCCachePin, archiveSha256: hash(archive), binarySha256: hash(binary)};
  let ordinal = 0;
  const invoke = (partition, {badArchive = false, badBinary = false, image = 'fixture-image'} = {}) => {
    const root = join(parent, String(ordinal++)); mkdirSync(root, {mode: 0o700});
    const output = join(root, 'output'), environment = join(root, 'environment'), calls = [];
    const tool = join(root, 'actql-core-ordinary-c-cache-tool'), executable = join(tool, 'ccache');
    let error;
    try { runInNewContext(body, {
      assert, createHash, appendFileSync, chmodSync, lstatSync, mkdirSync, readFileSync, join, pin,
      process: {platform: 'darwin', arch: 'arm64', cwd: () => '/original/source',
        env: {RUNNER_TEMP: root, CACHE_PARTITION: partition, ImageVersion: image,
          GITHUB_OUTPUT: output, GITHUB_ENV: environment}},
      execFileSync(command, args, options) {
        calls.push(command);
        if (command === '/usr/bin/curl') {
          assert.deepEqual(JSON.parse(JSON.stringify(args)), ['--fail', '--location', '--silent', '--show-error',
            '--connect-timeout', '20', '--max-time', '60', pin.url, '--output', join(tool, 'original.tar.gz')]);
          assert.equal(options.timeout, 65000);
          writeFileSync(args.at(-1), badArchive ? Buffer.from('changed archive') : archive);
        } else if (command === '/usr/bin/tar') {
          assert.deepEqual(JSON.parse(JSON.stringify(args)), ['-xzf', join(tool, 'original.tar.gz'), '-C', tool,
            '--strip-components=1', `ccache-${pin.version}-darwin/ccache`]);
          writeFileSync(executable, badBinary ? Buffer.from('changed binary') : binary);
        } else {
          assert.equal(command, executable); assert.deepEqual(JSON.parse(JSON.stringify(args)), ['--version']);
          assert.equal(lstatSync(executable).mode & 0o777, 0o700);
        }
      },
    }); } catch (cause) { error = cause; }
    return {error, calls, executable,
      output: existsSync(output) ? readFileSync(output, 'utf8') : '',
      environment: existsSync(environment) ? readFileSync(environment, 'utf8') : ''};
  };
  const prefixes = new Set();
  for (const partition of ['1/2', '2/2', 'scoped']) {
    const actual = invoke(partition); assert.ifError(actual.error);
    assert.equal(actual.calls.length, 3);
    assert.match(actual.output, /^key-prefix=ordinary-c-v1-darwin-arm64-fixture-image-[a-f0-9]{64}-/u);
    assert(actual.output.endsWith(`-${partition}-\n`)); prefixes.add(actual.output);
    assert(actual.environment.includes(`ACTQL_TEST_NATIVE_CORE_CCACHE=${actual.executable}\n`));
    assert.equal(actual.environment.includes('ACTQL_TEST_NATIVE_CORE_SCOPED_SOFTWARE_ROOT='), partition === 'scoped');
  }
  assert.equal(prefixes.size, 3, 'Each actual partition retains an independent source/profile cache key');
  for (const partition of ['1/4', '4/4', '0/2', '3/2', '1/8', 'linux-common-1/8', 'source', 'http', 'scoped-copy', '', undefined]) {
    const actual = invoke(partition);
    assert.equal(actual.error?.code, 'ERR_ASSERTION', String(partition));
    assert.equal(actual.output, ''); assert.equal(actual.environment, '');
  }
  for (const [options, calls] of [[{badArchive: true}, 1], [{badBinary: true}, 2], [{image: 'bad/image'}, 3]]) {
    const actual = invoke('1/2', options);
    assert.equal(actual.error?.code, 'ERR_ASSERTION'); assert.equal(actual.calls.length, calls);
    assert.equal(actual.output, ''); assert.equal(actual.environment, '');
  }
});

function compilerDiagnosticsFixture(t, prior = '') {
  const root = mkdtempSync(join(tmpdir(), 'actql-current-compiler-log-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const cache = join(root, 'cache'); mkdirSync(cache);
  const log = join(cache, 'compiler.log'), object = join(cache, 'retained.o');
  if (prior) writeFileSync(log, prior);
  writeFileSync(object, Buffer.from([0, 127, 255, 42]));
  const original = lstatSync(object);
  const steps = workflow.jobs['core-darwin'].steps;
  const mark = steps.find(step => step.name === 'Mark current-job Native C compiler diagnostics');
  const report = steps.find(step => step.name === 'Report ordinary Native C cache results');
  const run = step => spawnSync('bash', ['-eo', 'pipefail', '-c', step.run], {
    encoding: 'utf8', timeout: 5000,
    env: {...process.env, RUNNER_TEMP: root, ACTQL_TEST_NATIVE_CORE_CCACHE_DIR: cache},
  });
  const retained = () => {
    const after = lstatSync(object);
    assert.deepEqual([after.dev, after.ino, after.mode], [original.dev, original.ino, original.mode]);
    assert.deepEqual(readFileSync(object), Buffer.from([0, 127, 255, 42]));
  };
  return {log, mark, report, run, retained};
}

test('Native C diagnostics exclude restored compiler records and count only appended current-job results', t => {
  const prior = '[old] Result: cache_miss\nACTQL_NATIVE_C_LINK {"status":0,"signal":null,"error":null}\n';
  const f = compilerDiagnosticsFixture(t, prior);
  if (f.mark) assert.equal(f.run(f.mark).status, 0);
  assert.equal(readFileSync(f.log, 'utf8'), prior, 'Keep restored diagnostic bytes');
  appendFileSync(f.log, '[new] Result: preprocessed_cache_hit\n' +
    'ACTQL_NATIVE_C_LINK {"status":0,"signal":null,"error":null}\n' +
    'ACTQL_NATIVE_C_LINK {"status":7,"signal":null,"error":null}\n');
  const result = f.run(f.report);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, 'Current-job compiler cache result keys: {"preprocessed_cache_hit":1}\n' +
    'Current-job fresh links: {"attempts":2,"succeeded":1}\n');
  assert(f.mark);
  f.retained();
});

test('Native C diagnostics accept an empty restore without creating or clearing compiler objects', t => {
  const f = compilerDiagnosticsFixture(t);
  assert(f.mark);
  assert.equal(f.run(f.mark).status, 0);
  const result = f.run(f.report);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, 'Current-job compiler cache result keys: {}\n' +
    'Current-job fresh links: {"attempts":0,"succeeded":0}\n');
  f.retained();
});

test('Native C diagnostics refuse a replaced or truncated restored prefix instead of misreporting current work', t => {
  for (const changed of ['[old] Result: cache_hit\n', '']) {
    const f = compilerDiagnosticsFixture(t, '[old] Result: cache_miss\n');
    assert(f.mark);
    assert.equal(f.run(f.mark).status, 0);
    writeFileSync(f.log, changed);
    const result = f.run(f.report);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Restored compiler log prefix changed/u);
    assert.equal(result.stdout, '');
    f.retained();
  }
});

test('every original Native command and environment has one same-VM execution owner', () => {
  for (const [family, obligations] of Object.entries(original.jobs)) {
    validateGroups(background[family]);
    const workload = workflow.jobs[family + '-workloads'];
    const http = workflow.jobs[family === 'native' ? 'native-http' : 'native-http-macos'];
    const cases = [...workload.steps, ...http.steps, ...background[family].flatMap(group => group.steps)]
      .filter(step => step.run && /^(?:Test |Verify registered)/u.test(step.name ?? ''));
    const transferred = family === 'native-macos' ? new Set(original.macosLinuxCounterparts.map(row => row.name)) : new Set();
    const selected = obligations.filter(row => !transferred.has(row.name));
    assert.deepEqual(cases.map(step => step.name).sort(), selected.map(step => step.name).sort());
    for (const expected of selected) {
      const matches = cases.filter(step => step.name === expected.name);
      assert.equal(matches.length, 1, expected.name);
      assert.equal(createHash('sha256').update(matches[0].run).digest('hex'), expected.commandSha256, expected.name);
      assert.deepEqual(matches[0].env ?? {}, expected.env, expected.name);
    }
  }
});

test('macOS removes only the five decided duplicates with unchanged Linux execution owners', () => {
  assert.deepEqual(original.macosLinuxCounterparts.map(row => row.name), [
    'Test Native Salesforce Effect preview', 'Test Native observation replay',
    'Test Native release recovery', 'Test Native remote runtime', 'Test Native Resident Effect computation',
  ]);
  const linux = [...workflow.jobs['native-workloads'].steps, ...background.native.flatMap(group => group.steps)];
  const mac = [...workflow.jobs['native-macos-workloads'].steps, ...background['native-macos'].flatMap(group => group.steps)];
  for (const row of original.macosLinuxCounterparts) {
    assert.equal(row.job, 'native-workloads');
    assert.equal(mac.filter(step => step.name === row.name).length, 0);
    const matches = linux.filter(step => step.id === row.id && step.name === row.name);
    assert.equal(matches.length, 1, row.name);
    const expected = original.jobs.native.find(step => step.name === row.name);
    assert.equal(createHash('sha256').update(matches[0].run).digest('hex'), expected.commandSha256);
    assert.deepEqual(matches[0].env ?? {}, expected.env);
  }
  assert.deepEqual(background['native-macos'].map(group => group.steps.map(step => step.id ?? step.name)), [
    ['Verify native macOS arm64 profile', 'Test finite original SQLite statement and selected API custody',
      'Test native macOS retained task file ownership', 'native-http', 'native-bundle-cli', 'native-publication-lock'],
    ['native-source', 'native-cancel', 'native-http-controls'],
  ]);
});

test('Linux HTTP remains independent while macOS HTTP shares the original same-VM preparation', () => {
  const httpSource = readFileSync(new URL('./test-native-http-client.mjs', import.meta.url), 'utf8');
  assert(!httpSource.includes('native-runtime-bundle-fixture.mjs'));
  assert(!httpSource.includes('ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION'));
  for (const family of ['native', 'native-macos']) {
    const workload = workflow.jobs[family + '-workloads'];
    const http = family === 'native' ? 'native-http' : 'native-http-macos';
    assert.deepEqual(workflow.jobs[http].needs, ['select-targets', ...(family === 'native-macos' ? ['native-macos-workloads', 'native-http', 'core'] : [])]);
    assert.deepEqual(workload.needs, ['select-targets']);
    assert.equal(workload.strategy, undefined);
    assert.equal(workload.steps.filter(step => step.run?.includes('prepare-native-runtime-bundle-fixture.mjs')).length, 1);
    assert(!workload.steps.some(step => step.uses === './.github/actions/download-client-packages'));
    const preparation = workload.steps.findIndex(step => step.id === 'native-preparation');
    const start = workload.steps.findIndex(step => step.id === 'native-background-start');
    const effect = workload.steps.findIndex(step => step.id === 'native-effect');
    const site = workload.steps.findIndex(step => step.id === 'native-runtime-test');
    const join = workload.steps.findIndex(step => step.id === 'native-background');
    assert(preparation < start && start < site && site < join);
    if (family === 'native') {
      assert(start < effect && effect < site);
      const retained = workload.steps.findIndex(step => step.name === 'Verify registered Native retained product path');
      assert(retained > join, 'The long retained compiler cannot hold the global Moon lock during npm prepack');
      assert.equal(workload.steps[retained].if,
        "${{ !cancelled() && steps.native-preparation.outcome == 'success' && steps.native-background.outcome == 'success' }}");
      const condition = workload.steps[retained].if.slice(3, -2)
        .replaceAll('steps.native-preparation.outcome', 'prepared')
        .replaceAll('steps.native-background.outcome', 'joined');
      for (const joined of ['success', 'failure', 'cancelled', 'skipped', undefined])
        assert.equal(runInNewContext(condition, {prepared: 'success', joined, cancelled: () => false}),
          joined === 'success', 'A failed or unconfirmed join cannot authorize another compiler');
      assert(!background[family].flatMap(group => group.steps).some(step =>
        step.name === 'Verify registered Native retained product path'));
    } else {
      assert.equal(effect, -1, 'Linux owns the complete unchanged Effect case');
      assert(workload.steps.slice(join + 1).every(step => step.run === undefined));
      const runtime = background[family].find(group => group.name === 'runtime');
      const consumer = runtime.steps.findIndex(step => step.id === 'native-http');
      assert(consumer > runtime.steps.findIndex(step => step.run === 'npm run check:native-retained-task-file'),
        'The HTTP compiler follows the existing Moon-writing check in the same ordered group');
      assert.equal(runtime.steps[consumer].timeoutMinutes, 115);
      assert.equal(workload.outputs['native-http-result'], '${{ steps.native-background.outputs.native-http-result }}');
      const installer = readFileSync(new URL('./native-application-bundle-fixture.mjs', import.meta.url), 'utf8');
      assert(installer.includes('const runtimeBundleExecutable = prepareNativeRuntimeBundle(repositoryRoot,'));
      assert(installer.includes('const runtimeBundleLibraries = prepareNativeRuntimeBundleLibraries(repositoryRoot,'));
    }
    assert.equal(workload.steps[start].if, "${{ !cancelled() && steps.native-preparation.outcome == 'success' }}");
    assert(workload.steps[join].if.includes("steps.native-background-start.outcome == 'success'"));
    assert(workload.steps[join].run.includes('steps.native-background-start.outputs.directory'));
    assert(workflow.jobs[family].needs.includes(family + '-workloads'));
    assert(workflow.jobs[family].needs.includes(http));
    assert(gateJobs.includes(family)); assert(workflow.jobs.check.needs.includes(family));
  }
  const portable = selectTargets(['README.md']);
  assert.equal(gateJobRequired(portable, 'native-macos'), portable.macos);
});

test('original Native aggregate refuses every missing failed cancelled or skipped required child', () => {
  for (const family of ['native', 'native-macos']) {
    const job = workflow.jobs[family];
    assert(job.if.includes('always()'));
    const code = /^node -e '\n([\s\S]*)'\n?$/u.exec(job.steps[0].run)?.[1];
    assert(code);
    const complete = Object.fromEntries(job.needs.map(name => [name, {result: 'success'}]));
    const evaluate = results => {
      const process = {env: {RESULTS: JSON.stringify(results)}};
      runInNewContext(code, {process, console: {error() {}}});
      return process.exitCode ?? 0;
    };
    assert.equal(evaluate(complete), 0);
    for (const dependency of [family + '-workloads', family === 'native' ? 'native-http' : 'native-http-macos']) {
      for (const result of ['failure', 'cancelled', 'skipped', undefined])
        assert.equal(evaluate({...complete, [dependency]: {result}}), 1, `${dependency}:${result}`);
      const missing = {...complete}; delete missing[dependency]; assert.equal(evaluate(missing), 1);
    }
  }
});

test('local Native route retains every original case serially with one preparation and no hosted worker', () => {
  const output = execFileSync(process.execPath, ['scripts/local-checks.mjs', 'run', 'native', '--dry-run'], {
    cwd: new URL('../', import.meta.url), encoding: 'utf8', timeout: 5000,
  });
  for (const {name} of original.jobs.native)
    assert.equal(output.split(`== native: ${name}\n`).length - 1, 1, name);
  assert.equal(output.split('node scripts/prepare-native-runtime-bundle-fixture.mjs').length - 1, 1);
  assert(!output.includes('ci-native-background-groups.mjs'));
  assert(!output.includes('native-ci-artifact.py'));
  assert(output.indexOf('== native: Verify registered Native retained product path\n') >
    output.indexOf('== native: Test packed Output report custody and ACK crash boundaries\n'));
});

test('required lint directly selects Native preparation controls and only macOS opts into isolated construction overlap',()=>{
  const required=workflow.jobs.lint.steps.filter(step=>step.name==='Test Native preparation originals and bounded compiler orchestration');
  assert.equal(required.length,1);assert.equal(required[0].if,undefined,'Drafts require these source/port controls too');
  assert.equal(required[0].run,'node --test scripts/native-preparation-originals.test.mjs scripts/native-runtime-bundle-fixture.test.mjs scripts/native-preparation-lanes.test.mjs scripts/native-remote-runtime-isolation.test.mjs scripts/native-core-linux-common.test.mjs scripts/native-http-phases.test.mjs');
  const core=workflow.jobs['core-darwin'].steps;
  const compiler=core.find(step=>step.name==='Test pinned Native C compiler orchestration');
  assert.equal(compiler.run,'node --test scripts/native-core-c-compiler.test.mjs');
  assert.equal(compiler.if,"${{ matrix.target == 'native' && matrix.partition == '1/2' }}");
  const setup=core.findIndex(step=>step.uses==='./.github/actions/setup-toolchain');
  assert(setup>=0&&setup<core.indexOf(compiler));
  assert(core.indexOf(compiler)<core.findIndex(step=>step.id==='native-c-object-cache'),
    'compiler controls retain their own clean profile before CI cache configuration');
  assert.equal(workflow.jobs['core-darwin']['runs-on'],'macos-15');
  const prepare=family=>workflow.jobs[family+'-workloads'].steps.find(step=>step.id==='native-preparation');
  assert(prepare('native-macos').run.endsWith('--resident-seconds 1200 --lanes 2'));
  assert(!prepare('native').run.includes('--lanes'));
  for(const family of ['native','native-macos'])assert.equal(prepare(family)['timeout-minutes'],family==='native'?65:70);
  const cli=readFileSync(new URL('./prepare-native-runtime-bundle-fixture.mjs',import.meta.url),'utf8');
  const awaited=cli.indexOf('?await prepareNativeParallel('),ready=cli.indexOf("writeFileSync(join(destination,'preparation.json')");
  const environment=cli.indexOf("if(process.env.GITHUB_ENV!==undefined)");
  assert(awaited>0&&ready>awaited&&environment>ready);
  assert.equal(cli.split("writeFileSync(join(destination,'preparation.json')").length-1,1);
});
