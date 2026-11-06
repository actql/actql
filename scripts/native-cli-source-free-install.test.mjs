import assert from 'node:assert/strict';
import {test} from 'node:test';
import {finishSourceFreeObservations} from './test-native-cli-source-free-install.mjs';

test('source-free provisional observations require successful registry close', async () => {
  const events = [], receipt = {scope: 'synthetic-orchestration-only'};
  let release;
  const pending = new Promise(resolve => { release = resolve; });
  const completed = finishSourceFreeObservations(receipt, undefined, {
    close: async () => { events.push('closing'); await pending; events.push('closed'); },
    saveObserved: async value => {
      assert.deepEqual(events, ['closing', 'closed']);
      assert.deepEqual(value, {...receipt, status: 'observed', registryClosed: true});
      events.push('passed');
    },
    saveFailed: async () => assert.fail('No failure expected'),
  });
  await Promise.resolve();
  assert.deepEqual(events, ['closing']);
  release(); await completed;
  assert.deepEqual(events, ['closing', 'closed', 'passed']);
});

test('primary and cleanup failures remain distinguishable and never publish success', async () => {
  for (const [primary, cleanup] of [[true, false], [false, true], [true, true]]) {
    const original = new Error('original runtime failure'), close = new Error('registry close failure');
    const events = [];
    await assert.rejects(finishSourceFreeObservations({scope: 'synthetic-only'}, primary ? original : undefined, {
      close: async () => { events.push('close'); if (cleanup) throw close; },
      saveObserved: async () => assert.fail('Failure cannot publish a passing receipt'),
      saveFailed: async error => {
        assert.deepEqual(events, ['close']);
        if (primary && cleanup) assert.deepEqual(error.errors, [original, close]);
        else assert.equal(error, primary ? original : close);
        events.push('failed');
      },
    }), error => primary && cleanup ? error instanceof AggregateError
      && error.errors[0] === original && error.errors[1] === close : error === (primary ? original : close));
    assert.deepEqual(events, ['close', 'failed']);
  }
});

test('failure evidence write errors do not erase the runtime or cleanup failure', async () => {
  const original = new Error('runtime failure'), saving = new Error('evidence write failed');
  await assert.rejects(finishSourceFreeObservations(undefined, original, {
    close: async () => {},
    saveObserved: async () => assert.fail('Failure cannot publish success'),
    saveFailed: async () => { throw saving; },
  }), error => error instanceof AggregateError && error.errors[0] === original && error.errors[1] === saving);
});

test('missing observations and passing-receipt write failures are not success', async () => {
  let closed = false, saved = false;
  await assert.rejects(finishSourceFreeObservations(undefined, undefined, {
    close: async () => { closed = true; },
    saveObserved: async () => { saved = true; },
    saveFailed: async () => assert.fail('No primary failure supplied'),
  }), /Completed source-free observations required/u);
  assert(closed); assert.equal(saved, false);
  const saving = new Error('passing evidence could not be saved');
  await assert.rejects(finishSourceFreeObservations({}, undefined, {
    close: async () => {}, saveObserved: async () => { throw saving; },
    saveFailed: async () => assert.fail('A write error must propagate'),
  }), error => error === saving);
});

// Real process-exit ownership tests, not Native execution or package evidence.
import {mkdtemp, readFile, readdir, rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {runCleanupConditionedConsumer} from './test-native-cli-source-free-install.mjs';
import {openReleaseTestRegistry} from './release-test-registry.mjs';

async function ownedConsumer(t, mode) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-source-free-cleanup-test-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const observationPath = join(directory, 'observed.json'), receiptPath = join(directory, 'passed.json'),
    failurePath = join(directory, 'failed.json');
  const expected = {scope: 'synthetic-cleanup-orchestration-only', cliSourceSha: 'a'.repeat(40)};
  const source = `
import {createOwnedScratch} from ${JSON.stringify(new URL('./owned-scratch.mjs', import.meta.url).href)};
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
const mode = ${JSON.stringify(mode)};
const scratch = await createOwnedScratch({parent: ${JSON.stringify(directory)}, prefix: 'consumer-',
  label: 'real consumer cleanup probe',
  digests: () => mode === 'cleanup-failure' ? ['missing-original.tgz'] : []});
await writeFile(join(scratch.path, 'original'), 'actual retained file');
await writeFile(${JSON.stringify(observationPath)}, JSON.stringify({
  ...${JSON.stringify(expected)}, status: 'observed', registryClosed: true, consumer: scratch.path}));
if (mode === 'primary-failure') throw new Error('actual child failure');
if (mode === 'signal') process.kill(process.pid, 'SIGTERM');
if (mode !== 'unconfirmed') scratch.passed();
`;
  const run = () => runCleanupConditionedConsumer({command: process.execPath,
    args: ['--input-type=module', '-e', source], observationPath, receiptPath, failurePath, expected,
    env: {...process.env, ACTQL_TEST_PRESERVE_SCRATCH: mode === 'preserve' ? '1' : ''}, timeout: 10_000});
  return {directory, observationPath, receiptPath, failurePath, run};
}

test('only a real child exit zero with its owned scratch removed publishes final success', async t => {
  const fixture = await ownedConsumer(t, 'success');
  const receipt = await fixture.run();
  assert.equal(receipt.status, 'passed'); assert.equal(receipt.scratchRemoved, true);
  assert.equal(receipt.consumerProcess.code, 0); assert.equal(receipt.consumerProcess.signal, null);
  assert.match(receipt.consumerProcess.stdout, /removed .*consumer-/u);
  assert.equal(existsSync(receipt.consumer), false);
  assert.equal(existsSync(fixture.observationPath), false);
  assert.deepEqual(JSON.parse(await readFile(fixture.receiptPath)), receipt);
  assert.deepEqual(await readdir(fixture.directory), ['passed.json']);
});

for (const [mode, code] of [['cleanup-failure', 2], ['unconfirmed', 1], ['primary-failure', 1], ['preserve', 0], ['signal', null]]) {
  test(`real child ${mode} never publishes a passed receipt`, async t => {
    const fixture = await ownedConsumer(t, mode);
    await assert.rejects(fixture.run());
    assert.equal(existsSync(fixture.receiptPath), false);
    const failed = JSON.parse(await readFile(fixture.failurePath));
    assert.equal(failed.status, 'failed'); assert.equal(failed.child.code, code);
    assert.equal(existsSync(failed.consumer), true);
    assert.equal(existsSync(fixture.observationPath), true);
    if (mode === 'cleanup-failure') assert.match(failed.child.stderr, /test passed; cleanup failed:.*ENOENT/u);
    if (mode === 'preserve') assert.match(failed.error, /Consumer scratch remains/u);
    if (mode === 'signal') assert.equal(failed.child.signal, 'SIGTERM');
  });
}

test('real registry callback failure cannot produce even provisional observations', async () => {
  const registry = await openReleaseTestRegistry([]);
  await registry.close();
  let failure;
  await assert.rejects(finishSourceFreeObservations({scope: 'synthetic-orchestration-only'}, undefined, {
    close: () => registry.close(),
    saveObserved: async () => assert.fail('A failed close cannot produce observations'),
    saveFailed: async error => { failure = error; },
  }), {code: 'ERR_SERVER_NOT_RUNNING'});
  assert.equal(failure.code, 'ERR_SERVER_NOT_RUNNING');
});
