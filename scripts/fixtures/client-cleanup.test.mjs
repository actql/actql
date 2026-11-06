import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {userInfo} from 'node:os';
import {parse} from 'acorn';
import {readFile} from 'node:fs/promises';
import {closeFixtureClient, withFixtureClientCleanup} from './client-cleanup.mjs';

const pending = () => Object.assign(new Error('ClientCleanupPending'),
  {code:'ClientCleanupPending', cleanupPending:true});

test('fixture closes only the same Client until its original cleanup fulfills', async () => {
  const calls = [], client = {async close() {
    assert.equal(this, client); calls.push(this);
    if (calls.length < 3) throw pending();
  }};
  await closeFixtureClient(client);
  assert.equal(calls.length, 3);
  assert(calls.every(value => value === client));
});

test('fixture cleanup does not turn another error into retry permission', async () => {
  for (const error of [new Error('PhysicalCloseUnknown'),
    {code:'ClientCleanupPending', cleanupPending:false},
    {code:'OtherCleanupPending', cleanupPending:true}, undefined]) {
    let attempts = 0;
    await assert.rejects(closeFixtureClient({async close() {attempts++; throw error;}}),
      observed => observed === error);
    assert.equal(attempts, 1);
  }
});

test('fixture deadline preserves the exact outstanding cleanup error and same owner', async () => {
  const abort = new AbortController(), original = pending();
  let attempts = 0;
  const client = {async close() {attempts++; abort.abort(); throw original;}};
  await assert.rejects(closeFixtureClient(client, {signal:abort.signal}), error => error === original);
  assert.equal(attempts, 1);
});

test('fixture cancellation during retry delay does not start another cleanup attempt', async () => {
  const abort = new AbortController(), original = pending();
  let attempts = 0;
  const result = closeFixtureClient({async close() {
    attempts++; setImmediate(() => abort.abort()); throw original;
  }}, {signal:abort.signal});
  await assert.rejects(result, error => error === original);
  assert.equal(attempts, 1);
});

test('fixture does not acknowledge cleanup while its same original close is unsettled', async () => {
  let settle, completed = false, attempts = 0;
  const original = new Promise(resolve => {settle = resolve;});
  const result = closeFixtureClient({close() {attempts++; return original;}})
    .then(() => {completed = true;});
  await Promise.resolve();
  assert.equal(completed, false); assert.equal(attempts, 1);
  settle(); await result; assert.equal(completed, true);
});

test('fixture returns the original operation result only after cleanup', async () => {
  const expected = Object.freeze({original:true}), events = [];
  const result = await withFixtureClientCleanup({async close() {events.push('closed');}},
    async () => {events.push('operation'); return expected;});
  assert.equal(result, expected); assert.deepEqual(events, ['operation','closed']);
});

test('fixture preserves an original primary failure after confirmed cleanup', async () => {
  const primary = Object.freeze(new Error('OriginalFailure'));
  let closed = 0;
  await assert.rejects(withFixtureClientCleanup({async close() {closed++;}},
    async () => {throw primary;}), error => error === primary);
  assert.equal(closed, 1);
});

test('fixture retains both primary and cleanup failure without masking either', async () => {
  const primary = Object.freeze(new Error('OriginalFailure')), cleanup = new Error('CleanupUnknown');
  await assert.rejects(withFixtureClientCleanup({async close() {throw cleanup;}},
    async () => {throw primary;}), error => {
    assert(error instanceof AggregateError);
    assert.equal(error.cause, primary);
    assert.deepEqual(error.errors, [primary, cleanup]);
    return true;
  });
});

test('fixture retains a raw undefined primary beside outstanding cleanup', async () => {
  const cleanup = new Error('CleanupUnknown');
  await assert.rejects(withFixtureClientCleanup({async close() {throw cleanup;}},
    async () => {throw undefined;}), error => {
    assert(error instanceof AggregateError); assert.deepEqual(error.errors, [undefined, cleanup]);
    return true;
  });
});

test('both normal external staging paths include every relative short-query helper', async () => {
  const consumer = await readFile(new URL('./packed-short-queries.mjs', import.meta.url), 'utf8');
  const names = [...consumer.matchAll(/from '\.\/([^']+\.mjs)'/gu)].map(match => match[1]);
  assert(names.includes('client-cleanup.mjs'));
  assert(names.includes('run-revision-assertions.mjs'));
  for (const path of ['test-package-release-install.mjs','test-packed-local-without-duckdb.mjs']) {
    const source = await readFile(new URL('../' + path, import.meta.url), 'utf8');
    for (const name of names) {
      assert(source.includes(`copyFile(join(repository, 'scripts/fixtures/${name}'),`),
        `${path} must stage ${name}`);
    }
  }
});


test('short-query fixture keeps Host reads separate from its selected write and delegation outcome', async () => {
  const source = await readFile(new URL('./packed-short-queries.mjs', import.meta.url), 'utf8');
  const declaration = parse(source, {sourceType: 'module', ecmaVersion: 'latest'}).body
    .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'authorization');
  assert.ok(declaration);
  const factory = new Function('generateKeyPairSync', 'userInfo', 'createComputedBarrier',
    'return (' + source.slice(declaration.start, declaration.end) + ');')(
    generateKeyPairSync, userInfo, () => {throw Error('No Compute is needed to select permissions');});
  for (const selected of ['allow', 'delegate']) {
    const value = factory(selected), account = JSON.parse(value.value.accountConfiguration);
    assert.equal(value.count(), 0);
    assert.deepEqual(account.entries.map(entry => entry.entry_id), ['owner-read', 'write']);
    const [read, write] = account.entries;
    assert.deepEqual(read, {entry_id: 'owner-read', outcome: 'allow',
      principal: {any_of: [userInfo().username]}, connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['result/answer', 'result/main', 'result/named', 'run']}, operation: {any_of: ['read']}, exclusions: []});
    assert.equal(write.outcome, selected); assert.deepEqual(write.operation, {any_of: ['write']});
  }
});
