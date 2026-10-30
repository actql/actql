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

async function fixture({pendingClose = false, currentAfterRead = true, closeGate} = {}) {
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
    prepareManagedRun(owner, intent, originalProfile) {
      assert.strictEqual(owner, prepared); assert.strictEqual(intent, request);
      assert.strictEqual(originalProfile, profile); calls.push('same-host-parent'); return managed;
    }});
  return {profile, prepared, request, managed, declaration, calls, get options() {return options;},
    allowClose() {closeAllowed = true;}, prepareRead(originalRead = {}) {
      return options.prepareSourceRead({checkedOwner: prepared, effectful: false, declaration,
        occurrence: {stage: 0, input: 0, task: 0}, managedRun: managed, originalRead});
    }};
}

test('ordinary Local Files delegates to the same Host Run without creating another Root or admission', async () => {
  const f = await fixture();
  f.profile.prepareManagedRun(f.prepared, f.request);
  assert.deepEqual(f.calls, ['same-host-parent']);
});

test('Local planned read keeps the same Core tuple and closes only its original external child', async () => {
  const f = await fixture(); f.profile.prepareManagedRun(f.prepared, f.request);
  const original = {};
  assert.strictEqual(f.prepareRead(original), original);
  assert.throws(() => f.prepareRead(original), {code: 'LocalFilesSourcePreparationMismatch'});
  assert.deepEqual(await f.options.closeSourceRead(original), {pending: false});
  assert.deepEqual(await f.options.closeSourceRead(original), {pending: false});
  await f.profile.close();
  assert.deepEqual(f.calls, ['same-host-parent', 'same-native-parent', 'same-raw-close']);
});

test('Local planned read keeps pending cleanup and never acknowledges or reopens its consumed occurrence', async () => {
  const f = await fixture({pendingClose: true}); f.profile.prepareManagedRun(f.prepared, f.request);
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
  const f = await fixture({currentAfterRead: false}); f.profile.prepareManagedRun(f.prepared, f.request);
  assert.throws(() => f.prepareRead(), /OriginalProjectSourceChanged/u);
  await f.profile.close();
  assert.deepEqual(f.calls, ['same-host-parent', 'same-native-parent', 'same-raw-close', 'core-read-retire']);
});

test('Local concurrent closes await the same original external cleanup without releasing twice', async () => {
  let release;
  const closeGate = new Promise(resolve => {release = resolve;});
  const f = await fixture({closeGate}); f.profile.prepareManagedRun(f.prepared, f.request);
  const original = f.prepareRead();
  const first = f.options.closeSourceRead(original), second = f.options.closeSourceRead(original);
  release();
  assert.deepEqual(await Promise.all([first, second]), [{pending: false}, {pending: false}]);
  assert.equal(f.calls.filter(value => value === 'same-raw-close').length, 1);
  await f.profile.close();
});

