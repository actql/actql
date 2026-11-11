import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
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
