import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {startInstalledRowRun} from './installed-row-run.mjs';

const ok = value => ({$tag: 1, _0: value});

const rowSource = readFileSync(new URL('./installed-row-source.mjs', import.meta.url), 'utf8');
const rowSourceProgram = parse(rowSource, {ecmaVersion: 'latest', sourceType: 'module'});
const rowSourceConstructor = rowSourceProgram.body.map(node => node.declaration ?? node)
  .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'createInstalledRowSource');
assert(rowSourceConstructor);
const prepareDeclaration = rowSourceConstructor.body.body.find(node =>
  node.type === 'FunctionDeclaration' && node.id.name === 'prepare');
const describePreparedSourceDeclaration = rowSourceConstructor.body.body.find(node =>
  node.type === 'FunctionDeclaration' && node.id.name === 'describePreparedSource');
const sourceBodyDeclaration = rowSourceConstructor.body.body.find(node =>
  node.type === 'VariableDeclaration' && node.declarations.some(value => value.id.name === 'sourceBody'));
const sourceBody = sourceBodyDeclaration?.declarations.find(value => value.id.name === 'sourceBody').init;
const closeMethod = sourceBody?.properties.find(value => value.type === 'Property' && value.key.name === 'close');
assert(prepareDeclaration && describePreparedSourceDeclaration &&
  sourceBody?.type === 'ObjectExpression' && closeMethod?.method);