// Actual shared Source and RowRun consumer, with explicit nominal Core ports.
// This checks routing/retirement; it does not issue a Ledger or file authority.
async function rowFixture({pending = false, empty = true, readFailure, recoveryGate,
  accountFailureAfterClose = false, localEffect = false, currentAfterRead = true, deferPrepare = false} = {}) {
  const owner = {}, request = {}, parent = {}, declaration = {}, originalRead = {}, requirement = {};
  const acquisition = {}, capacity = {}, ledger = {}, row = {}, captured = {}, source = {};
  const calls = [], occurrence = {stage: 0, input: 0, task: 0};
  let closeAllowed = !pending, localCurrent = true;
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
  const options = {moon, declaration,
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
  };
  let adapter, profile;
  if (localEffect) {
    moon.clientProgramLocalFileTimestamp = () => assert.fail('No Native constructor');
    moon.clientProgramResourceReferenceIssuer = () => ({});
    moon.clientProgramInstalledEffectManagedRunCheck = (run, checkedOwner, intent) => {
      assert.strictEqual(run, parent); assert.strictEqual(checkedOwner, owner);
      assert.strictEqual(intent, request); calls.push('check-effect'); return ok();
    };
    moon.clientProgramInstalledEffectManagedSourceRead = (run, selected, index) => {
      assert.strictEqual(run, parent); assert.strictEqual(selected, declaration); assert.equal(index, 0);
      calls.push('same-plan-tuple');
      return ok({_0: originalRead, _1: requirement, _2: acquisition, _3: capacity});
    };
    moon.clientProgramInstalledSourceReadBindEffectProgram = (read, checkedOwner) => {
      assert.strictEqual(read, originalRead); assert.strictEqual(checkedOwner, owner);
      calls.push('bind-original'); return ok();
    };
    for (const name of ['clientProgramNodeEffectManagedRunPrepare', 'clientProgramInstalledEffectManagedRunBegin',
      'clientProgramInstalledManagedRunRetire', 'clientProgramNodeEffectManagedRunCleanup',
      'clientProgramInstalledKeyedSourceReadCheckCurrent', 'clientProgramInstalledKeyedSourceReadAcquisition',
      'clientProgramInstalledKeyedSourceReadRetire']) {
      moon[name] = () => assert.fail('No Connector Root, admission or Host Run retirement');
    }
    const entry = {connection: 'local', rootPath: '/not-opened', declaration,
      scopeCid: 'sha256:' + 'a'.repeat(64), queryAliases: [],
      limits: {maxReadBytes: 4096, maxPages: 2, maxPageBytes: 1024, maxFileBytes: 1024,
        maxPageRows: 4, maxFiles: 4},
      wire: JSON.stringify(options.declared)};
    const bundle = {sources: [entry]};
    const raw = {retainChild() {assert.fail('No Native constructor');},
      close() {assert.strictEqual(this, raw); calls.push('close-native'); return {pending: !closeAllowed};}};
    const sourceManaged = {
      assertCurrent() {if (!localCurrent) throw new Error('OriginalProjectSourceChanged');},
      prepareEffectRun() {assert.fail('No Connector Root');},
      prepareRead(checkedOwner, selected, run, selectedOccurrence) {
        assert.strictEqual(checkedOwner, owner); assert.strictEqual(selected, declaration);
        assert.strictEqual(run, parent); assert.deepEqual(selectedOccurrence, occurrence);
        calls.push('retain-native'); localCurrent = currentAfterRead; return raw;
      },
    };
    const install = factory(createHash, canonicalJson, checked, runtimeOptionalField, readFile, moduleUrl,
      createInstalledRowSource, () => ({wire: '{}'}), () => '{}', async cause => cause,
      AcquisitionOpenError, () => assert.fail('No Native constructor'), mime);
    profile = await install({moon, preparation: {originalsForRuntime: () => bundle}, sourceManaged,
      baseEnvironmentWire: '{}', authorizationFor: async () => ({...options.authorization,
        context: {contextCid: 'sha256:' + 'b'.repeat(64)}, assertAccountCurrent() {assert.fail('No native grant');}})});
    adapter = profile.sources[0];
  } else adapter = await createInstalledRowSource(options);
  const facts = { ...(localEffect ? {preparedEffect: owner} : {preparedProgram: owner}),
    requestIdentity: request, managedRun: parent, occurrence};
  const prepared = deferPrepare ? undefined : await adapter.prepare(facts);
  return {calls, capacity, adapter, prepared, profile, facts, originalRecovery, originalFailure, accountFailure, allowClose() {closeAllowed = true;},
    open: () => adapter.openCapture({preparedProgram: owner, preparedSource: prepared, ledger, occurrence})};
}

test('Local Effect Source consumes the actual Host Run and original retained Plan without a Connector Root', async () => {
  const f = await rowFixture({localEffect: true});
  assert.equal(f.profile.prepareManagedEffectRun, undefined);
  const capacity = f.adapter.ledgerCapacity(f.prepared);
  assert.strictEqual(capacity.capacity, f.capacity);
  assert.strictEqual(capacity.managedRun, f.facts.managedRun);
  assert.equal(f.calls.filter(value => value === 'same-plan-tuple').length, 1);
  assert.equal(f.calls.filter(value => value === 'retain-native').length, 1);
  assert.equal(f.calls.filter(value => value === 'bind-original').length, 1);
  // No RowRun or file was opened. Local closes only the retained original
  // child/read; the shared Host still owns its Run and admission.
  await f.profile.close();
  assert.deepEqual(f.calls.slice(-2), ['close-native', 'retire-core']);
});

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
    assert.strictEqual(this, host); assert.deepEqual(args, [runtime, prepared, request, profile]);
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
  assert.strictEqual(supplied(prepared, request, profile), parent);
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

