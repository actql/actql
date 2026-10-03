import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync,
  readdirSync, rmSync, symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-local-checks-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  for (const directory of ['scripts', '.github/workflows', 'bin', 'home']) mkdirSync(join(root, directory), {recursive: true});
  for (const name of ['local-checks.mjs', 'local-checks-guard.mjs', 'local-checks-supervisor.mjs',
    'local-checks-policy.mjs', 'test-execution.mjs', 'test-execution-reporter.mjs', 'packed-query-evidence.mjs']) {
    copyFileSync(new URL(name, import.meta.url), join(root, 'scripts', name));
  }
  symlinkSync(new URL('../node_modules', import.meta.url), join(root, 'node_modules'));
  const job = {steps: [{name: 'actual job step', env: {EXPECTED: 'from workflow'},
    run: 'printf "%s\\n" "$EXPECTED" >> calls; printf "done\\n"'}], 'timeout-minutes': 20};
  const pipelineJob = {steps: [{name: 'CI provenance step',
    run: 'printf "%s\\n" "${{ github.sha }}" "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT" "$GITHUB_OUTPUT" >> calls'}],
    'timeout-minutes': 60};
  writeFileSync(join(root, '.github/workflows/ci.yml'), JSON.stringify({jobs: {
    lint: job, core: job, future: job, 'native-macos': job,
    'pipeline-mutations': pipelineJob, 'pipeline-capacity': pipelineJob, 'pipeline-mutations-rest': pipelineJob, 'pipeline-capacity-mutants': pipelineJob, 'pipeline-validation': pipelineJob, 'pipeline-evidence': pipelineJob,
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

test('CI-only pipeline wrappers refuse even heavy overrides and supplied GitHub metadata without side effects', t => {
  const f = fixture(t);
  for (const name of ['pipeline-mutations', 'pipeline-capacity', 'pipeline-mutations-rest', 'pipeline-capacity-mutants', 'pipeline-validation', 'pipeline-evidence']) {
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
  for (const name of ['pipeline-mutations', 'pipeline-capacity', 'pipeline-mutations-rest', 'pipeline-capacity-mutants', 'pipeline-validation', 'pipeline-evidence']) {
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
  for (const name of ['pipeline-mutations', 'pipeline-capacity', 'pipeline-mutations-rest', 'pipeline-capacity-mutants', 'pipeline-validation', 'pipeline-evidence']) {
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
