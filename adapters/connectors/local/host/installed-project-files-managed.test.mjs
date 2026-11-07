import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {parse} from 'acorn';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeOptionalField} from '../../../host-common/compiler-binding.generated.mjs';
import {AcquisitionOpenError} from '../../../host-common/acquisition-outcome.mjs';
import {defaultFileMediaType as mime} from '../../../host-common/file-media-type.mjs';
import {createInstalledRowSource} from '../../../host-node/installed-row-source.mjs';

// Exact Local installer with explicit original Host/Core ports. No test here
// issues a real Resource admission, Native filesystem or public Run.
const moduleUrl = new URL('./installed-project-files.mjs', import.meta.url);
const source = await readFile(moduleUrl, 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const selected = new Set(['fail', 'canonical', 'cid', 'positive', 'text',
  'acknowledged', 'physicalReadChild', 'installPreparedProjectLocalFiles']);
const statements = ast.body.flatMap(node => {
  const value = node.type === 'ExportNamedDeclaration' ? node.declaration : node;
  const names = value?.type === 'VariableDeclaration'
    ? value.declarations.map(item => item.id.name) : [value?.id?.name];
  if (!names.some(name => selected.has(name))) return [];
  names.forEach(name => assert(selected.delete(name), name));
  return [source.slice(value.start, value.end)];
});
assert.equal(selected.size, 0);
const factory = new Function('createHash', 'canonicalJson', 'checked', 'runtimeOptionalField',
  'readFile', 'moduleUrl', 'createInstalledRowSource', 'rowSourceCheckEnvironment',
  'composeInstalledCheckEnvironment', 'retainInstalledHostInitializationFailure',
  'AcquisitionOpenError', 'openLocalFileRoot', 'mime',
  statements.join('\n').replaceAll('import.meta.url', 'moduleUrl') + '\nreturn installPreparedProjectLocalFiles;');
const ok = value => ({$tag: 1, _0: value});

async function fixture({pendingClose = false, currentAfterRead = true, closeGate, expectedInvocation} = {}) {
  const prepared = {}, request = {}, managed = {}, declaration = {}, admission = {}, oldOriginal = {};
  const calls = [], scopeCid = 'sha256:' + 'a'.repeat(64), contextCid = 'sha256:' + 'b'.repeat(64);
  let options, valid = true, closeAllowed = !pendingClose;
  const entry = {connection: 'local', rootPath: '/not-opened', declaration, scopeCid,
    limits: {maxReadBytes: 4096, maxPages: 4, maxPageBytes: 1024, maxFileBytes: 1024,
      maxPageRows: 4, maxFiles: 8},
    queryAliases: [{name: 'local', resource: 'files'}],
    wire: JSON.stringify({views: [{resource: 'files', source_ref: 'local:files',
      view_cid: 'view', carrier_schema_cid: 'schema'}]})};
  const bundle = {sources: [entry]};
  const moon = {clientProgramLocalFileTimestamp() {}, clientProgramResourceReferenceIssuer: () => ({}),
    clientProgramNodeManagedRunPrepare(value, owner) {
      assert.strictEqual(value, oldOriginal); assert.strictEqual(owner, prepared);
      calls.push('legacy-admission'); return ok(admission);
    },
    clientProgramInstalledManagedRunBegin(value, owner, intent) {
      assert.strictEqual(value, admission); assert.strictEqual(owner, prepared);
      assert.strictEqual(intent, request); calls.push('legacy-begin'); return ok(managed);
    },
    clientProgramInstalledManagedRunCheck: () => ok(),
    clientProgramInstalledSourceReadRetire() {calls.push('core-read-retire'); return ok();},
  };
  const raw = {retainChild() {assert.fail('No Native constructor selected');},
    close() {assert.strictEqual(this, raw); calls.push('same-raw-close');
      return closeGate === undefined ? {pending: !closeAllowed} : closeGate.then(() => ({pending: !closeAllowed}));}};
  const sourceManaged = {assertCurrent() {if (!valid) throw new Error('OriginalProjectSourceChanged');},
    prepareRun() {calls.push('legacy-root'); return oldOriginal;},
    prepareRead(owner, selected, parent, occurrence) {
      assert.strictEqual(owner, prepared); assert.strictEqual(selected, declaration);
      assert.strictEqual(parent, managed); assert.equal(occurrence.stage, 0);
      calls.push('same-native-parent'); valid = currentAfterRead; return raw;
    }};
  let profile;
  const install = factory(createHash, canonicalJson, checked, runtimeOptionalField, readFile, moduleUrl,
    async value => {options = value; return {connectorBindings: [], admitsSource: () => true};}, () => ({wire: '{}'}),
    () => '{}', async cause => cause, AcquisitionOpenError,
    () => assert.fail('No Native constructor selected'), mime);
  profile = await install({moon, preparation: {originalsForRuntime: () => bundle}, sourceManaged,
    baseEnvironmentWire: '{}', authorizationFor: async () => ({context: {contextCid}, assertAccountCurrent() {}}),
    prepareManagedRun({preparedProgram: owner, requestIdentity: intent, sourceProfile: originalProfile, prepareInvocation: invocation}) {
      assert.strictEqual(owner, prepared); assert.strictEqual(intent, request);
      assert.strictEqual(originalProfile, profile); assert.strictEqual(invocation, expectedInvocation); calls.push('same-host-parent'); return managed;
    }});
  return {profile, prepared, request, managed, declaration, calls, get options() {return options;},
    allowClose() {closeAllowed = true;}, prepareRead(originalRead = {}) {
      return options.prepareSourceRead({checkedOwner: prepared, effectful: false, declaration,
        occurrence: {stage: 0, input: 0, task: 0}, managedRun: managed, originalRead});
    }};
}

test('ordinary Local Files delegates to the same Host Run without creating another Root or admission', async () => {
  const f = await fixture();
  f.profile.prepareManagedRun({preparedProgram: f.prepared, requestIdentity: f.request});
  assert.deepEqual(f.calls, ['same-host-parent']);
});

test('Local Files returns its same retained Host Run to the original submission caller', async () => {
  const f = await fixture();
  assert.strictEqual(f.profile.prepareManagedRun({preparedProgram: f.prepared, requestIdentity: f.request}), f.managed);
  assert.strictEqual(f.profile.prepareManagedRun({preparedProgram: f.prepared, requestIdentity: f.request}), f.managed);
  assert.deepEqual(f.calls, ['same-host-parent', 'same-host-parent']);
});

test('Local planned read keeps the same Core tuple and closes only its original external child', async () => {
  const f = await fixture(); f.profile.prepareManagedRun({preparedProgram: f.prepared, requestIdentity: f.request});
  const original = {};
  assert.strictEqual(f.prepareRead(original), original);
  assert.throws(() => f.prepareRead(original), {code: 'LocalFilesSourcePreparationMismatch'});
  assert.deepEqual(await f.options.closeSourceRead(original), {pending: false});
  assert.deepEqual(await f.options.closeSourceRead(original), {pending: false});
  await f.profile.close();
  assert.deepEqual(f.calls, ['same-host-parent', 'same-native-parent', 'same-raw-close']);
});

test('Local planned read keeps pending cleanup and never acknowledges or reopens its consumed occurrence', async () => {
  const f = await fixture({pendingClose: true}); f.profile.prepareManagedRun({preparedProgram: f.prepared, requestIdentity: f.request});
  const original = f.prepareRead();
  await assert.rejects(f.options.closeSourceRead(original), {code: 'LocalFileCleanupPending'});
  assert.throws(() => f.prepareRead(), {code: 'LocalFilesSourcePreparationMismatch'});
  f.allowClose();
  assert.deepEqual(await f.options.closeSourceRead(original), {pending: false});
  await f.profile.close();
  assert.equal(f.calls.filter(value => value === 'same-native-parent').length, 1);
  assert.equal(f.calls.filter(value => value === 'core-read-retire').length, 0);
});

test('Local partial read retains original cleanup before a post-acquisition current refusal', async () => {
  const f = await fixture({currentAfterRead: false}); f.profile.prepareManagedRun({preparedProgram: f.prepared, requestIdentity: f.request});
  assert.throws(() => f.prepareRead(), /OriginalProjectSourceChanged/u);
  await f.profile.close();
  assert.deepEqual(f.calls, ['same-host-parent', 'same-native-parent', 'same-raw-close', 'core-read-retire']);
});

test('Local concurrent closes await the same original external cleanup without releasing twice', async () => {
  let release;
  const closeGate = new Promise(resolve => {release = resolve;});
  const f = await fixture({closeGate}); f.profile.prepareManagedRun({preparedProgram: f.prepared, requestIdentity: f.request});
  const original = f.prepareRead();
  const first = f.options.closeSourceRead(original), second = f.options.closeSourceRead(original);
  release();
  assert.deepEqual(await Promise.all([first, second]), [{pending: false}, {pending: false}]);
  assert.equal(f.calls.filter(value => value === 'same-raw-close').length, 1);
  await f.profile.close();
});

// Actual shared Source and RowRun consumer, with explicit nominal Core ports.
// This checks routing/retirement; it does not issue a Ledger or file authority.
async function rowFixture({pending = false, empty = true, readFailure, recoveryGate, accountFailureAfterClose = false} = {}) {
  const owner = {}, request = {}, parent = {}, declaration = {}, originalRead = {}, requirement = {};
  const acquisition = {}, capacity = {}, ledger = {}, row = {}, captured = {}, source = {};
  const calls = [], occurrence = {stage: 0, input: 0, task: 0};
  let closeAllowed = !pending;
  const originalRecovery = {
    async cleanup() {assert.strictEqual(this, originalRecovery); calls.push('original-native-recovery');
      if (recoveryGate !== undefined) await recoveryGate; return closeAllowed;},
    cleanupPending() {assert.strictEqual(this, originalRecovery); return !closeAllowed;},
    close() {assert.fail('No substitute close request');},
  };
  if (readFailure === 'getter') Object.defineProperty(originalRecovery, 'cleanup', {
    get() {calls.push('original-recovery-getter'); throw new Error('OriginalRecoveryGetterFailed');},
  });
  const originalFailure = new AcquisitionOpenError(new Error('OriginalNativeUnknown'), 'unknown',
    readFailure === 'unowned' ? undefined : originalRecovery);
  const accountFailure = new AcquisitionOpenError(new Error('OriginalAccountUnknown'), 'unknown');
  const moon = {
    clientProgramInstalledManagedRunCheck: () => ok(),
    clientProgramInstalledManagedCaptureSourceRead(run, checked, intent, selected, index) {
      assert.deepEqual([run, checked, intent, selected, index], [parent, owner, request, declaration, 0]);
      calls.push('same-plan-tuple'); return ok({_0: originalRead, _1: requirement, _2: acquisition, _3: capacity});
    },
    clientProgramInstalledSourceReadCheckCurrent: () => assert.fail('Bind already checks the same current boundary'),
    clientProgramInstalledSourceReadBindProgram(read, checked) {
      assert.strictEqual(read, originalRead); assert.strictEqual(checked, owner); calls.push('bind-original'); return ok();
    },
    clientProgramInstalledSourceReadBindEffectProgram: () => assert.fail('No Effect'),
    clientProgramInstalledSourceReadAttachAcquisition: () => assert.fail('No second acquisition'),
    clientProgramQueryRequirementSourceEvidenceFacts: () => ok(['local:files', 'source', 'schema', 'policy', 'class', 'view']),
    clientProgramRowSourceTarget: () => ok(['files', 'path']),
    clientProgramQueryRequirementCid: () => 'requirement',
    clientProgramQueryRequirementInputContractCid: () => 'input',
    clientProgramQueryRequirementOutputContractCid: () => 'output',
    clientProgramInstalledRowCaptureCapacity: () => assert.fail('No repeated capacity construction'),
    clientProgramRowSourceColumns: () => ['path'],
    clientProgramInstalledSourceReadCheckLedger(read, actual) {
      assert.strictEqual(read, originalRead); assert.strictEqual(actual, ledger); return ok();
    },
    clientProgramInstalledSourceReadStartRows: () => ok(row),
    clientProgramRowSourceRequestWire: () => ok('{}'),
    clientProgramRowSourceBegin: () => ok(),
    clientProgramRowSourceIsListing: () => true,
    clientProgramRowSourceListingComplete: () => empty,
    clientProgramRowSourceFinish() {calls.push('finish-row'); return ok();},
    clientProgramRowSourceAttempt: () => ({}),
    clientProgramRowSourceCaptureBegin: () => ok(),
    clientProgramRowSourceCaptureAdvance: () => ok({_0: true}),
    clientProgramRowSourceCapture: () => ok(captured),
    clientProgramRowSourceCaptureSource: () => ok(source),
    clientProgramCapturedTaskSourceMatches: () => true,
    clientProgramIdentifyCapturedSourceRelation: () => ok({}),
    clientProgramIssueCapturedTaskSourceLogical: () => ok({}),
    clientProgramRowSourceCloseAccounted() {calls.push('close-row'); return ok();},
    clientProgramRowSourceCaptureCleanup: () => ok(true),
    clientProgramInstalledSourceReadRetire(read) {
      assert.strictEqual(read, originalRead); assert(closeAllowed); calls.push('retire-core'); return ok();
    },
    clientProgramRowSourceCaptureCleanupAdvance: () => ok(true),
  };
  const adapter = await createInstalledRowSource({moon, declaration,
    declared: {views: [{resource: 'files', source_ref: 'local:files'}]},
    environmentWire: '{}', connectorId: 'local', connectorRegistration: 'local', connectorRevision: 'local/0.1',
    bindingCid: 'sha256:' + 'c'.repeat(64), site: {connection: 'local', close() {},
      issueReadGrant() {assert.fail('No native credential grant');}},
    authorization: {context: {}, authorize: async () => {
      if (accountFailureAfterClose && calls.includes('close-native')) throw accountFailure;
      return {action: 'dispatch'};
    }},
    readOperation: 'read', physicalTarget: () => ({root: '/not-opened'}),
    limits: {maxPages: 2, maxPageBytes: 1024, maxPageRows: 4, maxCaptureRows: 4},
    prepareSourceRead(facts) {
      assert.strictEqual(facts.managedRun, parent); assert.strictEqual(facts.originalRead, originalRead);
      assert.strictEqual(facts.requirement, requirement); calls.push('retain-native'); return originalRead;
    },
    async closeSourceRead(read) {
      assert.strictEqual(read, originalRead); calls.push('close-native'); return {pending: !closeAllowed};
    },
    async readPages() {calls.push('read-native'); if (readFailure !== undefined) throw originalFailure;},
  });
  const prepared = await adapter.prepare({preparedProgram: owner, requestIdentity: request, managedRun: parent, occurrence});
  return {calls, capacity, adapter, prepared, originalRecovery, originalFailure, accountFailure, allowClose() {closeAllowed = true;},
    open: () => adapter.openCapture({preparedProgram: owner, preparedSource: prepared, ledger, occurrence})};
}

test('shared native Source uses its retained Plan tuple and closes empty listing control before completion', async () => {
  const f = await rowFixture();
  assert.strictEqual(f.adapter.ledgerCapacity(f.prepared).capacity, f.capacity);
  const capture = await f.open();
  assert.deepEqual(f.calls, ['same-plan-tuple', 'retain-native', 'bind-original', 'close-native', 'finish-row']);
  capture.close();
  assert.deepEqual(f.calls.slice(-2), ['close-row', 'retire-core']);
});

test('shared native Source never retires Core rows before original external cleanup acknowledgment', async () => {
  const f = await rowFixture({pending: true});
  let failure;
  await assert.rejects(f.open(), error => {failure = error; return error.outcome === 'unknown';});
  assert.equal(f.calls.includes('close-row'), false);
  assert.equal(f.calls.filter(value => value === 'close-native').length, 1);
  assert.equal(failure.recovery.cleanupPending(), true);
  f.allowClose(); assert.equal(await failure.recovery.cleanup(), true);
  assert.equal(failure.recovery.cleanupPending(), false);
  assert.deepEqual(f.calls.slice(-3), ['close-native', 'close-row', 'retire-core']);
});

test('shared native Source closes its actual selected read before completing a nonempty capture', async () => {
  const f = await rowFixture({empty: false});
  const capture = await f.open();
  assert.deepEqual(f.calls, ['same-plan-tuple', 'retain-native', 'bind-original',
    'read-native', 'close-native', 'finish-row']);
  capture.close();
  assert.deepEqual(f.calls.slice(-2), ['close-row', 'retire-core']);
});

test('shared native Source retains its original unknown recovery without an automatic second close', async () => {
  const f = await rowFixture({empty: false, pending: true, readFailure: 'owned'});
  let failure;
  await assert.rejects(f.open(), error => {failure = error; return error.outcome === 'unknown';});
  assert.equal(f.calls.includes('close-native'), false);
  assert.equal(f.calls.includes('original-native-recovery'), false);
  assert.equal(f.calls.includes('close-row'), false);
  // The existing RowRun owner must retain original methods and receiver,
  // rather than discover replacement callbacks during a later cleanup.
  f.originalRecovery.cleanup = f.originalRecovery.cleanupPending = () => assert.fail('No replacement recovery');
  assert.equal(await failure.recovery.cleanup(), false);
  assert.equal(failure.recovery.cleanupPending(), true);
  assert.equal(f.calls.includes('close-row'), false);
  f.allowClose();
  assert.equal(await failure.recovery.cleanup(), true);
  assert.equal(await failure.recovery.cleanup(), true);
  assert.equal(failure.recovery.cleanupPending(), false);
  assert.deepEqual(f.calls.slice(-3), ['original-native-recovery', 'close-row', 'retire-core']);
  assert.equal(f.calls.filter(value => value === 'original-native-recovery').length, 2);
});

test('shared native Source preserves an unknown without a recovery instead of inferring stop from another close', async () => {
  const f = await rowFixture({empty: false, readFailure: 'unowned'});
  let failure;
  await assert.rejects(f.open(), error => {failure = error; return error.outcome === 'unknown';});
  assert.equal(f.calls.includes('close-native'), false);
  assert.equal(await failure.recovery.cleanup(), false);
  assert.equal(failure.recovery.cleanupPending(), true);
  assert.equal(f.calls.includes('close-row'), false);
});

test('shared native Source retains uncertain cleanup when original recovery method capture throws', async () => {
  const f = await rowFixture({empty: false, readFailure: 'getter'});
  let failure;
  await assert.rejects(f.open(), error => {failure = error; return error.outcome === 'unknown';});
  assert.equal(await failure.recovery.cleanup(), false);
  assert.equal(failure.recovery.cleanupPending(), true);
  assert.equal(f.calls.filter(value => value === 'original-recovery-getter').length, 1);
  assert.equal(f.calls.includes('close-native'), false);
  assert.equal(f.calls.includes('close-row'), false);
});

test('shared native Source concurrent recovery awaits one original operation before one Core close', async () => {
  let release;
  const recoveryGate = new Promise(resolve => {release = resolve;});
  const f = await rowFixture({empty: false, pending: true, readFailure: 'owned', recoveryGate});
  let failure;
  await assert.rejects(f.open(), error => {failure = error; return error.outcome === 'unknown';});
  f.allowClose();
  const first = failure.recovery.cleanup(), second = failure.recovery.cleanup();
  release();
  assert.deepEqual(await Promise.all([first, second]), [true, true]);
  assert.equal(f.calls.filter(value => value === 'original-native-recovery').length, 1);
  assert.equal(f.calls.filter(value => value === 'close-row').length, 1);
  assert.equal(failure.recovery.cleanupPending(), false);
});

test('shared native Source keeps post-close Account uncertainty separate from native recovery', async () => {
  const f = await rowFixture({accountFailureAfterClose: true});
  let failure;
  await assert.rejects(f.open(), error => {failure = error; return error.outcome === 'unknown';});
  assert.equal(f.calls.includes('close-row'), true);
  assert.equal(f.calls.includes('retire-core'), true);
  assert.equal(f.calls.includes('original-native-recovery'), false);
  assert.strictEqual(failure, f.accountFailure);
});

const hostSource = await readFile(new URL('../../../host-node/embedded-local.mjs', import.meta.url), 'utf8');
const hostAst = parse(hostSource, {ecmaVersion: 'latest', sourceType: 'module'});
let installationMethod;
function visit(node) {
  if (node === null || typeof node !== 'object') return;
  if (node.type === 'Property' && node.method && node.key.name === 'installProjectSources') {
    assert.equal(installationMethod, undefined); installationMethod = node;
  }
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === 'object') visit(value);
  }
}
visit(hostAst); assert(installationMethod);
const hostFactory = new Function('moon', 'projectSourcePreparation', 'mockPreparation',
  'assertSourceManagedInstallationCurrent', 'sourceManaged', 'originals',
  'installPreparedProjectLocalFiles', 'localProjectFilesystem', 'preparation', 'record',
  'originalInstallation', 'retainInstalledHostInitializationFailure', 'clientOperationError',
  `return ({${hostSource.slice(installationMethod.start, installationMethod.end)}}).installProjectSources;`);
