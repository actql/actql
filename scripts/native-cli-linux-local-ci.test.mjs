import './native-cli-ci-artifact.test.mjs';
import assert from 'node:assert/strict';
import {chmodSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {test} from 'node:test';
import {parse} from 'yaml';
import {gateJobs} from './ci-targets.mjs';
import {classifyJob} from './local-checks-policy.mjs';
import {nativeInstalledIngressSelection} from './test-native-cli-source-free-install.mjs';
import {nativeFileSourceQueries} from './fixtures/native-file-source-queries.mjs';

const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const job = workflow.jobs['native-cli-linux-local'];
const installedJob = workflow.jobs['native-cli-linux-local-installed'];
const mockJob = workflow.jobs['native-cli-linux-local-mock'];

test('normal Linux Local job is separate, mandatory and explicitly bounded', () => {
  assert(job);
  assert.deepEqual(job.needs, ['select-targets']);
  assert.equal(job['runs-on'], 'ubuntu-24.04');
  assert.equal(job['timeout-minutes'], 50);
  assert.match(job.if, /outputs\.profile == 'full'/u);
  assert.equal(job['continue-on-error'], undefined);
  assert(gateJobs.includes('native-cli-linux-local'));
  assert(workflow.jobs.check.needs.includes('native-cli-linux-local'));
  assert.equal(classifyJob('native-cli-linux-local').heavy, true);
  assert(!job.steps.some(step => step.uses === './.github/actions/download-client-packages'),
    'Source-free acceptance cannot borrow a Node Host package cohort');
});

test('Local CI finishes normal production and packaging before independent installed acceptance', () => {
  const commands = job.steps.filter(step => step.run).map(step => step.run);
  const producer = commands.findIndex(command => command.includes('node scripts/produce-native-cli-linux-local.mjs'));
  const pack = commands.findIndex(command => command.includes('node scripts/native-cli-release.mjs prepare-local'));
  assert(producer >= 0 && producer < pack);
  assert(!commands.some(command => command.includes('node scripts/test-native-cli-source-free-install.mjs')));
  assert(!commands.some(command => command.includes('node scripts/test-native-cli-mock-install.mjs')));
  const command = commands[producer];
  for (const selected of ['--source "$(git rev-parse HEAD)"', '--package-version 0.0.2',
    '--clang "$(realpath /usr/bin/clang-19)"', '--sqlite-archive', '--component-seconds 300', '--compile-seconds 1800']) {
    assert(command.includes(selected), selected);
  }
  assert.equal(command.match(/--openssl-package-archive/gu).length, 2);
  assert(!command.includes('--system-header-root'), 'Normal Ubuntu headers need no implicit extra-root widening');
  assert(!commands.some(value => /\|\|\s*(?:true|node)|--ignore-scripts.*artifact/u.test(value)));
  for (const index of [producer, pack]) {
    const step = job.steps.find(value => value.run === commands[index]);
    assert.equal(step.if, undefined); assert.equal(step['continue-on-error'], undefined);
  }
  assert.equal(job.steps.find(value => value.run === commands[pack]).id, 'local_cohort');
});

test('installed Local acceptance consumes the successful producer independently of Mock acceptance', () => {
  assert.deepEqual(installedJob.needs, ['select-targets', 'native-cli-linux-local']);
  assert.equal(installedJob['runs-on'], 'ubuntu-24.04');
  assert(Number.isFinite(installedJob['timeout-minutes']) && installedJob['timeout-minutes'] > 0);
  assert(gateJobs.includes('native-cli-linux-local-installed'));
  assert(workflow.jobs.check.needs.includes('native-cli-linux-local-installed'));
  assert(workflow.jobs.native.needs.includes('native-cli-linux-local-installed'));
  assert.equal(classifyJob('native-cli-linux-local-installed').heavy, true);
  assert.equal(installedJob['continue-on-error'], undefined);
  assert(!installedJob.steps.some(step => /produce-native|native-cli-release|test-native-cli-mock-install/u.test(step.run ?? '')));
  const consumer = installedJob.steps.find(step => step.run?.includes('node scripts/test-native-cli-source-free-install.mjs'));
  assert(consumer);
  assert.equal(consumer.if, undefined);
  assert.equal(consumer['continue-on-error'], undefined);
  assert.equal(consumer.run.split(' ').at(-1), '"$RUNNER_TEMP/native-cli-linux-local/release"');
  const download = installedJob.steps.find(step => step.uses?.startsWith('actions/download-artifact@'));
  assert.deepEqual(download.with, {
    'artifact-ids': '${{ needs.native-cli-linux-local.outputs.artifact-id }}',
    path: '${{ runner.temp }}/native-cli-linux-local', 'merge-multiple': true,
  });
  assert(installedJob.steps.indexOf(download) < installedJob.steps.indexOf(consumer));
  const condition = installedJob.if.replace(/^\$\{\{\s*|\s*\}\}$/gu, '')
    .replace(/needs\.([a-z][a-z0-9-]*)/gu, (_, name) => `needs[${JSON.stringify(name)}]`);
  const enabled = Function('needs', 'github', 'inputs', 'toJSON', `return (${condition});`);
  for (const result of ['success', 'failure', 'cancelled', 'skipped', undefined]) {
    assert.equal(enabled({'select-targets': {outputs: {profile: 'full'}},
      'native-cli-linux-local': {result}}, {event: {repository: {visibility: 'public', private: false}}},
    {}, JSON.stringify), result === 'success');
  }
});

test('Mock workflows require a fresh runner and the successful exact producer cohort', () => {
  assert.deepEqual(mockJob.needs, ['select-targets', 'native-cli-linux-local']);
  assert.equal(mockJob['runs-on'], 'ubuntu-24.04');
  assert(Number.isFinite(mockJob['timeout-minutes']) && mockJob['timeout-minutes'] > 0);
  assert.equal(mockJob['continue-on-error'], undefined);
  assert(gateJobs.includes('native-cli-linux-local-mock'));
  assert(workflow.jobs.check.needs.includes('native-cli-linux-local-mock'));
  assert(workflow.jobs.native.needs.includes('native-cli-linux-local-mock'));
  assert.equal(classifyJob('native-cli-linux-local-mock').heavy, true);
  const condition = mockJob.if.replace(/^\$\{\{\s*|\s*\}\}$/gu, '')
    .replace(/needs\.([a-z][a-z0-9-]*)/gu, (_, name) => `needs[${JSON.stringify(name)}]`);
  const enabled = Function('needs', 'github', 'inputs', 'toJSON', `return (${condition});`);
  for (const result of ['success', 'failure', 'cancelled', 'skipped', undefined]) {
    assert.equal(enabled({'select-targets': {outputs: {profile: 'full'}},
      'native-cli-linux-local': {result}}, {event: {repository: {visibility: 'public', private: false}}},
    {}, JSON.stringify), result === 'success');
  }
  const setup = mockJob.steps.find(step => step.uses === './.github/actions/setup-toolchain');
  assert.equal(setup.with.python, 'true');
  assert(mockJob.steps.some(step => step.uses === job.steps[0].uses && step.with['persist-credentials'] === false));
  const download = mockJob.steps.find(step => step.uses?.startsWith('actions/download-artifact@'));
  assert.deepEqual(download.with, {
    'artifact-ids': '${{ needs.native-cli-linux-local.outputs.artifact-id }}',
    path: '${{ runner.temp }}/native-cli-linux-local', 'merge-multiple': true,
  });
  assert.match(download.uses, /@[a-f0-9]{40}$/u);
  assert.equal(download.if, undefined);
  const upload = job.steps.find(step => step.id === 'local_evidence');
  assert(upload.uses.startsWith('actions/upload-artifact@'));
  assert.deepEqual(job.outputs, {
    'artifact-id': '${{ steps.local_evidence.outputs.artifact-id }}',
    'artifact-run-id': '${{ github.run_id }}',
    'artifact-run-attempt': '${{ github.run_attempt }}',
    'artifact-source-sha': '${{ github.sha }}',
  });
  const authentication = mockJob.steps.find(step => step.run?.includes('inspect-native-approval-source'));
  assert.equal(mockJob.permissions.actions, 'read');
  assert.equal(authentication.env.PACKAGE_RUN_ID, '${{ github.run_id }}');
  assert.equal(authentication.env.PACKAGE_ARTIFACT_ID, '${{ needs.native-cli-linux-local.outputs.artifact-id }}');
  assert.equal(authentication.env.PACKAGE_PRODUCER_JOB, 'native-cli-linux-local');
  assert.equal(authentication.env.PACKAGE_EVENT_HEAD_SHA, '${{ github.event.pull_request.head.sha || github.sha }}');
  assert(authentication.run.includes('inspect-native-approval-producer'));
  const mock = mockJob.steps.find(step => step.run?.includes('node scripts/test-native-approval-performance.mjs'));
  for (const argument of ['--normal "$RUNNER_TEMP/native-cli-linux-local/release"',
    '--binding "$RUNNER_TEMP/native-cli-linux-local/approval/source.json"',
    '--output "$RUNNER_TEMP/native-cli-linux-local/approval/assessment.json"', '--runner ubuntu-24.04'])
    assert(mock.run.includes(argument), argument);
  assert.equal(mock.env?.TMPDIR, undefined, 'Use the existing formal collector filesystem context');
  assert(!mock.run.includes('--diagnostic'), 'The required profile must enforce all thirty samples');
  assert.equal(mock.if, undefined);
  assert.equal(mock['continue-on-error'], undefined);
  assert(mockJob.steps.indexOf(download) < mockJob.steps.indexOf(mock));
  assert(mockJob.steps.indexOf(download) < mockJob.steps.indexOf(authentication));
  assert(mockJob.steps.indexOf(authentication) < mockJob.steps.indexOf(mock));
  assert(!/--measure|performance-diagnostic/u.test(mock.run), 'The formal collector is not the diagnostic consumer');
  assert(!mockJob.steps.some(step => /produce-native|native-cli-release/u.test(step.run ?? '')),
    'Neither formal sampling nor failure diagnostics may rebuild the fixed Native payload');
  const diagnostics = mockJob.steps.filter(step => step.run?.includes('--diagnose-approval-syscalls'));
  assert.equal(diagnostics.length, 1, 'One separate diagnostic may follow a failed formal campaign');
  const diagnostic = diagnostics[0];
  const diagnosticCondition = diagnostic.if.replace(/^\$\{\{\s*|\s*\}\}$/gu, '');
  const diagnose = Function('failure', 'steps', `return (${diagnosticCondition});`);
  for (const failed of [false, true]) for (const outcome of ['success', 'failure', 'cancelled', 'skipped', undefined]) {
    assert.equal(diagnose(() => failed, {[mock.id]: {outcome}}), failed && outcome === 'failure');
  }
  assert(mockJob.steps.indexOf(diagnostic) > mockJob.steps.indexOf(mock));
  assert(diagnostic.run.includes('"$RUNNER_TEMP/native-cli-linux-local/release"'), 'Keep the same original RC');
  assert(diagnostic.run.includes('--measure-approval-resources'));
});

test('exact Local artifact preflight refuses other attempts sources and missing or multiple IDs', () => {
  for (const consumer of [installedJob, mockJob]) {
    const preflight = consumer.steps.find(step => step.env?.ARTIFACT_ID === '${{ needs.native-cli-linux-local.outputs.artifact-id }}');
    assert.deepEqual(preflight.env, {
      ARTIFACT_ID: '${{ needs.native-cli-linux-local.outputs.artifact-id }}',
      ARTIFACT_RUN_ID: '${{ needs.native-cli-linux-local.outputs.artifact-run-id }}',
      ARTIFACT_RUN_ATTEMPT: '${{ needs.native-cli-linux-local.outputs.artifact-run-attempt }}',
      ARTIFACT_SOURCE_SHA: '${{ needs.native-cli-linux-local.outputs.artifact-source-sha }}',
      EXPECTED_RUN_ID: '${{ github.run_id }}', EXPECTED_RUN_ATTEMPT: '${{ github.run_attempt }}',
      EXPECTED_SOURCE_SHA: '${{ github.sha }}',
    });
    const original = {ARTIFACT_ID: '101', ARTIFACT_RUN_ID: '42', ARTIFACT_RUN_ATTEMPT: '3',
      ARTIFACT_SOURCE_SHA: 'a'.repeat(40), EXPECTED_RUN_ID: '42', EXPECTED_RUN_ATTEMPT: '3',
      EXPECTED_SOURCE_SHA: 'a'.repeat(40)};
    const execute = changed => spawnSync('bash', ['-eo', 'pipefail', '-c', preflight.run],
      {encoding: 'utf8', timeout: 3000, env: {...process.env, ...original, ...changed}});
    assert.equal(execute({}).status, 0);
    for (const changed of [{ARTIFACT_ID: ''}, {ARTIFACT_ID: '0'}, {ARTIFACT_ID: '101,102'},
      {ARTIFACT_RUN_ID: '43'}, {ARTIFACT_RUN_ATTEMPT: '2'}, {ARTIFACT_SOURCE_SHA: 'b'.repeat(40)}]) {
      const result = execute(changed);
      assert.equal(result.error, undefined);assert.equal(result.signal, null);
      assert.notEqual(result.status, 0, JSON.stringify(changed));
    }
    const download = consumer.steps.findIndex(step => step.uses?.startsWith('actions/download-artifact@'));
    assert(consumer.steps.indexOf(preflight) < download);
  }
});

test('Native aggregate rejects a failed missing or skipped independent Local consumer', () => {
  const step = workflow.jobs.native.steps.find(step => step.run);
  for (const name of ['native-cli-linux-local-installed', 'native-cli-linux-local-mock']) {
    for (const result of ['success', 'failure', 'cancelled', 'skipped', undefined]) {
      const needs = {'native-workloads': {result: 'success'}, 'native-http': {result: 'success'},
        'native-cli-linux-local-installed': {result: 'success'}, 'native-cli-linux-local-mock': {result: 'success'}};
      needs[name] = {result};
      const checked = spawnSync('bash', ['-eo', 'pipefail', '-c', step.run],
        {encoding: 'utf8', timeout: 3000, env: {...process.env, RESULTS: JSON.stringify(needs)}});
      assert.equal(checked.error, undefined);assert.equal(checked.signal, null);
      assert.equal(checked.status === 0, result === 'success', String(result));
    }
  }
});

test('required Native producer also executes all real allocator cases with original prepared inputs', () => {
  const selected = job.steps.find(step => step.name === 'Require actual bounded Crypto allocator conformance');
  assert(selected);
  assert.equal(selected['timeout-minutes'], 3);
  assert.equal(selected['continue-on-error'], undefined);
  assert.match(selected.if, /!cancelled\(\) && steps\.local_cohort\.outcome == 'success'/u);
  assert(selected.run.includes('python3 scripts/test-native-crypto-allocator.py'));
  assert(selected.run.includes('--source "$(git rev-parse HEAD)"'));
  assert(selected.run.includes('--clang "$(realpath /usr/bin/clang-19)"'));
  assert(selected.run.includes('/production/crypto/producer.json"'));
  assert(!selected.run.includes('--openssl-prefix'), 'Hosted execution uses the original producer, never a host fallback');
  const cohort = job.steps.findIndex(step => step.id === 'local_cohort');
  assert(job.steps.indexOf(selected) > cohort);
  const retained = job.steps.find(step => step.uses?.startsWith('actions/upload-artifact@'));
  assert(retained.with.path.includes('/crypto-allocator/summary.json'));
  assert(!retained.with.path.includes('/crypto-allocator/**'), 'Retain safe numeric reports, not whole test backing');
  const cases = spawnSync('python3', ['-c', `
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location('allocator_cases', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert module.MODES and len(set(module.MODES)) == len(module.MODES)
for mode in module.MODES:
    row = {'case': mode, 'passed': True, 'original_cleanup': True}
    if mode.startswith('callback-invalid-'):
        row.update(original_cleanup=False, failure_custody=True, physical_stop='process-exit-required')
    assert module.observed_case_passed(mode, 0, [row])
    assert not module.observed_case_passed(mode, 1, [row])
    assert not module.observed_case_passed(mode, 0, [])
    assert not module.observed_case_passed(mode, 0, [row, row])
    assert not module.observed_case_passed(mode, 0, [{**row, 'passed': False}])
    assert not module.observed_case_passed(mode, 0, [{**row, 'original_cleanup': not row['original_cleanup']}])
    if mode.startswith('callback-invalid-'):
        assert not module.observed_case_passed(mode, 0, [{**row, 'failure_custody': False}])
assert not module.observed_case_passed('unknown', 0, [{'case': 'unknown', 'passed': True, 'original_cleanup': True}])
print(json.dumps(list(module.MODES)))
`, fileURLToPath(new URL('./test-native-crypto-allocator.py', import.meta.url))],
  {encoding: 'utf8', timeout: 5000, env: {...process.env, PYTHONDONTWRITEBYTECODE: '1'}});
  assert.equal(cases.error, undefined); assert.equal(cases.status, 0, cases.stderr);
  for (const mode of ['bounded-search', 'split-merge-membership', 'partial', 'callback-current'])
    assert(JSON.parse(cases.stdout).includes(mode), mode);
});

test('CI downloads original hash-bounded archives and retains exact production and failure receipts', () => {
  const download = job.steps.find(step => step.name === 'Retain exact official component archives').run;
  for (const text of ['sqlite-component/source.json', 'crypto-component/source.json',
    "response.read(original['bytes'] + 1)", "hashlib.sha256(data).hexdigest() == original['sha256']",
    ".open('xb')"]) assert(download.includes(text), text);
  assert(download.includes("crypto['license']['package']"));
  const retain = job.steps.find(step => step.uses?.startsWith('actions/upload-artifact@'));
  assert.equal(retain.if, 'always()');
  for (const path of ['sqlite/process-producer.json', 'crypto/producer.json', 'recipe/',
    'artifact/artifact.json', 'native-producer/build.json', 'release/release.json']) {
    assert(retain.with.path.includes(path), path);
  }
  assert(!retain.with.path.includes('mock-install-'), 'Mock evidence belongs to its independent job');
  assert(!retain.with.path.includes('source-free-install-'), 'Installed evidence belongs to its independent job');
  const installedRetain = installedJob.steps.find(step => step.uses?.startsWith('actions/upload-artifact@'));
  assert.equal(installedRetain.if, 'always()');
  assert.equal(installedRetain.with.name, 'native-cli-linux-local-installed-${{ github.run_id }}-${{ github.run_attempt }}');
  assert(installedRetain.with.path.includes('/release/source-free-install-*.json'));
  assert(installedRetain.with.path.includes('/release/source-free-observed-*.json'));
  const mockRetain = mockJob.steps.find(step => step.uses?.startsWith('actions/upload-artifact@'));
  assert.equal(mockRetain.if, 'always()');
  assert.equal(mockRetain.with.name, 'native-cli-linux-local-mock-${{ github.run_id }}-${{ github.run_attempt }}');
  const paths = new Set(mockRetain.with.path.trim().split('\n'));
  for (const path of [
    '${{ runner.temp }}/native-cli-linux-local/approval/*.json',
    '${{ runner.temp }}/native-cli-linux-local/release/mock-install-*.json',
    '${{ runner.temp }}/native-cli-linux-local/release/mock-syscalls-*.json',
    '${{ runner.temp }}/native-cli-linux-local/release/approval-resources-*.txt',
    '${{ runner.temp }}/native-cli-linux-local/release/approval-syscalls-*.txt',
    '/tmp/actql-native-mock-install-*/commands.json',
    '/tmp/actql-native-mock-install-*/approval-resources-*.txt',
    '/tmp/actql-native-mock-install-*/approval-syscalls-*.txt',
  ]) assert(paths.has(path), `Missing formal or diagnostic evidence family: ${path}`);
  assert(!mockRetain.with.path.includes('mock-consumers/**'), 'Do not upload private project state or keys');
});

test('CI pinned component downloader keeps bounded reset retries and original refusals', () => {
  const command = job.steps.find(step => step.name === 'Retain exact official component archives').run;
  const inline = command.match(/^python3 - <<'PY'\n([\s\S]+)\nPY\n?$/u);
  assert(inline, 'Exercise the actual workflow caller, not a duplicate downloader');
  const fixture = fileURLToPath(new URL('./fixtures/native-component-archive-retry.py', import.meta.url));
  const result = spawnSync('python3', [fixture], {input:inline[1], encoding:'utf8', timeout:20000});
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /^Pinned component archive controls: 10\/10$/mu);
});