// Exact original installer, with explicit nominal Core/Host ports. Count JS
// calls to the existing check API and Project-current callback, not full Core
// validation work, physical resource use or ordinary execution time.
async function reuseFixture(kind,{beginFailure}={}) {
  const owner={}, request={}, restored={}, managed={}, original={}, admission={}, selected={}, keyed={};
  const declaration={}, requirement={}, acquisition={}, capacity={}, cause=new Error('OriginalRunBindingRefused');
  let checks=0, currents=0, roots=0, begins=0, handler;
  const requests=new Set([request]), tuples=[];
  const check=(value, prepared, intent)=>{
    checks++; tuples.push([value,prepared,intent]);
    assert.strictEqual(value,managed); assert.strictEqual(prepared,owner);
    if(handler!==undefined) return handler(intent);
    return requests.has(intent)?ok():{$tag:0,_0:cause};
  };
  const moon={clientProgramLocalFileTimestamp(){},clientProgramResourceReferenceIssuer:()=>({}),
    clientProgramInstalledEffectManagedRunCheck:check,clientProgramInstalledManagedRunCheck:check,
    clientProgramNodeEffectManagedRunPrepare(value,prepared){
      assert.strictEqual(value,original);assert.strictEqual(prepared,owner);return ok(admission);},
    clientProgramInstalledEffectManagedRunBegin(value,prepared,intent){
      assert.strictEqual(value,admission);assert.strictEqual(prepared,owner);assert.strictEqual(intent,request);
      begins++;if(beginFailure!==undefined)throw beginFailure;return ok(managed);},
    clientProgramKeyedAcquisitionMatchesProgram:(value,prepared)=>value===keyed&&prepared===owner,
    clientProgramKeyedDirectAcquisitionCoordinates:()=>({_0:0,_1:0}),
    clientProgramPrepareLocalQueryRequirement:()=>ok(requirement),
    clientProgramQueryRequirementSourceRef:()=> 'local:files',
    clientProgramKeyedAcquisitionSourceEvidenceFacts:()=>ok(['local:contents']),
    clientProgramRowSourcePrepareAcquisition:()=>ok(acquisition),
    clientProgramInstalledRowCaptureCapacity:()=>capacity,
    clientProgramInstalledManagedKeyedContentPrepare:()=>ok(selected),
    clientProgramNodeLocalContentRunPrepare(value,prepared){
      assert.strictEqual(value,original);assert.strictEqual(prepared,owner);return ok(admission);},
    clientProgramInstalledManagedKeyedContentRunBegin(value,prepared,intent,plan){
      assert.strictEqual(value,admission);assert.strictEqual(prepared,owner);assert.strictEqual(intent,request);
      assert.strictEqual(plan,selected);begins++;if(beginFailure!==undefined)throw beginFailure;return ok(managed);},
    clientProgramInstalledManagedRunRetire:value=>{assert.strictEqual(value,managed);return ok();},
    clientProgramNodeEffectManagedRunCleanup:value=>{assert.strictEqual(value,admission);return ok();},
    clientProgramNodeManagedRunCleanup:value=>{assert.strictEqual(value,admission);return ok();},
  };
  const entry={connection:'local',rootPath:'/not-opened',declaration,
    scopeCid:'sha256:'+'a'.repeat(64),limits:{maxReadBytes:4096,maxPages:4,maxPageBytes:1024,
      maxFileBytes:1024,maxPageRows:4,maxFiles:8},queryAliases:[],
    wire:JSON.stringify({views:[{resource:'files',source_ref:'local:files'},
      {resource:'contents',source_ref:'local:contents'}]})};
  const bundle={sources:[entry]}, recipe={keyedAcquisition:keyed,registry:{},values:'values',
    fragment:'fragment',ordered:undefined,task:0,step:0,prefixRetainedBytes:1n,prefixExecutionBytes:1n};
  const sourceManaged={assertCurrent(){currents++;},prepareRead(){assert.fail('No Source read');},
    prepareEffectRun(prepared){assert.strictEqual(prepared,owner);roots++;return original;},
    prepareContentRun(prepared,plan){assert.strictEqual(prepared,owner);assert.strictEqual(plan,selected);
      roots++;return original;}};
  const install=factory(createHash,canonicalJson,checked,runtimeOptionalField,readFile,moduleUrl,
    async()=>({connectorBindings:[],admitsSource:()=>true}),()=>({wire:'{}'}),()=> '{}',
    async failure=>failure,AcquisitionOpenError,()=>assert.fail('No Native constructor'),mime);
  const profile=await install({moon,preparation:{originalsForRuntime:()=>bundle},sourceManaged,
    baseEnvironmentWire:'{}',authorizationFor:async()=>({context:{contextCid:'sha256:'+'b'.repeat(64)},
      assertAccountCurrent(){assert.fail('No dispatch');}})});
  const prepare=intent=>kind==='effect'?profile.prepareManagedEffectRun(owner,intent):
    profile.prepareManagedContentRun(owner,intent,recipe);
  if(beginFailure===undefined)prepare(request);
  return {profile,request,restored,cause,tuples,prepare,accept(value){requests.add(value);},
    setHandler(value){handler=value;},counts(){return {checks,currents,roots,begins};}};
}

