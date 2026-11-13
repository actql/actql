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

const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
const job = workflow.jobs['native-cli-linux-local'];

test('normal Linux Local job is separate, mandatory and explicitly bounded', () => {
  assert(job);
  assert.deepEqual(job.needs, ['select-targets', 'preflight']);
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

test('Local CI uses the normal selected producer and Local-required packaging before actual install', () => {
  const commands = job.steps.filter(step => step.run).map(step => step.run);
  const producer = commands.findIndex(command => command.includes('node scripts/produce-native-cli-linux-local.mjs'));
  const pack = commands.findIndex(command => command.includes('node scripts/native-cli-release.mjs prepare-local'));
  const install = commands.findIndex(command => command.includes('node scripts/test-native-cli-source-free-install.mjs'));
  const mock = commands.findIndex(command => command.includes('node scripts/test-native-cli-mock-install.mjs'));
  assert(producer >= 0 && producer < pack && pack < install);
  assert(pack < mock);
  const command = commands[producer];
  for (const selected of ['--source "$(git rev-parse HEAD)"', '--package-version 0.0.2-rc.0',
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
  for (const index of [install, mock]) {
    const step = job.steps.find(value => value.run === commands[index]);
    assert.equal(step['continue-on-error'], undefined);
    assert.equal(step.run.split(' ').at(-1), '"$RUNNER_TEMP/native-cli-linux-local/release"');
  }
});

test('prepared Local consumers remain independently required after sibling failure', () => {
  const consumers = ['test-native-cli-source-free-install.mjs', 'test-native-cli-mock-install.mjs']
    .map(script => job.steps.find(step => step.run?.includes(`node scripts/${script}`)));
  for (const consumer of consumers) {
    assert(consumer);
    assert.match(consumer.if, /!cancelled\(\)/u, 'explicit status guard must not inherit success()');
    assert.match(consumer.if, /steps\.local_cohort\.outcome/u);
    assert.equal(consumer['continue-on-error'], undefined);
    const condition = consumer.if.replace(/^\$\{\{\s*|\s*\}\}$/gu, '');
    const evaluate = Function('steps', 'cancelled', 'success', `return (${condition});`);
    for (const prepared of ['success', 'failure', 'skipped', 'cancelled']) {
      for (const sibling of ['success', 'failure', 'skipped', 'cancelled']) {
        for (const cancelled of [false, true]) {
          assert.equal(evaluate({local_cohort: {outcome: prepared}, sibling: {outcome: sibling}},
            () => cancelled, () => sibling === 'success'), prepared === 'success' && !cancelled);
        }
      }
    }
  }
  const mock = consumers[1];
  assert.equal(mock.env.TMPDIR, '${{ runner.temp }}/native-cli-linux-local/mock-consumers');
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
  const runner = readFileSync(new URL('./test-native-crypto-allocator.py', import.meta.url), 'utf8');
  assert(runner.includes("MODES = ('bounded-search', 'split-merge-membership', 'partial')"));
  for (const text of ['P.linux_member_inputs(prefix, selected)', "producer['source'] != source",
    "producer['inputs'].get(name) != expected", 'P.verify_original_inputs(inputs)',
    "selected[0].get('original_cleanup') is True", "len(report['cases']) == 3"])
    assert(runner.includes(text), text);
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
    'artifact/artifact.json', 'native-producer/build.json', 'release/release.json', 'release/source-free-install-*.json', 'release/source-free-observed-*.json',
    'release/mock-install-*.json', 'mock-consumers/actql-native-mock-install-*/commands.json']) {
    assert(retain.with.path.includes(path), path);
  }
  assert(!retain.with.path.includes('mock-consumers/**'), 'Do not upload private project state or keys');
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
  assert(installed.includes("new URL('./test-native-local-cli.test.mjs',import.meta.url)"));
  assert(installed.includes('expectedTests:12'));
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
