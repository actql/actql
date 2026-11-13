import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync,
  readdirSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {partJobs} from '../proofs/relation-pipeline/proof-parts.mjs';

const pipelineJobs = [...Object.values(partJobs), 'pipeline-validation', 'pipeline-evidence'];

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-local-checks-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  for (const directory of ['scripts', 'proofs/relation-pipeline', '.github/workflows', 'bin', 'home']) mkdirSync(join(root, directory), {recursive: true});
  for (const name of ['local-checks.mjs', 'local-checks-guard.mjs', 'local-checks-supervisor.mjs',
    'local-checks-policy.mjs', 'test-execution.mjs', 'test-execution-reporter.mjs', 'packed-query-evidence.mjs']) {
    copyFileSync(new URL(name, import.meta.url), join(root, 'scripts', name));
  }
  copyFileSync(new URL('../proofs/relation-pipeline/proof-parts.mjs', import.meta.url),
    join(root, 'proofs/relation-pipeline/proof-parts.mjs'));
  symlinkSync(new URL('../node_modules', import.meta.url), join(root, 'node_modules'));
  const job = {steps: [{name: 'actual job step', env: {EXPECTED: 'from workflow'},
    run: 'printf "%s\\n" "$EXPECTED" >> calls; printf "done\\n"'}], 'timeout-minutes': 20};
  const pipelineJob = {steps: [{name: 'CI provenance step',
    run: 'printf "%s\\n" "${{ github.sha }}" "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT" "$GITHUB_OUTPUT" >> calls'}],
    'timeout-minutes': 60};
  writeFileSync(join(root, '.github/workflows/ci.yml'), JSON.stringify({jobs: {
    lint: job, core: job, future: job, 'native-macos': job,
    ...Object.fromEntries(pipelineJobs.map(name => [name, pipelineJob])),
  }}));
  const moon = join(root, 'bin/moon');
  writeFileSync(moon, `#!${process.execPath}\nconst fs=require('fs');
    fs.appendFileSync('moon-args',JSON.stringify(process.argv.slice(2))+'\\n');
    console.log('Total tests: 1, passed: 1, failed: 0.');\n`); chmodSync(moon, 0o755);
  const env = {...process.env, HOME: join(root, 'home'), PATH: join(root, 'bin') + ':' + process.env.PATH};
  delete env.NODE_TEST_CONTEXT;
  const run = (args, extraEnv = {}) => spawnSync(process.execPath, ['scripts/local-checks.mjs', ...args],
    {cwd: root, env: {...env, ...extraEnv}, encoding: 'utf8', timeout: 10_000});
  return {root, run};
}

test('list and dry-run execute nothing or create locks/evidence', t => {
  const f = fixture(t);
  assert.equal(f.run(['list']).status, 0);
  const dry = f.run(['run', 'core', '--dry-run']);
  assert.equal(dry.status, 0, dry.stderr);
  assert.match(dry.stdout, /actual job step/u);
  assert.equal(existsSync(join(f.root, '_build')), false);
  assert.equal(existsSync(join(f.root, 'calls')), false);
  assert.deepEqual(readdirSync(join(f.root, 'home')), []);
});

test('heavy jobs require deliberate override; light lint remains usable', t => {
  const f = fixture(t);
  const denied = f.run(['run', 'core']);
  assert.equal(denied.status, 2);
  assert.match(denied.stderr, /--allow-heavy/u);
  assert.equal(existsSync(join(f.root, 'calls')), false);
  assert.equal(f.run(['run', 'lint']).status, 0);
  const heavy = f.run(['run', 'core', '--allow-heavy']);
  assert.equal(heavy.status, 0, heavy.stderr);
  assert.match(heavy.stderr, /budget: 1200s/u);
  assert.equal(readFileSync(join(f.root, 'calls'), 'utf8'), 'from workflow\nfrom workflow\n');
});