for(const kind of ['effect','content']){
  test(`Local original ${kind} reuse checks the requested tuple once without another current boundary`,async()=>{
    const f=await reuseFixture(kind), before=f.counts();
    f.prepare(f.request);
    const after=f.counts();
    assert.equal(after.checks-before.checks,1);
    assert.equal(after.currents-before.currents,1);
    assert.equal(after.roots,before.roots);assert.equal(after.begins,before.begins);
    assert.strictEqual(f.tuples.at(-1)[2],f.request);
    await f.profile.close();
  });

  test(`Local original ${kind} reuse forwards foreign and explicit absent requests to the original Core binding`,async()=>{
    const f=await reuseFixture(kind);
    for(const request of [{},undefined]){
      const before=f.counts();
      assert.throws(()=>f.prepare(request),error=>error.code==='MoonBitHostFailure'&&error.cause===f.cause);
      const after=f.counts();
      assert.equal(after.checks-before.checks,1);assert.equal(after.currents-before.currents,1);
      assert.strictEqual(f.tuples.at(-1)[2],request);
      assert.equal(after.roots,before.roots);assert.equal(after.begins,before.begins);
    }
    await f.profile.close();
  });

  test(`Local original ${kind} reuse leaves requested-tuple equivalence with the Core owner`,async()=>{
    const f=await reuseFixture(kind);f.accept(f.restored);
    const before=f.counts();f.prepare(f.restored);
    const after=f.counts();
    assert.equal(after.checks-before.checks,1);assert.equal(after.currents-before.currents,1);
    assert.strictEqual(f.tuples.at(-1)[2],f.restored);
    assert.equal(after.roots,before.roots);assert.equal(after.begins,before.begins);
    await f.profile.close();
  });

  test(`Local original ${kind} reuse retains the original current refusal without issuing another Run`,async()=>{
    const f=await reuseFixture(kind), failure=new Error('OriginalManagedCurrentRefused');
    f.setHandler(()=>{throw failure;});
    const before=f.counts();assert.throws(()=>f.prepare(f.request),error=>error===failure);
    const after=f.counts();
    assert.equal(after.checks-before.checks,1);assert.equal(after.currents-before.currents,1);
    assert.equal(after.roots,before.roots);assert.equal(after.begins,before.begins);
    await f.profile.close();
  });

  test(`Local original ${kind} reuse preserves the original partial-begin failure and cleanup`,async()=>{
    const failure=new Error('OriginalManagedBeginFailed'),f=await reuseFixture(kind,{beginFailure:failure});
    assert.throws(()=>f.prepare(f.request),error=>error===failure);
    const before=f.counts();assert.throws(()=>f.prepare(f.request),error=>error===failure);
    const after=f.counts();
    assert.equal(after.checks,before.checks);assert.equal(after.currents-before.currents,1);
    assert.equal(after.roots,before.roots);assert.equal(after.begins,before.begins);
    await f.profile.close();
  });
}