test('whole input consumes the same Run/reader/evidence originals without Query or output transfer', async () => {
  const acquisition = {}, originalRead = {}, ledger = {}, provider = {}, capacity = {};
  const run = {}, attempt = {}, borrow = {}, capture = {}, source = {}, identity = {}, logical = {}, evidence = {};
  const checkedOwner = {}, dag = {}, calls = [];
  let settled, observeStop, stopped = false, retired = false;
  const moon = {
    clientProgramInstalledSourceReadCheckLedger(read, actual) {
      assert.equal(read, originalRead); assert.equal(actual, ledger); return ok();
    },
    clientProgramInstalledWholeSourceReadStartRows(read, actual, nonce, verify, transfer, scratch) {
      assert.equal(read, originalRead); assert.equal(actual, acquisition); assert.equal(nonce, 'original');
      assert.equal(transfer, 1024n); assert.equal(scratch, 512n); settled = verify;
      assert.equal(verify(attempt), false); calls.push('start'); return ok(run);
    },
    clientProgramWholeSourceBorrowResponses(actual, selected) {
      assert.equal(actual, run); assert.equal(selected, acquisition); calls.push('borrow'); return ok(borrow);
    },
    clientProgramRowSourceBindResponseCleanup(actual, observe) {
      assert.equal(actual, borrow); observeStop = observe; return ok();
    },
    clientProgramRowSourceFinish(actual) {assert.equal(actual, run); assert.equal(settled(attempt), false); return ok();},
    clientProgramRowSourceAttempt: () => attempt,
    clientProgramRowSourceCaptureBegin() {assert.equal(settled(attempt), true); return ok();},
    clientProgramRowSourceCaptureAdvance: () => ok({_0: true, _1: 1n}),
    clientProgramRowSourceCapture: () => ok(capture),
    clientProgramRowSourceCaptureSource(actual) {assert.equal(actual, capture); return ok(source);},
    clientProgramCapturedTaskSourceMatches(prepared, actual, task) {
      assert.equal(prepared, checkedOwner); assert.equal(actual, source); assert.equal(task, 0); return true;
    },
    clientProgramIdentifyCapturedSourceRelation: () => ok(identity),
    clientProgramIssueWholeSourceInputLogical(prepared, actual, measured, selected) {
      assert.equal(prepared, checkedOwner); assert.equal(actual, source);
      assert.equal(measured, identity); assert.equal(selected, capacity); calls.push('logical'); return ok(logical);
    },
    clientProgramWholeSourceCheckComputeBinding(actual, owner, task) {
      assert.equal(actual, capture); assert.equal(owner, dag); assert.equal(task, 0); calls.push('binding'); return ok();
    },
    clientProgramWholeSourceIssueSourceEvidenceOriginal(selected, actual, measured, input, scope, policy) {
      assert.equal(selected, acquisition); assert.equal(actual, capture); assert.equal(measured, identity);
      assert.equal(input, logical); assert.equal(scope, 'scope'); assert.equal(policy, 'policy');
      calls.push('evidence'); return ok(evidence);
    },
    clientProgramRowSourceCloseAccounted() {
      if (!observeStop()) return {$tag: 0, _0: 'physical-stop-pending'};
      calls.push('close'); return ok();
    },
    clientProgramRowSourceCaptureCleanup: () => ok(true),
    clientProgramRowSourceCaptureCleanupAdvance: () => ok(true),
    clientProgramInstalledSourceReadRetire(read) {assert.equal(read, originalRead); retired = true; return ok();},
  };
  const reader = {
    async read() {assert.equal(this, reader); calls.push('read');},
    requestStop() {assert.equal(this, reader); calls.push('stop');},
    retry() {assert.equal(this, reader); calls.push('retry');},
    observe() {assert.equal(this, reader); return {cleanupConfirmed: stopped};},
  };
  const receiver = {prepare(options) {assert.equal(this, receiver); assert.equal(options, input); return reader;}};
  const currentRead = async () => {calls.push('current');};
  const input = {verifyRead: currentRead};
  const session = startInstalledRowRun({moon, acquisition, originalRead, ledger, wholeInput: true,
    nonce: 'original', capacity: {provider, transferBytes: 1024n, executionBytes: 512n}});
  await session.readProvider({receiver, prepare: receiver.prepare, options: input});
  const result = await session.complete({owner: {checkedOwner, wholeInput: true,
    providerCaptureCapacity: capacity, occurrence: {stage: 0, input: 0, task: 0}},
  prepared: {checkedSource: {}}, currentRead});
  assert.equal(result.logicalInput, logical);
  assert.equal(Object.hasOwn(result, 'requirement'), false);
  assert.equal(result.capture.originalWholeInput(), capture);
  const copied = {...result.capture};
  assert.throws(() => copied.originalWholeInput(), {code: 'ForeignInstalledSourceCapture'});
  result.capture.retainTask(dag, 0);
  await result.prepareSourceEvidenceOriginal({authorityScopeCid: 'scope', effectiveDataPolicyCid: 'policy'});
  assert.equal(result.capture.takeSourceEvidenceOriginal(), evidence);
  assert.throws(() => session.close(), error => error.cause === 'physical-stop-pending');
  assert.equal(retired, false);
  stopped = true;
  assert.equal(await session.cleanup(), true);
  assert.equal(retired, true);
  assert.throws(() => result.capture.originalWholeInput(), {code: 'ForeignInstalledSourceCapture'});
  assert.equal(calls.filter(value => value === 'start').length, 1);
  assert.equal(calls.filter(value => value === 'read').length, 1);
  assert.equal(calls.filter(value => value === 'logical').length, 1);
  assert.equal(calls.filter(value => value === 'evidence').length, 1);
});

test('whole input cannot select a bare, keyed or listing RowRun', () => {
  const base = {moon: {}, acquisition: {}, nonce: 'original', wholeInput: true, ledger: {},
    originalRead: {}, capacity: {provider: {}, transferBytes: 1n, executionBytes: 1n}};
  for (const patch of [{originalRead: undefined}, {ledger: undefined}, {keyed: true},
    {capacity: {provider: {}, listingReport: {}}}]) {
    assert.throws(() => startInstalledRowRun({...base, ...patch}), {code: 'InstalledWholeSourceReadUnavailable'});
  }
});