test('required packed README job is classified and its exact command remains inspectable without execution', t => {
  const f = fixture(t), path = join(f.root, '.github/workflows/ci.yml');
  const workflow = JSON.parse(readFileSync(path, 'utf8'));
  const command = 'node scripts/test-packed-readme-workflows.mjs "$RUNNER_TEMP/client-readme-packed"';
  workflow.jobs['client-readme-packed'] = {steps: [{name: 'original packed README consumer', run: command}],
    'timeout-minutes': 15};
  writeFileSync(path, JSON.stringify(workflow));
  const denied = f.run(['run', 'client-readme-packed']);
  assert.equal(denied.status, 2); assert.match(denied.stderr, /--allow-heavy/u);
  assert.doesNotMatch(denied.stderr, /unclassified|No local cost classification/u);
  const dry = f.run(['run', 'client-readme-packed', '--allow-heavy', '--dry-run']);
  assert.equal(dry.status, 0, dry.stderr); assert(dry.stdout.includes(command));
  assert.equal(existsSync(join(f.root, 'calls')), false);
  assert.equal(existsSync(join(f.root, '_build')), false);
});

function coreBudget(fixture, value) {
  const path = join(fixture.root, '.github/workflows/ci.yml');
  const workflow = JSON.parse(readFileSync(path, 'utf8'));
  workflow.jobs.core['timeout-minutes'] = value;
  writeFileSync(path, JSON.stringify(workflow));
}

const nativeMatrixBudget = "${{ matrix.target == 'native' && 75 || 30 }}";

test('local Core uses original unpartitioned commands and budget after hosted matrix separation', t => {
  const f = fixture(t), path = join(f.root, '.github/workflows/ci.yml');
  const workflow = JSON.parse(readFileSync(path, 'utf8'));
  workflow.jobs['core-common'] = workflow.jobs.core;
  workflow.jobs.core = {steps: [{run: 'exit 91'}], 'timeout-minutes': 5};
  writeFileSync(path, JSON.stringify(workflow));
  const result = f.run(['run', 'core', '--allow-heavy']);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stderr, /budget: 1200s/u);
  assert.equal(readFileSync(join(f.root, 'calls'), 'utf8'), 'from workflow\n');
});

test('local Core adapter runs complete unpartitioned coverage for the hosted Native partition expression', t => {
  const f = fixture(t), path = join(f.root, '.github/workflows/ci.yml');
  const workflow = JSON.parse(readFileSync(path, 'utf8'));
  workflow.jobs.core.steps = [{name: 'original full selection',
    env: {TARGET: '${{ matrix.target }}', ACTQL_TEST_NATIVE_CORE_PARTITION:
      "${{ matrix.target == 'native' && matrix.partition || '' }}"},
    run: 'printf "%s:%s\\n" "$TARGET" "$ACTQL_TEST_NATIVE_CORE_PARTITION" >> calls'}];
  writeFileSync(path, JSON.stringify(workflow));
  for (const target of ['native', 'js', 'wasm']) {
    const result = f.run(['run', 'core', '--target', target, '--allow-heavy']);
    assert.equal(result.status, 0, result.stderr);
  }
  assert.equal(readFileSync(join(f.root, 'calls'), 'utf8'), 'native:\njs:\nwasm:\n');
});

test('local Core adapter keeps full coverage without inventing or inheriting a hosted Moon plan', t => {
  const f = fixture(t), path = join(f.root, '.github/workflows/ci.yml');
  const workflow = JSON.parse(readFileSync(path, 'utf8'));
  workflow.jobs.core.steps = [{name:'original full local selection',
    env:{CI_PLAN:'${{ needs.select-targets.outputs.plan }}'},
    run:'if [ "${{ needs.select-targets.outputs.moon_test_selection }}" = true ]; then exit 99; fi\n' +
      'printf "%s:%s\\n" "${{ matrix.target }}" "$CI_PLAN" >> calls'}];
  writeFileSync(path, JSON.stringify(workflow));
  for (const target of ['native', 'js', 'wasm']) {
    const result = f.run(['run', 'core', '--target', target, '--allow-heavy'],
      {CI_PLAN:'{"selection":{"moonTests":{"foreign":true}}}'});
    assert.equal(result.status, 0, result.stderr);
  }
  assert.equal(readFileSync(join(f.root, 'calls'), 'utf8'), 'native:\njs:\nwasm:\n');
  for (const value of ['${{ needs.other.outputs.plan }}', '{"selection":{"moonTests":{}}}']) {
    workflow.jobs.core.steps[0].env.CI_PLAN = value;
    writeFileSync(path, JSON.stringify(workflow));
    const refused = f.run(['run', 'core', '--target', 'js', '--allow-heavy']);
    assert.equal(refused.status, 2);
    assert.match(refused.stderr, /local CI must retain complete coverage/u);
  }
  assert.equal(readFileSync(join(f.root, 'calls'), 'utf8'), 'native:\njs:\nwasm:\n');
});