const operationError = code => Object.assign(new Error(code), {code});

test('Local installation forwards the captured actual Host method and original receiver to its same profile', async () => {
  const runtime = {}, originalPreparation = {}, manager = {}, originals = {}, namespace = {};
  const profile = {}, prepared = {}, request = {}, parent = {}, record = {}, installation = {};
  let supplied, calls = 0;
  const host = {prepareManagedSourceRun(...args) {
    assert.strictEqual(this, host); assert.deepEqual(args, [runtime, prepared, request, profile, undefined]);
    assert.strictEqual(record.managedSourceProfile, profile);
    assert.strictEqual(installation.managedSourceProfile, profile); calls++; return parent;
  }};
  const install = hostFactory(runtime, originalPreparation, undefined,
    (actual, input) => {assert.strictEqual(actual, manager); assert.strictEqual(input, originals);},
    manager, originals, options => {
      assert.strictEqual(options.preparation, originalPreparation);
      assert.strictEqual(options.sourceManaged, manager);
      assert.strictEqual(options.nativeFilesystem, namespace);
      supplied = options.prepareManagedRun; return Promise.resolve(profile);
    }, () => namespace, host, record, installation,
    () => assert.fail('No failed initialization'), operationError);
  assert.strictEqual(await install(runtime, '{}', () => {}), profile);
  host.prepareManagedSourceRun = () => assert.fail('No later method lookup');
  assert.strictEqual(supplied({preparedProgram: prepared, requestIdentity: request, sourceProfile: profile}), parent);
  assert.equal(calls, 1);
  assert.throws(() => install({}, '{}', () => {}), {code: 'ForeignInstalledProjectSourcePreparation'});
});

