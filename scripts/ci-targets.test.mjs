import {partJobs} from '../proofs/relation-pipeline/proof-parts.mjs';
import {nativeCoreLinuxCommonPartitions} from './test-native-core-linux-common.mjs';
import {nativeCoreCiPartitions} from './ci-core-partitions.mjs';
import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, mkdirSync, rmSync, writeFileSync, chmodSync, symlinkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {runInNewContext} from 'node:vm';
import test from 'node:test';
import {parse} from 'yaml';
import {pullRequestDraft, readChanges, selectTargets, validateSelection, verifyGate, maintenanceFiles, documentationFiles, gateJobs, pythonWheelAcceptanceRequired, deepProofRequired, gateJobRequired, readPushChanges} from './ci-targets.mjs';
import {occurrences} from './check-owned-contract-versions.mjs';
import {prepareNativeRuntimeBundle} from './native-runtime-bundle-fixture.mjs';
import {readCiInput} from './ci-input.mjs';
const all = ['js', 'wasm', 'native'];
const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const {jobs} = workflow;
const nativeGroups = JSON.parse(readFileSync(new URL('./ci-native-background-groups.json', import.meta.url)));
const nativeWorkload = family => jobs[family + '-workloads'];
const nativeCases = family => [...nativeWorkload(family).steps,
  ...nativeGroups[family].flatMap(group => group.steps.map(step => ({...step, 'timeout-minutes': step.timeoutMinutes})))];
const nativeCaseCondition = (family, step) => step.if ??
  nativeWorkload(family).steps.find(value => value.id === 'native-background-start').if;

function nativeScratchSourceFixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-native-scratch-source-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const repository = join(root, 'checkout'), runner = join(root, 'runner-temp');
  mkdirSync(repository);mkdirSync(runner);
  const git = args => {
    const result = spawnSync('git', args, {cwd: repository, encoding: 'utf8', timeout: 5000});
    assert.equal(result.error, undefined);assert.equal(result.status, 0, result.stderr);
    return result.stdout;
  };
  git(['init', '--quiet']);
  writeFileSync(join(repository, 'source.txt'), 'Original tracked Source\n');
  git(['add', 'source.txt']);
  git(['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
    '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'Original Source']);
  const afterSourceAdmission = new Error('Source admitted before compiler selection');
  const prepare = () => prepareNativeRuntimeBundle(repository, join(root, 'bundle'), {
    platform: 'linux', arch: 'x64', moonHome: root,
    execute(command, args) {
      if (command === 'git') return git(args);
      assert.equal(command, 'sh');assert.deepEqual(args, ['-c', 'command -v clang']);
      // Stop before any compiler, producer, prepared artifact or Native Runtime.
      throw afterSourceAdmission;
    },
  });
  return {repository, runner, git, prepare, afterSourceAdmission};
}

test('Linux Native scratch output leaves Source clean for delayed bundle admission', t => {
  const f = nativeScratchSourceFixture(t);
  const step = jobs['native-http'].steps.find(row => row.name === 'Test Node-free native storage publication and control');
  const scratch = step.env.ACTQL_TEST_SCRATCH_ROOT
    .replaceAll('${{ github.workspace }}', f.repository)
    .replaceAll('${{ runner.temp }}', f.runner);
  mkdirSync(scratch, {recursive: true});
  const original = mkdtempSync(join(scratch, 'native-http-'));
  writeFileSync(join(original, 'original-fixture-output.txt'), 'Retained original output\n');
  assert.throws(f.prepare, error => error === f.afterSourceAdmission);
  assert.equal(f.git(['status', '--porcelain']), '');
  assert.equal(readFileSync(join(original, 'original-fixture-output.txt'), 'utf8'), 'Retained original output\n');
});

test('Native bundle Source admission still refuses untracked checkout scratch output', t => {
  const f = nativeScratchSourceFixture(t);
  mkdirSync(join(f.repository, '.native-tests'));
  writeFileSync(join(f.repository, '.native-tests', 'original-output.txt'), 'Retained output\n');
  assert.throws(f.prepare, /Clean fixed bundle build Source required/u);
  assert.equal(f.git(['status', '--porcelain']), '?? .native-tests/\n');
});

test('preflight checks Native counter assignments before the build toolchain', () => {
  const steps = jobs.preflight.steps;
  const index = steps.findIndex(row =>
    row.name === 'Check Native diagnostic counter assignments before fan-out');
  assert.ok(index >= 0);
  assert.equal(steps[index].run, 'python3 scripts/test_native_timings.py CommandCounterMap');
  assert.ok(index < steps.findIndex(row => row.name === 'Install pinned MoonBit'));
  assert.ok(!jobs.native.needs.includes('preflight'));
});

test('early Source admission runs original recipes once and refuses plan publication on failure', t => {
  const steps = jobs['select-targets'].steps, select = steps.find(step => step.id === 'select');
  const recipes = ['check:contract-versions', 'check:client-types'];
  for (const recipe of recipes) {
    const selected = Object.entries(jobs).flatMap(([job, value]) => (value.steps ?? [])
      .filter(step => step.run?.trim().split(/\s+/u).join(' ') === `npm run ${recipe}`)
      .map(step => ({job, step})));
    assert.equal(selected.length, 1, `${recipe}: missing or duplicated original recipe`);
    assert.equal(selected[0].job, 'select-targets');
    for (const docs of [false, true]) {
      const step = selected[0].step;
      const enabled = !step.if || runInNewContext(step.if.replace(/steps\.([a-z][a-z0-9-]*)/gu, (_, key) => `steps[${JSON.stringify(key)}]`), {steps: {'documentation-candidate': {outputs: {required: String(docs)}}}});
      assert.equal(enabled, recipe !== 'check:client-types' || !docs);
    }
    assert.notEqual(selected[0].step['continue-on-error'], true);
    assert(steps.indexOf(selected[0].step) < steps.indexOf(select));
  }
  const graph = steps.find(step => step.id === 'moon-candidate');
  assert(steps.indexOf(graph) < steps.indexOf(select));
  const prefix = steps.slice(0, steps.indexOf(select) + 1).filter(step => step.run && (!step.if || runInNewContext(step.if.replace(/steps\.([a-z][a-z0-9-]*)/gu, (_, key) => `steps[${JSON.stringify(key)}]`),
    {steps: {'documentation-candidate': {outputs: {required: 'false'}}, 'moon-candidate': {outputs: {required: 'false'}}}})));
  const directory = mkdtempSync(join(tmpdir(), 'actql-source-admission-')), bin = join(directory, 'bin');
  t.after(() => rmSync(directory, {recursive: true, force: true}));mkdirSync(bin);
  // Execute the actual YAML command prefix with closed recording command ports.
  // No npm installation, type sweep, compiler or target-selection scan runs.
  const record = `#!${process.execPath}\nconst fs = require('node:fs');
    const command = require('node:path').basename(process.argv[1]), args = process.argv.slice(2);
    fs.appendFileSync(process.env.CALLS, JSON.stringify({command,args})+'\\n');
    if(command==='npm') {
      const recipe=args[0]==='run'?args[1]:args[0];
      if(recipe===process.env.FAIL_RECIPE)process.exit(71);
    } else if(args.length===1 && args[0]==='scripts/ci-targets.mjs') {
      fs.appendFileSync(process.env.GITHUB_OUTPUT,'plan=recording-port\\n');
    }\n`;
  for (const command of ['npm', 'node']) writeFileSync(join(bin, command), record, {mode: 0o755});
  for (const failure of [...recipes, 'ci', '']) {
    const calls = join(directory, `calls-${failure || 'success'}`), output = join(directory, `output-${failure || 'success'}`);
    writeFileSync(output, '');
    const child = spawnSync('/bin/bash', ['-eo', 'pipefail', '-c', prefix.map(step => step.run).join('\n')], {
      cwd: directory, encoding: 'utf8', timeout: 5000,
      env: {...process.env, PATH: bin + ':/usr/bin:/bin', CALLS: calls, FAIL_RECIPE: failure, GITHUB_OUTPUT: output},
    });
    assert.equal(child.error, undefined);assert.equal(child.signal, null);
    assert.equal(child.status, failure ? 71 : 0, child.stderr);
    const observed = readFileSync(calls, 'utf8').trim().split('\n').map(line => JSON.parse(line));
    const npmCalls = observed.filter(row => row.command === 'npm');
    for (const recipe of recipes) assert.equal(npmCalls.filter(row => row.args[1] === recipe).length,
      recipe === recipes[1] && [recipes[0], 'ci'].includes(failure) ? 0 : 1);
    assert.equal(npmCalls.filter(row => row.args[0] === 'ci').length, failure === recipes[0] ? 0 : 1);
    assert.equal(readFileSync(output, 'utf8').includes('plan='), failure === '');
    // A refused Source cannot start even the optional Moon discovery entrance.
    assert.equal(observed.some(row => row.args.includes('moon-graph-candidate')), failure === '');
  }
  const {scripts} = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  const types = scripts['check:client-types'].split(/\s+/u);
  for (const required of ['--strict', '--noEmit', 'packages/sdk/index.d.ts', 'packages/client-wire/index.d.ts'])
    assert(types.includes(required), required);
  assert(!types.includes('--skipLibCheck'));
});

test('Linux Native profile compilers retain their commands and existing stack prerequisite', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-native-profile-stack-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const npm = join(root, 'npm');
  writeFileSync(npm, '#!/bin/sh\nprintf "%s:%s\\n" "$ACTQL_FIXTURE_STACK_KIB" "$*"\nexit "$ACTQL_FIXTURE_NPM_EXIT"\n');
  chmodSync(npm, 0o755);
  writeFileSync(join(root, 'node'), readFileSync(npm));
  chmodSync(join(root, 'node'), 0o755);
  for (const [job, name, command] of [
    ['native', 'Test Node-free native storage publication and control', 'scripts/test-native-http-client.mjs'],
    ['native-separated-network', 'Verify native direct and outbound-only Store profiles', 'check:native-separated-network'],
  ]) {
    assert.equal(jobs[job]['runs-on'], 'ubuntu-24.04');
    const step = (job === 'native' ? [...nativeCases('native'), ...jobs['native-http'].steps] : jobs[job].steps).find(row => row.name === name);
    assert.ok(step);
    assert.equal(step.if, undefined);
    assert.equal(step['continue-on-error'], undefined);
    assert.match(step.run, /ulimit -S -s 65536\s+?(?:node |npm run )/u);
    // Observe exact shell ordering and child inheritance without starting a
    // Native compiler or changing the host shell's hard resource limit.
    const observe = 'ulimit() { test "$*" = "-S -s 65536" || return 93; ' +
      'export ACTQL_FIXTURE_STACK_KIB="$3"; }\n';
    for (const status of [0, 7]) {
      const result = spawnSync('bash', ['-eo', 'pipefail', '-c', observe + step.run], {
        cwd: root, encoding: 'utf8', timeout: 5000,
        env: {...process.env, PATH: root + ':' + process.env.PATH,
          ACTQL_FIXTURE_NPM_EXIT: String(status)},
      });
      assert.equal(result.error, undefined);
      assert.equal(result.signal, null);
      assert.equal(result.status, status, result.stderr);
      assert.equal(result.stdout.trim(), `65536:${job === 'native' ? command : `run ${command}`}`);
    }
  }
});

test('separated Native profiles each retain a required independent sixty-minute job', () => {
  const job = jobs['native-separated-network'];
  assert.equal(job.name, 'native-separated-network (${{ matrix.profile }})');
  assert.deepEqual(job.strategy, {'fail-fast': false, matrix: {profile: ['direct', 'store']}});
  assert.equal(job['timeout-minutes'], 60);
  assert.equal(job['continue-on-error'], undefined);
  assert.ok(jobs.check.needs.includes('native-separated-network'));
  const step = job.steps.find(row => row.name === 'Verify native direct and outbound-only Store profiles');
  assert.equal(step.env.ACTQL_TEST_NATIVE_NETWORK_PROFILE, '${{ matrix.profile }}');
  assert.equal(step.env.ACTQL_TEST_SCRATCH_ROOT, '${{ runner.temp }}/actql-native-network-${{ matrix.profile }}');
  assert.equal(step.if, undefined);
  assert.equal(step['continue-on-error'], undefined);
  const receipt = job.steps.find(row => row.name === 'Retain scoped Native preparation source and compiler receipts');
  assert.equal(receipt.with.name,
    'native-scoped-preparation-${{ github.job }}-${{ matrix.profile }}-${{ github.run_id }}-${{ github.run_attempt }}');
  assert.equal(receipt.if, 'always()');
  for (const extension of ['json', 'stdout', 'stderr']) {
    assert.ok(receipt.with.path.includes('${{ runner.temp }}/native-scoped-preparation-${{ matrix.profile }}/**/*.' + extension));
  }
});

function separatedNetworkRoutingFixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-separated-routing-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const log = join(root, 'calls');
  writeFileSync(join(root, 'node'), '#!/bin/sh\n' +
    'entry="${1##*/}"\n' +
    'printf "node|%s|%s|%s\\n" "${ACTQL_TEST_NATIVE_APPLICATION_OUTPUT_ROUTE-}" "$entry" "$ACTQL_TEST_SCRATCH_ROOT" >> "$ACTQL_CALL_LOG"\n' +
    'if [ "${ACTQL_FIXTURE_FAIL-}" = "${ACTQL_TEST_NATIVE_APPLICATION_OUTPUT_ROUTE-}:$entry" ]; then exit 7; fi\n');
  chmodSync(join(root, 'node'), 0o755);
  // Explicit command ports observe the original shell routing. They perform
  // no privileged network operation, Native test, producer or physical probe.
  const ports = 'uname() { case "$1" in -s) echo Linux;; -m) echo x86_64;; *) return 91;; esac; }\n' +
    'ip() { return 92; }\niptables() { return 92; }\n' +
    'sudo() { printf "sudo|%s\\n" "$*" >> "$ACTQL_CALL_LOG"; case " $* " in *" curl "*) return 1;; esac; }\n' +
    'curl() { return 1; }\nsleep() { test "$*" = 1; }\nkill() { return 0; }\n';
  return (profile, fail = '') => {
    writeFileSync(log, '');
    const env = {...process.env, PATH: root + ':' + process.env.PATH,
      ACTQL_CALL_LOG: log, ACTQL_FIXTURE_FAIL: fail,
      ACTQL_TEST_SCRATCH_ROOT: join(root, 'scratch'), ACTQL_TEST_NATIVE_SITE_USER: 'fixture'};
    delete env.ACTQL_TEST_NATIVE_NETWORK_PROFILE;
    delete env.ACTQL_TEST_NATIVE_APPLICATION_OUTPUT_ROUTE;
    if (profile !== undefined) env.ACTQL_TEST_NATIVE_NETWORK_PROFILE = profile;
    const result = spawnSync('bash', ['-c', ports + 'source "$1"', '--',
      fileURLToPath(new URL('./test-native-separated-network.sh', import.meta.url))], {
      cwd: root, env, encoding: 'utf8', timeout: 5000,
    });
    assert.equal(result.error, undefined);
    assert.equal(result.signal, null);
    return {...result, calls: readFileSync(log, 'utf8').trim().split('\n').filter(Boolean), root};
  };
}

test('separated Native routing preserves both defaults and every selected full harness', t => {
  const run = separatedNetworkRoutingFixture(t);
  const expected = {
    direct: [['direct', 'test-native-http-client.mjs', 'direct']],
    store: [['store', 'test-native-http-client.mjs', 'store'], ['', 'test-native-runtime-bundle-cli.mjs', 'bundle']],
  };
  for (const profile of [undefined, 'both', 'direct', 'store']) {
    const result = run(profile);
    assert.equal(result.status, 0, result.stderr);
    const calls = result.calls.filter(line => line.startsWith('node|')).map(line => {
      const [, route, entry, scratch] = line.split('|');
      return [route, entry, scratch.slice(scratch.lastIndexOf('/') + 1)];
    });
    assert.deepEqual(calls, profile === 'direct' || profile === 'store'
      ? expected[profile] : [...expected.direct, ...expected.store], String(profile));
    const permit = result.calls.filter(line => /sudo\|ip netns exec .* iptables -I INPUT 1 .* -j ACCEPT$/u.test(line));
    const remove = result.calls.filter(line => /sudo\|ip netns exec .* iptables -D INPUT .* -j ACCEPT$/u.test(line));
    assert.equal(permit.length, profile === 'store' ? 0 : 1);
    // EXIT cleanup still retries removal after the direct transition (and
    // owns the sole removal attempt when the Store profile never opened it).
    assert.equal(remove.length, profile === 'store' ? 1 : 2);
    const direct = result.calls.findIndex(line => line.startsWith('node|direct|'));
    if (direct >= 0) {
      assert.ok(result.calls.indexOf(permit[0]) < direct);
      assert.ok(result.calls.indexOf(remove[0]) > direct);
    }
    const store = result.calls.findIndex(line => line.startsWith('node|store|'));
    if (store >= 0 && direct >= 0) assert.ok(result.calls.indexOf(remove[0]) < store);
  }
});

test('separated Native routing refuses unknown profiles and preserves child failure', t => {
  const run = separatedNetworkRoutingFixture(t);
  for (const profile of ['', 'unknown', 'DIRECT', 'direct,store']) {
    const result = run(profile);
    assert.equal(result.status, 2, profile);
    assert.match(result.stderr, /Unsupported Native network profile/u);
    assert.deepEqual(result.calls, []);
  }
  for (const [profile, fail, count] of [
    ['both', 'direct:test-native-http-client.mjs', 1],
    ['both', 'store:test-native-http-client.mjs', 2],
    ['store', ':test-native-runtime-bundle-cli.mjs', 2],
  ]) {
    const result = run(profile, fail);
    assert.equal(result.status, 7, result.stderr);
    assert.equal(result.calls.filter(line => line.startsWith('node|')).length, count);
    assert.ok(result.calls.some(line => /^sudo\|ip netns delete /u.test(line)), 'the original EXIT cleanup remains active');
  }
});