test('local Core adapter excludes inherited inline and file plans on every backend', t => {
  const f = fixture(t), path = join(f.root, '.github/workflows/ci.yml');
  const workflow = JSON.parse(readFileSync(path, 'utf8'));
  workflow.jobs.core.steps = [{name: 'original full local file selection',
    env: {CI_PLAN_PATH: '${{ runner.temp }}/actql-ci-plan.json'},
    run: 'if [ -n "$CI_PLAN_PATH" ]; then exit 99; fi\n' +
      'printf "%s:%s:%s\\n" "${{ matrix.target }}" "$CI_PLAN" "$CI_PLAN_PATH" >> calls'}];
  writeFileSync(path, JSON.stringify(workflow));
  for (const target of ['native', 'js', 'wasm']) {
    const result = f.run(['run', 'core', '--target', target, '--allow-heavy'],
      {CI_PLAN: '{"selection":{"moonTests":{"foreign":true}}}', CI_PLAN_PATH: '/foreign/plan.json'});
    assert.equal(result.status, 0, result.stderr);
  }
  assert.equal(readFileSync(join(f.root, 'calls'), 'utf8'), 'native::\njs::\nwasm::\n');
  workflow.jobs.core.steps[0].env.CI_PLAN_PATH = '${{ needs.other.outputs.path }}';
  writeFileSync(path, JSON.stringify(workflow));
  const refused = f.run(['run', 'core', '--target', 'js', '--allow-heavy']);
  assert.equal(refused.status, 2);
  assert.match(refused.stderr, /local CI must retain complete coverage/u);
});

test('local Core adapter refuses a literal half or unfamiliar partition instead of narrowing coverage', t => {
  const f = fixture(t), path = join(f.root, '.github/workflows/ci.yml');
  const workflow = JSON.parse(readFileSync(path, 'utf8'));
  for (const value of ['1/2', '2/2', '${{ matrix.partition }}/2']) {
    workflow.jobs.core.steps = [{name: 'must not run half',
      env: {ACTQL_TEST_NATIVE_CORE_PARTITION: value}, run: 'printf bad >> calls'}];
    writeFileSync(path, JSON.stringify(workflow));
    const result = f.run(['run', 'core', '--target', 'native', '--allow-heavy']);
    assert.equal(result.status, 2); assert.match(result.stderr, /complete coverage/u);
    assert.equal(existsSync(join(f.root, 'calls')), false);
  }
});

test('Core job matrix budgets preserve Native and portable workflow rows', t => {
  const f = fixture(t);
  coreBudget(f, nativeMatrixBudget);
  for (const [target, seconds] of [['native', 4500], ['js', 1800], ['wasm', 1800]]) {
    const result = f.run(['run', 'core', '--allow-heavy', '--target', target]);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, new RegExp(`budget: ${seconds}s`, 'u'));
  }
  assert.equal(readFileSync(join(f.root, 'calls'), 'utf8'), 'from workflow\n'.repeat(3));
});