async function failedPreparationFixture({pendingRetirement = false, validFacts = false, identity, authorization, effectful = false} = {}) {
  const {types} = await import('node:util');
  const {runtimeField, runtimeIsOk, runtimeIsBoxedSome} = await import('../host-common/compiler-binding.generated.mjs');
  const {checked} = await import('../host-common/runtime-result.mjs');
  // Capture this constructor's actual prepare and public close methods. A
  // later Credential/Site close in the same module is a different owner.
  const source = rowSource;
  const start = prepareDeclaration.start, end = prepareDeclaration.end;
  const closeStart = closeMethod.start, closeEnd = closeMethod.end;
  const read = {}, managedRun = {}, preparedProgram = {}, declaration = {};
  let retireCalls = 0, siteCloses = 0;
  const moon = {
    clientProgramEffectDirectSourceCoordinates(actual) {
      assert.equal(actual, preparedProgram);return ok([[0, 0, 0, 0], [0, 1, 1, 0]]);
    },
    clientProgramInstalledEffectManagedRunCheck(actual, owner) {
      assert.equal(actual, managedRun);assert.equal(owner, preparedProgram);return ok();
    },
    clientProgramInstalledEffectManagedSourceInputKind(actual, owner, request, slot) {
      assert.equal(actual, managedRun);assert.equal(owner, preparedProgram);assert.equal(slot, 1);return ok('whole-input');
    },
    clientProgramInstalledEffectManagedSourceRead() {assert.fail('whole Effect input cannot borrow a Query acquisition');},
    clientProgramInstalledEffectManagedWholeSourceRead(actual, owner, request, declared, slot) {
      assert.equal(actual, managedRun);assert.equal(owner, preparedProgram);assert.equal(declared, declaration);assert.equal(slot, 1);
      return ok({_0: read, _1: {}, _2: {}, _3: {}});
    },
    clientProgramInstalledManagedSourceInputKind(actual, owner) {
      assert.equal(actual, managedRun); assert.equal(owner, preparedProgram); return ok('whole-input');
    },
    clientProgramInstalledManagedCaptureSourceRead() {assert.fail('whole Source must retain its own acquisition');},
    clientProgramInstalledManagedWholeSourceRead(actual, owner, request, declared) {
      assert.equal(actual, managedRun); assert.equal(owner, preparedProgram); assert.equal(declared, declaration);
      return ok({_0: read, _1: {}, _2: {}, _3: {}});
    },
    // This deliberately malformed DATA observation fails AFTER the same
    // original read has been opened, before any provider/RowRun/send exists.
    clientProgramWholeSourceFacts: () => validFacts ? ['source', 'contract', 'carrier', 'policy', 'class', 'view'] : [],
    clientProgramWholeSourceTarget: () => ['resource', 'field'],
    clientProgramWholeSourceInputIdentity: () => identity,
    clientProgramEffectWholeSourceInputIdentity: () => identity,
    clientProgramInstalledSourceReadBindProgram(actual, owner) {
      assert.equal(actual, read); assert.equal(owner, preparedProgram); return ok();
    },
    clientProgramInstalledSourceReadRetire(actual) {
      assert.equal(actual, read); retireCalls++;
      if (pendingRetirement) return {$tag: 0, _0: 'original-read-still-pending'};
      return ok();
    },
  };
  const bindings = {moon, declaration, runtimeField, runtimeIsOk, runtimeIsBoxedSome, checked,
    fail(code) {throw Object.assign(new Error(code), {code});},
    sourceAccess: {}, directReadIdentity: undefined, originalReader: {retire: () => true, receiver: {}},
    immutableTargets: undefined, physicalTargetGeneration: undefined,
    prepareSourceRead: undefined, sourceInitialization: undefined,
    site: {close() {siteCloses++;}}, nodeTypes: types,
    preparingSourceReads: new Set(), sourceRefs: new Set(['source']), preparations: new WeakMap(),
    cidPattern: /^sha256:[0-9a-f]{64}$/u,
    physicalTarget: (resource, fields) => ({resource, fields}), valueCid: value => JSON.stringify(value),
    decideRead: async () => authorization === undefined ? {action: 'dispatch'} : await authorization, ordinaryRecoveryBinding() {}};
  const fixture = new Function(...Object.keys(bindings),
    source.slice(describePreparedSourceDeclaration.start, describePreparedSourceDeclaration.end) + '\n' +
    source.slice(start, end) +
    '\nreturn {prepare,' + source.slice(closeStart, closeEnd) + '};')(...Object.values(bindings));
  return {fixture, originalRead: read, pendingReads: bindings.preparingSourceReads, input: effectful
    ? {preparedEffect: preparedProgram, managedRun, occurrence: {stage: 0, input: 1, task: 1, computeTask: 0}}
    : {preparedProgram, managedRun},
    retireCalls: () => retireCalls, siteCloses: () => siteCloses,
    allowRetirement() {pendingRetirement = false;}, retireOriginal() {checked(moon.clientProgramInstalledSourceReadRetire(read));}};
}

