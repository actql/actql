import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, writeFile, rm, rename} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {writeFileSync} from 'node:fs';
import {createLocalAuthorizationGate, observeInstalledAccount,
  sourceReadAccountConfiguration} from './local-account-config.mjs';

const tuple = {connection: 'connection', resource: 'resource', operation: 'read'};
const wire = sourceReadAccountConfiguration(tuple);
const subjectCid = `sha256:${'a'.repeat(64)}`;
const fakeMoon = {
  executionAuthorizationAdmit: text => ({state: 'admitted', text}),
  executionAuthorizationMissing: () => ({state: 'missing'}),
};

test('the account observer allocates only the opened file length and growth sentinel', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-account-buffer-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'account.json');
  await writeFile(path, wire);
  const requested = [];
  const original = Buffer.alloc;
  t.mock.method(Buffer, 'alloc', function(size, ...args) {
    requested.push(size);
    return original.call(this, size, ...args);
  });
  assert.equal(observeInstalledAccount(fakeMoon, {accountConfig: path}).text, wire);
  assert.deepEqual(requested, [Buffer.byteLength(wire) + 1]);
});

test('the account observer refuses growth after sizing instead of admitting a prefix', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-account-growth-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'account.json');
  await writeFile(path, wire);
  let changed = false;
  const original = Buffer.alloc;
  t.mock.method(Buffer, 'alloc', function(size, ...args) {
    if (!changed) {
      changed = true;
      writeFileSync(path, wire + ' '.repeat(64));
    }
    return original.call(this, size, ...args);
  });
  assert.deepEqual(observeInstalledAccount(fakeMoon, {accountConfig: path}), {state: 'missing'});
  assert.equal(changed, true);
});

test('the shared account observer keeps its fixed byte and fatal UTF-8 bounds', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-account-observation-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'account.json');
  for (const bytes of [Buffer.alloc(1_000_001, 32), Buffer.from([0xc3, 0x28])]) {
    await writeFile(path, bytes);
    assert.deepEqual(observeInstalledAccount(fakeMoon, {accountConfig: path}), {state: 'missing'});
  }
  await writeFile(path, Buffer.alloc(1_000_000, 32));
  assert.equal(observeInstalledAccount(fakeMoon, {accountConfig: path}).text.length, 1_000_000);
  assert.deepEqual(observeInstalledAccount(fakeMoon,
    {accountConfig: path, accountConfiguration: wire}), {state: 'missing'});
  await rm(path);
  assert.deepEqual(observeInstalledAccount(fakeMoon, {accountConfig: path}), {state: 'missing'});
  assert.equal(observeInstalledAccount(fakeMoon, {accountConfiguration: wire}).text, wire);
});

// These controls use the real Node loader and compiled authorization runtime.
// They must run through the repository's bounded local-checks wrapper.
test('file-backed gate observes replacement and deletion at the original path', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-account-current-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'account.json');
  await writeFile(path, wire);
  const gate = await createLocalAuthorizationGate({accountConfig: path});
  t.after(() => gate.close());
  const original = await gate.authorize('acquisition', tuple, {subjectCid});
  gate.assertAccountCurrent(original);
  const replacement = join(root, 'replacement.json');
  await writeFile(replacement, sourceReadAccountConfiguration({...tuple, outcome: 'deny'}));
  await rename(replacement, path);
  assert.throws(() => gate.assertAccountCurrent(original),
    {code: 'AuthorizationCurrentAccountChanged'});
  await assert.rejects(gate.authorize('acquisition', tuple, {subjectCid}),
    {code: 'AuthorizationCurrentAccountChanged'});
  await rm(path);
  assert.throws(() => gate.assertAccountCurrent(original),
    {code: 'AuthorizationCurrentAccountUnavailable'});
});

test('wire-backed gate keeps its installed configuration current until its scope closes', async () => {
  const input = {accountConfiguration: wire};
  const gate = await createLocalAuthorizationGate(input);
  const original = await gate.authorize('acquisition', tuple, {subjectCid});
  input.accountConfiguration = sourceReadAccountConfiguration({...tuple, outcome: 'deny'});
  gate.assertAccountCurrent(original);
  gate.close();
  assert.throws(() => gate.assertAccountCurrent(original),
    {code: 'AuthorizationDecisionScopeClosed'});
});

test('installed file-backed gate retains the exact Account wire and context for its Source projection', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-account-source-original-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'account.json');
  await writeFile(path, wire);
  const gate = await createLocalAuthorizationGate({accountConfig: path, principal: 'original-reader'});
  t.after(() => gate.close());
  assert.equal(gate.accountConfiguration, wire);
  assert.deepEqual(gate.context, {principal: 'original-reader', contextCid: gate.contextCid});
  assert.equal(Object.isFrozen(gate.context), true);
  const projection = await createLocalAuthorizationGate({accountConfiguration: gate.accountConfiguration,
    context: gate.context});
  t.after(() => projection.close());
  assert.equal((await projection.authorize('acquisition', tuple, {subjectCid})).action, 'dispatch');
  const original = await gate.authorize('acquisition', tuple, {subjectCid});
  await writeFile(path, sourceReadAccountConfiguration({...tuple, outcome: 'deny'}));
  assert.throws(() => gate.assertAccountCurrent(original), {code: 'AuthorizationCurrentAccountChanged'});
});

test('installed wire-backed gate preserves original context and cannot synthesize a missing Account', async () => {
  const context = Object.freeze({principal: 'original-reader', contextCid: subjectCid});
  const gate = await createLocalAuthorizationGate({accountConfiguration: wire, context});
  const missing = await createLocalAuthorizationGate({context});
  try {
    assert.equal(gate.accountConfiguration, wire);
    assert.strictEqual(gate.context, context);
    assert.equal(missing.accountConfiguration, undefined);
    assert.notEqual((await missing.authorize('acquisition', tuple, {subjectCid})).action, 'dispatch');
  } finally {gate.close(); missing.close();}
});
