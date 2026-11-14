// The numeric port below is a protocol double, not compiled Core ABI proof.
// Core's same-Ledger reservation/retirement is covered by its focused tests.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {readFileSync} from 'node:fs';
import {parse as parseJavaScript} from 'acorn';
import {createAuthorizationGate} from '../host-common/authorization-gate.mjs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createAccountConstruction, isAccountConstruction, readAccountOriginal, readAccountCurrent} from './account-construction.mjs';
import {readAccountConfiguration, observeInstalledAccount, sourceReadAccountConfiguration, localAuthorizationContext, contentCid} from './local-account-config.mjs';

const ok = _0 => ({$tag: 1, _0});
const err = _0 => ({$tag: 0, _0});
function fixture(limit = 100000000000n) {
  const live = new Map(), events = [];
  let admits = 0, current = true, issued = 0;
  const moon = {
    clientProgramAccountReadControlBytes: () => 64n,
    clientProgramPrepareAccountReadConstruction(read, retained, execution) {
      events.push(['prepare', read, retained, execution]);
      if (!live.has(read) || !current) return err('Retired');
      let total = retained;
      for (const [other, amount] of live) if (other !== read) total += amount;
      if (total > limit || execution > limit) return err('RetentionLimit');
      live.set(read, retained); return ok(undefined);
    },
    clientProgramCloseAccountRead(read, ack) {
      events.push(['close', read, ack]);
      if (ack) live.delete(read);
      return ok(ack);
    },
    executionAuthorizationAdmitPrepared(wire, prepare) {
      if (!prepare(512n, 1024n)) return undefined;
      admits++; return Object.freeze({wire});
    },
    executionAuthorizationMissing: () => Object.freeze({missing: true}),
  };
  const facet = createAccountConstruction({moon, current() {
    if (!current) throw new Error('Retired');
  }, prepareRead() {
    if (!current) return err('Retired');
    const read = {issued: ++issued}; live.set(read, 64n); return ok(read);
  }});
  return {facet, moon, live, events, admits: () => admits, retire() {current = false;}};
}
async function files(fn) {
  const root = await mkdtemp(join(tmpdir(), 'actql-account-read-'));
  try {await fn(join(root, 'account.json'));} finally {await rm(root, {recursive: true});}
}

test('funded original and synchronous current read support exact Account beyond old million-byte ceiling', async () => files(async path => {
  const wire = sourceReadAccountConfiguration({connection: 'source', resource: 'records', entryId: 'x'.repeat(1000001)});
  await writeFile(path, wire);
  const f = fixture(), frame = f.facet.begin();
  const configuration = await readAccountConfiguration(path, frame);
  assert.equal(configuration.text, wire);
  frame.finish(false);
  assert.equal(f.facet.observe(read => readAccountCurrent(path, read)), wire);
  assert.equal(f.live.size, 0);
  assert.equal(await f.facet.close(), true);
}));

test('original refusal occurs before Buffer backing or UTF8 decode and failed prefix stays held until cleanup', async () => files(async path => {
  await writeFile(path, 'x'.repeat(256));
  const f = fixture(100n), frame = f.facet.begin();
  const allocate = Buffer.alloc;
  let allocations = 0;
  Buffer.alloc = (...args) => {allocations++; return allocate(...args);};
  try {await assert.rejects(readAccountOriginal(path, frame), {code: 'MoonBitHostFailure'});}
  finally {Buffer.alloc = allocate; frame.finish(false);}
  assert.equal(allocations, 0);
  assert.equal(f.live.size, 1);
  assert.equal(await f.facet.close(), true);
  assert.equal(f.live.size, 0);
}));