test('focused Moon matrix budgets preserve the exact target and test/build arguments', t => {
  const f = fixture(t);
  coreBudget(f, nativeMatrixBudget);
  const expected = [];
  for (const [flag, target, seconds] of [['--target', 'native', 4500], ['--target=js', 'js', 1800]]) {
    const args = [flag, ...(flag === '--target' ? [target] : []), '-p', 'query_integration'];
    const result = f.run(['test', 'moon', '--', ...args]);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, new RegExp(`budget: ${seconds}s`, 'u'));
    expected.push(['test', ...args]);
  }
  const build = f.run(['build', 'moon', '--', '--target=native', 'src/query_integration']);
  assert.equal(build.status, 0, build.stderr);
  assert.match(build.stderr, /budget: 4500s/u);
  expected.push(['build', '--target=native', 'src/query_integration']);
  assert.deepEqual(readFileSync(join(f.root, 'moon-args'), 'utf8').trim().split('\n').map(JSON.parse), expected);
});

test('unknown workflow expressions require an explicit budget and are never evaluated', t => {
  const f = fixture(t);
  coreBudget(f, "${{ matrix.target == 'native' && 40 || process.exit(99) }}");
  for (const args of [['run', 'core', '--allow-heavy', '--target', 'native'],
    ['test', 'moon', '--', '--target', 'js', '-p', 'query_integration']]) {
    const denied = f.run(args);
    assert.equal(denied.status, 2);
    assert.match(denied.stderr, /supply --timeout-seconds/u);
  }
  assert.equal(existsSync(join(f.root, 'calls')), false);
  assert.equal(existsSync(join(f.root, 'moon-args')), false);
  assert.equal(existsSync(join(f.root, '_build')), false);
  for (const args of [['run', 'core', '--allow-heavy', '--target', 'native', '--timeout-seconds', '7'],
    ['test', 'moon', '--timeout-seconds', '7', '--', '--target', 'js', '-p', 'query_integration']]) {
    const result = f.run(args);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, /budget: 7s/u);
  }
});

test('ambiguous and unsupported Moon matrix targets keep explicit-budget admission', t => {
  const f = fixture(t);
  coreBudget(f, nativeMatrixBudget);
  for (const args of [['--target', 'js', '--target', 'native'], ['--target=all']]) {
    const result = f.run(['test', 'moon', '--', ...args, '-p', 'query_integration']);
    assert.equal(result.status, 2);
    assert.match(result.stderr, /supply --timeout-seconds/u);
  }
  assert.equal(existsSync(join(f.root, 'moon-args')), false);
});

test('CI-only pipeline wrappers refuse even heavy overrides and supplied GitHub metadata without side effects', t => {
  const f = fixture(t);
  for (const name of pipelineJobs) {
    for (const options of [[], ['--allow-heavy'], ['--allow-heavy', '--timeout-seconds', '7']]) {
      const refused = f.run(['run', name, ...options], {
        GITHUB_SHA: 'a'.repeat(40), GITHUB_RUN_ID: '123', GITHUB_RUN_ATTEMPT: '1',
        GITHUB_OUTPUT: join(f.root, 'github-output'),
      });
      assert.equal(refused.status, 2, refused.stderr);
      assert.match(refused.stderr, new RegExp(`${name} is CI only`, 'u'));
      assert.match(refused.stderr, /--allow-heavy cannot enable this job locally; use hosted CI/u);
    }
  }
  for (const path of ['calls', '_build', '.artifacts', 'github-output']) {
    assert.equal(existsSync(join(f.root, path)), false, path);
  }
  assert.deepEqual(readdirSync(join(f.root, 'home')), []);
});

test('CI-only pipeline list and dry-run report literal commands without fake context or side effects', t => {
  const f = fixture(t);
  const listed = f.run(['list']);
  assert.equal(listed.status, 0, listed.stderr);
  for (const name of pipelineJobs) {
    assert.match(listed.stdout, new RegExp(`${name} \\(CI only:`, 'u'));
    for (const options of [['--dry-run'], ['--allow-heavy', '--dry-run']]) {
      const dry = f.run(['run', name, ...options]);
      assert.equal(dry.status, 0, dry.stderr);
      assert.match(dry.stdout, /CI only:.*\nLiteral workflow commands for inspection only:/u);
      assert.match(dry.stdout, /CI provenance step/u);
      assert.ok(dry.stdout.includes('${{ github.sha }}'));
      for (const variable of ['GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT', 'GITHUB_OUTPUT']) {
        assert.ok(dry.stdout.includes(`$${variable}`));
      }
      assert.doesNotMatch(dry.stdout, /"local"/u);
    }
  }
  // The pre-existing CI-only job routes still refuse, including dry-run.
  assert.equal(f.run(['run', 'native-macos', '--dry-run']).status, 2);
  for (const path of ['calls', '_build', '.artifacts']) {
    assert.equal(existsSync(join(f.root, path)), false, path);
  }
  assert.deepEqual(readdirSync(join(f.root, 'home')), []);
});