test('Native consumers retain selected original commands and collect independent failures after preparation', t => {
  const manifest = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  const expected = manifest.scripts['check:native-http-client'].split(' && ');
  const condition = "${{ !cancelled() && steps.native-preparation.outcome == 'success' }}";
  const root = mkdtempSync(join(tmpdir(), 'actql-native-independent-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const log = join(root, 'calls');
  writeFileSync(join(root, 'node'), '#!/bin/sh\nprintf "%s\\n" "$*" >> "$ACTQL_CALL_LOG"\n' +
    'exit "$ACTQL_FIXTURE_EXIT"\n');
  chmodSync(join(root, 'node'), 0o755);
  const linuxOwned = new Set([
    'node scripts/test-native-salesforce-effect-preview.mjs',
    'node scripts/test-native-remote-runtime.mjs',
    'node scripts/test-native-resident-site.mjs --effect-computation-only',
    'node scripts/test-native-resident-site.mjs --observation-replay-only',
    'node scripts/test-native-resident-site.mjs --release-recovery-only',
  ]);
  let selectedCount = 0;
  for (const name of ['native', 'native-macos']) {
    const selectedCommands = name === 'native-macos'
      ? [expected[0], ...expected.filter(command => !linuxOwned.has(command))] : expected;
    selectedCount += selectedCommands.length;
    const http = name === 'native' ? jobs['native-http'].steps.find(step => step.id === 'native-http')
      : nativeCases(name).find(step => step.id === 'native-http');
    const steps = [http,
      ...nativeCases(name).filter(step => step.id?.startsWith('native-') && step.id !== 'native-http' && step.name.startsWith('Test '))]
      .sort((a, b) => expected.indexOf(a.run.trim().split('\n').at(-1)) - expected.indexOf(b.run.trim().split('\n').at(-1)));
    assert.deepEqual(steps.map(step => step.run.trim().split('\n').at(-1)), selectedCommands);
    assert.equal(new Set(steps.map(step => step.env.ACTQL_TEST_SCRATCH_ROOT)).size, selectedCommands.length);
    const results = steps.map((step, index) => {
      assert.equal(name === 'native' && step.id === 'native-http' ? step.if : nativeCaseCondition(name, step),
        name === 'native' && step.id === 'native-http' ? undefined : condition);
      assert.equal(step['continue-on-error'], undefined, 'a failed case must still fail the job');
      return spawnSync('bash', ['-eo', 'pipefail', '-c',
        (name === 'native' ? 'ulimit() { test \"$*\" = \"-S -s 65536\"; }\n' : '') + step.run], {
        cwd: root, encoding: 'utf8', timeout: 5000,
        env: {...process.env, PATH: root + ':' + process.env.PATH,
          ACTQL_CALL_LOG: log, ACTQL_FIXTURE_EXIT: index === 0 ? '7' : '0'},
      });
    });
    assert.equal(results[0].status, 7, results[0].stderr);
    assert(results.slice(1).every(result => result.status === 0));
    assert(nativeWorkload(name).steps.find(step => step.id === 'native-preparation').run
      .includes('prepare-native-runtime-bundle-fixture.mjs'));
  }
  assert.equal(readFileSync(log, 'utf8').trim().split('\n').length, selectedCount);
  for (const id of ['packed-materials', 'packed-redelivery', 'packed-output-report'])
    assert.equal(nativeCaseCondition('native', nativeCases('native').find(step => step.id === id)), condition);
});

test('SQLite physical regressions require their prepared macOS Native owner', () => {
  const selection = selectTargets(['src/platform_native/sqlite/sqlite_stub.c'], {draft: false});
  assert.equal(selection.profile, 'full');
  assert.equal(gateJobRequired(selection, 'native-macos'), true);
  const selected = nativeCases('native-macos').filter(row =>
    row.run === 'node scripts/test-native-sqlite-read-statement.mjs');
  assert.equal(selected.length, 1, 'The actual SQLite regression command has one prepared owner');
  const [step] = selected;
  assert.equal(nativeCaseCondition('native-macos', step), "${{ !cancelled() && steps.native-preparation.outcome == 'success' }}");
  assert.equal(step['continue-on-error'], undefined);
  assert.equal(step['timeout-minutes'], 5);
  assert.equal(step.run, 'node scripts/test-native-sqlite-read-statement.mjs');
  assert(nativeWorkload('native-macos').steps.findIndex(row => row.id === 'native-background-start') >
    nativeWorkload('native-macos').steps.findIndex(row => row.id === 'native-preparation'));
  const runner = readFileSync(new URL('./test-native-sqlite-read-statement.mjs', import.meta.url), 'utf8');
  assert.match(runner, /ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION/u);
  const env = {...process.env};
  delete env.ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION;
  const missing = spawnSync(process.execPath, ['scripts/test-native-sqlite-read-statement.mjs'],
    {encoding: 'utf8', timeout: 5000, maxBuffer: 65536, env});
  assert.equal(missing.status, 1);
  assert(!missing.signal && !missing.error);
  assert.match(missing.stderr, /same job exact-source Native component preparation is required/u);
  const consumer = readFileSync(new URL('./native-sqlite-read-statement.test.mjs', import.meta.url), 'utf8');
  assert.match(consumer, /prepareNativeRuntimeBundleLibraries/u);
  assert.match(consumer, /preparation: process\.env\.ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_PREPARATION/u);
  assert.match(consumer, /xcrun', \['--show-sdk-path'\]/u);
  assert.doesNotMatch(consumer, /MacOSX26\.2\.sdk|CommandLineTools\/usr\/bin\/clang/u);
  const compiler = readFileSync(new URL('./prepare-native-sqlite-read-statement-fixture.py', import.meta.url), 'utf8');
  assert(compiler.includes('sqlite-component/fixtures/read_statement.c'));
  assert(!compiler.includes("'component.c'"), 'The consumer compiles no replacement engine/component');
  assert(!compiler.includes('urlopen'), 'The consumer downloads no replacement input');
});

test('macOS HTTP retains its original command under shared preparation and a mandatory joined outcome', t => {
  const workload = nativeWorkload('native-macos');
  assert.equal(workload['runs-on'], 'macos-15');
  const runtime = nativeGroups['native-macos'].find(group => group.name === 'runtime');
  const http = runtime.steps.find(step => step.id === 'native-http');
  assert(http);
  assert.equal(http.run, 'node scripts/test-native-http-client.mjs\n');
  assert.equal(http.timeoutMinutes, 115);
  assert.deepEqual(http.env, {ACTQL_TEST_SCRATCH_ROOT: '${{ runner.temp }}/native-tests/native-http',
    ACTQL_TEST_NATIVE_HTTP_FOCUS: 'http-packages', ACTQL_TEST_PRESERVE_SCRATCH: '1',
    ACTQL_TEST_NATIVE_HTTP_SOURCE_OWNER: 'linux-http+darwin-core-source'});
  const controls = nativeGroups['native-macos'].flatMap(group => group.steps)
    .filter(step => step.id === 'native-http-controls');
  assert.equal(controls.length, 1);
  assert.equal(controls[0].run, http.run);
  assert.equal(controls[0].timeoutMinutes, http.timeoutMinutes);
  assert.deepEqual(controls[0].env, {ACTQL_TEST_SCRATCH_ROOT: '${{ runner.temp }}/native-tests/native-http-controls',
    ACTQL_TEST_NATIVE_HTTP_FOCUS: 'http-controls', ACTQL_TEST_PRESERVE_SCRATCH: '1'});
  assert.equal(nativeCases('native-macos').filter(step => step.id === 'native-http').length, 1);
  assert.equal(workload.outputs['native-http-result'], '${{ steps.native-background.outputs.native-http-result }}');
  const gate = jobs['native-http-macos'];
  assert.deepEqual(gate.needs, ['select-targets', 'native-macos-workloads', 'native-http', 'core']);
  assert.equal(gate['runs-on'], 'ubuntu-24.04');
  assert.match(gate.if, /always\(\)/u);
  assert.equal(gate['timeout-minutes'], 5);
  assert.equal(gate['continue-on-error'], undefined);
  assert.equal(gate.steps.length, 1, 'No second compiler/toolchain/component producer is selected');
  const selected = gate.steps[0];
  assert.equal(selected.env.WORKLOAD_RESULT, '${{ needs.native-macos-workloads.result }}');
  assert.equal(selected.env.HTTP_RESULT, '${{ needs.native-macos-workloads.outputs.native-http-result }}');
  for (const workloadResult of ['success', 'failure', 'cancelled', 'skipped', ''])
    for (const httpResult of ['success', 'failure', 'unexecuted', 'skipped', '']) {
      const result = spawnSync('bash', ['-eo', 'pipefail', '-c', selected.run], {
        encoding: 'utf8', timeout: 5000,
        env: {...process.env, WORKLOAD_RESULT: workloadResult, HTTP_RESULT: httpResult,
          LINUX_HTTP_RESULT: 'success', DARWIN_CORE_RESULT: 'success', CORE_TARGETS: '["js","wasm","native"]'},
      });
      assert.equal(result.error, undefined); assert.equal(result.signal, null);
      assert.equal(result.status, workloadResult === 'success' && httpResult === 'success' ? 0 : 1);
    }
  assert(jobs['native-macos'].needs.includes('native-http-macos'));
  assert(jobs['native-macos'].needs.includes('native-macos-workloads'));
});

test('Native retained verification builds exactly its checked release module inventory', () => {
  const step = nativeCases('native').find(step => step.name === 'Verify registered Native retained product path');
  assert(step);
  const source = readFileSync(new URL('../benchmarks/retained-results/release-artifacts.mjs', import.meta.url), 'utf8');
  const inventory = /const modules = Object\.freeze\((\[[\s\S]*?\])\);/u.exec(source);
  assert(inventory, 'the original checked release inventory must remain explicit');
  const modules = Array.from(runInNewContext(inventory[1]));
  assert(modules.length > 0);
  const targets = modules.map(path => 'src/' + path.slice(0, path.lastIndexOf('/')));
  assert.equal(new Set(targets).size, targets.length);
  const commands = step.run.replace(/\\\n\s*/gu, ' ').trim().split('\n').map(line => line.trim().replace(/\s+/gu, ' '));
  assert.deepEqual(commands[0].split(/\s+/u), ['moon', 'build', '--target', 'js', '--release', ...targets]);
  assert.equal(nativeCaseCondition('native', step),
    "${{ !cancelled() && steps.native-preparation.outcome == 'success' && steps.native-background.outcome == 'success' }}");
  assert.deepEqual(commands.slice(1), [
    'moon build src/cmd/native_retained_case_probe --target native --release',
    'node benchmarks/retained-results/native-case-probe.mjs native-acquisition-full-validation-low-selectivity/narrow/100',
    'node benchmarks/retained-results/native-case-probe.mjs fixed-join-count-shrinking-intermediate/narrow/1000',
    'node benchmarks/retained-results/native-estimate-calibration.mjs native-acquisition-full-validation-low-selectivity/narrow/1000 native-acquisition-full-validation-low-selectivity/narrow/100 "$RUNNER_TEMP/native-retained-calibration.json"',
    'ACTQL_NATIVE_CALIBRATION_PROFILE="$RUNNER_TEMP/native-retained-calibration.json" node scripts/test-native-direct-pair.mjs',
  ]);
});

test('normal lint executes installed-interface correspondence controls once', () => {
  const file = 'scripts/installed-interface-correspondence.test.mjs';
  const owners = Object.entries(jobs).flatMap(([job, value]) => (value.steps ?? [])
    .filter(step => step.run?.split(/\s+/u).includes(file)).map(step => ({job, step})));
  assert.equal(owners.length, 1);
  const [{job, step}] = owners;
  assert.equal(job, 'lint');
  const args = step.run.trim().split(/\s+/u);
  assert.deepEqual(args.slice(0, 2), ['node', '--test']);
  assert.equal(args.filter(value => value === file).length, 1);
  for (const profile of ['full', 'maintenance', 'focused-tests']) assert.equal(draftStepEnabled(step, profile), true);
  for (const profile of ['draft', 'draft-focused', 'documentation']) assert.equal(draftStepEnabled(step, profile), false);
  assert.equal(step['continue-on-error'], undefined);
});

test('normal lint executes behavioral operation performance assessment tests', () => {
  const collectors = jobs.lint.steps.filter(row => row.run === 'npm run test:operation-performance-collectors');
  const policies = jobs.lint.steps.filter(row => row.run === 'npm run test:operation-performance-policy');
  assert.equal(collectors.length, 1);
  assert.equal(policies.length, 1);
  const [step] = collectors, [policy] = policies;
  for (const profile of ['full', 'maintenance', 'focused-tests', 'draft', 'draft-focused']) assert.equal(draftStepEnabled(policy, profile), true);
  assert.equal(draftStepEnabled(policy, 'documentation'), false);
  for (const profile of ['full', 'maintenance', 'focused-tests']) assert.equal(draftStepEnabled(step, profile), true);
  for (const profile of ['draft', 'draft-focused', 'documentation']) assert.equal(draftStepEnabled(step, profile), false);
  // These tests validate raw samples, frame counts, faults and incomplete
  // evidence. Running them is not an ordinary-package performance result.
  assert.ok(jobs.host.steps.some(row => row.run === 'npm run check:checkpoint-runtime'));
  const observations = jobs.host.steps.filter(row => row.run === 'npm run test:host-observations');
  assert.equal(observations.length, 1);
  assert.equal(observations[0].if, "${{ !cancelled() && steps.host-runtime-preparation.outcome == 'success' }}");
});

test('normal lint executes ordinary process collector protocol tests', () => {
  const selected = jobs.lint.steps.filter(row => row.run === 'python3 -I -B scripts/benchmark-ordinary-processes.test.py');
  assert.equal(selected.length, 1);
  const [step] = selected;
  for (const profile of ['full', 'maintenance', 'focused-tests']) assert.equal(draftStepEnabled(step, profile), true);
  for (const profile of ['draft', 'draft-focused', 'documentation']) assert.equal(draftStepEnabled(step, profile), false);
  assert.equal(step['continue-on-error'], undefined);
  // Process fixtures exercise the collector and package fence, not product speed.
});

test('normal Host CI executes bounded Journal preparation and cursor regressions', () => {
  const files = ['adapters/host-node/client-request-journal-sql-bounds.test.mjs',
    'adapters/host-node/client-request-journal-execution-bounds.test.mjs',
    'adapters/host-node/client-request-journal-wal-bounds.test.mjs',
    'adapters/host-node/client-request-journal-fresh-schema.test.mjs'];
  for (const file of files) {
    const owners = jobs.host.steps.filter(row => row.run?.split(/\s+/u).includes(file));
    assert.equal(owners.length, 1, file);
    const [step] = owners, args = step.run.split(/\s+/u);
    assert.deepEqual(args.slice(0, 2), ['node', '--test']);
    assert.equal(args.filter(value => value === file).length, 1, file);
    assert.equal(step.if, "${{ !cancelled() && steps.host-runtime-preparation.outcome == 'success' }}");
    assert.equal(step['continue-on-error'], undefined);
  }
});

test('normal Host CI checks real connector initialization after its ordinary runtime build', () => {
  const steps = jobs.host.steps;
  const build = steps.findIndex(row => row.name === 'Build runtime packages without prebuilt bundles');
  const index = steps.findIndex(row => row.name === 'Test actual bound connector initialization and cleanup');
  assert.ok(build >= 0 && index > build);
  assert.equal(steps[index].run, 'node --test adapters/host-node/installed-bound-construction.actual.test.mjs adapters/host-node/installed-bound-construction-failures.actual.test.mjs adapters/host-node/installed-source-construction-geometry.test.mjs');
  assert.equal(steps[index].if, "${{ !cancelled() && steps.cold-runtime-preparation.outcome == 'success' }}");
  assert.equal(steps[index]['continue-on-error'], undefined);
  // These cases use actual Core/Resource/registration and temporary SQLite,
  // not live provider credentials or another runtime build/cleanup substitute.
});

test('Host collection retains original command bodies and their actual build prerequisites', () => {
  const {scripts} = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  const steps = jobs.host.steps;
  const step = name => {
    const found = steps.filter(row => row.name === name);
    assert.equal(found.length, 1, name);
    return found[0];
  };
  const commands = name => scripts[name].split(' && ');
  const retained = commands('check:retained-boundary');
  const publication = commands('check:publication-runtime');
  assert.equal(retained[0], publication[0]);
  const sharedBuild = step('Prepare the shared Host runtime').run.trim().split(/\s+/u);
  for (const prerequisite of retained[0].trim().split(/\s+/u)) {
    assert(sharedBuild.includes(prerequisite), `Missing shared Host build prerequisite: ${prerequisite}`);
  }
  const retainedArguments = retained[1].trim().split(/\s+/u);
  const storageArguments = step('Test bounded retained storage and process lifecycle').run.trim().split(/\s+/u);
  assert.deepEqual(storageArguments.slice(0, 2), ['node', '--test']);
  assert(storageArguments.slice(2).every(argument => argument.endsWith('.test.mjs')),
    'Run each selected whole test file without name/skip filters');
  for (const file of new Set([...retainedArguments.slice(2),
    'adapters/host-node/client-original-plan-control.test.mjs',
    'adapters/host-node/dispatch-failure-observation.test.mjs'])) {
    assert.equal(storageArguments.filter(argument => argument === file).length, 1, file);
  }
  assert.equal(step('Test prepared holder cleanup owner').run, retained[2]);
  assert.equal(step('Test portable publication control with the durable Store').run, publication[1]);
  assert.equal(step('Test original publication owned extents').run, publication[2]);
  const ownedHost = commands('check:publication-owned-host');
  assert.deepEqual(ownedHost.length, 2);
  assert.equal(publication[3], 'npm run check:publication-owned-host');
  assert.equal(step('Test original publication Host extents').run, ownedHost[0]);
  assert.equal(step('Test original publication Host callers').run, ownedHost[1]);
  const runHost = commands('check:run-host-core');
  assert.equal(runHost.length, 4);
  assert.equal(step('Prepare the Run Host runtime').run, runHost[0]);
  assert.equal(step('Check Run Host types').run, runHost[1]);
  assert.equal(step('Test portable Run Host compilation package').run, runHost[2]);
  assert.equal(step('Test packed Run Host compilation package').run, runHost[3]);
  assert.equal(step('Test original Local result authorization').run,
    'node --test adapters/host-node/local-result-authorization.test.mjs adapters/host-node/local-result-read-workspace.actual.test.mjs adapters/host-node/local-result-read-wire-workspace.test.mjs adapters/host-node/local-result-metadata-demand.actual.test.mjs adapters/host-node/local-result-read-policy.test.mjs adapters/host-node/ordinary-local-account.test.mjs adapters/host-node/ordinary-mock-account-profile-history.test.mjs');
  const wireWorkspace = 'adapters/host-node/local-result-read-wire-workspace.test.mjs';
  assert.equal(step('Test original Local result authorization').run.split(/\s+/u).filter(value => value === wireWorkspace).length, 1);
  assert.equal(steps.filter(row => row.run?.split(/\s+/u).includes(wireWorkspace)).length, 1);
  assert.equal(step('Test original Local result authorization')['continue-on-error'], undefined);
  assert.equal(steps.filter(row => row.run?.includes('ordinary-local-account.test.mjs')).length, 1,
    'Actual standard Account bootstrap/current cases run once behind the existing runtime preparation');
  assert.equal(steps.filter(row => row.run?.includes('ordinary-mock-account-profile-history.test.mjs')).length, 1,
    'Mock Account observation, override and saved-original cases run in the existing Account lane');
  assert.equal(step('Test original Local Source inventory and lookup policy').run,
    'node --test adapters/host-node/ordinary-source-inventory.test.mjs adapters/host-node/local-files-lookup-policy.test.mjs');
  assert.equal(step('Test original Local Source inventory and lookup policy').if,
    "${{ !cancelled() && steps.host-runtime-preparation.outcome == 'success' }}");
  assert.equal(steps.filter(row => row.run?.includes('ordinary-source-inventory.test.mjs')).length, 1,
    'Original Source inventory cases use existing Host preparation without another supplier');
  assert.equal(step('Test original Model registration and material inventories').run,
    'node --test adapters/host-node/installed-model-registration-snapshot.test.mjs adapters/host-node/request-model-material-resources.test.mjs');
  assert.equal(step('Test original Model registration and material inventories').if,
    "${{ !cancelled() && steps.host-runtime-preparation.outcome == 'success' }}");
  assert.equal(steps.filter(row => row.run?.includes('request-model-material-resources.test.mjs')).length, 1,
    'Original Model metadata cases use existing Host preparation without another supplier');
  assert.equal(steps.filter(row => row.run?.split(/\s+/u).includes('src/connectors_builtin_node')).length, 1,
    'the required Common entry is prepared once for both original consumers');
});

test('Host independent failures are collected while failed prerequisites and cancellation stop consumers', () => {
  const steps = jobs.host.steps;
  const prerequisites = {
    'host-toolchain': new Set(['host-runtime-preparation']),
    'remote-site-preparation': new Set(['Test durable Remote Site dispatch admission',
      'Test packed Remote coordinator', 'Test original holder terminal facade']),
    'run-host-preparation': new Set(['Check Run Host types',
      'Test portable Run Host compilation package', 'Test packed Run Host compilation package',
      'Test original Local result authorization']),
    'cold-runtime-preparation': new Set(['Test actual bound connector initialization and cleanup',
      'Test ordinary Project Source and STORE original recovery']),
  };
  const setup = steps.find(row => row.id === 'host-toolchain');
  assert.equal(setup.uses, './.github/actions/setup-toolchain');
  assert.equal(setup.if, undefined);
  for (const row of steps.filter(row => row.run)) {
    const preparation = Object.entries(prerequisites).find(([, names]) =>
      names.has(row.id) || names.has(row.name))?.[0] ?? 'host-runtime-preparation';
    assert.equal(row.if, '${{ !cancelled() && steps.' + preparation + ".outcome == 'success' }}", row.name);
    assert.equal(row['continue-on-error'], undefined, row.name);
    const expression = row.if.slice(3, -3).replace(/steps\.([a-z][a-z0-9-]*)/gu,
      (_, name) => `steps[${JSON.stringify(name)}]`);
    const admitted = (outcome, cancelled = false) => Function('steps', 'cancelled',
      `return (${expression});`)({[preparation]: {outcome}, 'earlier-independent-test': {outcome: 'failure'}},
      () => cancelled);
    assert.equal(admitted('success'), true, 'a failed sibling cannot suppress this original case');
    for (const outcome of ['failure', 'cancelled', 'skipped', undefined])
      assert.equal(admitted(outcome), false, `${row.name}: ${outcome}`);
    assert.equal(admitted('success', true), false, 'workflow cancellation remains authoritative');
    assert(steps.findIndex(item => item.id === preparation) < steps.indexOf(row), row.name);
  }
  assert.equal(jobs.host['timeout-minutes'], 30);
  assert.equal(jobs.host.strategy, undefined, 'collect serially without new shared-state concurrency');
  assert.equal(jobs.host['continue-on-error'], undefined);
});

test('manual integration keeps full core and explicit macOS opt-in', () => {
  assert.deepEqual(selectTargets(['README.md'], {event: 'push'}).targets, all);
  assert.equal(selectTargets(['README.md'], {event: 'push'}).macos, true);
  assert.deepEqual(selectTargets([], {event: 'workflow_dispatch'}).targets, all);
  assert.equal(selectTargets([], {event: 'workflow_dispatch'}).macos, false);
  assert.equal(selectTargets([], {event: 'workflow_dispatch', nativeMacos: true}).macos, true);
});
test('portable PR paths choose JS and explain deferred macOS coverage', () => {
  for (const path of ['README.md', 'src/source_span/span.mbt', 'scripts/worktree-inventory.mjs']) {
    const result = validateSelection(selectTargets([path]));
    assert.deepEqual(result.targets, ['js'], path); assert.equal(result.macos, false, path);
    assert.match(result.reason, /full targets run on main integration; optional macOS can be requested manually/u);
  }
});
test('platform, per-file target, runtime ownership, identities and build retain every target', () => {
  for (const path of ['src/platform_native/sqlite/moon.pkg', 'src/platform_native/executor_slot/moon.pkg',
    'src/cmd/native_client/main.mbt', 'src/something/backend_js.mbt', 'src/a/ffi.mbt',
    'src/managed_record_runtime/read.mbt', 'src/execution_relation/rows.mbt',
    'src/connectors/local/driver.mbt', 'src/canonical_json/read.mbt', 'src/sha256/hash.mbt',
    'adapters/host-node/completion-custody.test.mjs', 'scripts/owned-scratch.mjs',
    'src/a/moon.pkg', 'adapters/workers/build.mjs', 'packages/sdk/package.json',
    'adapters/store-local/publication-commit-owner.mjs', 'src/a/native.c', 'src/a/memory.mbt', 'src/value_contract/cid.mbt',
    '.github/workflows/ci.yml', 'toolchain.json', 'moon.mod', 'package-lock.json',
    'spec/contracts/pin.json', 'docs/spec/language.md', 'docs/reviews/runtime.json',
    'src/random/new.S', 'src/encode_core/value.mbt', 'src/decode_scalar/value.mbt', 'src/a/pkg.generated.mbti', 'packages/new-runtime/index.mjs', 'portability/corpus/value.json', 'proofs/relation-pipeline/run.mjs',
    'vendor/runtime/code.mbt']) {
    const result = selectTargets([path]);
    assert.deepEqual(result.targets, all, path); assert.equal(result.macos, true, path);
  }
});
test('unknown, unavailable, malformed and empty diff cannot omit target coverage', () => {
  for (const paths of [[], null, ['README.md', 'new-tool/config.json'], ['../src/a.mbt'],
    ['src/a\nb.mbt'], ['/tmp/a'], ['src//a'], ['src/a\0b']]) {
    assert.deepEqual(selectTargets(paths).targets, all, JSON.stringify(paths));
  }
  assert.equal(selectTargets(['README.md'], {failure: 'Git object unavailable'}).macos, true);
  assert.equal(selectTargets(['src/a/ordinary.mbt'], {targetSensitiveDiff: true}).macos, true);
  assert.throws(() => validateSelection({schema: 'actql-ci-targets/0.1', targets: ['wasm'], macos: false, reason: 'bad'}));
  assert.throws(() => validateSelection({schema: 'actql-ci-targets/0.1', targets: ['js'], macos: undefined, reason: 'bad'}));
});
test('diff uses exact merge checkout, NUL paths, no rename hiding and no 300-file limit', () => {
  const base = 'a'.repeat(40), head = 'b'.repeat(40), calls = [];
  const paths = [...Array.from({length: 350}, (_, i) => `docs/file-${i}.md`), 'src/platform_native/old.mbt'];
  const result = readChanges({pull_request: {base: {sha: base}}}, args => {
    calls.push(args);
    if (args[0] === 'rev-parse') return head + '\n';
    return args.includes('--name-only') ? paths.join('\0') + '\0' : '+ordinary source\n';
  });
  assert.deepEqual(result.paths, paths);
  assert.deepEqual(calls[1], ['diff', '--no-renames', '--name-only', '-z', base, head, '--']);
  assert.deepEqual(selectTargets(result.paths).targets, all);
  assert.throws(() => readChanges({}), /Missing PR base/u);
  assert.throws(() => readChanges({pull_request: {base: {sha: base}}}, () => {throw new Error('missing base');}), /missing base/u);
  assert.throws(() => readChanges({pull_request: {base: {sha: base}}}, args => args[0] === 'rev-parse' ? head : 'README.md'), /Truncated/u);
});
test('ordinary filename cannot hide target-specific syntax changes', () => {
  const base = 'a'.repeat(40), head = 'b'.repeat(40);
  for (const line of ['+extern "C"', '-supported_targets = "native"', '+unsafe fn f()', '+malloc(12)', '+#cfg(target="js")', '+#borrow(value)', '+#owned(value)']) {
    const result = readChanges({pull_request: {base: {sha: base}}}, args =>
      args[0] === 'rev-parse' ? head : args.includes('--name-only') ? 'src/a/plain.mbt\0' : line);
    assert.equal(result.targetSensitiveDiff, true, line);
  }
});
test('read-only PR lifecycle, main pushes and explicit dispatch trigger CI', () => {
  assert.deepEqual(Object.keys(workflow.on).sort(), ['pull_request', 'push', 'schedule', 'workflow_dispatch']);
  assert.deepEqual(workflow.on.push.branches, ['main']);
  assert.deepEqual(workflow.on.pull_request.types, ['opened', 'synchronize', 'reopened', 'ready_for_review', 'converted_to_draft']);
  assert.equal(workflow.on.pull_request_target, undefined);
  assert.deepEqual(workflow.on.schedule, [{cron: '23 3 * * 1'}]);
  assert.equal(workflow.on.workflow_run, undefined);
  assert.equal(workflow.on.merge_group, undefined);
  assert.equal(workflow.concurrency['cancel-in-progress'], "${{ !inputs.performance_matrix && github.ref != 'refs/heads/main' }}");
});
test('manual normal dispatch retains all full-family obligations, separate from probes', () => {
  const inputs = workflow.on.workflow_dispatch.inputs;
  assert.equal(inputs.performance_matrix.default, false);
  assert.equal(inputs.packed_query_evidence_probe.default, false);
  const selection = validateSelection(selectTargets([], {event: 'workflow_dispatch'}));
  assert.equal(selection.profile, 'full');
  assert.deepEqual(selection.targets, all);
  assert.equal(Object.hasOwn(selection, 'mainBaseline'), false);
  const results = Object.fromEntries(gateJobs.map(name => [name, {result: 'success'}]));
  results['main-performance'] = {result: 'skipped'};
  results['health-quick'] = {result: 'skipped'};
  results['focused-tests'] = {result: 'skipped'};
  results['native-macos'] = {result: 'skipped'};
  verifyGate({sourceRevision: 'a'.repeat(40), selection}, results, {event: 'workflow_dispatch', sourceRevision: 'a'.repeat(40)});
  for (const status of ['failure', 'skipped', undefined]) {
    assert.throws(() => verifyGate({sourceRevision: 'a'.repeat(40), selection},
      {...results, core: {result: status}}, {event: 'workflow_dispatch', sourceRevision: 'a'.repeat(40)}));
  }
});
test('active main finishes while pending work coalesces; branches and performance are separate', () => {
  assert.equal(workflow.concurrency.group, "${{ github.workflow }}-${{ github.ref }}-${{ inputs.packed_query_evidence_probe && 'evidence-probe' || inputs.performance_matrix && 'performance' || 'normal' }}");
  assert.equal(workflow.concurrency.queue, undefined);
  const expression = workflow.concurrency['cancel-in-progress'].slice(3, -2);
  for (const ref of ['refs/heads/main', 'refs/heads/feature']) {
    for (const performance of [false, undefined, true]) {
      assert.equal(runInNewContext(expression, {github: {ref}, inputs: {performance_matrix: performance}},
        {timeout: 100}), ref !== 'refs/heads/main' && !performance);
    }
  }
});
for (const [name, entries, producerCount, residentSeconds, remainingMinutes] of [
  ['native', 'all', 4, 900, 45],
  ['native-macos', 'all', 4, 1200, 45],
  ['native-separated-network', 'bundle', 2, 900, 25],
]) {
  test(`Native preparation outer budgets retain every producer and consumer window (${name})`, () => {
    const job = jobs[name + '-workloads'] ?? jobs[name];
    assert.equal(job['runs-on'], name === 'native-macos' ? 'macos-15' : 'ubuntu-24.04');
    const preparation = job.steps.find(step =>
      step.name === 'Prepare exact-source scoped Native commands and components once');
    assert.equal(preparation.run, 'node scripts/prepare-native-runtime-bundle-fixture.mjs ' +
      '--destination "${{ runner.temp }}/native-scoped-preparation' +
      (name === 'native-separated-network' ? '-${{ matrix.profile }}' : '') + '" --entries ' + entries + ' --seconds 900' +
      (entries === 'all' ? ' --http-jobs 2' : '') +
      (residentSeconds === 900 ? '' : ' --resident-seconds ' + residentSeconds) +
      (entries === 'all' ? ' --lanes 2' : ''));
    assert.equal(preparation.if, undefined);
    assert.equal(preparation['continue-on-error'], undefined);
    // Only the macOS Resident cold build selects 1200 seconds; all other
    // producers retain 900 seconds. Each has its own 30-second
    // enclosing-call allowance. Keep three minutes for metadata and cleanup,
    // rounded up to a finite five-minute workflow window. This is not a
    // runtime capacity, a runtime test timeout, or a cleanup acknowledgment.
    const producerSeconds = producerCount * 900 + (entries === 'all' ? residentSeconds - 900 : 0);
    const preparationMinutes = Math.ceil((producerSeconds + producerCount * 30 + 180) / 300) * 5;
    assert.equal(preparation['timeout-minutes'], preparationMinutes);
    assert.equal(job['timeout-minutes'], preparationMinutes + remainingMinutes,
      'the existing non-preparation window survives the outer scheduling correction');
  });
}

test('ordinary Read activation regressions run on the selected Native toolchain', () => {
  const steps = nativeWorkload('native').steps;
  const setup = steps.findIndex(step => step.uses === './.github/actions/setup-toolchain');
  const process = steps.findIndex(step => step.name ===
    'Test selected Linux x64 process-provider ABI and original physical custody');
  const index = steps.findIndex(step => step.name ===
    'Test original Read slab activation custody on selected Linux x64');
  assert.ok(setup >= 0 && setup < process && process < index);
  assert.equal(steps[index].run, 'python3 -B scripts/test_native_read_activation.py');
  assert.equal(steps[index]['timeout-minutes'], 3);
  assert.equal(steps[index].if, undefined);
  assert.equal(steps[index]['continue-on-error'], undefined);
  assert.equal(steps[index].env, undefined, 'inherit the original selected compiler and MoonBit');
  const retained = steps.find(step => step.name ===
    'Retain Linux x64 process-provider original controls');
  assert.equal(retained.if, 'always()');
  assert.deepEqual(retained.with.path.trim().split('\n'),
    ['_build/linux-x64-owned-process/', '_build/native-read-activation/',
      '_build/native-prepared-controls/', '_build/native-working-origin/']);
});

for (const [name, driver, output] of [
  ['prepared constructor cohorts', 'test_native_prepared_controls.py', '_build/native-prepared-controls/'],
  ['working carrier custody', 'test_native_working_origin.py', '_build/native-working-origin/'],
]) {
  test(`original ${name} execute on selected Native toolchain and retain failed diagnostics`, () => {
    const steps = nativeWorkload('native').steps;
    const setup = steps.findIndex(step => step.uses === './.github/actions/setup-toolchain');
    const read = steps.findIndex(step => step.run === 'python3 -B scripts/test_native_read_activation.py');
    const index = steps.findIndex(step => step.run === `python3 -B scripts/${driver}`);
    assert.ok(setup >= 0 && setup < read && read < index);
    assert.equal(steps[index]['timeout-minutes'], 3);
    assert.equal(steps[index].if, undefined);
    assert.equal(steps[index]['continue-on-error'], undefined);
    assert.equal(steps[index].env, undefined, 'inherit selected compiler and MoonBit');
    const retained = steps.find(step => step.name ===
      'Retain Linux x64 process-provider original controls');
    assert.equal(retained.if, 'always()');
    assert.ok(retained.with.path.trim().split('\n').includes(output));
  });
}

test('whole-family scheduling retains the core matrix and complete selected proof campaigns', () => {
  assert.equal(jobs['session-evidence']['timeout-minutes'], 60);
  assert.deepEqual(jobs.core.needs, ['select-targets', 'core-js', 'core-common', 'core-darwin']);
  assert.equal(jobs['core-common'].strategy['fail-fast'], false);
  assert.equal(jobs['core-darwin'].strategy['fail-fast'], false);
  for (const target of ['js', 'wasm', 'native']) {
    assert.equal(runInNewContext(jobs['core-common']['timeout-minutes'].slice(3, -2),
      {matrix: {target}}, {timeout: 100}), target === 'native' ? 90 : 30);
  }
  assert.equal(jobs['core-common'].strategy.matrix.target, '${{ fromJSON(needs.select-targets.outputs.targets) }}');
  assert.deepEqual(jobs['native-macos-workloads'].needs, ['select-targets']);
  assert.equal(jobs['native-macos-workloads']['timeout-minutes'], 115);
  assert.equal(jobs['native-workloads']['timeout-minutes'], 110);
  assert.match(jobs['native-macos'].if, /needs\.select-targets\.outputs\.macos == 'true'/u);
  for (const name of ['session-evidence', 'session-controls', 'pipeline-mutations', 'pipeline-mutations-rest', 'pipeline-capacity', 'pipeline-capacity-mutants', 'pipeline-validation']) {
    assert.match(jobs[name].if, /needs\.select-targets\.outputs\.profile == 'full'/u);
    assert.deepEqual(jobs[name].needs, ['select-targets']);
  }
  assert.deepEqual(jobs['pipeline-evidence'].needs, [...Object.values(partJobs), 'pipeline-validation']);
  const capacity = jobs['pipeline-capacity'].steps.map(step => step.run ?? '').join('\n');
  assert.match(capacity, /node proofs\/relation-pipeline\/capacity\/run\.mjs all/u);
  assert.match(capacity, /node proofs\/relation-pipeline\/run\.mjs all/u);
  const check = jobs.check;
  assert(check.needs.includes('select-targets'));
  assert.equal(check.steps.find(step => step.run?.includes('node scripts/ci-targets.mjs gate')).env.CI_PLAN_PATH, '${{ runner.temp }}/actql-ci-plan.json');
  assert.match(check.if, /always\(\)/u);
});
const head = 'b'.repeat(40);
const plan = selection => ({sourceRevision: head, selection});
const context = {event: 'pull_request', sourceRevision: head};
const results = selection => Object.fromEntries(gateJobs.map(name => [name, {result:
  gateJobRequired(selection, name) ? 'success' : 'skipped'}]));
const changes = paths => paths.map(path => ({path, before: {mode: '100644', object: 'c'.repeat(40)},
  after: {mode: '100644', object: 'd'.repeat(40)}}));
const maintenanceSelection = paths => selectTargets(paths, {maintenanceChanges: changes(paths)});

test('Native Core matrix retains Darwin profiles and adds Linux common without multiplying portable targets', t => {
  const core = jobs['core-darwin'], common = jobs['core-common'];
  const partitions = [...core.strategy.matrix.partition, ...common.strategy.matrix.partition.filter(value => value.startsWith('linux-common-'))];
  assert.deepEqual([...partitions].sort(), [...nativeCoreCiPartitions, ...nativeCoreLinuxCommonPartitions].sort());
  const selected = [{target: 'js', partition: '1/4'}].concat(all.flatMap(target => common.strategy.matrix.partition.map(partition => ({target, partition})))
    .filter(row => !common.strategy.matrix.exclude.some(excluded => excluded.target === row.target && excluded.partition === row.partition)))
    .concat(core.strategy.matrix.partition.map(partition => ({target: 'native', partition})));
  assert.deepEqual(selected.map(row => JSON.stringify(row)).sort(), [{target: 'js', partition: '1/4'}, {target: 'wasm', partition: '1/4'},
    ...nativeCoreLinuxCommonPartitions.map(partition => ({target: 'native', partition})),
    ...nativeCoreCiPartitions.map(partition => ({target: 'native', partition}))].map(row => JSON.stringify(row)).sort());
  assert.equal(core.name, "core (${{ matrix.target }}${{ matrix.target == 'native' && format(' {0}', matrix.partition) || '' }})");
  assert.equal(core.strategy['fail-fast'], false);
  assert(jobs.check.needs.includes('core'));
  assert.equal(core['continue-on-error'], undefined);
  const checks = core.steps.filter(step => step.name === 'Check common core');
  assert.equal(checks.length, 1);
  const [check] = checks;
  assert.equal(check.run, 'moon check --target "${{ matrix.target }}" --deny-warn');
  assert.equal(check.if, "${{ matrix.target != 'native' || matrix.partition == '1/2' }}");
  assert.equal(check['continue-on-error'], undefined);
  const checked = selected.filter(matrix => runInNewContext(check.if.slice(3, -2), {matrix}));
  assert.deepEqual(checked, [{target: 'js', partition: '1/4'},
    {target: 'wasm', partition: '1/4'}, {target: 'native', partition: '1/2'}]);
  // The complete matrix above requires this Native owner. The existing final
  // gate must reject missing, failed, cancelled or skipped Core matrix work.
  const full = selectTargets(['.github/workflows/ci.yml']);
  assert(full.targets.includes('native'));
  assert.equal(gateJobRequired(full, 'core'), true);
  assert.doesNotThrow(() => verifyGate(plan(full), results(full), context));
  for (const result of ['failure', 'cancelled', 'skipped', undefined]) {
    assert.throws(() => verifyGate(plan(full), {...results(full), core: {result}}, context));
  }
  const command = core.steps.find(step => step.name === 'Test common core');
  assert.equal(command.env.ACTQL_TEST_NATIVE_CORE_PARTITION,
    "${{ matrix.target == 'native' && !startsWith(matrix.partition, 'linux-common-') && matrix.partition || '' }}");
  assert.equal(command.env.ACTQL_TEST_NATIVE_CORE_SCOPED_JOBS,
    '1');
  const artifact = core.steps.find(step => step.name === 'Retain only sanitized current Native compiler diagnostics');
  assert(artifact.with.name.includes('${{ strategy.job-index }}'));
  assert(!artifact.with.name.includes('${{ matrix.partition }}'), 'Partition slashes are invalid artifact names');
  const f = nativeCoreCommandPort(t, command.run);
  for (const partition of partitions) for (const status of [0, 7]) {
    const {result, calls} = f.run(partition, {clock: status, ordinary: status});
    assert.equal(result.error, undefined); assert.equal(result.signal, null);
    assert.equal(result.status, status, result.stderr);
    if (partition.startsWith('linux-common-')) {
      assert.equal(calls.length, 1);
      assert.equal(calls[0].entry, 'scripts/test-native-core-linux-common.mjs');
      assert.equal(calls[0].args[0], partition); assert.equal(calls[0].backend, '0');
      continue;
    }
    assert.equal(calls[0].phase, 'clock'); assert.equal(calls[0].partition, '');
    assert(calls[0].args.includes('platform_native/trusted_clock'));
    const profiles = calls.filter(call => call.phase === 'profile');
    assert.deepEqual(profiles.map(call => call.partition), status ? [] :
      partition === '1/2' ? [partition, 'source'] : [partition]);
    for (const call of profiles) {
      assert.equal(call.entry, 'scripts/test-native-core.mjs'); assert.equal(call.backend, '0');
      for (const flag of ['--deny-warn', '--release', '--strip', '--no-parallelize']) assert(call.args.includes(flag));
      assert.equal(Number(call.args[call.args.indexOf('-j') + 1]), 2);
      assert(!call.args.some(arg => /^(?:--filter|--index|--test-name-pattern)(?:=|$)/u.test(arg)));
    }
  }
});


// Execute the actual YAML recipe with its public partition module. Only the
// compiler entrances are command ports; no test/runtime compiler is started.
function nativeCoreCommandPort(t, command) {
  const root = mkdtempSync(join(tmpdir(), 'actql-native-partition-workflow-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  mkdirSync(join(root, 'scripts'));
  writeFileSync(join(root, 'scripts/ci-core-partitions.mjs'),
    readFileSync(new URL('./ci-core-partitions.mjs', import.meta.url)));
  const log = join(root, 'commands.jsonl');
  writeFileSync(join(root, 'node'), '#!' + process.execPath + '\n' + `
    const {appendFileSync}=require('node:fs'),{spawnSync}=require('node:child_process');
    const args=process.argv.slice(2),entry=args.shift();
    if(entry==='--input-type=module') {
      const result=spawnSync(process.execPath,[entry,...args],{stdio:'inherit',env:process.env});
      process.exit(result.status??1);
    }
    const phase=entry==='scripts/test-native-core-linux-common.mjs'?'linux':args.includes('--release')?'profile':'clock';
    const partition=process.env.ACTQL_TEST_NATIVE_CORE_PARTITION??'';
    appendFileSync(${JSON.stringify(log)},JSON.stringify({entry,args,phase,partition,pid:process.pid,
      backend:process.env.MOONBIT_NEW_NATIVE,cache:process.env.ACTQL_TEST_NATIVE_CORE_CCACHE,
      cacheDirectory:process.env.ACTQL_TEST_NATIVE_CORE_CCACHE_DIR})+'\\n');
    if(phase==='profile'&&partition!=='source'&&process.env.ACTQL_FIXTURE_SIGNAL==='ordinary')process.kill(process.pid,'SIGTERM');
    else process.exit(Number(process.env[phase==='clock'?'ACTQL_FIXTURE_CLOCK_EXIT':
      partition==='source'?'ACTQL_FIXTURE_SOURCE_EXIT':'ACTQL_FIXTURE_ORDINARY_EXIT']??0));
  `);
  chmodSync(join(root, 'node'), 0o755);
  return {run(partition, {clock = 0, ordinary = 0, source = 0, signal = '', readonlyCache = false, hostedPlan = false} = {}) {
    writeFileSync(log, '');
    const run = command.replaceAll('${{ matrix.target }}', 'native')
      .replaceAll('${{ matrix.partition }}', partition);
    const result = spawnSync('bash', ['-eo', 'pipefail', '-c',
      (readonlyCache ? 'readonly ACTQL_TEST_NATIVE_CORE_CCACHE\n' : '') + run], {cwd: root,
      encoding: 'utf8', timeout: 5000, env: {...process.env,
        PATH: root + ':' + process.env.PATH, CI_PLAN: '',
        CI_PLAN_PATH: hostedPlan ? join(root, 'original-hosted-plan.json') : '',
        ACTQL_TEST_NATIVE_CORE_PARTITION: partition.startsWith('linux-common-') ? '' : partition,
        ACTQL_TEST_NATIVE_CORE_CCACHE: '/explicit-original-cache',
        ACTQL_TEST_NATIVE_CORE_CCACHE_DIR: '/explicit-original-cache-directory',
        ACTQL_FIXTURE_CLOCK_EXIT: String(clock), ACTQL_FIXTURE_ORDINARY_EXIT: String(ordinary),
        ACTQL_FIXTURE_SOURCE_EXIT: String(source), ACTQL_FIXTURE_SIGNAL: signal}});
    return {result, calls: readFileSync(log, 'utf8').split('\n').filter(Boolean).map(line => JSON.parse(line))};
  }};
}

test('Darwin Source co-location retains independent failures and its original non-cache child', t => {
  const command = jobs['core-darwin'].steps.find(step => step.name === 'Test common core');
  const f = nativeCoreCommandPort(t, command.run);
  for (const ordinary of [0, 7]) {
    const local = f.run('', {ordinary});
    assert.equal(local.result.status, ordinary, local.result.stderr);
    assert.deepEqual(local.calls.map(call => [call.phase, call.partition]),
      [['clock', ''], ['profile', '']], 'local Core keeps one complete original invocation');
  }
  const missingHostedPartition = f.run('', {hostedPlan: true});
  assert.notEqual(missingHostedPartition.result.status, 0);
  assert.match(missingHostedPartition.result.stderr, /Unknown hosted Native Core partition/u);
  assert.equal(missingHostedPartition.calls.filter(call => call.phase === 'profile').length, 0);
  for (const [ordinary, source] of [[0, 0], [7, 0], [0, 9], [7, 9]]) {
    const {result, calls} = f.run('1/2', {ordinary, source});
    assert.ifError(result.error); assert.equal(result.signal, null);
    assert.equal(result.status, ordinary || source, result.stderr);
    const selected = calls.filter(call => call.phase === 'profile');
    assert.deepEqual(selected.map(call => call.partition), ['1/2', 'source']);
    assert.notEqual(selected[0].pid, selected[1].pid, 'each original entrance is a fresh process');
    assert.equal(selected[0].cache, '/explicit-original-cache');
    assert.equal(selected[0].cacheDirectory, '/explicit-original-cache-directory');
    assert.equal(selected[1].cache, undefined); assert.equal(selected[1].cacheDirectory, undefined);
  }
  const stopped = f.run('1/2', {signal: 'ordinary'});
  assert.equal(stopped.result.status, 143, stopped.result.stderr);
  assert.deepEqual(stopped.calls.filter(call => call.phase === 'profile').map(call => call.partition), ['1/2']);
  const retainedCache = f.run('1/2', {readonlyCache: true});
  assert.notEqual(retainedCache.result.status, 0, 'cannot select Source if cache isolation failed');
  assert.deepEqual(retainedCache.calls.filter(call => call.phase === 'profile').map(call => call.partition), ['1/2']);
  const invalid = f.run('foreign');
  assert.notEqual(invalid.result.status, 0);
  assert.match(invalid.result.stderr, /Unknown hosted Native Core partition/u);
  assert.equal(invalid.calls.filter(call => call.phase === 'profile').length, 0);
});

test('required aggregate rejects failed, cancelled, skipped and missing selected jobs', () => {
  const selection = selectTargets(['src/unregistered/engine.mbt']);
  assert.equal(verifyGate(plan(selection), results(selection), context).length, gateJobs.length);
  for (const name of gateJobs.filter(name => gateJobRequired(selection, name))) {
    for (const result of ['failure', 'cancelled', 'skipped', 'in_progress', undefined]) {
      const candidate = results(selection); candidate[name] = {result};
      assert.throws(() => verifyGate(plan(selection), candidate, context), undefined, `${name}: ${result}`);
    }
    const candidate = results(selection); delete candidate[name];
    assert.throws(() => verifyGate(plan(selection), candidate, context), /dependency inventory/u);
  }
  assert.throws(() => verifyGate(plan(selection), {...results(selection), unknown: {result: 'success'}}, context));
  const portable = selectTargets(['README.md']);
  assert.doesNotThrow(() => verifyGate(plan(portable), results(portable), context));
  assert.throws(() => verifyGate(plan(selection), results(portable), context));
});

// The unchanged annotation can be far outside the edited hunk.
test('whole source versions retain target and ownership annotation context', () => {
  const base = 'a'.repeat(40), head = 'b'.repeat(40);
  const result = readChanges({pull_request: {base: {sha: base}}}, args =>
    args[0] === 'rev-parse' ? head : args[0] === 'show' ? '#cfg(target="js")\nfn f() { 2 }' :
      args.includes('--name-only') ? 'src/a/plain.mbt\0' : '+ 2');
  assert.equal(result.targetSensitiveDiff, true);
  const added = readChanges({pull_request: {base: {sha: base}}}, args => {
    if (args[0] === 'show') throw new Error('new source has no base object');
    return args[0] === 'rev-parse' ? head : args.includes('--name-only') ? 'src/a/new.mbt\0' : '+ 2';
  });
  assert.equal(added.targetSensitiveDiff, true);
});

test('canonical identities in otherwise portable source files retain all targets', () => {
  const base = 'a'.repeat(40), head = 'b'.repeat(40);
  for (const token of ['law_cid', '@sha256.hash(text)', 'canonical_value', 'preimage', 'hash_value']) {
    const result = readChanges({pull_request: {base: {sha: base}}}, args =>
      args[0] === 'rev-parse' ? head : args[0] === 'show' ? token :
        args.includes('--name-only') ? 'src/graph_contract/contract.mbt\0' : '+ordinary edit');
    assert.equal(result.targetSensitiveDiff, true, token);
    assert.deepEqual(selectTargets(result.paths, result).targets, all, token);
  }
});

test('P1: unregistered runtime files and configuration cannot qualify by directory', () => {
  for (const path of [
    'adapters/new-engine/index.mjs',
    'adapters/workers/wrangler.toml',
    'packages/sdk/tsconfig.json',
    'src/source_frontend/lower.mbt',
  ]) {
    const selected = selectTargets([path], {targetSensitiveDiff: false});
    assert.deepEqual(selected.targets, all, path);
    assert.equal(selected.macos, true, path);
  }
});
test('an existing unregistered MoonBit file stays full even with portable contents', () => {
  const base = 'a'.repeat(40), head = 'b'.repeat(40);
  const result = readChanges({pull_request: {base: {sha: base}}}, args =>
    args[0] === 'rev-parse' ? head : args[0] === 'show' ? 'fn add(a: Int, b: Int) -> Int { a + b }' :
      args.includes('--name-only') ? 'src/unregistered/arithmetic.mbt\0' : '+ a + b');
  assert.equal(result.targetSensitiveDiff, false);
  assert.deepEqual(selectTargets(result.paths, result).targets, all);
  assert.equal(selectTargets(result.paths, result).macos, true);
});
test('only the exact registered portable file qualifies, not siblings or configuration', () => {
  assert.deepEqual(selectTargets(['src/source_span/span.mbt']).targets, ['js']);
  for (const path of ['src/source_span/other.mbt', 'src/source_span/moon.pkg',
    'scripts/worktree-inventory.config.json', 'docs/new-engine.md',
    'packages/sdk/index.mjs', 'adapters/workers/runtime.mjs']) {
    assert.deepEqual(selectTargets([path]).targets, all, path);
  }
  assert.deepEqual(selectTargets(['src/source_span/span.mbt'], {targetSensitiveDiff: true}).targets, all);
});

test('registered files cannot hide type/mode changes or head-only target annotations', () => {
  const base = 'a'.repeat(40), head = 'b'.repeat(40), path = 'src/source_span/span.mbt';
  const calls = [];
  const result = readChanges({pull_request: {base: {sha: base}}}, args => {
    if (args[0] === 'rev-parse') return head;
    if (args[0] === 'show') {
      calls.push(args[1]);
      return args[1].startsWith(base) ? 'pub struct Span { line : Int }' : '#cfg(target="js")\npub struct Span { line : Int }';
    }
    return args.includes('--name-only') ? path + '\0' : '+ line : Int';
  });
  assert.equal(result.targetSensitiveDiff, true);
  assert.deepEqual(calls, [`${base}:${path}`, `${head}:${path}`]);
  for (const header of ['old mode 100644\nnew mode 120000', 'new file mode 100644', 'deleted file mode 100644']) {
    const changed = readChanges({pull_request: {base: {sha: base}}}, args =>
      args[0] === 'rev-parse' ? head : args[0] === 'show' ? 'pub struct Span { line : Int }' :
        args.includes('--name-only') ? path + '\0' : header + '\n+ other-path');
    assert.equal(changed.targetSensitiveDiff, true, header);
    assert.deepEqual(selectTargets(changed.paths, changed).targets, all);
  }
});

test('CI selection follows the owned contract baseline without a legacy exception', () => {
  for (const path of ['README.md', 'src/unregistered/engine.mbt']) {
    assert.equal(validateSelection(selectTargets([path])).schema, 'actql-ci-targets/0.1');
  }
  const previous = ['actql-ci-targets', '1'].join('/');
  assert.throws(() => validateSelection({...selectTargets(['README.md']), schema: previous}));
  for (const file of ['ci-targets.mjs', 'ci-targets.test.mjs']) {
    assert.deepEqual(occurrences(readFileSync(new URL(file, import.meta.url), 'utf8'), `scripts/${file}`), []);
  }
});


test('reviewed evaluation test modifications retain the existing light gate', () => {
  const paths = ['examples/infer-evaluation/evaluate.test.mjs',
    'examples/infer-evaluation/compare-source-instructions.test.mjs'];
  for (const path of paths) {
    assert(readFileSync(new URL('../' + path, import.meta.url), 'utf8').includes('test('));
    const value = validateSelection(maintenanceSelection([path]));
    assert.equal(value.profile, 'maintenance', path);
    assert.equal(deepProofRequired(value), false);
    assert.equal(verifyGate(plan(value), results(value), context).length, gateJobs.length);
  }
  assert.equal(maintenanceSelection([...paths, 'docs/development.md']).profile, 'maintenance');
  for (const input of ['examples/infer-evaluation/evaluate.mjs',
    'examples/infer-evaluation/compare-source-instructions.mjs',
    'examples/infer-evaluation/evidence-reference.mjs',
    'packages/sdk/host-port.mjs', 'src/client_local_host/moon.pkg',
    'package.json', 'toolchain.json', '.github/workflows/ci.yml',
    'proofs/relation-pipeline/inventory.mjs', 'examples/infer-evaluation/new.test.mjs']) {
    const value = maintenanceSelection([paths[0], input]);
    assert.equal(value.profile, 'full', input);
    assert.equal(deepProofRequired(value), true, input);
  }
});

test('actual evaluation Source Git changes reject additions deletions renames and shared inputs', t => {
  const checkout = mkdtempSync(join(tmpdir(), 'actql-ci-evaluation-'));
  t.after(() => rmSync(checkout, {recursive: true, force: true}));
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
  Object.assign(env, {GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null'});
  const git = args => {
    const result = spawnSync('git', args, {cwd: checkout, env, encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr); return result.stdout;
  };
  const reviewed = ['examples/infer-evaluation/evaluate.test.mjs',
    'examples/infer-evaluation/compare-source-instructions.test.mjs'];
  const shared = ['examples/infer-evaluation/evaluate.mjs', 'packages/sdk/host-port.mjs',
    'src/client_local_host/source_capture.mbt', 'package.json', 'toolchain.json',
    '.github/workflows/ci.yml', 'proofs/relation-pipeline/inventory.mjs'];
  for (const file of [...reviewed, ...shared, 'docs/development.md']) {
    const target = join(checkout, file); mkdirSync(dirname(target), {recursive: true});
    writeFileSync(target, readFileSync(new URL('../' + file, import.meta.url)));
  }
  git(['init', '--quiet']); git(['config', 'user.name', 'Evaluation Source Fixture']);
  git(['config', 'user.email', 'evaluation@example.invalid']); git(['config', 'commit.gpgsign', 'false']);
  git(['config', 'core.filemode', 'true']); git(['add', '.']); git(['commit', '--quiet', '-m', 'Actual original Source inputs']);
  const base = git(['rev-parse', 'HEAD']).trim();
  const edit = file => writeFileSync(join(checkout, file), readFileSync(join(checkout, file), 'utf8') + '\n');
  const inspect = (before = base) => {
    git(['add', '--all']); git(['commit', '--quiet', '-m', 'Independent fixture change']);
    const read = readChanges({pull_request: {base: {sha: before}}}, git);
    return validateSelection(selectTargets(read.paths, read));
  };
  for (const file of reviewed) {
    git(['reset', '--hard', base]); edit(file);
    const value = inspect(); assert.equal(value.profile, 'maintenance', file);
    const revision = git(['rev-parse', 'HEAD']).trim();
    const envelope = {sourceRevision: revision, selection: value};
    assert.equal(verifyGate(envelope, results(value), {event: 'pull_request', sourceRevision: revision}).length, gateJobs.length);
  }
  git(['reset', '--hard', base]);
  for (const file of [...reviewed, 'docs/development.md']) edit(file);
  assert.equal(inspect().profile, 'maintenance', 'known independent regions keep the same required union');
  for (const file of shared) {
    git(['reset', '--hard', base]); edit(reviewed[0]); edit(file);
    assert.equal(inspect().profile, 'full', file);
  }
  git(['reset', '--hard', base]); git(['rm', reviewed[0]]); assert.equal(inspect().profile, 'full');
  git(['reset', '--hard', base]); git(['rm', reviewed[1]]); git(['mv', reviewed[0], reviewed[1]]);
  assert.equal(inspect().profile, 'full', 'a rename between two reviewed names still exposes the deletion');
  git(['reset', '--hard', base]); chmodSync(join(checkout, reviewed[0]), 0o755);
  assert.equal(inspect().profile, 'full');
  git(['reset', '--hard', base]); git(['rm', reviewed[0]]); git(['commit', '--quiet', '-m', 'Absent reviewed file']);
  const absent = git(['rev-parse', 'HEAD']).trim();
  writeFileSync(join(checkout, reviewed[0]), readFileSync(new URL('../' + reviewed[0], import.meta.url)));
  assert.equal(inspect(absent).profile, 'full', 'a reviewed pathname is not permission for a new file');
});

test('Native command parsing remains a full execution input when its implementation changes alone', () => {
  const path = 'scripts/verification-actions.mjs';
  for (const caller of ['native-core-test-selection.mjs', 'native-core-scoped-profile.mjs']) {
    const source = readFileSync(new URL(caller, import.meta.url), 'utf8');
    assert(source.includes("import {parseCommands} from './verification-actions.mjs'"), caller);
  }
  const selection = maintenanceSelection([path]);
  assert.equal(selection.profile, 'full');
  assert.deepEqual(selection.targets, ['js', 'wasm', 'native']);
  assert.equal(selection.macos, true);
  assert.equal(deepProofRequired(selection), true);
  assert(!maintenanceFiles.includes(path));
  for (const job of ['core', 'native', 'native-macos', 'host', 'client', 'pipeline-evidence', 'pipeline-validation'])
    assert.equal(gateJobRequired(selection, job), true, job);
  assert.throws(() => verifyGate(plan(selection), {...results(selection), core: {result: 'skipped'}}, context));
  assert.equal(maintenanceSelection(['scripts/verification-actions.test.mjs']).profile, 'maintenance');
});

test('maintenance inventory is nonempty unique and every existing reviewed modification qualifies', () => {
  assert(maintenanceFiles.length > 0);
  assert.equal(new Set(maintenanceFiles).size, maintenanceFiles.length);
  for (const path of maintenanceFiles) {
    const selection = validateSelection(maintenanceSelection([path]));
    assert.equal(selection.profile, documentationFiles.includes(path) ? 'documentation' : 'maintenance', path);
    const lines = verifyGate(plan(selection), results(selection), context);
    assert(lines.some(line => line.startsWith('NOT APPLICABLE pipeline-evidence')));
    assert(lines.some(line => line.startsWith('PASS lint')));
    assert(lines.some(line => line.startsWith('PASS spec')));
  }
  assert.equal(maintenanceSelection(maintenanceFiles).profile, 'maintenance');
  for (const path of ['README.md', 'src/source_span/span.mbt', 'packages/sdk/README.md',
    'docs/spec/language.md', 'docs/design/something.md', 'docs/reviews/report.json',
    'scripts/local-checks.mjs', 'proofs/relation-pipeline/ci-artifacts.mjs',
    'scripts/ci-review.config.json', 'scripts/new-reporter.mjs',
    'scripts/ci-artifact-reader.mjs', 'scripts/ci-artifact-reader.test.mjs',
    'scripts/verification-actions.mjs']) {
    assert.equal(maintenanceSelection([path]).profile, 'full', path);
    assert.equal(maintenanceSelection([maintenanceFiles[0], path]).profile, 'full', path);
  }
  assert.equal(selectTargets(maintenanceFiles).profile, 'full', 'paths alone are not modification evidence');
});

test('documentation modifications select the same mandatory lightweight jobs on PR and main push', () => {
  for (const event of ['pull_request', 'push']) for (const paths of [[...documentationFiles], ...documentationFiles.map(path => [path])]) {
    const selection = validateSelection(selectTargets(paths, {event, maintenanceChanges: changes(paths)}));
    assert.equal(selection.profile, 'documentation');
    assert.equal(deepProofRequired(selection), false);
    assert.equal(pythonWheelAcceptanceRequired(selection), false);
    for (const name of gateJobs) assert.equal(gateJobRequired(selection, name),
      ['select-targets', 'preflight', 'lint', 'spec'].includes(name), name);
    const env = {...context, event};
    verifyGate(plan(selection), results(selection), env);
    for (const name of ['select-targets', 'preflight', 'lint', 'spec']) for (const result of ['failure', 'cancelled', 'skipped', undefined])
      assert.throws(() => verifyGate(plan(selection), {...results(selection), [name]: {result}}, env), new RegExp(name));
    for (const mutate of [
      value => {value.event = 'schedule';}, value => {value.event = 'workflow_dispatch';},
      value => {value.paths.push('docs/spec/language.md');},
      value => {value.maintenanceChanges[0].before.mode = '120000';},
      value => {value.maintenanceChanges[0].after.mode = '100755';},
      value => {value.maintenanceChanges[0].before.object = '0'.repeat(40);},
      value => {value.maintenanceChanges[0].after.object = value.maintenanceChanges[0].before.object;},
    ]) {
      const changed = structuredClone(selection); mutate(changed);
      assert.throws(() => validateSelection(changed));
    }
  }
  const paths = ['docs/reference/status.md'];
  for (const event of ['schedule', 'workflow_dispatch'])
    assert.equal(selectTargets(paths, {event, maintenanceChanges: changes(paths)}).profile, 'full');
  assert.equal(selectTargets(paths, {draft: true, maintenanceChanges: changes(paths)}).profile, 'draft');
  for (const event of ['pull_request', 'push']) {
    assert.equal(selectTargets(paths, {event}).profile, 'full', 'a pathname alone is insufficient');
    assert.equal(selectTargets(paths, {event, failure: 'Missing Git endpoint', maintenanceChanges: changes(paths)}).profile, 'full');
    for (const other of ['docs/spec/language.md', 'docs/design/versioning.md', 'docs/reference/check-reasons.md',
      'docs/getting-started/quickstart.md', 'docs/development.md', 'README.md',
      'docs/guides/unreviewed.md', 'spec/contracts/example.json', 'src/source_span/span.mbt', 'package.json']) {
      const mixed = [...paths, other];
      assert.equal(selectTargets(mixed, {event, maintenanceChanges: changes(mixed)}).profile, 'full', other);
    }
  }
});

test('real Git endpoints admit only existing regular documentation modifications for both events', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-docs-endpoints-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const git = args => {
    const result = spawnSync('git', args, {cwd: root, encoding: 'utf8', timeout: 5000});
    assert.equal(result.error, undefined); assert.equal(result.status, 0, result.stderr);
    return result.stdout;
  };
  git(['init', '--quiet']); git(['config', 'user.name', 'Fixture']); git(['config', 'user.email', 'fixture@example.invalid']);
  const path = 'docs/reference/status.md'; mkdirSync(dirname(join(root, path)), {recursive: true});
  writeFileSync(join(root, path), '# Original status\n');
  git(['add', '.']); git(['-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'Original documentation']);
  const before = git(['rev-parse', 'HEAD']).trim();
  const inspect = event => {
    const after = git(['rev-parse', 'HEAD']).trim();
    const read = event === 'push' ? readPushChanges({ref: 'refs/heads/main', before, after}, after, git)
      : readChanges({pull_request: {base: {sha: before}}}, git);
    return selectTargets(read.paths, {...read, event});
  };
  const commit = () => {git(['add', '-A']); git(['-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'Changed documentation']);};
  const reset = () => git(['reset', '--hard', before]);
  writeFileSync(join(root, path), '# Updated status\nRun and cleanup are documented, not executed.\n'); commit();
  for (const event of ['pull_request', 'push']) {
    assert.equal(inspect(event).profile, 'documentation');
    const after = git(['rev-parse', 'HEAD']).trim();
    const payload = event === 'push' ? {ref: 'refs/heads/main', before, after}
      : {action: 'synchronize', pull_request: {draft: false, base: {sha: before}}};
    const eventFile = join(root, 'event.json'), output = join(root, 'output.txt');
    writeFileSync(eventFile, JSON.stringify(payload));
    for (const command of ['documentation-candidate', null]) {
      writeFileSync(output, '');
      const result = spawnSync(process.execPath, [fileURLToPath(new URL('./ci-targets.mjs', import.meta.url)), ...(command ? [command] : [])], {
        cwd: root, encoding: 'utf8', timeout: 10000,
        env: {...process.env, GITHUB_EVENT_NAME: event, GITHUB_EVENT_PATH: eventFile, GITHUB_SHA: after,
          GITHUB_REF: event === 'push' ? 'refs/heads/main' : 'refs/pull/1/merge', GITHUB_OUTPUT: output, GITHUB_STEP_SUMMARY: ''},
      });
      assert.equal(result.error, undefined); assert.equal(result.status, 0, result.stderr);
      const published = readFileSync(output, 'utf8');
      if (command) assert.equal(published, 'required=true\n');
      else {
        const envelope = JSON.parse(published.split('\n').find(line => line.startsWith('plan=')).slice(5));
        assert.equal(envelope.sourceRevision, after); assert.equal(envelope.selection.profile, 'documentation');
        assert(published.includes('deep_proofs=false\n')); assert(published.includes('python_wheels=false\n'));
      }
    }
  }
  // Event/command outputs are not fixture Source inputs for the next commit.
  rmSync(join(root, 'event.json')); rmSync(join(root, 'output.txt'));
  for (const edit of [
    () => {chmodSync(join(root, path), 0o755);},
    () => {git(['rm', path]);},
    () => {git(['mv', path, 'CONTRIBUTING.md']);},
    () => {git(['rm', path]); mkdirSync(dirname(join(root, path)), {recursive: true}); symlinkSync('../../target', join(root, path));},
    () => {writeFileSync(join(root, 'CONTRIBUTING.md'), '# Newly added reviewed filename\n');},
    () => {writeFileSync(join(root, 'product.mbt'), 'new runtime input\n');},
  ]) {
    reset(); edit(); commit();
    for (const event of ['pull_request', 'push']) assert.equal(inspect(event).profile, 'full');
  }
});

test('documentation keeps required job names and real document checks without compiler or product fan-out', () => {
  for (const event of ['pull_request', 'push']) {
    const paths = ['docs/reference/status.md'];
    const selection = selectTargets(paths, {event, maintenanceChanges: changes(paths)});
    const needs = Object.fromEntries(Object.keys(jobs).map(name => [name, {result: 'skipped'}]));
    needs['select-targets'] = {result: 'success', outputs: {profile: selection.profile, targets: JSON.stringify(selection.targets),
      macos: 'false', deep_proofs: 'false', python_wheels: 'false'}};
    for (const [name, job] of Object.entries(jobs)) {
      const expression = job.if.replace(/^\$\{\{\s*|\s*\}\}$/gu, '')
        .replace(/needs\.([a-z][a-z0-9-]*)/gu, (_, key) => `needs[${JSON.stringify(key)}]`);
      const enabled = runInNewContext(expression, {needs, inputs: {}, vars: {},
        always: () => true, cancelled: () => false, toJSON: JSON.stringify, fromJSON: JSON.parse,
        contains: (items, item) => items.includes(item),
        github: {event_name: event, ref: 'refs/heads/main', event: {repository: {visibility: 'public', private: false}, pull_request: {draft: false}}},
      }, {timeout: 100});
      assert.equal(enabled, ['select-targets', 'preflight', 'lint', 'spec', 'check'].includes(name), `${event}/${name}`);
    }
  }
  const enabled = name => jobs[name].steps.filter(step => draftStepEnabled(step, 'documentation'));
  for (const name of ['preflight', 'lint', 'spec']) {
    const steps = enabled(name);
    assert(!steps.some(step => /setup-toolchain|setup-python/u.test(step.uses ?? '') || /\bmoon\b|setup-moonbit|check-moonbit-api/u.test(step.run ?? '')), name);
    assert(steps.some(step => step.uses?.startsWith('actions/setup-node@')));
    assert(steps.some(step => step.run === 'npm ci'));
    assert(!steps.some(step => step['continue-on-error']));
  }
  assert(enabled('preflight').some(step => step.run === 'npm run check:metadata'));
  assert(enabled('preflight').some(step => step.run === 'node scripts/ci-preflight.mjs'));
  const lint = enabled('lint').filter(step => step.run && step.run !== 'npm ci');
  assert(lint.some(step => step.run.includes('scripts/document-validation.test.mjs')));
  for (const step of lint) {
    assert(step.run.startsWith('node scripts/local-checks.mjs test node '));
    assert(step.run.includes('--timeout-seconds')); assert(step.run.includes('--kill-grace-seconds'));
    assert(!step.run.includes('continue-on-error'));
  }
  for (const recipe of ['check:links', 'check:examples'])
    assert(enabled('spec').some(step => step.run === `npm run ${recipe}`));
});

test('raw Git classification rejects additions deletions renames modes and malformed inventories', () => {
  const path = 'scripts/worktree-inventory.mjs', base = 'a'.repeat(40);
  const raw = (status = 'M', before = '100644', after = '100644') =>
    `:${before} ${after} ${'c'.repeat(40)} ${'d'.repeat(40)} ${status}\0${path}\0`;
  const inspect = output => readChanges({pull_request: {base: {sha: base}}}, args =>
    args[0] === 'rev-parse' ? head : args.includes('--name-only') ? path + '\0' :
      args.includes('--raw') ? output : '+report hash and target text');
  const modified = inspect(raw());
  assert.equal(modified.targetSensitiveDiff, true, 'report terminology still triggers existing target scanner');
  assert.equal(selectTargets(modified.paths, modified).profile, 'maintenance');
  for (const output of [raw('A', '000000'), raw('D', '100644', '000000'), raw('R100'),
    raw('T', '100644', '120000'), raw('M', '100644', '100755'), raw('M', '120000', '120000')]) {
    const changed = inspect(output);
    assert.equal(selectTargets(changed.paths, changed).profile, 'full');
    assert.deepEqual(selectTargets(changed.paths, changed).targets, all);
  }
  for (const output of ['', raw().slice(0, -1), raw() + raw(), raw().replace(path, 'scripts/other.mjs'), 'malformed\0']) {
    assert.throws(() => inspect(output));
  }
});

test('maintenance plans reject inconsistent fields identities and input membership', () => {
  const selection = maintenanceSelection(['docs/development.md']);
  for (const mutate of [
    value => { value.profile = 'unknown'; }, value => { value.event = 'push'; },
    value => { value.macos = true; }, value => { value.targets = all; },
    value => { value.paths.push('unknown'); }, value => { value.paths.push(value.paths[0]); },
    value => { value.maintenanceChanges = null; }, value => { value.maintenanceChanges[0].path = 'unknown'; },
    value => { value.maintenanceChanges[0].before.mode = '120000'; },
    value => { value.maintenanceChanges[0].after.object = value.maintenanceChanges[0].before.object; },
    value => { value.maintenanceChanges[0].before.object = 'bad'; },
    value => { value.maintenanceChanges[0].before.object = '0'.repeat(40); },
    value => { value.maintenanceChanges[0].status = 'M'; }, value => { value.extra = true; },
    value => { delete value.profile; }, value => { value.reason = ''; },
  ]) {
    const invalid = structuredClone(selection); mutate(invalid);
    assert.throws(() => validateSelection(invalid));
  }
  assert.throws(() => verifyGate({...plan(selection), sourceRevision: 'a'.repeat(40)}, results(selection), context));
  assert.throws(() => verifyGate(plan(selection), results(selection), {...context, event: 'push'}));
  assert.throws(() => verifyGate({...plan(selection), extra: true}, results(selection), context));
  for (const event of ['push', 'workflow_dispatch', 'merge_group']) {
    const value = selectTargets(maintenanceFiles, {event, maintenanceChanges: changes(maintenanceFiles)});
    assert.equal(value.profile, 'full'); assert.deepEqual(value.targets, all);
    assert.throws(() => validateSelection({...value, targets: ['js']}));
    if (event !== 'workflow_dispatch') assert.throws(() => validateSelection({...value, macos: false}));
  }
});

test('maintenance N/A is explicit and cannot hide execution or selected check failures', () => {
  const selection = maintenanceSelection(['docs/development.md']);
  for (const name of gateJobs) {
    const candidate = results(selection);
    candidate[name] = {result: candidate[name].result === 'success' ? 'skipped' : 'success'};
    assert.throws(() => verifyGate(plan(selection), candidate, context), undefined, name);
    for (const result of ['failure', 'cancelled', undefined]) {
      candidate[name] = {result};
      assert.throws(() => verifyGate(plan(selection), candidate, context), undefined, name);
    }
  }
});

// Exercise the real GitHub job expressions, including always() behavior.
const scheduled = (name, needs, inputs = {}, isCancelled = false) => {
  const expression = jobs[name].if.slice(3, -3).replace(/needs\.([a-z][a-z0-9-]*)/gu, (_, name) => `needs[${JSON.stringify(name)}]`);
  return Function('needs', 'inputs', 'always', 'cancelled', 'vars', 'github', 'toJSON', 'fromJSON', 'contains', `return (${expression});`)(needs, inputs, () => true, () => isCancelled,
    {}, {event: {repository: {visibility: 'public', private: false}}}, JSON.stringify, JSON.parse, (values, value) => values.includes(value));
};
test('pipeline evidence aggregates dependency failures but stops on workflow cancellation', () => {
  const names = jobs['pipeline-evidence'].needs;
  const healthy = Object.fromEntries(names.map(name => [name, {result: 'success'}]));
  for (const result of ['success', 'failure', 'cancelled', 'skipped', undefined]) {
    const needs = {...healthy, 'pipeline-capacity': {result}};
    assert.equal(scheduled('pipeline-evidence', needs), true, `dependency ${result} must be aggregated`);
    assert.equal(scheduled('pipeline-evidence', needs, {}, true), false,
      `workflow cancellation must stop evidence work after dependency ${result}`);
  }
  const selection = selectTargets(['src/unregistered/engine.mbt']);
  for (const result of ['failure', 'cancelled', 'skipped']) {
    const candidate = results(selection);
    candidate['pipeline-evidence'] = {result};
    assert.throws(() => verifyGate(plan(selection), candidate, context), /pipeline-evidence/u);
  }
});
test('aggregate workflow expressions run on mixed failures and skip only wholly unselected families', () => {
  for (const [name, groups] of [['client', ['client-packages', 'client-supported-versions', 'client-distribution', 'client-distribution-callers', 'client-distribution-mutations', 'client-distribution-packed', 'native-cli-installed', 'client-packed', 'client-packed-composition', 'client-salesforce']],
    ['pipeline-evidence', [...Object.values(partJobs), 'pipeline-validation']]]) {
    assert.deepEqual(jobs[name].needs, groups);
    assert.match(jobs[name].if, /always\(\)/u);
    const skipped = Object.fromEntries(groups.map(group => [group, {result: 'skipped'}]));
    assert.equal(scheduled(name, skipped), false);
    for (const group of groups.filter(group => group !== 'pipeline-validation')) for (const result of ['success', 'failure', 'cancelled', undefined]) {
      assert.equal(scheduled(name, {...skipped, [group]: {result}}), true, `${name}/${group}/${result}`);
    }
    assert.equal(scheduled(name, Object.fromEntries(groups.map(group => [group, {result: 'success'}]))), true);
    assert.equal(scheduled(name, skipped, {performance_matrix: true}), false);
  }
  const evidence = jobs['pipeline-evidence'];
  assert.equal(evidence.steps.find(step => step.name === 'Require every producer and mandatory validation before transfer').env.PIPELINE_NEEDS,
    '${{ toJSON(needs) }}');
  assert.equal(evidence.steps.find(step => step.run === 'node proofs/relation-pipeline/ci-parts.mjs join').env.PIPELINE_NEEDS,
    '${{ toJSON(needs) }}');
});

test('every heavy primitive is selected as one complete job and lint/spec always retain their tests', () => {
  const heavy = ['core', 'host', 'client-packages', 'client-readme-packed', 'client-supported-versions', 'client-distribution', 'client-distribution-callers',
    'client-distribution-mutations', 'client-distribution-packed', 'client-packed', 'client-packed-composition', 'client-salesforce',
    'native-cli-installed', 'native-cli-linux-local', 'native-cli-linux-local-installed', 'native-cli-linux-local-mock', 'native', 'session-evidence', 'session-controls', 'pipeline-mutations', 'pipeline-mutations-rest', 'pipeline-capacity', 'pipeline-capacity-mutants', 'pipeline-validation', 'native-macos', 'python-wheels',
    'native-separated-network', 'workers', 'connector-addition', 'duckdb-node'];
  for (const name of heavy) {
    assert(jobs[name].needs.includes('select-targets'));
    assert.equal(scheduled(name, {'select-targets': {outputs: {profile: 'maintenance', targets: '["js"]', macos: 'false'}},
      lint: {result: 'success'}, 'core-js': {result: 'skipped'}}), false);
    assert.equal(scheduled(name, {'select-targets': {result: 'success', outputs: {profile: 'full', targets: '["js","wasm","native"]', python_wheels: 'true', deep_proofs: 'true', macos: 'true'}},
      lint: {result: 'success'}, 'core-js': {result: 'success'}, 'native-cli-linux-local': {result: 'success'}}), true);
    assert.equal(scheduled(name, {'select-targets': {outputs: {profile: '', targets: '[]', macos: 'true'}},
      lint: {result: 'success'}, 'core-js': {result: 'skipped'}}), false);
  }
  assert.deepEqual(jobs.check.needs, gateJobs);
  for (const name of ['lint', 'spec']) assert.deepEqual(jobs[name].needs, ['select-targets']);
  const lint = jobs.lint.steps.map(step => step.run ?? '');
  assert(lint.includes('node --test scripts/ci-evidence.test.mjs'));
  assert(lint.includes('node --test scripts/worktree-inventory.test.mjs'));
  const reporter = readFileSync(new URL('./ci-evidence.test.mjs', import.meta.url), 'utf8');
  for (const file of ['ci-artifact-reader.test.mjs', 'ci-artifacts.test.mjs', 'verification-actions.test.mjs']) {
    assert(reporter.includes(`import './${file}';`), `Missing retained reporter suite ${file}`);
  }
  assert(jobs.spec.steps.some(step => step.run?.includes('npm run check:spec')));
});

test('full integration cannot skip, omit or fail any actual CLI acceptance job', () => {
  for (const [name, script] of [['native-cli-linux-local-installed', 'test-native-cli-source-free-install.mjs'],
    ['native-cli-linux-local-mock', 'test-native-cli-mock-install.mjs']]) {
    assert(jobs[name].steps.some(step =>
      step.run?.includes(`node scripts/${script}`) && step['continue-on-error'] === undefined),
    `The required Local job must execute ${script}`);
  }
  const selection = selectTargets(['README.md'], {event: 'workflow_dispatch', mainIntegration: true, nativeMacos: false});
  for (const name of ['native-cli-installed', 'native-cli-linux-local', 'native-cli-linux-local-installed', 'native-cli-linux-local-mock']) {
    for (const result of ['missing', 'failure', 'cancelled', 'skipped']) {
      const needs = results(selection);
      if (result === 'missing') delete needs[name];
      else needs[name].result = result;
      assert.throws(() => verifyGate(plan(selection), needs, {...context, event: 'workflow_dispatch'}), new RegExp(name));
    }
  }
});

test('actual final gate command fails closed for missing or corrupted plans', t => {
  const dir = mkdtempSync(join(tmpdir(), 'actql-pr-event-'));
  t.after(() => rmSync(dir, {recursive: true, force: true}));
  const eventPath = join(dir, 'event.json');
  writeFileSync(eventPath, JSON.stringify({action: 'synchronize', pull_request: {draft: false}}));
  const selection = maintenanceSelection(['docs/development.md']);
  const finalGate = jobs.check.steps.find(step => step.run?.includes('node scripts/ci-targets.mjs gate'));
  const prepare = jobs.check.steps.find(step => step.run === 'npm ci');
  const tools = jobs.check.steps.filter(step => step.uses?.startsWith('actions/setup-node@'));
  assert(finalGate && prepare);
  assert.equal(tools.length, 1, 'The same pinned Node prepares and runs the final gate');
  assert.equal(tools[0].with['node-version'], jobs['select-targets'].steps
    .find(step => step.uses?.startsWith('actions/setup-node@')).with['node-version']);
  assert.equal(tools[0].if, undefined);
  assert.equal(prepare.if, undefined, 'Failed selection still reaches the required gate');
  assert.equal(prepare['continue-on-error'], undefined);
  assert.equal(finalGate.if, undefined, 'Failed preparation cannot execute a stale gate');
  assert(jobs.check.steps.indexOf(tools[0]) < jobs.check.steps.indexOf(prepare));
  assert(jobs.check.steps.indexOf(prepare) < jobs.check.steps.indexOf(finalGate));
  const script = finalGate.run;
  const run = (value, needs = results(selection)) => spawnSync('bash', ['-eo', 'pipefail', '-c', script
    .replaceAll('${{ needs.select-targets.outputs.plan }}', value)
    .replaceAll('${{ toJSON(needs) }}', JSON.stringify(needs))], {cwd: new URL('../', import.meta.url),
    encoding: 'utf8', env: {...process.env, CI_PLAN: '', RESULTS: '',
      CI_PLAN_PATH: join(dir, 'plan.json'), RESULTS_PATH: join(dir, 'results.json'),
      GITHUB_SHA: head, GITHUB_EVENT_NAME: 'pull_request', GITHUB_EVENT_PATH: eventPath, GITHUB_STEP_SUMMARY: ''}});
  const good = run(JSON.stringify(plan(selection)));
  assert.equal(good.status, 0, good.stderr);
  assert.match(good.stdout, /NOT APPLICABLE pipeline-evidence/u);
  writeFileSync(eventPath, JSON.stringify({action: 'converted_to_draft', pull_request: {draft: true}}));
  const draftAttempt = run(JSON.stringify(plan(selection)));
  assert.notEqual(draftAttempt.status, 0);
  assert.match(draftAttempt.stderr, /awaiting ready_for_review/u);
  writeFileSync(eventPath, JSON.stringify({action: 'ready_for_review', pull_request: {draft: false}}));
  assert.equal(run(JSON.stringify(plan(selection))).status, 0);
  for (const value of ['', 'undefined', '{}', JSON.stringify({...plan(selection), sourceRevision: 'a'.repeat(40)})]) {
    assert.notEqual(run(value).status, 0);
  }
  for (const result of ['failure', 'cancelled', 'skipped', undefined]) {
    const needs = Object.fromEntries(gateJobs.map(name => [name, {result: name === 'select-targets' ? result : 'skipped'}]));
    assert.equal(scheduled('check', needs), true, 'Failed selection must not skip the required final gate');
    assert.notEqual(run('', needs).status, 0, 'No selection output is not a valid unselected profile');
    const withPlan = run(JSON.stringify(plan(selection)), needs);
    assert.notEqual(withPlan.status, 0);
    assert.match(withPlan.stderr, /select-targets: expected success/u);
  }
});

test('CI JSON file input preserves originals and refuses conflicting, absent or malformed evidence', t => {
  const dir = mkdtempSync(join(tmpdir(), 'actql-ci-input-'));
  t.after(() => rmSync(dir, {recursive: true, force: true}));
  const path = join(dir, 'plan.json'), original = plan(selectTargets(['src/original.mbt']));
  writeFileSync(path, JSON.stringify(original));
  assert.deepEqual(readCiInput('CI_PLAN', {CI_PLAN_PATH: path}), original);
  assert.deepEqual(readCiInput('CI_PLAN', {CI_PLAN: JSON.stringify(original)}), original);
  assert.equal(readCiInput('CI_PLAN', {}), undefined);
  assert.throws(() => readCiInput('CI_PLAN', {CI_PLAN_PATH: path, CI_PLAN: '{}'}), /Conflicting/u);
  assert.throws(() => readCiInput('CI_PLAN', {CI_PLAN_PATH: join(dir, 'missing')}), {code: 'ENOENT'});
  for (const invalid of ['', '{', 'undefined']) {
    writeFileSync(path, invalid);
    assert.throws(() => readCiInput('CI_PLAN', {CI_PLAN_PATH: path}), SyntaxError);
  }
  // No fallback from an unreadable/malformed file to a different inline plan.
  assert.throws(() => readCiInput('CI_PLAN', {CI_PLAN_PATH: path, CI_PLAN: JSON.stringify(original)}), /Conflicting/u);
});

test('large CI plans reach the original aggregate through files without shell interpretation', t => {
  const dir = mkdtempSync(join(tmpdir(), 'actql-large-ci-plan-'));
  t.after(() => rmSync(dir, {recursive: true, force: true}));
  const selection = selectTargets(Array.from({length: 6000}, (_, i) => `src/changed/package-${i}/original-file.mbt`),
    {event: 'push'});
  selection.paths.push('src/$(touch injected)', 'src/`touch injected`');
  const original = JSON.stringify(plan(selection));
  assert(Buffer.byteLength(original) > 128 * 1024, 'Exceed Linux single-environment-string limit');
  const outcomes = results(selection);
  // The real needs object repeats the full plan in select-targets outputs.
  outcomes['select-targets'].outputs = {plan: original};
  for (const [job, name] of [['focused-tests', 'Check package and execute changed tests plus owning JS family'],
    ['core-js', 'Test common core'], ['core-common', 'Test common core'], ['core-darwin', 'Test common core'],
    ['check', 'Require every selected integration obligation']]) {
    const step = (job === 'native' ? [...nativeCases('native'), ...jobs['native-http'].steps] : jobs[job].steps).find(step => step.name === name);
    assert.equal(step.env.CI_PLAN, undefined, job);
    assert.equal(step.env.CI_PLAN_PATH, '${{ runner.temp }}/actql-ci-plan.json', job);
  }
  const step = jobs.check.steps.find(step => step.name === 'Require every selected integration obligation');
  const run = (value, needs = outcomes, revision = head) => {
    const script = step.run.replaceAll('${{ needs.select-targets.outputs.plan }}', value)
      .replaceAll('${{ toJSON(needs) }}', JSON.stringify(needs));
    const scriptPath = join(dir, 'step.sh');
    writeFileSync(scriptPath, script);
    return spawnSync('bash', ['-eo', 'pipefail', scriptPath], {cwd: new URL('../', import.meta.url),
      encoding: 'utf8', env: {...process.env, CI_PLAN: '', RESULTS: '',
        CI_PLAN_PATH: join(dir, 'plan.json'), RESULTS_PATH: join(dir, 'results.json'),
        GITHUB_SHA: revision, GITHUB_EVENT_NAME: 'push', GITHUB_STEP_SUMMARY: ''}});
  };
  const good = run(original);
  assert.equal(good.status, 0, good.stderr);
  assert.match(good.stdout, /PASS core/u);
  assert.equal(readFileSync(join(dir, 'plan.json'), 'utf8'), original + '\n');
  assert.notEqual(run('{}').status, 0);
  assert.notEqual(run(original, outcomes, 'a'.repeat(40)).status, 0);
  assert.notEqual(run(original, {...outcomes, core: {result: 'failure'}}).status, 0);
  assert(!readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8')
    .includes('CI_PLAN: ${{ needs.select-targets.outputs.plan }}'));
  assert.throws(() => readFileSync(new URL('../injected', import.meta.url)), {code: 'ENOENT'});
});

test('large CI plans launch both original portable Core step command sequences', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-core-ci-transport-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  mkdirSync(join(root, 'bin'));
  const selection = selectTargets(Array.from({length: 6000}, (_, i) => `src/package-${i}/original-code.mbt`),
    {event: 'push'});
  const original = JSON.stringify(plan(selection));
  assert(Buffer.byteLength(original) > 128 * 1024);
  // Only process/argument transport is under test: no compiler or product
  // runtime is invoked by these executable recording ports.
  const recorder = `#!${process.execPath}\nconst fs = require('node:fs');
    const plan = JSON.parse(fs.readFileSync(process.env.CI_PLAN_PATH, 'utf8'));
    fs.appendFileSync(process.env.CALLS, JSON.stringify({
      command: require('node:path').basename(process.argv[1]), args: process.argv.slice(2),
      revision: plan.sourceRevision, paths: plan.selection.paths.length}) + '\\n');\n`;
  const recordingPort = recorder + `
    if (process.env.FAIL_CASE && process.argv.at(-1) === process.env.FAIL_CASE) process.exit(23);\n`;
  for (const command of ['moon', 'node']) {
    writeFileSync(join(root, 'bin', command), recordingPort, {mode: 0o755});
  }
  writeFileSync(join(root, 'bin/getconf'), '#!/bin/sh\nprintf "2\\n"\n', {mode: 0o755});
  const step = jobs['core-common'].steps.find(step => step.name === 'Test common core');
  for (const target of ['js', 'wasm']) {
    const script = step.run.replaceAll('${{ needs.select-targets.outputs.plan }}', original)
      .replaceAll('${{ matrix.target }}', target)
      .replaceAll('${{ needs.select-targets.outputs.moon_test_selection }}', 'false');
    const scriptPath = join(root, `${target}.sh`), calls = join(root, `${target}.jsonl`);
    writeFileSync(scriptPath, script);
    const child = spawnSync('bash', ['-eo', 'pipefail', scriptPath], {encoding: 'utf8',
      env: {...process.env, CI_PLAN: '', CI_PLAN_PATH: join(root, 'plan.json'),
        PATH: `${join(root, 'bin')}:/usr/bin:/bin`, CALLS: calls}});
    assert.equal(child.status, 0, child.stderr);
    const observed = readFileSync(calls, 'utf8').trim().split('\n').map(line => JSON.parse(line));
    assert.deepEqual(observed[0].args, ['test', '--target', target, '--deny-warn', '-j', '2']);
    if (target === 'js') assert(observed.every(entry => entry.command === 'moon'));
    // The Wasm branch below checks each actual required case/argument and
    // producer prerequisite; an old number of node calls is not its contract.
    if (target === 'wasm') {
      assert.deepEqual(observed[1].args, ['test', '--target', 'wasm', '--release', '--build-only',
        '--deny-warn', '-j', '2', 'src/client_host_wasm', '--filter', '*exported validation reaches*']);
      const requiredCases = ['saved_lookup_validation_dispatch_wbtest.mbt',
        'non_sdk_source_restore_wbtest.mbt', 'managed_task_current_wbtest.mbt', 'sdk_row_original_wbtest.mbt', 'journal_decode_originals_wbtest.mbt'];
      assert.deepEqual(observed.slice(2).map(entry => entry.args), requiredCases.map(name => [
        'scripts/test-python-local-metadata-wasm.mjs',
        '_build/wasm/release/test/client_host_wasm/client_host_wasm.whitebox_test.wasm',
        '_build/wasm/release/test/client_host_wasm/__whitebox_test_info.json', name]));
      for (const failedCase of requiredCases) {
        const failedCalls = join(root, `wasm-failed-${failedCase}.jsonl`);
        const failed = spawnSync('bash', ['-eo', 'pipefail', scriptPath], {encoding: 'utf8',
          env: {...process.env, CI_PLAN: '', CI_PLAN_PATH: join(root, 'plan.json'),
            PATH: `${join(root, 'bin')}:/usr/bin:/bin`, CALLS: failedCalls,
            FAIL_CASE: failedCase}});
        assert.equal(failed.status, 23, failed.stderr);
        const actual = readFileSync(failedCalls, 'utf8').trim().split('\n').map(line => JSON.parse(line));
        // Preserve each original prerequisite and stop at the actual failed
        // case; later required cases must never run after an earlier failure.
        const failedIndex = observed.findIndex(entry => entry.command === 'node' &&
          entry.args.at(-1) === failedCase);
        assert(failedIndex >= 0);
        assert.deepEqual(actual, observed.slice(0, failedIndex + 1));
      }
    }
    assert(observed.every(entry => entry.revision === head && entry.paths === selection.paths.length));
    assert.equal(readFileSync(join(root, 'plan.json'), 'utf8'), original + '\n');
  }
});

test('real Git raw changes admit a regular modification and reject structural changes', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-ci-maintenance-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
  Object.assign(env, {GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null'});
  const git = args => {
    const result = spawnSync('git', args, {cwd: root, env, encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
    return result.stdout;
  };
  git(['init', '--quiet']);
  git(['config', 'user.name', 'Maintenance Fixture']);
  git(['config', 'user.email', 'maintenance@example.invalid']);
  git(['config', 'commit.gpgsign', 'false']);
  git(['config', 'core.filemode', 'true']);
  mkdirSync(join(root, 'docs'));
  const path = join(root, 'docs/development.md');
  const original = readFileSync(new URL('../docs/development.md', import.meta.url), 'utf8');
  writeFileSync(path, original);
  git(['add', '.']); git(['commit', '--quiet', '-m', 'Original regular file']);
  const base = git(['rev-parse', 'HEAD']).trim();
  const inspect = () => {
    git(['add', '--all']); git(['commit', '--quiet', '-m', 'Fixture change']);
    const change = readChanges({pull_request: {base: {sha: base}}}, git);
    return selectTargets(change.paths, change);
  };
  writeFileSync(path, original + '\nChanged developer instructions about hash reports\n');
  assert.equal(inspect().profile, 'maintenance');
  chmodSync(path, 0o755);
  assert.equal(inspect().profile, 'full');
  git(['reset', '--hard', base]);
  git(['mv', 'docs/development.md', 'docs/verification-actions.md']);
  assert.equal(inspect().profile, 'full');
  git(['reset', '--hard', base]);
  writeFileSync(join(root, 'docs/ci-artifact-analysis.md'), 'New documentation\n');
  assert.equal(inspect().profile, 'full');
  git(['reset', '--hard', base]);
  git(['rm', 'docs/development.md']);
  assert.equal(inspect().profile, 'full');
});


test('unclassified proof records retain full coverage without a historical declaration profile', () => {
  const path = 'proofs/relation-pipeline/new-record.json';
  const selected = validateSelection(selectTargets([path]));
  assert.equal(selected.profile, 'full');
  assert.deepEqual(selected.targets, all);
  assert.throws(() => validateSelection({...selected, profile: 'declaration'}), /Invalid selection profile/u);
  assert.throws(() => validateSelection({...selected, declarationChanges: []}), /Invalid selection fields/u);
});

test('normal workflow has no historical declaration admission or artifact requirement', () => {
  assert.deepEqual(jobs.preflight.needs, ['select-targets']);
  for (const job of Object.values(jobs)) {
    for (const step of job.steps ?? []) {
      assert(!step.run?.includes('proofs/relation-pipeline/history.mjs'));
      assert(!step.with?.path?.includes('current-foundation.json'));
      assert(!step.if?.includes("profile == 'declaration'"));
    }
  }
});

test('main cumulative product changes retain all backend coverage even for portable PR paths', () => {
  for (const paths of [['proofs/relation-pipeline/new-record.json', 'src/source_span/span.mbt'], ['src/source_span/span.mbt'], ['README.md']]) {
    const selected = validateSelection(selectTargets(paths, {event: 'push', mainIntegration: false}));
    assert.equal(selected.profile, 'full'); assert.deepEqual(selected.targets, all); assert.equal(selected.macos, true);
  }
});
test('normal selection needs no Actions token or history API permission', () => {
  assert.deepEqual(workflow.permissions, {contents: 'read'});
  assert.deepEqual(jobs['select-targets'].permissions, {contents: 'read'});
  const select = jobs['select-targets'].steps.find(step => step.id === 'select');
  assert.equal(select.env.GITHUB_TOKEN, undefined);
  assert(jobs.lint.steps.some(step => step.run?.includes('scripts/ci-main-base.test.mjs')));
});


test('PR lifecycle uses current event Draft state; ready and later heads retain normal coverage', () => {
  const product = ['src/execution_relation/product.mbt'];
  for (const action of ['opened', 'synchronize', 'reopened', 'converted_to_draft']) {
    const draft = pullRequestDraft('pull_request', {action, pull_request: {draft: true}});
    const selection = validateSelection(selectTargets(product, {draft}));
    assert.equal(selection.profile, 'draft', action);
    assert.equal(selection.macos, false);
    assert.throws(() => verifyGate(plan(selection), results(selection), {...context, draft}), /awaiting ready_for_review/u);
  }
  for (const action of ['opened', 'synchronize', 'reopened', 'ready_for_review']) {
    const draft = pullRequestDraft('pull_request', {action, pull_request: {draft: false}});
    const selection = validateSelection(selectTargets(product, {draft}));
    assert.equal(selection.profile, 'full', action);
    assert.deepEqual(selection.targets, all);
    assert.equal(verifyGate(plan(selection), results(selection), {...context, draft}).length, gateJobs.length);
    assert.throws(() => verifyGate(plan(selection), results(selection), {...context, sourceRevision: 'a'.repeat(40), draft}), /another checkout/u);
  }
  for (const payload of [{}, {action: 'synchronize', pull_request: {draft: 'false'}},
    {action: 'ready_for_review', pull_request: {draft: true}},
    {action: 'converted_to_draft', pull_request: {draft: false}}]) {
    assert.throws(() => pullRequestDraft('pull_request', payload));
  }
  const ready = maintenanceSelection(['docs/development.md']);
  assert.equal(selectTargets(ready.paths, {draft: false, maintenanceChanges: ready.maintenanceChanges}).profile, 'maintenance');
  assert.throws(() => verifyGate(plan(ready), results(ready), {...context, draft: true}), /awaiting ready_for_review/u);
  assert.equal(pullRequestDraft('workflow_dispatch', {pull_request: {draft: true}}), null);
  assert.equal(selectTargets(product, {event: 'workflow_dispatch', draft: true}).profile, 'full');
});

test('Unrelated Draft cannot start product, packed, proof or backend jobs; final gate still runs', () => {
  const heavy = ['core', 'host', 'client-packages', 'client-readme-packed', 'client-supported-versions', 'client-distribution', 'client-distribution-callers',
    'client-distribution-mutations', 'client-distribution-packed', 'client-packed', 'client-packed-composition', 'client-salesforce',
    'native-cli-installed', 'native-cli-linux-local', 'native-cli-linux-local-installed', 'native-cli-linux-local-mock', 'native', 'session-evidence', 'session-controls', 'pipeline-mutations', 'pipeline-mutations-rest', 'pipeline-capacity',
    'pipeline-capacity-mutants', 'pipeline-validation', 'native-macos', 'python-wheels', 'native-separated-network',
    'workers', 'connector-addition', 'duckdb-node'];
  for (const profile of ['draft', 'draft-focused']) {
    const needs = {'select-targets': {outputs: {profile, targets: '["js"]', macos: 'false'}},
      lint: {result: 'success'}, 'core-js': {result: 'skipped'}};
    for (const name of heavy) assert.equal(scheduled(name, needs), false, `${profile}/${name}`);
    assert.equal(scheduled('focused-tests', needs), profile === 'draft-focused');
    for (const name of ['preflight', 'lint', 'spec', 'check']) assert.equal(scheduled(name, needs), true, name);
  }
  // Converted-to-draft and ready events have the same PR ref/group. The existing
  // cancel-in-progress expression supersedes prior preparation/full attempts.
  assert(workflow.concurrency.group.includes('${{ github.ref }}'));
  assert.equal(workflow.concurrency['cancel-in-progress'], "${{ !inputs.performance_matrix && github.ref != 'refs/heads/main' }}");
});

function draftStepEnabled(step, profile) {
  if (!step.if) return true;
  const expression = step.if.replace(/^\$\{\{\s*|\s*\}\}$/gu, '')
    .replace(/needs\.([a-z][a-z0-9-]*)/gu, (_, name) => `needs[${JSON.stringify(name)}]`);
  return Function('needs', 'startsWith', `return (${expression});`)(
    {'select-targets': {outputs: {profile}}}, (value, prefix) => value.startsWith(prefix));
}
test('Explorer components require original built assets and keep Draft preparation source-only', () => {
  const steps = jobs.lint.steps;
  const prepare = steps.filter(step => step.name === 'Build Explorer component assets');
  const consume = steps.filter(step => step.name === 'Test Explorer gateway and UI components');
  assert.equal(prepare.length, 1); assert.equal(consume.length, 1);
  assert.equal(prepare[0].run, 'npm run build --prefix packages/explorer');
  assert.equal(consume[0].run, 'node scripts/local-checks.mjs test node --timeout-seconds 120 --kill-grace-seconds 5 -- packages/explorer/*.test.mjs packages/explorer-ui/*.test.mjs');
  assert(steps.indexOf(prepare[0]) < steps.indexOf(consume[0]));
  for (const step of [prepare[0], consume[0]]) {
    assert.equal(step['continue-on-error'], undefined);
    for (const profile of ['draft', 'draft-focused']) assert.equal(draftStepEnabled(step, profile), false);
    for (const profile of ['full', 'maintenance', 'focused-tests']) assert.equal(draftStepEnabled(step, profile), true);
  }
});
test('fast health monitor harness runs in PR and Draft lint without enabling the main-only campaign', () => {
  const command = 'node scripts/local-checks.mjs test node --timeout-seconds 120 --kill-grace-seconds 5 -- scripts/health-monitor.test.mjs';
  const selected = jobs.lint.steps.filter(step => step.run === command);
  assert.equal(selected.length, 1);
  assert.equal(selected[0]['continue-on-error'], undefined);
  for (const profile of ['draft', 'draft-focused', 'focused-tests', 'maintenance', 'full']) {
    assert.equal(draftStepEnabled(selected[0], profile), true);
  }
  assert.deepEqual(jobs.lint.needs, ['select-targets']);
  assert(!jobs.lint.steps.some(step => step.run?.includes('npm run health:quick')));
});
test('Draft excludes compiler API and full specification work while Ready runs both', () => {
  // Check scheduling obligations, not a second copy of every lint command.
  // Cheap tests may be added, reordered or regrouped without changing this contract.
  for (const [name, command] of [
    ['preflight', 'node scripts/check-moonbit-api.mjs'],
    ['spec', 'npm run check:spec-after-preflight'],
  ]) {
    const selected = jobs[name].steps.filter(step => step.run === command);
    assert.equal(selected.length, 1, `${name}: required check is missing or duplicated`);
    assert.notEqual(selected[0]['continue-on-error'], true);
    for (const profile of ['draft', 'draft-focused']) {
      assert.equal(draftStepEnabled(selected[0], profile), false, `${name}/${profile}`);
    }
    for (const profile of ['full', 'maintenance', 'focused-tests']) {
      assert.equal(draftStepEnabled(selected[0], profile), true, `${name}/${profile}`);
    }
  }
  for (const name of ['lint', 'spec']) {
    assert(!jobs[name].steps.some(step => draftStepEnabled(step, 'draft') &&
      (step.uses === './.github/actions/setup-toolchain' || step.uses?.startsWith('actions/setup-python@'))));
  }
});

test('public jobs do not require an activation variable; private and unknown repositories stay excluded', () => {
  const guard = "github.event.repository.visibility == 'public' && toJSON(github.event.repository.private) == 'false'";
  const workflows = ['ci', 'performance-matrix', 'packed-query-evidence-probe', 'health-monitor']
    .map(name => parse(readFileSync(new URL(`../.github/workflows/${name}.yml`, import.meta.url), 'utf8')));
  for (const workflow of workflows) for (const [name, job] of Object.entries(workflow.jobs)) {
    assert(job.if.startsWith('${{ ' + guard), name);
    assert(!job.if.includes('vars.'), name);
    const expression = job.if.slice(4, 4 + guard.length);
    for (const [visibility, privateFlag, expected] of [
      ['public', false, true], ['private', true, false], ['public', true, false],
      [undefined, false, false], ['public', undefined, false], ['public', null, false],
      ['public', 0, false], ['public', 'false', false],
    ]) {
      assert.equal(runInNewContext(expression, {
        github: {event: {repository: {visibility, private: privateFlag}}}, toJSON: JSON.stringify}, {timeout: 100}), expected, name);
    }
  }
  for (const name of ['check', 'client', 'pipeline-evidence']) assert(jobs[name].if.includes('always()'), name);
});

test('automatic main integration remains full without cumulative evidence', () => {
  const cases = [
    {paths: ['proofs/relation-pipeline/new-record.json']},
    {paths: ['docs/development.md'], maintenanceChanges: changes(['docs/development.md'])},
    {paths: []},
  ];
  for (const inputs of cases) {
    const selected = validateSelection(selectTargets(inputs.paths, {...inputs, event: 'push'}));
    assert.equal(selected.profile, 'full');
    assert.deepEqual(selected.targets, all); assert.equal(selected.macos, true);
    const lines = verifyGate(plan(selected), results(selected), {...context, event: 'push'});
    assert(!lines.some(line => line.startsWith('NOT APPLICABLE core')));
  }
});

test('Source profile custody runs once beside original profile intake after preparation', () => {
  const files = ['adapters/host-node/source-profile-json.test.mjs',
    'adapters/host-node/source-profile-custody.test.mjs'];
  const steps = jobs['client-distribution-callers'].steps;
  const owners = files.map(file => {
    const selected = Object.values(jobs).flatMap(job => job.steps ?? [])
      .filter(step => step.run?.split(/\s+/u).includes(file));
    assert.equal(selected.length, 1, file);
    return selected[0];
  });
  assert.equal(owners[0], owners[1]);
  const [owner] = owners, args = owner.run.trim().split(/\s+/u);
  assert.deepEqual(args.slice(0, 5), ['node', 'scripts/local-checks.mjs', 'test', 'node', '--']);
  assert(!args.some(argument => /^--test-(?:name|skip|only)/u.test(argument)));
  assert.equal(owner.if, "${{ !cancelled() && steps.distribution-preparation.outcome == 'success' }}");
  assert.equal(owner['continue-on-error'], undefined);
  assert(steps.findIndex(step => step.id === 'distribution-preparation') < steps.indexOf(owner));
  const command = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'))
    .scripts['check:distribution-client'].split(/\s+/u);
  for (const file of files) assert.equal(command.filter(argument => argument === file).length, 1, file);
});

test('REST demand controls have one prepared public package owner without narrowing CI admission', () => {
  const file = 'adapters/host-node/rest-source-initial-material.test.mjs';
  const scripts = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8')).scripts;
  assert.equal(scripts['test:remote-site-runtime'].split(/\s+/u).includes(file), false);
  const recipes = scripts['check:distribution-client'].split(' && ')
    .filter(command => command.split(/\s+/u).includes(file));
  assert.equal(recipes.length, 1);
  assert.equal(recipes[0].split(/\s+/u).filter(argument => argument === file).length, 1);
  const steps = jobs['client-distribution'].steps;
  const owners = steps.filter(step => step.name === 'Test source-backed distribution contracts');
  assert.equal(owners.length, 1);
  const [owner] = owners;
  // The original local command and CI's split command need not contain every
  // identical peer test. Require this whole module's real Node entrance once.
  const arguments_ = owner.run.trim().split(/\s+/u);
  assert.deepEqual(arguments_.slice(0, 2), ['node', '--test']);
  assert.equal(arguments_.filter(argument => argument === file).length, 1);
  assert(!arguments_.some(argument => /^--test-(?:name|skip|only)/u.test(argument)));
  assert.equal(owner.if, "${{ !cancelled() && steps.distribution-preparation.outcome == 'success' }}");
  assert.equal(owner['continue-on-error'], undefined);
  assert(jobs['client-distribution'].needs.includes('client-packages'));
  const runtime = steps.findIndex(step => step.run === 'node scripts/build-runtime-packages.mjs local-node run-host-core');
  const adapters = steps.findIndex(step => step.run === 'node scripts/build-local-node-adapters.mjs');
  const prepared = steps.findIndex(step => step.id === 'distribution-preparation');
  assert(runtime >= 0 && runtime < adapters && adapters < prepared && prepared < steps.indexOf(owner));
  assert.equal(Object.values(jobs).flatMap(job => job.steps ?? [])
    .filter(step => step.run?.split(/\s+/u).includes(file)).length, 1);

  for (const options of [{draft: false}, {draft: false, focusedTests: {}, focusedChanges: {}},
    {draft: true}, {draft: true, focusedTests: {}, focusedChanges: {}}, {event: 'push'}]) {
    const selection = selectTargets([file], options);
    const full = options.draft !== true;
    assert.equal(selection.profile, full ? 'full' : 'draft');
    assert.equal(gateJobRequired(selection, 'client-distribution'), full);
    // The prior Host owner and new prepared owner retain the SAME runtime
    // applicability. Draft preparation is not silently promoted to acceptance.
    assert.equal(gateJobRequired(selection, 'host'), full);
    for (const name of ['host', 'client-distribution']) {
      // Read the existing workflow's profile entrance; do not reinterpret
      // GitHub expression syntax as a second JavaScript condition engine.
      assert(jobs[name].if.includes("needs.select-targets.outputs.profile == 'full'"));
    }
    if (full) {
      verifyGate(plan(selection), results(selection), {...context, event: selection.event});
      for (const result of ['failure', 'cancelled', 'skipped', undefined]) {
        assert.throws(() => verifyGate(plan(selection),
          {...results(selection), 'client-distribution': {result}},
          {...context, event: selection.event}));
      }
    }
  }
});

test('distribution isolates pinned provider tests with their required GC recipe', () => {
  const scripts = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8')).scripts;
  // client-ci executes this same recipe to check type-gate ordering and refusal.
  const providerTests = scripts['check:provider-ai-sdk'].split(' && ')
    .map(command => command.trim().split(/\s+/u))
    .filter(args => args[1] === 'scripts/local-checks.mjs');
  assert.equal(providerTests.length, 1);
  const [provider] = providerTests;
  assert.deepEqual(provider.slice(0, 4), ['node', 'scripts/local-checks.mjs', 'test', 'node']);
  const separator = provider.indexOf('--');
  assert(separator > 3);
  for (const option of ['--timeout-seconds', '--kill-grace-seconds']) {
    const index = provider.indexOf(option);
    assert(index > 3 && index + 1 < separator, option);
    const seconds = Number(provider[index + 1]);
    assert(Number.isSafeInteger(seconds) && seconds > 0, option);
  }
  for (const required of ['--expose-gc', 'packages/provider-ai-sdk/*.test.mjs']) {
    assert.equal(provider.slice(separator + 1).filter(value => value === required).length, 1, required);
  }
  assert(!scripts['check:distribution-client'].includes('npm run check:provider-ai-sdk'));
  assert.equal(scripts['postcheck:distribution-client'], 'npm run check:provider-ai-sdk && npm run check:otel-node');
  assert(!scripts['check:distribution-client'].includes('packages/provider-ai-sdk/*.test.mjs'));
  const steps = jobs['client-distribution'].steps;
  assert(!steps.some(step => step.run === 'npm run postcheck:distribution-client'));
  for (const command of scripts['postcheck:distribution-client'].split(' && ')) {
    const selected = steps.filter(step => step.run === command);
    assert.equal(selected.length, 1);
    assert.equal(selected[0].if, steps.find(step => step.name === 'Test source-backed distribution contracts').if);
    assert.equal(selected[0]['continue-on-error'], undefined);
    assert(steps.indexOf(steps.find(step => step.run === 'npm ci --prefix packages/provider-ai-sdk --ignore-scripts')) < steps.indexOf(selected[0]));
  }
  assert(steps.some(step => step.run === 'npm ci --prefix packages/provider-ai-sdk --ignore-scripts'));
  for (const step of steps.filter(step => step.run?.startsWith('node --test '))) {
    assert(!step.run.includes('packages/provider-ai-sdk/*.test.mjs'));
    assert(!step.run.includes('--expose-gc'));
  }
});

test('normal distribution keeps original Request resource and cleanup regressions selected once', () => {
  const command = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'))
    .scripts['check:distribution-client'];
  const selected = command.split(/\s+/u);
  for (const file of [
  "adapters/host-node/metadata-capacity-public.test.mjs",
  "adapters/host-node/local-result-read-wire-workspace.test.mjs",
  "adapters/host-node/installed-duckdb-source-owner.test.mjs",
  "adapters/host-node/table-owned-site-retirement.test.mjs",
  "adapters/host-node/table-original-metadata.test.mjs",
  "adapters/host-node/content-pre-record-retirement.test.mjs",
  "adapters/host-node/effect-capture-connection.test.mjs",
  "adapters/host-node/effect-capture-resources.test.mjs",
  "adapters/host-common/recovered-effect-capture-control.test.mjs",
  "adapters/host-node/effect-publication-binding.test.mjs",
  "adapters/host-common/deferred-catalog-control.test.mjs",
  "adapters/host-node/request-content-graph-resources.test.mjs",
  "adapters/host-node/request-keyed-prefix-execution.test.mjs",
  "adapters/host-node/acquired-effect-keyed-prefix.test.mjs",
  "adapters/host-node/acquired-effect-keyed-publication.test.mjs",
  "adapters/host-node/acquired-direct-publication.test.mjs",
  "adapters/host-node/original-retention-rebinding.test.mjs",
  "adapters/host-node/source-keyed-adoption-original.test.mjs",
  "adapters/host-node/local-file-keyed-effect-current.test.mjs",
  "adapters/host-node/request-model-material-resources.test.mjs",
  "adapters/host-node/request-model-source-ledger.test.mjs",
  "adapters/store-local/private-evidence-consumer-lifetime.test.mjs",
  "adapters/host-node/request-domain-source-preflight.test.mjs",
  "adapters/host-node/content-execution-alias-retirement.test.mjs"
]) {
    assert.equal(selected.filter(value => value === file).length, 1, file);
  }
  const recoveredCapture = 'adapters/host-common/recovered-effect-capture-control.test.mjs';
  const captureSteps = jobs['client-distribution-callers'].steps.filter(step =>
    step.run?.includes('adapters/host-node/effect-capture-resources.test.mjs'));
  assert.equal(captureSteps.length, 1);
  assert.equal(captureSteps[0].run.split(/\s+/u).filter(value => value === recoveredCapture).length, 1);
  assert.equal(captureSteps[0].run.split(/\s+/u).filter(value => value === 'adapters/host-node/effect-publication-binding.test.mjs').length, 1);
  assert.equal(captureSteps[0].run.split(/\s+/u).filter(value => value === 'adapters/host-common/deferred-catalog-control.test.mjs').length, 1);
  for (const file of ['adapters/host-node/acquired-effect-keyed-prefix.test.mjs',
    'adapters/host-node/acquired-effect-keyed-publication.test.mjs',
    'adapters/host-node/acquired-direct-publication.test.mjs',
    'adapters/host-node/original-retention-rebinding.test.mjs',
    'adapters/host-node/source-keyed-adoption-original.test.mjs',
    'adapters/host-node/local-file-keyed-effect-current.test.mjs']) {
    assert.equal(captureSteps[0].run.split(/\s+/u).filter(value => value === file).length, 1);
  }
  assert.equal(captureSteps[0].if, "${{ !cancelled() && steps.distribution-preparation.outcome == 'success' }}");
  assert.equal(captureSteps[0]['continue-on-error'], undefined);
});


test('main CLI selects full checks from a fresh checkout without API token or previous run history', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-ci-main-direct-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const command = (args) => {
    const result = spawnSync('git', args, {cwd: root, encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
    return result.stdout.trim();
  };
  command(['init', '-q']); command(['config', 'user.name', 'CI fixture']);
  command(['config', 'user.email', 'fixture@example.invalid']);
  writeFileSync(join(root, 'fixture.txt'), 'current source\n');
  command(['add', 'fixture.txt']); command(['commit', '-qm', 'fixture']);
  const revision = command(['rev-parse', 'HEAD']);
  const payloadPath = join(root, 'event.json'), output = join(root, 'output');
  writeFileSync(payloadPath, JSON.stringify({ref: 'refs/heads/main', after: revision}));
  const result = spawnSync(process.execPath, [new URL('./ci-targets.mjs', import.meta.url).pathname], {
    cwd: root, encoding: 'utf8', env: {...process.env, GITHUB_EVENT_NAME: 'push',
      GITHUB_REF: 'refs/heads/main', GITHUB_SHA: revision, GITHUB_EVENT_PATH: payloadPath,
      GITHUB_OUTPUT: output, GITHUB_STEP_SUMMARY: '', GITHUB_TOKEN: '', GH_TOKEN: ''},
  });
  assert.equal(result.status, 0, result.stderr);
  const plan = JSON.parse(readFileSync(output, 'utf8').split('\n').find(row => row.startsWith('plan=')).slice(5));
  assert.equal(plan.sourceRevision, revision);
  assert.match(readFileSync(output, 'utf8'), /^python_wheels=true$/mu);
  assert.equal(plan.selection.profile, 'full');
  assert.deepEqual(plan.selection.targets, ['js', 'wasm', 'native']);
  assert.equal(plan.selection.macos, true);
  assert.equal(Object.hasOwn(plan.selection, 'mainBaseline'), false);
  assert.deepEqual(plan.selection.paths, []);
});

test('neutral ABI and existing Host source changes retain required current families and unknown fallback', () => {
  for (const path of ['src/client_host_wasm/host.mbt', 'spec/contracts/core-wasm-abi.generated.json',
    'scripts/generate-local-wasm-abi.py', 'packages/python-sdk/src/actql_sdk/_local_wasm_abi.py',
    'unclassified/future-abi-input']) {
    const selection = selectTargets([path]);
    assert.equal(selection.profile, 'full', path);
    assert.deepEqual(selection.targets, ['js', 'wasm', 'native'], path);
    assert.equal(selection.macos, true, path);
    assert.equal(pythonWheelAcceptanceRequired(selection), true, path);
    for (const name of ['select-targets', 'preflight', 'lint', 'core', 'host', 'client', 'native', 'python-wheels']) {
      assert.equal(gateJobRequired(selection, name), true, `${path}/${name}`);
      for (const result of ['failure', 'cancelled', 'skipped', undefined]) {
        assert.throws(() => verifyGate(plan(selection), {...results(selection), [name]: {result}}, context));
      }
    }
    verifyGate(plan(selection), results(selection), context);
  }
});

test('normal Python wheels are mandatory for full profiles independently of optional native macOS', () => {
  const job = jobs['python-wheels'];
  assert.equal(job['runs-on'], '${{ matrix.runner }}');
  assert.deepEqual(job.needs, ['select-targets']);
  assert.equal(scheduled('python-wheels', {'select-targets': {result: 'success', outputs: {profile: 'full', targets: '["js","wasm","native"]', python_wheels: 'true', macos: 'false'}},
    lint: {result: 'success'}, 'core-js': {result: 'success'}}), true);
  assert(job.steps.some(step => step.run === 'python3 -B scripts/ci-python-wheels.py --destination "$RUNNER_TEMP/python-wheel-acceptance"'));
  assert(jobs.lint.steps.some(step => step.run === 'python3 -B scripts/test_ci_python_wheels.py'));
  const selection = selectTargets(['README.md'], {event: 'workflow_dispatch', mainIntegration: true, nativeMacos: false});
  for (const result of ['failure', 'cancelled', 'skipped']) {
    const needs = results(selection); needs['python-wheels'].result = result;
    assert.throws(() => verifyGate(plan(selection), needs, {...context, event: 'workflow_dispatch'}), /python-wheels/);
  }
});

test('Python wheel overlap requires successful Source admission and cannot clear final validation failures', () => {
  const selected = {profile: 'full', targets: '["js","wasm","native"]', python_wheels: 'true'};
  for (const result of ['success', 'failure', 'cancelled', 'skipped', undefined]) {
    // Even retained selection outputs cannot authorize work after admission
    // failed. Independent lint/Core outcomes are not wheel build inputs.
    const needs = {'select-targets': {result, outputs: selected},
      lint: {result: 'failure'}, 'core-js': {result: 'cancelled'}};
    assert.equal(scheduled('python-wheels', needs), result === 'success');
  }
  const needs = {'select-targets': {result: 'success', outputs: selected}};
  for (const flag of ['false', '', undefined])
    assert.equal(scheduled('python-wheels', {'select-targets': {
      result: 'success', outputs: {...selected, python_wheels: flag}}}), false);
  assert.equal(scheduled('python-wheels', needs, {}, true), false);
  for (const inputs of [{performance_matrix: true}, {packed_query_evidence_probe: true}])
    assert.equal(scheduled('python-wheels', needs, inputs), false);
  const selection = selectTargets(['README.md'], {event: 'workflow_dispatch', mainIntegration: true, nativeMacos: false});
  for (const name of ['select-targets', 'preflight', 'lint', 'core', 'python-wheels'])
    for (const result of ['failure', 'cancelled', 'skipped', undefined]) {
      const actual = results(selection); actual[name] = {result};
      assert.throws(() => verifyGate(plan(selection), actual, {...context, event: 'workflow_dispatch'}));
    }
});

test('normal wheel platforms reject foreign machines and keep independent same-platform artifacts', t => {
  const job = jobs['python-wheels'];
  assert.equal(job.strategy['fail-fast'], false);
  const platforms = job.strategy.matrix.include;
  assert.deepEqual(platforms.map(row => row.platform).sort(), ['darwin-arm64', 'linux-x64']);
  const expected = {'darwin-arm64': ['macos-15', 'Darwin', 'arm64'],
    'linux-x64': ['ubuntu-24.04', 'Linux', 'x86_64']};
  const admission = job.steps.find(step => step.env?.EXPECTED_SYSTEM);
  assert(admission);
  assert.equal(admission.env.EXPECTED_SYSTEM, '${{ matrix.system }}');
  assert.equal(admission.env.EXPECTED_ARCHITECTURE, '${{ matrix.architecture }}');
  const producer = job.steps.find(step => step.id === 'python-normal-cohort');
  assert(job.steps.indexOf(admission) < job.steps.indexOf(producer));
  const root = mkdtempSync(join(tmpdir(), 'python-wheel-platform-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  writeFileSync(join(root, 'uname'), '#!/bin/sh\ncase "$1" in\n-s) printf "%s\\n" "$OBSERVED_SYSTEM";;\n-m) printf "%s\\n" "$OBSERVED_ARCHITECTURE";;\n*) exit 1;;\nesac\n');
  chmodSync(join(root, 'uname'), 0o755);
  const cwd = fileURLToPath(new URL('../', import.meta.url));
  const revision = spawnSync('git', ['rev-parse', 'HEAD'], {cwd, encoding: 'utf8', timeout: 5000});
  assert.equal(revision.status, 0, revision.stderr);
  for (const row of platforms) {
    assert.deepEqual([row.runner, row.system, row.architecture], expected[row.platform]);
    const invoke = overrides => spawnSync('/bin/bash', ['-eu', '-c', admission.run], {
      cwd, encoding: 'utf8', timeout: 5000, env: {...process.env, PATH: root + ':' + process.env.PATH,
        EXPECTED_SYSTEM: row.system, EXPECTED_ARCHITECTURE: row.architecture,
        OBSERVED_SYSTEM: row.system, OBSERVED_ARCHITECTURE: row.architecture,
        GITHUB_SHA: revision.stdout.trim(), ...overrides}});
    const actual = invoke({}); assert.equal(actual.status, 0, actual.stderr);
    for (const overrides of [{OBSERVED_SYSTEM: 'foreign'}, {OBSERVED_ARCHITECTURE: 'foreign'},
      {GITHUB_SHA: '0'.repeat(40)}]) assert.notEqual(invoke(overrides).status, 0);
  }
  const retention = job.steps.find(step => step.uses?.startsWith('actions/upload-artifact@'));
  assert.equal(retention.if, '${{ always() }}');
  assert(retention.with.name.includes('${{ matrix.platform }}'));
  assert(retention.with.name.includes('${{ github.run_id }}'));
  assert(retention.with.name.includes('${{ github.run_attempt }}'));
});

test('Python original observation fixture selects its same-source wheel consumer on draft', () => {
  for (const path of ['scripts/fixtures/python-local-submission-observation-abi.py',
    'scripts/fixtures/python-local-public-cancellation-abi.py',
    'scripts/fixtures/python-local-saved-state-abi.py',
    'scripts/fixtures/python-local-public-success-abi.py',
    'scripts/fixtures/python_local_task_drive_trace.py']) {
    readFileSync(new URL('../' + path, import.meta.url));
    const selection = selectTargets([path], {draft: true});
    assert.equal(pythonWheelAcceptanceRequired(selection), true);
    for (const outcome of ['failure', 'cancelled', 'skipped']) {
      const needs = results(selection);
      needs['python-wheels'].result = outcome;
      assert.throws(() => verifyGate(plan(selection), needs, context), /python-wheels/);
    }
  }
});

test('Draft normal Python and CI changes automatically select real wheel acceptance without Ready', () => {
  for (const path of ['.github/workflows/ci.yml', '.github/actions/setup-toolchain/action.yml',
    'scripts/ci-targets.mjs', 'scripts/ci-preflight.mjs', 'scripts/ci-focused-tests.mjs',
    'scripts/ci-python-wheels.py', 'scripts/test_ci_python_wheels.py',
    'scripts/ci-supported-python.py', 'scripts/test_ci_supported_python.py',
    'scripts/fixtures/ci-python-installed-audit.py', 'scripts/fixtures/ci-python-installed-health.py',
    'scripts/fixtures/ci-python-installed-run.py',
    'scripts/fixtures/python-product-installed.py', 'scripts/fixtures/python-local-duckdb-physical.py',
    'scripts/build-python-product-wheels.py', 'scripts/produce-python-local-runtime.py',
    'scripts/compile-python-local-image.py', 'scripts/prepare-python-local-runtime.py',
    'scripts/python_release_cohort.py', 'scripts/python_interface_inventory.py',
    'scripts/generate-local-wasm-abi.py', 'scripts/release-version.mjs',
    'toolchain.json', 'moon.mod', 'package.json', 'package-lock.json',
    'packages/python-sdk/src/example.py', 'packages/python-product/pyproject.toml',
    'packages/python-local-runtime/new.py']) {
    const selection = selectTargets([path], {draft: true});
    assert.equal(pythonWheelAcceptanceRequired(selection), true, path);
    assert.equal(scheduled('python-wheels', {'select-targets': {result: 'success', outputs: {
      profile: 'draft', targets: JSON.stringify(selection.targets), python_wheels: String(pythonWheelAcceptanceRequired(selection)), macos: 'false'}},
      lint: {result: 'success'}, 'core-js': {result: 'skipped'}}), true);
    assert.throws(() => verifyGate(plan(selection), results(selection), {...context, draft: true}), /awaiting ready_for_review/);
    for (const result of ['failure', 'cancelled', 'skipped', undefined]) {
      const needs = results(selection); needs['python-wheels'].result = result;
      assert.throws(() => verifyGate(plan(selection), needs, {...context, draft: true}), /python-wheels: expected success/);
    }
  }
  for (const path of ['README.md', 'docs/development.md', 'src/source_span/span.mbt',
    'packages/node-sdk/index.mjs', 'scripts/unrelated.mjs', 'packages/python-sdk-other/test.py']) {
    assert.equal(pythonWheelAcceptanceRequired(selectTargets([path], {draft: true})), false, path);
  }
  for (const paths of [[], null, ['../invalid']]) {
    assert.equal(pythonWheelAcceptanceRequired(selectTargets(paths, {draft: true})), true);
  }
  assert.equal(pythonWheelAcceptanceRequired(maintenanceSelection(['docs/development.md'])), false);
});

test('deleted or renamed Python inputs remain in the tested merge diff and select acceptance', () => {
  for (const paths of [['scripts/ci-python-wheels.py'],
    ['scripts/ci-python-wheels.py', 'scripts/renamed-wheel-acceptance.py'],
    ['scripts/old.py', 'packages/python-sdk/new.py']]) {
    const git = args => {
      if (args[0] === 'rev-parse') return head;
      assert(args.includes('--no-renames'));
      return args.includes('--name-only') ? paths.join('\0') + '\0' : '-deleted old input\n+new input\n';
    };
    const changed = readChanges({pull_request: {base: {sha: 'a'.repeat(40)}}}, git);
    assert.deepEqual(changed.paths, paths);
    assert.equal(pythonWheelAcceptanceRequired(selectTargets(changed.paths, {draft: true})), true);
  }
});

test('deep proof scheduling covers its complete snapshot and safety inputs without narrowing runtime', async () => {
  const {snapshotDirectories, snapshotFiles} = await import('../proofs/relation-pipeline/inventory.mjs');
  for (const path of [...snapshotFiles, ...snapshotDirectories.map(root => `${root}/new-input`),
    'adapters/store-local/new-owner.mjs', 'packages/sdk/resource-control.mjs',
    'proofs/ci-evidence/receipts.mjs', 'scripts/new-tool.mjs', 'unknown/config']) {
    assert.equal(deepProofRequired(selectTargets([path])), true, path);
  }
  for (const path of ['README.md', 'LICENSE', 'CONTRIBUTING.md']) {
    const selection = selectTargets([path], {event: 'push'});
    assert.equal(selection.profile, 'full'); assert.deepEqual(selection.targets, all);
    assert.equal(deepProofRequired(selection), false, path);
    assert.equal(gateJobRequired(selection, 'pipeline-validation'), true);
    assert.equal(gateJobRequired(selection, 'main-performance'), true);
  }
  for (const options of [{failure: 'unavailable'}, {event: 'schedule'}, {event: 'workflow_dispatch'}])
    assert.equal(deepProofRequired(selectTargets(['README.md'], options)), true);
  assert.equal(deepProofRequired(selectTargets([])), true);
});

test('unclassified adapter and package safety inputs retain deep campaigns', () => {
  const duckdbWitness = 'adapters/connectors/duckdb/node/test/standard-host.test.mjs';
  const nest = JSON.parse(readFileSync(new URL('../proofs/bounded-session/nest-obligations.json', import.meta.url), 'utf8'));
  assert(nest.retainedSuites.includes(duckdbWitness), 'Use the actual retained Nest proof input');
  for (const path of [
    'adapters/host-node/infer-original-installation.mjs',
    'packages/python-sdk/src/actql_sdk/_local_core.py',
    'adapters/workers/wrangler.toml',
    'packages/sdk/tsconfig.json',
    duckdbWitness,
    'packages/sdk/format.mjs',
    'adapters/connectors/rest/format.test.mjs',
  ]) for (const event of ['pull_request', 'push']) {
    const selection = selectTargets([path], {event});
    assert.equal(selection.profile, 'full', path);
    assert.deepEqual(selection.targets, all, path);
    assert.equal(selection.macos, true, path);
    assert.equal(deepProofRequired(selection), true, `${event}/${path}`);
  }
});

test('unclassified safety changes require proof success while reviewed shallow changes require skips', () => {
  for (const event of ['pull_request', 'push']) for (const [path, deep] of [
    ['adapters/host-node/infer-original-installation.mjs', true],
    ['README.md', false],
  ]) {
    const selection = selectTargets([path], {event});
    const needs = results(selection);
    for (const name of ['session-evidence', 'session-controls', 'pipeline-evidence']) needs[name].result = deep ? 'success' : 'skipped';
    const lines = verifyGate(plan(selection), needs, {...context, event});
    for (const name of ['session-evidence', 'session-controls', 'pipeline-evidence']) {
      assert(lines.some(line => line.startsWith(`${deep ? 'PASS' : 'NOT APPLICABLE'} ${name}:`)));
      assert.throws(() => verifyGate(plan(selection), {...needs,
        [name]: {result: deep ? 'skipped' : 'success'}}, {...context, event}), undefined, `${event}/${path}/${name}`);
    }
    const scheduleNeeds = {'select-targets': {outputs: {profile: 'full', deep_proofs: String(deepProofRequired(selection))}}};
    for (const name of ['session-evidence', 'session-controls', 'pipeline-mutations', 'pipeline-mutations-rest', 'pipeline-capacity', 'pipeline-capacity-mutants']) {
      assert.equal(scheduled(name, scheduleNeeds), deep, `${event}/${path}/${name}`);
    }
  }
});

test('shallow and deep aggregate expectations reject every wrong status, including cheap validation', () => {
  for (const event of ['pull_request', 'push', 'schedule', 'workflow_dispatch']) {
    for (const paths of [['README.md'], ['src/bounded_execution/session.mbt'], []]) {
      const selection = selectTargets(paths, {event});
      const env = {...context, event};
      assert.doesNotThrow(() => verifyGate(plan(selection), results(selection), env));
      for (const name of gateJobs) {
        const correct = gateJobRequired(selection, name) ? 'success' : 'skipped';
        for (const wrong of ['success', 'skipped', 'failure', 'cancelled', undefined].filter(value => value !== correct)) {
          const candidate = results(selection); candidate[name] = {result: wrong};
          assert.throws(() => verifyGate(plan(selection), candidate, env), undefined, `${event}/${name}/${wrong}`);
        }
      }
    }
  }
  const needs = Object.fromEntries(jobs['pipeline-evidence'].needs.map(name => [name, {result: 'skipped'}]));
  needs['pipeline-validation'].result = 'success';
  assert.equal(scheduled('pipeline-evidence', needs), false, 'cheap checks alone do not start deep assembly');
});

test('Ready PR record-only observations and the aggregate select the same existing package consumers', () => {
  const job = jobs['main-performance'];
  assert(gateJobs.includes('main-performance') && jobs.check.needs.includes('main-performance'));
  const cases = [
    selectTargets(['src/query/new-case.mbt'], {event: 'pull_request', draft: false}),
    selectTargets(['src/query/new-case.mbt'], {event: 'pull_request', draft: true}),
    maintenanceSelection(['scripts/operation-performance.mjs']),
    ...['push', 'schedule', 'workflow_dispatch'].map(event => selectTargets(['README.md'], {event})),
  ];
  for (const selection of cases) {
    const required = selection.event === 'push' || selection.event === 'pull_request' && selection.profile === 'full';
    const scheduled = runInNewContext(job.if.slice(3, -2).trim(), {
      inputs: {}, needs: {'select-targets': {outputs: {profile: selection.profile}}}, toJSON: JSON.stringify,
      github: {event_name: selection.event, ref: 'refs/heads/main', event: {
        repository: {visibility: 'public', private: false}, pull_request: {draft: selection.profile.startsWith('draft')},
      }},
    }, {timeout: 100});
    assert.equal(scheduled, required, `${selection.event}/${selection.profile}`);
    assert.equal(gateJobRequired(selection, 'main-performance'), required);
    const env = {...context, event: selection.event};
    if (selection.profile.startsWith('draft')) {
      assert.throws(() => verifyGate(plan(selection), results(selection), env), /Draft preparation is not merge verification/);
      continue;
    }
    assert.doesNotThrow(() => verifyGate(plan(selection), results(selection), env));
    for (const wrong of required ? ['failure', 'cancelled', 'skipped', undefined] : ['success']) {
      assert.throws(() => verifyGate(plan(selection),
        {...results(selection), 'main-performance': {result: wrong}}, env), /main-performance/);
    }
  }
  assert.deepEqual(job.needs, ['select-targets', 'client-packages']);
});

test('record-only PR observations preserve private, Draft, lightweight and alternate-mode exclusions', () => {
  const runs = ({profile = 'full', draft = false, visibility = 'public', privateFlag = false,
    event = 'pull_request', ref = 'refs/heads/main', inputs = {}} = {}) => runInNewContext(
    jobs['main-performance'].if.slice(3, -2).trim(), {
      inputs, needs: {'select-targets': {outputs: {profile}}}, toJSON: JSON.stringify,
      github: {event_name: event, ref, event: {repository: {visibility, private: privateFlag}, pull_request: {draft}}},
    }, {timeout: 100});
  assert.equal(runs(), true);
  for (const profile of ['maintenance', 'focused-tests', 'draft', 'draft-focused']) {
    assert.equal(runs({profile}), false, profile);
    assert.equal(gateJobRequired({event: 'pull_request', profile}, 'main-performance'), false, profile);
  }
  for (const options of [{draft: true}, {visibility: 'private', privateFlag: true},
    {privateFlag: null}, {event: 'schedule'}, {event: 'workflow_dispatch'},
    {event: 'push', ref: 'refs/heads/feature'},
    {inputs: {performance_matrix: true}}, {inputs: {packed_query_evidence_probe: true}}]) {
    assert.equal(runs(options), false, JSON.stringify(options));
  }
});

test('existing push-only health result is required by the same aggregate that schedules it', () => {
  assert(jobs.check.needs.includes('health-quick'));
  assert(gateJobs.includes('health-quick'));
  assert.equal(jobs['health-quick'].uses, './.github/workflows/health-monitor.yml');
  assert(jobs['health-quick'].needs.includes('select-targets'));
  assert(jobs['health-quick'].needs.includes('client-packages'));
  const runs = (event, ref = 'refs/heads/main', inputs = {}, outcomes = {admission: 'success', producer: 'success'}) => runInNewContext(
    jobs['health-quick'].if.slice(3, -3).replace(/needs\.([a-z][a-z0-9-]*)/gu, (_, name) => `needs[${JSON.stringify(name)}]`),
    {inputs, always: () => true, toJSON: JSON.stringify,
      needs: {'select-targets': {result: outcomes.admission, outputs: {profile: 'full'}}, 'client-packages': {result: outcomes.producer}},
      github: {event_name: event, ref, event: {repository: {visibility: 'public', private: false}}}});
  for (const event of ['push', 'pull_request', 'schedule', 'workflow_dispatch']) {
    const selection = selectTargets(['README.md'], {event});
    const required = event === 'push';
    assert.equal(runs(event), required, event);
    assert.equal(gateJobRequired(selection, 'health-quick'), required, event);
    const env = {...context, event};
    verifyGate(plan(selection), results(selection), env);
    for (const result of required ? ['failure', 'cancelled', 'skipped', undefined] : ['success']) {
      assert.throws(() => verifyGate(plan(selection),
        {...results(selection), 'health-quick': {result}}, env), /health-quick/);
    }
  }
  assert.equal(runs('push', 'refs/heads/feature'), false);
  for (const mode of ['performance_matrix', 'packed_query_evidence_probe'])
    assert.equal(runs('push', 'refs/heads/main', {[mode]: true}), false);
  for (const producer of ['success', 'failure', 'cancelled', 'skipped', undefined]) {
    assert.equal(runs('push', 'refs/heads/main', {}, {admission: 'success', producer}), true,
      'Valid admission must preserve the real producer outcome in the monitor');
    for (const admission of ['failure', 'cancelled', 'skipped', undefined])
      assert.equal(runs('push', 'refs/heads/main', {}, {admission, producer}), false,
        'Failed admission cannot reach the fresh-package monitor fallback');
  }
});

test('push applicability reads only exact authenticated endpoints and keeps deleted/renamed paths', () => {
  const before = 'c'.repeat(40), payload = {ref: 'refs/heads/main', before, after: head};
  const calls = [];
  const git = args => { calls.push(args); return args[0] === 'rev-parse' ? head : 'src/deleted.mbt\0packages/sdk/renamed.mjs\0'; };
  assert.deepEqual(readPushChanges(payload, head, git).paths, ['src/deleted.mbt', 'packages/sdk/renamed.mjs']);
  assert.deepEqual(calls, [['rev-parse', 'HEAD'], ['diff', '--no-renames', '--name-only', '-z', before, head, '--']]);
  for (const patch of [{before: null}, {before: '0'.repeat(40)}, {before: 'bad'}, {after: before}, {ref: 'refs/heads/other'}])
    assert.throws(() => readPushChanges({...payload, ...patch}, head, git));
  assert.throws(() => readPushChanges(payload, head, args => args[0] === 'rev-parse' ? head : 'truncated'));
  assert.throws(() => readPushChanges(payload, head, () => { throw Error('missing base object'); }));
});

test('same-environment duplicate checks retain one explicit owner without weakening platform evidence', () => {
  const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  assert(pkg.scripts['check:retained-boundary'].includes('adapters/store-local/publication-commit-owner.test.mjs'));
  assert(!jobs.host.steps.some(step => step.run?.startsWith('node --test adapters/store-local/publication-commit-owner.test.mjs')));
  assert(pkg.scripts['check:distribution-client'].includes('scripts/owned-scratch.test.mjs'));
  const scratch = jobs.lint.steps.find(step => step.run === 'node --test scripts/owned-scratch.test.mjs');
  for (const profile of ['full', 'maintenance', 'focused-tests']) assert.equal(draftStepEnabled(scratch, profile), true);
  for (const profile of ['draft', 'draft-focused', 'documentation']) assert.equal(draftStepEnabled(scratch, profile), false);
  assert.deepEqual(Object.entries(jobs).flatMap(([name, job]) =>
    job.steps?.filter(step => step.run?.split(/\s+/u).includes('scripts/owned-scratch.test.mjs'))
      .map(() => name) ?? []), ['lint'], 'normal scratch checks have one runtime-independent owner');
  assert(jobs.lint.steps.some(step => step.run === 'node --test scripts/dependency-isolation-scratch.test.mjs'));
  // Operation inventory remains fail-fast before fan-out: deleting that safety
  // admission is not justified merely because spec also checks the inventory.
  assert(jobs.preflight.steps.some(step => step.run === 'node --test scripts/pure-operation-inventory.test.mjs' && !step.if));
});


test('mandatory packed query CI selects its finite full-corpus envelope inside the job', () => {
  const job = jobs['client-packed'];
  assert.equal(job['timeout-minutes'], 45);
  const step = job.steps.find(value => value.id === 'packed-query');
  assert.ok(step);
  assert.equal(step.env.ACTQL_TEST_QUERY_TIMEOUT_MS, '1800000');
  assert.match(step.run, /node scripts\/test-packed-public-query\.mjs/u);
  assert.doesNotMatch(step.run, /--[a-z-]+-only/u);
  assert.ok(job['timeout-minutes'] * 60_000 > Number(step.env.ACTQL_TEST_QUERY_TIMEOUT_MS) + 120_000,
    'the whole job retains time for installation, other selected checks and original Saved');
});
