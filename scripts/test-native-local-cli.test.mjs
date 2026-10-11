// Native ingress only. This does not stand in for Source execution, durable
// Run recovery, encrypted capture, approval or external package acceptance.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {cp, mkdir, readFile, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {after, test} from 'node:test';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from './owned-scratch.mjs';

const executable = process.env.ACTQL_TEST_NATIVE_CLIENT_BINARY ?? fileURLToPath(new URL(
  '../_build/native/release/build/cmd/native_client/native_client.exe', import.meta.url));
const scratch = await createOwnedScratch({parent: tmpdir(), prefix: 'actql-native-local-cli-',
  label: 'Native Local CLI ingress'});
await cp(fileURLToPath(new URL('./fixtures/native-local-cli', import.meta.url)), scratch.path,
  {recursive: true});
const emptyPath = join(scratch.path, 'empty-path');
await mkdir(emptyPath);
console.log(`Native CLI binary sha256:${createHash('sha256').update(await readFile(executable)).digest('hex')}`);
after(() => scratch.passed());

function check(file, format = 'json', options = [], global = [], configuration = 'actql.config.json') {
  const args = ['--mode', 'local', '--config-root', scratch.path,
    '--config-file', configuration, ...global, 'check', '--program-file', file,
    '--format', format, '--json', ...options];
  return runNative(args);
}

function runNative(args) {
  const launcher = process.env.ACTQL_TEST_NATIVE_CLIENT_LAUNCHER;
  const result = spawnSync(launcher ? process.execPath : executable,
    launcher ? [launcher, ...args] : args,
    {cwd: scratch.path, env: {...process.env, PATH: emptyPath},
      encoding: 'utf8', timeout: 15_000});
  assert.ifError(result.error);
  assert.equal(result.signal, null);
  return result;
}

for (const [file, format] of [['values.json', 'json'], ['literal.sql', 'sql']]) {
  test(`Native Local prepares ${format} without credentials or a separate Host`, () => {
    const result = check(file, format);
    assert.equal(result.status, 0, result.stderr);
    const report = JSON.parse(result.stdout);
    assert.equal(report.kind, 'prepared');
    assert.equal(report.mode, 'local');
    assert.equal(report.effectful, false);
    assert.match(report.programDefinitionCid, /^sha256:[0-9a-f]{64}$/u);
    assert.match(report.parameterValuesCid, /^sha256:[0-9a-f]{64}$/u);
    assert.equal(Object.hasOwn(report, 'run'), false);
    assert.equal(Object.hasOwn(report, 'verified'), false);
  });
}

test('Native Local rejects wrong text form without a JSON fallback', () => {
  const result = check('values.json', 'aql-text');
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /LocalPreparationNotReady/u);
});

test('Native Local never switches to a Remote endpoint', () => {
  const result = check('values.json', 'json', [], ['--endpoint', 'https://127.0.0.1:1/']);
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /Local mode cannot use Remote connection options/u);
});

test('Native Remote refuses a Local cancellation Submission binding before transport setup', () => {
  for (const operation of ['lookup-cancellation', 'cancel']) {
    const options = operation === 'cancel' ? ['--operation-attempt-id', 'original-invocation'] : [];
    const result = runNative(['--mode', 'remote', operation, '--ref-file', 'absent-run.json',
      '--submission-ref-file', 'absent-submission.json', '--cancel-id', 'original', '--expected-revision', '0', ...options]);
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /Original Local submission binding is unavailable in Remote mode/u);
  }
});

test('Native Remote refuses Local original-delivery bindings before transport setup', () => {
  const common = ['--mode', 'remote', 'delivery-attempt', '--ref-file', 'absent-run.json',
    '--result-name', 'answer', '--attempt-id', 'original'];
  for (const [options, reason] of [
    [['--submission-ref-file', 'absent-submission.json'], /Original Local submission binding is unavailable in Remote mode/u],
    [['--purpose', 'cli-read'], /Explicit Local delivery purpose is unavailable in Remote mode/u],
  ]) {
    const result = runNative([...common, ...options]);
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, reason);
  }
});

test('Native Local retains parameter values and distinguishes wrong type', async () => {
  await writeFile(join(scratch.path, 'parameter.sql'), 'SELECT @message AS message\n');
  await writeFile(join(scratch.path, 'declarations.json'), JSON.stringify({message: {type: 'string'}}));
  const identities = [];
  for (const [index, value] of ['e\u0301', 'é', '\r', '\n', '\r\n'].entries()) {
    const name = `parameters-${index}.json`;
    await writeFile(join(scratch.path, name), JSON.stringify({message: value}));
    const result = check('parameter.sql', 'sql', ['--parameter-declarations-file', 'declarations.json',
      '--parameters-file', name]);
    assert.equal(result.status, 0, result.stderr);
    identities.push(JSON.parse(result.stdout).parameterValuesCid);
    assert.equal(result.stdout.includes('message'), false);
  }
  assert.equal(new Set(identities).size, 5, 'Different authored values cannot share parameter identity');
  await writeFile(join(scratch.path, 'wrong-type.json'), '{"message":null}');
  const wrong = check('parameter.sql', 'sql', ['--parameter-declarations-file', 'declarations.json',
    '--parameters-file', 'wrong-type.json']);
  assert.equal(wrong.status, 1);
  assert.equal(wrong.stdout, '');
});

test('Native Local validates environment custody instead of trusting a declared CID', async () => {
  const original = await readFile(join(scratch.path, 'actql.config.json'), 'utf8');
  const configuration = JSON.parse(original);
  configuration.native.check_environment.evidence_bundle_cid = `sha256:${'0'.repeat(64)}`;
  await writeFile(join(scratch.path, 'wrong-environment.json'), JSON.stringify(configuration));
  const result = check('values.json', 'json', [], [], 'wrong-environment.json');
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /InvalidLocalCheckEnvironment/u);
});

test('Native Local refuses duplicate configuration fields', async () => {
  await writeFile(join(scratch.path, 'duplicate.json'),
    '{"version":"actql-config/0.1","version":"actql-config/0.1","native":{}}');
  const result = check('values.json', 'json', [], [], 'duplicate.json');
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
});

test('Native Local human preparation output does not claim Run acceptance', () => {
  const result = runNative(['--mode', 'local', '--config-root', scratch.path,
    '--config-file', 'actql.config.json', 'check', '--program-file', 'values.json', '--format', 'json']);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /^Local Program prepared; no Run has been admitted\.\n/u);
  assert.match(result.stdout, /Effectful: false\n$/u);
  assert.equal(result.stdout.includes('"id"'), false);
});