test('changed pipeline paths report all CI-only wrappers without suggesting a heavy bypass', t => {
  const f = fixture(t);
  const git = join(f.root, 'bin/git');
  writeFileSync(git, `#!${process.execPath}\nconsole.log('proofs/relation-pipeline/capacity/run.mjs');\n`);
  chmodSync(git, 0o755);
  const result = f.run(['changed']);
  assert.equal(result.status, 0, result.stderr);
  for (const name of pipelineJobs) {
    assert.match(result.stdout, new RegExp(`run ${name} --dry-run  # CI only:`, 'u'));
  }
  assert.doesNotMatch(result.stdout, /--allow-heavy/u);
  for (const path of ['calls', '_build', '.artifacts']) {
    assert.equal(existsSync(join(f.root, path)), false, path);
  }
  assert.deepEqual(readdirSync(join(f.root, 'home')), []);
});

test('unknown jobs/options are refused before execution', t => {
  const f = fixture(t);
  for (const args of [['run', 'future', '--allow-heavy'], ['run', 'core', '--all'],
    ['run', 'core', '--allow-heavy', '--target', 'unknown']]) {
    assert.equal(f.run(args).status, 2);
  }
  assert.equal(existsSync(join(f.root, 'calls')), false);
});

test('focused and full Moon routes retain exact test/build arguments', t => {
  const f = fixture(t);
  const focused = f.run(['test', 'moon', '--', '--target', 'js', '-p', 'query_integration']);
  assert.equal(focused.status, 0, focused.stderr);
  for (const action of ['test', 'build']) {
    assert.equal(f.run([action, 'moon', '--', '--target', 'js']).status, 2);
    const missingBudget = f.run([action, 'moon', '--allow-heavy', '--', '--target', 'js']);
    assert.equal(missingBudget.status, 2);
    assert.match(missingBudget.stderr, /supply --timeout-seconds/u);
    const full = f.run([action, 'moon', '--allow-heavy', '--timeout-seconds', '7', '--', '--target', 'js']);
    assert.equal(full.status, 0, full.stderr);
    assert.match(full.stderr, /budget: 7s/u);
  }
  assert.deepEqual(readFileSync(join(f.root, 'moon-args'), 'utf8').trim().split('\n').map(JSON.parse), [
    ['test', '--target', 'js', '-p', 'query_integration'], ['test', '--target', 'js'], ['build', '--target', 'js'],
  ]);
});

test('focused Node route preserves nonzero-execution refusal', t => {
  const f = fixture(t);
  writeFileSync(join(f.root, 'selected.test.mjs'), "import {test} from 'node:test'; test('selected',()=>{});\n");
  const passed = f.run(['test', 'node', '--', 'selected.test.mjs']);
  assert.equal(passed.status, 0, passed.stderr);
  const empty = f.run(['test', 'node', '--', '--test-name-pattern', 'absent', 'selected.test.mjs']);
  assert.equal(empty.status, 1, empty.stderr);
  assert.match(empty.stdout + empty.stderr, /no successfully executed test cases/u);
});

