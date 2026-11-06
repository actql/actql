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
  assert(producer >= 0 && producer < pack && pack < install);
  const command = commands[producer];
  for (const selected of ['--source "$(git rev-parse HEAD)"', '--package-version 0.0.2-rc.0',
    '--clang "$(realpath /usr/bin/clang-19)"', '--sqlite-archive', '--component-seconds 300', '--compile-seconds 1800']) {
    assert(command.includes(selected), selected);
  }
  assert.equal(command.match(/--openssl-package-archive/gu).length, 2);
  assert(!command.includes('--system-header-root'), 'Normal Ubuntu headers need no implicit extra-root widening');
  assert(!commands.some(value => /\|\|\s*(?:true|node)|--ignore-scripts.*artifact/u.test(value)));
  for (const index of [producer, pack, install]) {
    const step = job.steps.find(value => value.run === commands[index]);
    assert.equal(step.if, undefined); assert.equal(step['continue-on-error'], undefined);
  }
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
    'artifact/artifact.json', 'native-producer/build.json', 'release/release.json', 'release/source-free-install-*.json', 'release/source-free-observed-*.json']) {
    assert(retain.with.path.includes(path), path);
  }
});


test('mandatory Local installation retains ingress controls on its actual installed runtime',()=>{
  const installed=readFileSync(new URL('./test-native-cli-source-free-install.mjs',import.meta.url),'utf8');
  const transport=readFileSync(new URL('./test-native-client.mjs',import.meta.url),'utf8');
  const fixture=readFileSync(new URL('./test-native-local-cli.test.mjs',import.meta.url),'utf8');
  assert(installed.includes("new URL('./test-native-local-cli.test.mjs',import.meta.url)"));
  assert(installed.includes('expectedTests:12'));
  assert(installed.includes('admitInstalledLocalRuntime({root:platformRoot,metadata:artifact.localRuntime'));
  for(const key of ['ACTQL_TEST_NATIVE_CLIENT_LAUNCHER','ACTQL_TEST_NATIVE_CLIENT_BINARY',
    'ACTQL_TEST_NATIVE_SQLITE_LIBRARY','ACTQL_TEST_NATIVE_CRYPTO_LIBRARY']) {
    assert(installed.includes(key),key);assert(fixture.includes(key),key);
  }
  assert(!transport.includes("import('./test-native-local-cli.test.mjs')"));
  assert(!fixture.includes('prepareNativeRuntimeBundleLibraries'));
  assert(installed.indexOf('if(runIngress)')>installed.indexOf('} catch (error) { failure = error; }'));
  assert(installed.includes("new AggregateError([failure,error],'Installed Local execution and ingress failed')"));
});