test('unchanged exact wire reuses immutable Account DATA, changed wire admits fresh on same original', async () => files(async path => {
  const f = fixture(), authorization = Object.freeze({accountConfig: path, accountConstruction: f.facet});
  await writeFile(path, '{"account_id":"a"}');
  const a = observeInstalledAccount(f.moon, authorization);
  assert.equal(observeInstalledAccount(f.moon, authorization), a);
  assert.equal(f.admits(), 1);
  await writeFile(path, '{"account_id":"b"}');
  const b = observeInstalledAccount(f.moon, authorization);
  assert.notEqual(b, a);
  assert.equal(f.admits(), 2);
  assert.equal(f.live.size, 2); // both retained children coexist until retirement
  assert.throws(() => f.facet.observe(frame => frame.admit({}, 'x')), /ForeignAccountConstructionRuntime/);
  f.retire();
  assert.throws(() => f.facet.begin(), /Retired/);
  assert.equal(await f.facet.close(), true);
  assert.equal(f.live.size, 0);
}));

test('unknown sync FD close is attempted once and never acknowledges parent retirement', async () => files(async path => {
  await writeFile(path, '{}');
  const f = fixture(), close = fs.closeSync;
  let attempts = 0;
  fs.closeSync = fd => {attempts++; close(fd); throw new Error('UnknownClose');};
  syncBuiltinESMExports();
  try {assert.throws(() => f.facet.observe(frame => readAccountCurrent(path, frame)), /UnknownClose/);}
  finally {fs.closeSync = close; syncBuiltinESMExports();}
  assert.equal(attempts, 1);
  assert.equal(await f.facet.close(), false);
  assert.equal(await f.facet.close(), false);
  assert.equal(attempts, 1);
  assert.equal(f.live.size, 1);
}));

// Execute the exact Local wrapper and its real async Node constructor, with
// only the compiled/numeric runtime load supplied as an explicit component
// port. The authorization Scope/decision cleanup is the original product JS.
// This neither loads a Common image nor qualifies compiled ABI/ordinary Host.
function originalFunctions(path, selected) {
  const source = readFileSync(new URL(path, import.meta.url), 'utf8');
  const parsed = parseJavaScript(source, {ecmaVersion: 'latest', sourceType: 'module'});
  const functions = parsed.body.map(node => node.type === 'ExportNamedDeclaration' ? node.declaration : node)
    .filter(node => node?.type === 'FunctionDeclaration' && selected.includes(node.id.name));
  assert.equal(functions.length, selected.length);
  return functions.map(node => source.slice(node.start, node.end)).join('\n');
}
const accountConstructorSource = originalFunctions('./local-account-config.mjs', [
  'createLocalAuthorizationGate', 'createLocalAuthorizationGateOriginal',
  'configurationOf', 'observeAccountConfigurationWire',
]);
const nodeConstructorSource = originalFunctions('./authorization.mjs', ['createNodeAuthorizationGate']);
const cid = 'sha256:' + '1'.repeat(64);
function scopeFixture(limit = 100000n, {onGate} = {}) {
  const f = fixture(limit), originalGates = [], closes = [], receivers = [];
  const fixedControl = f.live.keys().next().value;
  // The installed facet has its own first fixed-control Read. Count only
  // actual per-observation/gate debt; an old consumed first Read ceases to be
  // that fixed baseline as soon as it grows for metadata.
  const retainedReads = () => f.live.size - (f.live.get(fixedControl) === 64n ? 1 : 0);
  let peak = 0;
  const originalPrepare = f.moon.clientProgramPrepareAccountReadConstruction;
  f.moon.clientProgramPrepareAccountReadConstruction = (...args) => {
    peak = Math.max(peak, retainedReads());
    return originalPrepare(...args);
  };
  Object.assign(f.moon, {
    executionAuthorizationAdmit() {assert.fail('No unprepared Account admission');},
    executionAuthorizationAccountJson: account => JSON.stringify({state: 'admitted', account_id: 'fixture',
      configuration_cid: contentCid(JSON.parse(account.wire))}),
    executionAuthorizationEvaluate: () => ({outcome: 'delegate', entry_id: 'fixture-rule'}),
    executionAuthorizationEvaluationJson: JSON.stringify,
    executionAuthorizationEvaluationAction() {assert.fail('No unprepared dispatch');},
    executionAuthorizationPrepare(_evaluation, configuration, boundary, subject, context, authorities, claims) {
      return {ok: true, answering_authorities: authorities, required_claims: claims,
        subject: {account_id: 'fixture', configuration_cid: configuration, entry_id: 'fixture-rule',
          principal: 'fixture', connection: 'fixture', resource: 'rows', operation: 'read',
          boundary, subject_cid: subject, context_cid: context}};
    },
    executionAuthorizationRequestJson: JSON.stringify,
    executionAuthorizationAnswer: () => ({action: 'failure', reason: 'unavailable'}),
    executionAuthorizationDecisionJson: JSON.stringify,
  });
  const actualNodeConstructor = new Function('createAuthorizationGate', 'loadExecutionAuthorizationRuntime',
    nodeConstructorSource + '\nreturn createNodeAuthorizationGate;')(
    options => {
      const gate = createAuthorizationGate(options), index = originalGates.length;
      originalGates.push(gate);
      const observed = Object.freeze({...gate, close() {
        closes[index] = (closes[index] ?? 0) + 1;
        receivers[index] ??= this;
        assert.strictEqual(this, receivers[index], 'Keep the captured original receiver through retry');
        return Reflect.apply(gate.close, gate, []);
      }});
      onGate?.(gate);
      return observed;
    }, () => Promise.resolve(f.moon));
  const create = new Function('createNodeAuthorizationGate', 'isAccountConstruction', 'readAccountConfiguration',
    'localAuthorizationContext', 'contentCid', 'readAccountCurrent', 'openSync', 'fstatSync', 'readSync', 'closeSync',
    `const ACCOUNT_CONFIG_INVALID='ACTQL_E_ACCOUNT_CONFIG_INVALID'; const MAX_CONFIGURATION_BYTES=1000000;
     const fail=(code,cause)=>{throw Object.assign(new Error(code,{cause}),{code});};\n` +
      accountConstructorSource + '\nreturn createLocalAuthorizationGate;')(
    actualNodeConstructor, isAccountConstruction, readAccountConfiguration, localAuthorizationContext,
    contentCid, readAccountCurrent, fs.openSync, fs.fstatSync, fs.readSync, fs.closeSync);
  return {...f, originalGates, closes, receivers, retainedReads, peak: () => peak,
    create(options = {}) {return create({accountConstruction: f.facet, principal: 'fixture',
      accountConfiguration: '{"account_id":"fixture"}', ...options});}};
}