test('mandatory Local installation retains ingress controls on its actual installed runtime',()=>{
  const installed=readFileSync(new URL('./test-native-cli-source-free-install.mjs',import.meta.url),'utf8');
  const transport=readFileSync(new URL('./test-native-client.mjs',import.meta.url),'utf8');
  const fixture=readFileSync(new URL('./test-native-local-cli.test.mjs',import.meta.url),'utf8');
  const selection=nativeInstalledIngressSelection();
  for(const file of ['test-native-local-cli.test.mjs','test-native-file-source-queries.test.mjs'])
    assert.equal(selection.files.filter(path=>path.endsWith('/'+file)).length,1,file);
  assert.equal(selection.expectedTests,13+nativeFileSourceQueries.length);
  assert(installed.includes('const {files,expectedTests}=nativeInstalledIngressSelection()'));
  assert(installed.includes('admitInstalledLocalRuntime({root:platformRoot,metadata:artifact.localRuntime'));
  for(const key of ['ACTQL_TEST_NATIVE_CLIENT_LAUNCHER','ACTQL_TEST_NATIVE_CLIENT_BINARY']) {
    assert(installed.includes(key),key);assert(fixture.includes(key),key);
  }
  for(const key of ['ACTQL_TEST_NATIVE_SQLITE_LIBRARY','ACTQL_TEST_NATIVE_CRYPTO_LIBRARY']) {
    assert(installed.includes(key),key);
    assert(!fixture.includes(key), 'public Project refusal must not fabricate legacy runtime bindings');
  }
  assert(!transport.includes("import('./test-native-local-cli.test.mjs')"));
  assert(!fixture.includes('prepareNativeRuntimeBundleLibraries'));
  assert(installed.indexOf('if(runIngress)')>installed.indexOf('} catch (error) { failure = error; }'));
  assert(installed.includes("new AggregateError([failure,error],'Installed Local execution and ingress failed')"));
});