test('whole Effect preparation retains its second Source read on the first Compute task before a fallible observation', async () => {
  const f = await failedPreparationFixture({effectful: true, pendingRetirement: true});
  await assert.rejects(f.fixture.prepare(f.input), {code: 'InstalledSourceEvidenceFactsUnavailable'});
  assert.equal(f.retireCalls(), 1);
  assert(f.pendingReads.has(f.originalRead));
  assert.throws(() => f.fixture.close(), error => error.cause === 'original-read-still-pending');
  f.allowRetirement();
  f.fixture.close();
  assert(!f.pendingReads.has(f.originalRead));
});

test('whole Effect preparation refuses a substituted Compute task before retaining a read', async () => {
  const f = await failedPreparationFixture({effectful: true});
  await assert.rejects(f.fixture.prepare({...f.input, occurrence: {...f.input.occurrence, computeTask: 1}}),
    {code: 'InstalledSourcePreparationMismatch'});
  assert.equal(f.retireCalls(), 0);
  assert.equal(f.pendingReads.size, 0);
});

test('whole Source failed preparation retires the same unopened read before parent cleanup', async () => {
  const f = await failedPreparationFixture();
  await assert.rejects(f.fixture.prepare(f.input), {code: 'InstalledSourceEvidenceFactsUnavailable'});
  assert.equal(f.retireCalls(), 1);
  f.fixture.close();
  assert.equal(f.retireCalls(), 1);
  assert.equal(f.siteCloses(), 1);
});

test('whole Source failed read retirement remains with the same Source close retry', async () => {
  const f = await failedPreparationFixture({pendingRetirement: true});
  await assert.rejects(f.fixture.prepare(f.input), {code: 'InstalledSourceEvidenceFactsUnavailable'});
  assert.equal(f.retireCalls(), 1);
  assert.throws(() => f.fixture.close(), error => error.cause === 'original-read-still-pending');
  assert.equal(f.siteCloses(), 0);
  f.allowRetirement();
  f.fixture.close();
  assert.equal(f.retireCalls(), 3);
  assert.equal(f.siteCloses(), 1);
});


test('whole Source identity keeps boxed payload and refuses None or malformed original CID pairs', async () => {
  const pair = ['sha256:' + 'a'.repeat(64), 'sha256:' + 'b'.repeat(64)];
  const some = value => Object.assign(Object.create({$tag: 1}), {_0: value});
  const f = await failedPreparationFixture({validFacts: true, identity: some(pair)});
  const prepared = await f.fixture.prepare(f.input);
  assert.deepEqual(prepared.checkedSource.sourceInput, pair);
  assert(Object.isFrozen(prepared.checkedSource.sourceInput));
  f.retireOriginal();
  f.fixture.close();
  for (const identity of [{$tag: 0}, pair, some([pair[0]]), some([pair[0], 'foreign'])]) {
    const refused = await failedPreparationFixture({validFacts: true, identity});
    await assert.rejects(refused.fixture.prepare(refused.input), {code: 'InstalledSourceProgramMismatch'});
    assert.equal(refused.retireCalls(), 1);
    refused.fixture.close();
  }
});