test('account gate repeated create and actual Scope close returns each SAME Read on one finite Host', async () => {
  const f = scopeFixture();
  for (let index = 0; index < 129; index++) {
    const gate = await f.create();
    assert.equal(f.retainedReads(), 1);
    assert.equal(gate.close(), true);
    assert.equal(gate.cleanupPending(), false);
    assert.equal(gate.close(), true);
    assert.equal(f.retainedReads(), 0, 'An already closed per-check gate must not retain its Account Read until Host close');
  }
  assert.equal(f.peak(), 1);
  assert.equal(f.admits(), 129);
  assert.equal(f.events.filter(event => event[0] === 'close').length, 129);
  assert.equal(await f.facet.close(), true);
  assert.deepEqual(f.closes, Array(129).fill(1), 'Host close retains no callback/capture for these retired gates');
});

test('account gate constructor-await close retains the already-created original before rejecting publication', async () => {
  let firstClose;
  const f = scopeFixture(100000n, {onGate() {firstClose = f.facet.close();}});
  await assert.rejects(f.create(), {code: 'AccountConstructionClosed'});
  assert.equal(await firstClose, false, 'The original active constructor is still owned');
  assert.equal(f.originalGates.length, 1);
  assert.equal(f.retainedReads(), 1);
  assert.equal(await f.facet.close(), true);
  assert.equal(f.closes[0], 1, 'Retire the original constructed Scope, even when the gate was never returned');
  assert.equal(f.live.size, 0);
});
