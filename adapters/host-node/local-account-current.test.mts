import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, writeFile, rm, rename} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {writeFileSync} from 'node:fs';
import {createLocalAuthorizationGate, observeInstalledAccount,
  readAccountConfiguration, sourceReadAccountConfiguration} from './local-account-config.mjs';

type BufferAllocTail = Parameters<typeof Buffer.alloc> extends [number, ...infer Tail] ? Tail : never;
type LocalGate = Awaited<ReturnType<typeof createLocalAuthorizationGate>>;

const tuple = {connection: 'connection', resource: 'resource', operation: 'read'};
const wire = sourceReadAccountConfiguration(tuple);
const subjectCid = `sha256:${'a'.repeat(64)}`;
type ObservedWire = Readonly<{text: string}>;
const fakeMoon = {
  executionAuthorizationAdmit: (text: string) => ({state: 'admitted', text}),
  executionAuthorizationMissing: () => ({state: 'missing'}),
};

test('reading Account configuration preserves original wire without issuing a Host CID', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-account-original-cid-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'account.json');
  const original = '{ "version": "actql-execution-account-config/0.1", "account_id": "operator", "entries": [] }';
  await writeFile(path, original);
  // This physical read supplies the original text and the Host context's
  // account name. Only the subsequent Common admission owns canonical identity.
  t.mock.method(String.prototype, 'normalize', () => {
    assert.fail('The physical Account reader must not canonicalize configuration');
  });
  const actual = await readAccountConfiguration(path);
  assert.deepEqual(actual, {path, text: original, accountId: 'operator'});
  assert.equal(Object.isFrozen(actual), true);
});

test('the account observer allocates only the opened file length and growth sentinel', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-account-buffer-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'account.json');
  await writeFile(path, wire);
  const requested: number[] = [];
  const original = Buffer.alloc;
  t.mock.method(Buffer, 'alloc', function(this: typeof Buffer, size: number, ...args: BufferAllocTail) {
    requested.push(size);
    return original.call(this, size, ...args);
  });
  assert.equal((observeInstalledAccount(fakeMoon, {accountConfig: path}) as ObservedWire).text, wire);
  assert.deepEqual(requested, [Buffer.byteLength(wire) + 1]);
});

test('the account observer refuses growth after sizing instead of admitting a prefix', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-account-growth-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'account.json');
  await writeFile(path, wire);
  let changed = false;
  const original = Buffer.alloc;
  t.mock.method(Buffer, 'alloc', function(this: typeof Buffer, size: number, ...args: BufferAllocTail) {
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
  assert.equal((observeInstalledAccount(fakeMoon, {accountConfig: path}) as ObservedWire).text.length, 1_000_000);
  assert.deepEqual(observeInstalledAccount(fakeMoon,
    {accountConfig: path, accountConfiguration: wire}), {state: 'missing'});
  await rm(path);
  assert.deepEqual(observeInstalledAccount(fakeMoon, {accountConfig: path}), {state: 'missing'});
  assert.equal((observeInstalledAccount(fakeMoon, {accountConfiguration: wire}) as ObservedWire).text, wire);
});

// These controls use the real Node loader and compiled authorization runtime.
// They must run through the repository's bounded local-checks wrapper.
test('file-backed gate observes replacement and deletion at the original path', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-account-current-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'account.json');
  await writeFile(path, wire);
  const gate = await createLocalAuthorizationGate({accountConfig: path});
  t.after((() => gate.close()) as () => void);
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
  t.after((() => gate.close()) as () => void);
  assert.equal(gate.accountConfiguration, wire);
  assert.deepEqual(gate.context, {principal: 'original-reader', contextCid: gate.contextCid});
  assert.equal(Object.isFrozen(gate.context), true);
  const projection = await createLocalAuthorizationGate({accountConfiguration: gate.accountConfiguration,
    context: gate.context});
  t.after((() => projection.close()) as () => void);
  assert.equal((await projection.authorize('acquisition', tuple, {subjectCid})).action, 'dispatch');
  const original = await gate.authorize('acquisition', tuple, {subjectCid});
  await writeFile(path, sourceReadAccountConfiguration({...tuple, outcome: 'deny'}));
  assert.throws(() => gate.assertAccountCurrent(original), {code: 'AuthorizationCurrentAccountChanged'});
});

test('installed gates preserve original context without synthesizing a missing Account', async () => {
  const context = Object.freeze({principal: 'original-reader', contextCid: subjectCid});
  const gate = await createLocalAuthorizationGate({accountConfiguration: wire, context});
  const missing = await createLocalAuthorizationGate({context});
  const defaultMissing = await createLocalAuthorizationGate({principal: 'default-reader'});
  try {
    assert.equal(gate.accountConfiguration, wire);
    assert.strictEqual(gate.context, context);
    assert.strictEqual(missing.context, context);
    assert.deepEqual(defaultMissing.context,
      {principal: 'default-reader', contextCid: defaultMissing.contextCid});
    assert.equal(Object.isFrozen(defaultMissing.context), true);
    for (const unconfigured of [missing, defaultMissing]) {
      assert.equal(unconfigured.accountConfiguration, undefined);
      assert.notEqual((await unconfigured.authorize('acquisition', tuple, {subjectCid})).action, 'dispatch');
    }
  } finally {gate.close(); missing.close(); defaultMissing.close();}
});

// Independent published Account corpus preimage, not a CID calculated by the
// Host writer or by this test's product runtime.
const corpusWire = '{"version":"actql-execution-account-config/0.1","account_id":"local:operator","entries":[{"entry_id":"files","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["local-files"]},"resource":{"all":true},"operation":{"all":true},"exclusions":[]}]}';
const corpusCid = 'sha256:e240525257340428cc9117b0b0e84a000996791f43b230abdb553e55223bec12';

test('installed Account uses the admitted Common identity for wire and original file', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-account-common-cid-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'account.json');
  await writeFile(path, corpusWire);
  for (const selection of [{accountConfiguration: corpusWire}, {accountConfig: path}]) {
    const gate = await createLocalAuthorizationGate({...selection, principal: 'operator'});
    try {
      assert.equal(gate.configurationCid, corpusCid);
      assert.equal(gate.accountConfiguration, corpusWire);
      const original = await gate.authorize('acquisition', {
        connection: 'local-files', resource: 'rows', operation: 'read',
      }, {subjectCid});
      assert.equal(original.action, 'dispatch');
      gate.assertAccountCurrent(original);
      if (selection.accountConfig) {
        await writeFile(path, corpusWire.replace('"allow"', '"deny"'));
        assert.throws(() => gate.assertAccountCurrent(original),
          {code: 'AuthorizationCurrentAccountChanged'});
      }
    } finally {gate.close();}
  }
});

test('installed Account retains an explicit expected-CID refusal instead of overwriting it', async () => {
  let gate: LocalGate | undefined;
  try {
    await assert.rejects(async () => {
      gate = await createLocalAuthorizationGate({accountConfiguration: corpusWire,
        principal: 'operator', configurationCid: subjectCid});
    }, {code: 'AuthorizationConfigurationCidMismatch'});
  } finally {gate?.close();}
});