test('whole Source close cannot return a constructor read retired during authorization await', async () => {
  let resume;
  const authorization = new Promise(resolve => {resume = resolve;});
  const pair = ['sha256:' + 'a'.repeat(64), 'sha256:' + 'b'.repeat(64)];
  const f = await failedPreparationFixture({validFacts: true, identity: {$tag: 1, _0: pair}, authorization});
  const preparing = f.fixture.prepare(f.input);
  f.fixture.close();
  assert.equal(f.retireCalls(), 1);
  resume({action: 'dispatch'});
  await assert.rejects(preparing, {code: 'InstalledSourceReadUnavailable'});
});


test('whole Source keeps its unstarted read when the actual managed wrapper rejects after prepare', async () => {
  const {bindInstalledManagedSources} = await import('./installed-managed-source.mjs');
  const pair = ['sha256:' + 'a'.repeat(64), 'sha256:' + 'b'.repeat(64)];
  const f = await failedPreparationFixture({validFacts: true, identity: {$tag: 1, _0: pair}});
  const parent = f.input.managedRun, currentLoss = new Error('OriginalParentNoLongerCurrent');
  const source = {prepare: f.fixture.prepare, close: f.fixture.close,
    managedCaptureCapacity() {}, ledgerCapacity() {assert.fail('No association after lost current');}};
  let observations = 0;
  const view = bindInstalledManagedSources(source, checked => {
    assert.equal(checked, f.input.preparedProgram);
    if (++observations === 2) throw currentLoss;
    return parent;
  });
  await assert.rejects(view.prepare({preparedProgram: f.input.preparedProgram}), error => error === currentLoss);
  assert.throws(() => view.ledgerCapacity({}), /ForeignInstalledManagedSource/);
  view.close();
  assert.equal(f.retireCalls(), 1);
  assert.equal(f.siteCloses(), 1);
});

test('whole Source closes an original prepared read which was never given to a RowRun', async () => {
  const pair = ['sha256:' + 'a'.repeat(64), 'sha256:' + 'b'.repeat(64)];
  const f = await failedPreparationFixture({validFacts: true, identity: {$tag: 1, _0: pair}});
  const prepared = await f.fixture.prepare(f.input);
  assert.deepEqual(prepared.checkedSource.sourceInput, pair);
  assert.equal(f.retireCalls(), 0);
  f.fixture.close();
  assert.equal(f.retireCalls(), 1);
  assert.equal(f.siteCloses(), 1);
});


test('whole Source transfers its original reference only after the RowRun constructor returns', async () => {
  const source = rowSource;
  const begin = source.indexOf('    const session = startInstalledRowRun({moon, acquisition, nonce, ledger, capacity,');
  const end = source.indexOf('    let externalClosed', begin);
  assert(begin > 0 && end > begin);
  const handoff = new Function('startInstalledRowRun', 'owner', 'preparingSourceReads',
    'const moon={},acquisition={},nonce="original",ledger={},capacity={};' +
    source.slice(begin, end) + 'return session;');
  const pair = ['sha256:' + 'a'.repeat(64), 'sha256:' + 'b'.repeat(64)];
  for (const fails of [true, false]) {
    const f = await failedPreparationFixture({validFacts: true, identity: {$tag: 1, _0: pair}});
    await f.fixture.prepare(f.input);
    assert(f.pendingReads.has(f.originalRead));
    const originalFailure = new Error('OriginalRowConstructorFailure');
    const session = {run: {}, close: () => f.retireOriginal()};
    const start = options => {
      assert.equal(options.originalRead, f.originalRead);
      assert(f.pendingReads.has(f.originalRead));
      if (fails) throw originalFailure;
      return session;
    };
    const enter = () => handoff(start, {originalRead: f.originalRead, wholeInput: true}, f.pendingReads);
    if (fails) {
      assert.throws(enter, error => error === originalFailure);
      assert(f.pendingReads.has(f.originalRead));
      f.fixture.close();
      assert.equal(f.retireCalls(), 1);
    } else {
      assert.equal(enter(), session);
      assert.equal(f.pendingReads.has(f.originalRead), false);
      f.fixture.close();
      assert.equal(f.retireCalls(), 0, 'Source close cannot retire a read already handed to its RowRun');
      session.close();
      assert.equal(f.retireCalls(), 1);
    }
  }
});