test('Local duplicate installation retains the actual returned profile for original initialization cleanup', async () => {
  const runtime = {}, original = {}, profile = {}, existing = {}, record = {managedSourceProfile: existing};
  let retained;
  const install = hostFactory(runtime, original, undefined, () => {}, {}, {},
    () => Promise.resolve(profile), () => ({}), {prepareManagedSourceRun() {}}, record, {},
    async (cause, owners) => {retained = owners.sourceProfile; return cause;}, operationError);
  await assert.rejects(install(runtime, '{}', () => {}), {code: 'InstalledSourcePreparationChanged'});
  assert.strictEqual(retained, profile);
  assert.strictEqual(record.managedSourceProfile, existing);
});


test('timed original Local wrapper forwards the same Host invocation constructor without invoking it',async()=>{
  const original=()=>assert.fail('Local must not invoke the Host constructor');
  const f=await fixture({expectedInvocation:original});f.profile.prepareManagedRun({preparedProgram:f.prepared,requestIdentity:f.request,prepareInvocation:original});
  assert.deepEqual(f.calls,['same-host-parent']);await f.profile.close();
});

// Actual Local installation and shared RowSource preparation, with explicit
// nominal Core/Host ports. No file, Ledger, Resource or public Run is opened.
async function effectSourceFixture({pending = false, changedAfterRead = false} = {}) {
  const owner = {}, request = {}, parent = {}, declaration = {}, read = {};
  const requirement = {}, acquisition = {}, capacity = {}, calls = [];
  let valid = true, closeAllowed = !pending;
  const scopeCid = 'sha256:' + 'a'.repeat(64), contextCid = 'sha256:' + 'b'.repeat(64);
  const declared = {views: [{resource: 'files', source_ref: 'local:files',
    view_cid: 'view', carrier_schema_cid: 'schema'}]};
  const entry = {connection: 'local', connectorId: 'local', rootPath: '/not-opened', declaration, scopeCid,
    limits: {maxReadBytes: 4096, maxPages: 4, maxPageBytes: 1024, maxFileBytes: 1024,
      maxPageRows: 4, maxFiles: 8}, queryAliases: [{name: 'local', resource: 'files'}],
    wire: JSON.stringify(declared)};
  const bundle = {sources: [entry]};
  const raw = {retainChild() {assert.fail('No native filesystem selected');},
    close() {assert.strictEqual(this, raw); calls.push('same-raw-close'); return {pending: !closeAllowed};}};
  const moon = {
    clientProgramLocalFileTimestamp() {}, clientProgramResourceReferenceIssuer: () => ({}),
    clientProgramInstalledManagedRunCheck: () => assert.fail('Effect must not select the Pure Run check'),
    clientProgramInstalledKeyedSourceReadCheckCurrent: () => assert.fail('No keyed read'),
    clientProgramInstalledKeyedSourceReadAcquisition: () => assert.fail('No keyed read'),
    clientProgramInstalledKeyedSourceReadRetire: () => assert.fail('No keyed read'),
    clientProgramInstalledSourceReadCheckCurrent: () => assert.fail('No repeated current before binding'),
    clientProgramInstalledSourceReadBindProgram: () => assert.fail('No Pure input'),
    clientProgramInstalledSourceReadAttachAcquisition: () => assert.fail('No replacement acquisition'),
    clientProgramInstalledEffectManagedRunCheck(run, checkedOwner, intent) {
      assert.strictEqual(run, parent); assert.strictEqual(checkedOwner, owner);
      if (intent !== request) throw new Error('OriginalEffectRequestMismatch');
      calls.push('effect-current'); return ok();
    },
    clientProgramInstalledEffectManagedSourceRead(run, selected, index) {
      assert.strictEqual(run, parent); assert.strictEqual(selected, declaration); assert.equal(index, 0);
      calls.push('same-plan-read'); return ok({_0: read, _1: requirement, _2: acquisition, _3: capacity});
    },
    clientProgramInstalledSourceReadBindEffectProgram(original, checkedOwner) {
      assert.strictEqual(original, read); assert.strictEqual(checkedOwner, owner); return ok();
    },
    clientProgramQueryRequirementSourceEvidenceFacts: () => ok(['local:files', 'source', 'schema', 'policy', 'class', 'view']),
    clientProgramRowSourceTarget: () => ok(['files', 'path']),
    clientProgramQueryRequirementCid: () => 'requirement',
    clientProgramQueryRequirementInputContractCid: () => 'input',
    clientProgramQueryRequirementOutputContractCid: () => 'output',
    clientProgramInstalledSourceReadRetire(original) {assert.strictEqual(original, read); calls.push('core-read-retire'); return ok();},
  };
  const sourceManaged = {assertCurrent() {if (!valid) throw new Error('OriginalProjectSourceChanged');},
    prepareRead(checkedOwner, selected, run, occurrence) {
      assert.strictEqual(checkedOwner, owner); assert.strictEqual(selected, declaration);
      assert.strictEqual(run, parent); assert.deepEqual(occurrence, {stage: 0, input: 0, task: 0});
      calls.push('same-host-read'); valid = !changedAfterRead; return raw;
    }};
  const install = factory(createHash, canonicalJson, checked, runtimeOptionalField, readFile, moduleUrl,
    createInstalledRowSource, () => ({wire: '{}'}), () => '{}', async cause => cause,
    AcquisitionOpenError, () => assert.fail('No native filesystem selected'), mime);
  const profile = await install({moon, preparation: {originalsForRuntime: () => bundle}, sourceManaged,
    baseEnvironmentWire: '{}', authorizationFor: async () => ({context: {contextCid}, assertAccountCurrent() {},
      authorize: async () => ({action: 'dispatch'})}),
    prepareManagedRun: () => assert.fail('Already adopted Effect must not issue a Pure Run')});
  const prepare = (intent = request, managedRun = parent) => profile.sources[0].prepare({
    preparedEffect: owner, requestIdentity: intent, managedRun, occurrence: {stage: 0, input: 0, task: 0}});
  return {profile, calls, prepare, allowClose() {closeAllowed = true;}};
}