test('changed shared-core guidance stays advisory without executing gates', t => {
  const f = fixture(t);
  const git = join(f.root, 'bin/git');
  writeFileSync(git, `#!${process.execPath}\nconsole.log('src/source_span/span.mbt');\n`);
  chmodSync(git, 0o755);
  const result = f.run(['changed']);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Candidate narrow checks.*affected callers and validators/u);
  assert.match(result.stdout, /moon check --target js src\/source_span/u);
  assert.match(result.stdout, /Related CI jobs \(advisory inspection; not required local execution\)/u);
  assert.match(result.stdout, /matching-target diagnostics for native-only or FFI changes/u);
  assert.match(result.stdout, /not complete reverse-dependent coverage/u);
  assert.match(result.stdout, /exact-SHA CI; report executed and unverified coverage separately/u);
  assert.doesNotMatch(result.stdout, /before push|add --target wasm|verify the whole SHA/u);
  for (const path of ['calls', 'moon-args', '_build', '.artifacts']) {
    assert.equal(existsSync(join(f.root, path)), false, path);
  }
  assert.deepEqual(readdirSync(join(f.root, 'home')), []);
});

const inferAdmissionPaths = [
  'scripts/infer-host-fixtures.mjs',
  'scripts/check-canonical-json.mjs',
  'spec/contracts/actql-aoa.json',
  'spec/dependencies/aoa-pipeline-registry.json',
  'spec/local-check-environment.json',
  'src/stage_results/infer_program_test.mbt',
  'src/run_publication_host/client_infer_prefix_wbtest.mbt',
  'src/client_infer_host/fixture.generated_wbtest.mbt',
];
const inferFreshness = '  node scripts/infer-host-fixtures.mjs';
const inferCallers = '  node scripts/local-checks.mjs test moon -- --target js -p client_infer_host';

function changedPaths(f, paths) {
  const git = join(f.root, 'bin/git');
  writeFileSync(git, `#!${process.execPath}\nconsole.log(${JSON.stringify(paths.join('\n'))});\n`);
  chmodSync(git, 0o755);
  return f.run(['changed']);
}

function unchangedFixture(f) {
  for (const path of ['calls', 'moon-args', '_build', '.artifacts']) {
    assert.equal(existsSync(join(f.root, path)), false, path);
  }
  assert.deepEqual(readdirSync(join(f.root, 'home')), []);
}