const compilerStep = job.steps.find(step => step.name === 'Install selected Linux compiler');
const compilerCommands = readFileSync(new URL('./ci-install-linux-clang.sh', import.meta.url), 'utf8');

test('selected Linux compiler acquisition keeps official signed sources and finite transport bounds', () => {
  assert.equal(compilerStep['timeout-minutes'], 5);
  assert.equal(compilerStep['continue-on-error'], undefined);
  assert(compilerCommands.includes('https://archive.ubuntu.com/ubuntu/'));
  for (const option of ['Acquire::Retries=2', 'Acquire::http::Timeout=30', 'Acquire::https::Timeout=30']) {
    assert(compilerCommands.includes(option));
  }
  assert(compilerCommands.includes('update --error-on=any'));
  assert(compilerCommands.includes('install --yes clang-19'));
  assert(compilerCommands.includes('test -x /usr/bin/clang-19'));
  assert(!/allow-unauthenticated|AllowInsecure|trusted=yes|apt-key|add-apt-repository|sources\.list|\|\|\s*true/u.test(compilerCommands));
});

// Exercise only the selected shell control flow. No APT, network, compiler or
// system repository is invoked; the two absolute paths use private fixtures.
function compilerAcquisitionControl(failure) {
  const root = mkdtempSync(join(tmpdir(), 'actql-compiler-acquisition-'));
  try {
    const bin = join(root, 'bin'), mirror = join(root, 'apt-mirrors.txt');
    const compiler = join(root, 'clang-19'), calls = join(root, 'calls');
    mkdirSync(bin);
    writeFileSync(mirror, 'http://azure.archive.ubuntu.com/ubuntu/\n');
    const sudo = join(bin, 'sudo');
    writeFileSync(sudo, `#!/bin/bash
set -euo pipefail
if [[ "$1" == tee ]]; then exec /usr/bin/tee "$2"; fi
[[ "$1" == apt-get ]] || exit 99
printf '%s\\n' "$*" >> "$ACQUISITION_CALLS"
if [[ "$*" == *' update '* && "$ACQUISITION_FAILURE" == update ]]; then exit 100; fi
if [[ "$*" == *' install '* ]]; then
  if [[ "$ACQUISITION_FAILURE" == install ]]; then exit 100; fi
  if [[ "$ACQUISITION_FAILURE" != missing ]]; then
    printf '#!/bin/sh\\nexit 0\\n' > "$ACQUISITION_COMPILER"
    chmod +x "$ACQUISITION_COMPILER"
  fi
fi
`);
    chmodSync(sudo, 0o755);
    const shell = compilerCommands.replaceAll('/etc/apt/apt-mirrors.txt', mirror)
      .replaceAll('/usr/bin/clang-19', compiler);
    const result = spawnSync('bash', ['-c', shell], {encoding: 'utf8', timeout: 3000,
      env: {...process.env, PATH: bin + ':/usr/bin:/bin', ACQUISITION_CALLS: calls,
        ACQUISITION_COMPILER: compiler, ACQUISITION_FAILURE: failure}});
    assert.equal(result.error, undefined);assert.equal(result.signal, null);
    return {status: result.status, mirror: readFileSync(mirror, 'utf8'),
      calls: readFileSync(calls, 'utf8').trim().split('\n')};
  } finally {rmSync(root, {recursive: true, force: true});}
}