test('Local Effect Source consumes its same adopted Host Run and original read without a second admission', async () => {
  const f = await effectSourceFixture();
  const selected = await f.prepare();
  assert.equal(selected.readTuple.resource, 'files');
  assert.deepEqual(f.calls, ['effect-current', 'same-plan-read', 'same-host-read', 'effect-current']);
  await f.profile.close();
  assert.deepEqual(f.calls.slice(-2), ['same-raw-close', 'core-read-retire']);
});

test('Local Effect Source rejects a foreign Request before acquiring a native child', async () => {
  const f = await effectSourceFixture();
  await assert.rejects(f.prepare({}), /OriginalEffectRequestMismatch/u);
  assert.deepEqual(f.calls, []);
  await f.prepare();
  // An existing local provenance record must not replace a supplied foreign
  // tuple with its original, thereby hiding the mismatch from Core.
  await assert.rejects(f.prepare({}), {code: 'LocalFilesSourcePreparationMismatch'});
  assert.equal(f.calls.filter(value => value === 'same-host-read').length, 1);
  await f.profile.close();
});

test('Local Effect Source preserves pending original cleanup and its consumed occurrence', async () => {
  const f = await effectSourceFixture({pending: true});
  await f.prepare();
  await assert.rejects(f.prepare(), {code: 'LocalFilesSourcePreparationMismatch'});
  await assert.rejects(f.profile.close(), {message: 'LocalFilesCleanupPending'});
  assert.equal(f.calls.includes('core-read-retire'), false);
  f.allowClose(); await f.profile.close();
  assert.equal(f.calls.filter(value => value === 'same-host-read').length, 1);
  assert.deepEqual(f.calls.slice(-2), ['same-raw-close', 'core-read-retire']);
});

test('Local Effect Source retains its actual child before post-acquisition current refusal', async () => {
  const f = await effectSourceFixture({changedAfterRead: true});
  await assert.rejects(f.prepare(), /OriginalProjectSourceChanged/u);
  assert.equal(f.calls.filter(value => value === 'same-host-read').length, 1);
  await f.profile.close();
  assert.equal(f.calls.filter(value => value === 'same-raw-close').length, 1);
});