test('known INFER hint paths retain the current generator and registry owners', () => {
  const source = readFileSync(new URL('infer-host-fixtures.mjs', import.meta.url), 'utf8');
  const aoa = JSON.parse(readFileSync(new URL('../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'));
  assert.equal(aoa.pipeline_registry_file, 'spec/dependencies/aoa-pipeline-registry.json');
  assert.match(source, /read\(\s*aoa\.pipeline_registry_file\)/u);
  assert.ok(source.includes("from './check-canonical-json.mjs'"));
  for (const path of inferAdmissionPaths.slice(2).filter(path => path !== aoa.pipeline_registry_file)) {
    assert.ok(source.includes(`'${path}'`), path);
  }
});

for (const path of inferAdmissionPaths) {
  test(`changed ${path} suggests the existing INFER checks without executing them`, t => {
    const f = fixture(t);
    const result = changedPaths(f, [path]);
    assert.equal(result.status, 0, result.stderr);
    const lines = result.stdout.split('\n');
    assert.equal(lines.filter(line => line === inferFreshness).length, 1);
    assert.equal(lines.filter(line => line === inferCallers).length, 1);
    assert.match(result.stdout, /Known INFER admission dependency \(advisory, incomplete\)/u);
    assert.match(result.stdout, /read-only freshness check requires the pinned MOON_HOME/u);
    assert.match(result.stdout, /no checks were executed/u);
    assert.match(result.stdout, /not complete reverse-dependent coverage/u);
    assert.doesNotMatch(result.stdout, /--write/u);
    unchangedFixture(f);
  });
}

test('multiple repeated INFER owner changes keep one deterministic pair of hints', t => {
  const f = fixture(t);
  const selected = output => output.split('\n')
    .filter(line => line === inferFreshness || line === inferCallers);
  const forward = changedPaths(f, [...inferAdmissionPaths, ...inferAdmissionPaths]);
  const reverse = changedPaths(f, [...inferAdmissionPaths].reverse());
  assert.equal(forward.status, 0, forward.stderr);
  assert.equal(reverse.status, 0, reverse.stderr);
  assert.deepEqual(selected(forward.stdout), [inferFreshness, inferCallers]);
  assert.deepEqual(selected(reverse.stdout), [inferFreshness, inferCallers]);
  unchangedFixture(f);
});

test('unrelated and similarly named changes do not claim an INFER dependency', t => {
  const f = fixture(t);
  const result = changedPaths(f, ['README.md', 'spec/contracts/actql-aoa.json.backup',
    'spec/dependencies/other-registry.json', 'src/source_span/span.mbt']);
  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(result.stdout, /INFER admission dependency|infer-host-fixtures|client_infer_host/u);
  unchangedFixture(f);
});

test('local Core keeps the original serial scoped profile despite hosted parallel scheduling and inherited jobs', t => {
  const f = fixture(t), path = join(f.root, '.github/workflows/ci.yml');
  const workflow = JSON.parse(readFileSync(path, 'utf8'));
  workflow.jobs.core.steps = [{name: 'original local scoped configuration',
    env: {ACTQL_TEST_NATIVE_CORE_SCOPED_JOBS:
      "${{ matrix.target == 'native' && matrix.partition == 'scoped' && '2' || '1' }}"},
    run: 'node -e "require(\'node:assert/strict\').equal(process.env.ACTQL_TEST_NATIVE_CORE_SCOPED_JOBS,\'1\')"; printf "%s\\n" "$ACTQL_TEST_NATIVE_CORE_SCOPED_JOBS" >> calls'}];
  writeFileSync(path, JSON.stringify(workflow));
  for (const target of ['native', 'js', 'wasm']) {
    const result = f.run(['run', 'core', '--target', target, '--allow-heavy'],
      {ACTQL_TEST_NATIVE_CORE_SCOPED_JOBS: '2'});
    assert.equal(result.status, 0, result.stderr);
  }
  assert.equal(readFileSync(join(f.root, 'calls'), 'utf8'), '1\n1\n1\n');
  for (const value of ['2', '${{ matrix.scoped_jobs }}', '']) {
    workflow.jobs.core.steps[0].env.ACTQL_TEST_NATIVE_CORE_SCOPED_JOBS = value;
    writeFileSync(path, JSON.stringify(workflow));
    const result = f.run(['run', 'core', '--target', 'native', '--allow-heavy']);
    assert.equal(result.status, 2); assert.match(result.stderr, /serial scoped profile/u);
  }
});


test('local distribution matrix retains one preparation and all four serial original scripts', t => {
  const f = fixture(t);
  const scripts = ['check-read-row-mutations.mjs', 'check-submission-input-mutations.mjs',
    'check-submission-check-observation-mutations.mjs', 'check-effect-uncertainty-mutations.mjs'];
  const job = {'timeout-minutes': 30, strategy: {matrix: {include: scripts.map((script, index) =>
    ({mutation: ['read-row', 'submission-input', 'submission-check-observation', 'effect-uncertainty'][index], script}))}},
    steps: [{name: 'Build original runtime', run: 'node scripts/original-preparation.mjs'},
      {name: 'Test check ${{ matrix.mutation }} mutations', run: 'node scripts/${{ matrix.script }}'}]};
  writeFileSync(join(f.root, '.github/workflows/ci.yml'), JSON.stringify({jobs: {'client-distribution-mutations': job}}));
  const result = f.run(['run', 'client-distribution-mutations', '--dry-run']);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.split('node scripts/original-preparation.mjs').length - 1, 1);
  for (const script of scripts) assert.equal(result.stdout.split('node scripts/' + script).length - 1, 1);
  assert(!result.stdout.includes('${{ matrix.'));
  job.strategy.matrix.include[3].script = scripts[0];
  writeFileSync(join(f.root, '.github/workflows/ci.yml'), JSON.stringify({jobs: {'client-distribution-mutations': job}}));
  assert.equal(f.run(['run', 'client-distribution-mutations', '--dry-run']).status, 2);
});