test('compiler acquisition selects the canonical Ubuntu mirror before update and exact clang install', () => {
  const result = compilerAcquisitionControl('none');
  assert.equal(result.status, 0);
  assert.equal(result.mirror, 'https://archive.ubuntu.com/ubuntu/\n');
  assert.deepEqual(result.calls, [
    'apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 update --error-on=any',
    'apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 install --yes clang-19',
  ]);
});

test('compiler acquisition fails closed on update, fetch and missing selected executable', () => {
  for (const [failure, code, calls] of [['update', 100, 1], ['install', 100, 2], ['missing', 1, 2]]) {
    const result = compilerAcquisitionControl(failure);
    assert.equal(result.status, code, failure);
    assert.equal(result.calls.length, calls, failure);
  }
});


test('packed Native Graph shares bounded compiler acquisition before exact compiler aliases', () => {
  const step = workflow.jobs['client-packed'].steps.find(step =>
    step.name === 'Select the packed Native Graph compiler');
  assert.equal(step['timeout-minutes'], 5);
  assert.equal(step['continue-on-error'], undefined);
  assert.equal(compilerStep.run.trim(), 'bash scripts/ci-install-linux-clang.sh');
  assert.equal(step.run.split('\n')[0], compilerStep.run.trim());
  assert.deepEqual(step.run.trim().split('\n').slice(1), [
    'compiler_bin="$RUNNER_TEMP/packed-query-compiler"',
    'mkdir -m 700 "$compiler_bin"',
    'ln -s "$(realpath /usr/bin/clang-19)" "$compiler_bin/cc"',
    'ln -s "$(realpath /usr/bin/ar)" "$compiler_bin/ar"',
    'echo "$compiler_bin" >> "$GITHUB_PATH"',
  ]);
});
