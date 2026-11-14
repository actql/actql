import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {parse} from 'acorn';
import {bindInstalledManagedSources} from './installed-managed-source.mjs';
import {computePhysicalCapacity} from '../connectors/duckdb/node/physical-capacity.mjs';
import {contentCid} from './local-account-config.mjs';
import {duckDBPhysicalTarget} from './duckdb-physical-target.mjs';
import {validInstallationBinding} from './ordinary-source-binding.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';

test('managed Source Plan selection captures the original declaration method and receiver', () => {
  const selection = Object.freeze({declaration: {}, provider: {}, transferBytes: 1n, executionBytes: 2n});
  const original = {managedCaptureCapacity() {}, prepare() {}, ledgerCapacity() {},
    managedEffectPlanSelection() {assert.strictEqual(this, original); return selection;}};
  const wrapped = bindInstalledManagedSources(original, () => ({}));
  original.managedEffectPlanSelection = () => assert.fail('the later method is not the installing original');
  assert.strictEqual(wrapped.managedEffectPlanSelection(), selection);
});

// Execute the actual Host boundary with explicit nominal service ports. This
// does not supply a native database, Resource admission or physical close ACK.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
function visit(node, select) {
  if (node === null || typeof node !== 'object') return;
  select(node);
  for (const child of Object.values(node)) {
    if (Array.isArray(child)) for (const value of child) visit(value, select);
    else if (child && typeof child === 'object') visit(child, select);
  }
}
// These are the actual loader/binder/publication call sites with explicit
// service ports, not a second Host or a namespace authorization decision.
async function publishLoadedSources(profile) {
  let loading, publication;
  visit(ast, node => {
    if (node.type === 'BlockStatement' && node.body.some(statement =>
      statement.type === 'ExpressionStatement' &&
      statement.expression.type === 'AssignmentExpression' &&
      statement.expression.left.name === 'sourceProfile' &&
      statement.expression.right.type === 'AwaitExpression' &&
      statement.expression.right.argument.callee?.name === 'loadInstalledSources')) loading = node;
    if (node.type === 'AssignmentExpression' && node.left.name === 'sourcePublication' &&
        node.right.callee?.name === 'sourceAliasPublication') publication = node;
  });
  assert(loading && publication);
  return new Function('loadInstalledSources', 'preparation', 'moon', 'sourceAliasPublication', `
    return (async () => {
      let sourceProfile, sourcePublication, sourcePublicationSources;
      const selectedSourcePaths=['/original/source.json'];
      const root='/host', principalId='reader', environment={};
      const runtimeUrl=undefined, baseEnvironmentWire=undefined, resolveSourceSecret=undefined;
      const connectorTable=undefined, installationServices=undefined;
      const installedEffect=undefined, effectInstallation=undefined, environmentWire=undefined;
      const sourceNamespace='queries', sourceSelectorNamespace=undefined;
      ${source.slice(loading.start, loading.end)}
      ${source.slice(publication.start, publication.end)};
      return {execution: sourceProfile, publication: sourcePublication};
    })();
  `)(async () => profile, {bindManagedSources: (_moon, selected) =>
    bindInstalledManagedSources(selected, () => assert.fail('Metadata does not admit a Run'))}, {},
  (_moon, _environment, _aliases, _writes, options) => options.installedSources);
}
for (const plural of [false, true]) {
  test(`Host namespace publication retains loader originals through ${plural ? 'plural' : 'single'} managed binding`, async () => {
    const originals = Array.from({length: plural ? 2 : 1}, () => ({
      managedCaptureCapacity() {}, prepare() {}, ledgerCapacity() {},
    }));
    const profile = plural ? {sources: originals} : originals[0];
    const issuedMetadata = new WeakMap(originals.map(original => [original, {}]));
    const result = await publishLoadedSources(profile);
    const execution = result.execution.sources ?? [result.execution];
    assert.equal(result.publication.length, originals.length);
    for (const [index, original] of originals.entries()) {
      assert.notStrictEqual(execution[index], original);
      assert.strictEqual(result.publication[index], original);
      assert.strictEqual(issuedMetadata.get(result.publication[index]), issuedMetadata.get(original));
    }
  });
}
function admission(preparation, sourceProfile, prepared, request, count, prepareTimedRunInvocation) {
  let declaration, route;
  visit(ast, node => {
    if (node.type === 'VariableDeclaration' && node.declarations.length === 1 &&
        node.declarations[0].id.name === 'admitPreparedSubmission') declaration = node;
    if (node.type === 'VariableDeclaration' && node.declarations.length === 1 &&
        node.declarations[0].id.name === 'prepareOrdinaryManagedRun') route = node;
  });
  const captureRoute=ast.body.find(node=>node.type==='FunctionDeclaration'&&node.id.name==='captureInstalledManagedRunRoute');
  assert(declaration&&route&&captureRoute);
  return new Function('preparation', 'sourceProfile', 'prepared', 'request', 'count', 'prepareTimedRunInvocation', `
    const requestOf=()=>({requested:request,acquisitionCount:count,effectful:false});
    const moon={clientProgramSerializationOccurrences:()=>[]},inferSelections=new WeakMap();
    const admissionFailures=new WeakMap(),holderRefusal=undefined;
    const clientOperationError=code=>Object.assign(new Error(code),{code});
    ${source.slice(captureRoute.start,captureRoute.end)}
    ${source.slice(route.start,route.end)}
    ${source.slice(declaration.start, declaration.end)}
    return admitPreparedSubmission({preparedProgram:prepared});
  `)(preparation, sourceProfile, prepared, request, count, prepareTimedRunInvocation);
}

test('ordinary installed Source admission uses the same generic Host Run service', () => {
  const prepared = {}, request = {}, profile = {sources: [{}, {}]}, calls = [];
  const invocation = () => assert.fail('This Source admission only forwards the original timed constructor');
  const preparation = {
    admitResultPublicationRun(value) {assert.strictEqual(value, prepared); calls.push('publication');},
    prepareManagedSourceRun(runtime, value, requested, selected, originalInvocation) {
      assert.equal(typeof runtime.clientProgramSerializationOccurrences, 'function');
      assert.strictEqual(value, prepared); assert.strictEqual(requested, request);
      assert.strictEqual(selected, profile); assert.strictEqual(originalInvocation, invocation); calls.push('same-source-parent');
    },
  };
  admission(preparation, profile, prepared, request, 2, invocation);
  assert.deepEqual(calls, ['publication', 'same-source-parent']);
});

test('plural Source preparations forward one original parent and retain original methods', async () => {
  const checked = {}, parent = {}, quote = {}, log = [], prepared = [{}, {}];
  const originals = [0, 1].map(index => ({
    managedCaptureCapacity(requirement) {assert.strictEqual(this, originals[index]); return {requirement, capacity: quote};},
    async prepare(facts) {assert.strictEqual(this, originals[index]); assert.strictEqual(facts.preparedProgram, checked);
      log.push(index); return prepared[index];},
    ledgerCapacity(value) {assert.strictEqual(this, originals[index]); assert.strictEqual(value, prepared[index]);
      return {capacity: quote, transferBytes: 7n, executionBytes: 11n};},
  }));
  let current = true;
  const profile = bindInstalledManagedSources({sources: originals}, value => {
    assert.strictEqual(value, checked); if (!current) throw new Error('RetiredOriginal'); return parent;
  });
  originals[0].prepare = originals[0].ledgerCapacity = () => assert.fail('Replaced original method');
  for (let index = 0; index < 2; index++) {
    const result = await profile.sources[index].prepare({preparedProgram: checked});
    assert.strictEqual(result, prepared[index]);
    assert.deepEqual(profile.sources[index].ledgerCapacity(result),
      {capacity: quote, transferBytes: 7n, executionBytes: 11n, managedRun: parent});
  }
  assert.deepEqual(log, [0, 1]);
  assert.throws(() => profile.sources[1].ledgerCapacity(prepared[0]), /ForeignInstalledManagedSource/);
  assert.throws(() => profile.sources[0].ledgerCapacity({...prepared[0]}), /ForeignInstalledManagedSource/);
  current = false;
  assert.throws(() => profile.sources[0].ledgerCapacity(prepared[0]), /RetiredOriginal/);
});

test('Source preparation cannot install a parent association after cancellation during await', async () => {
  const checked = {}, parent = {}, prepared = {}; let current = true, capacities = 0;
  const profile = bindInstalledManagedSources({managedCaptureCapacity() {},
    async prepare() {await Promise.resolve(); current = false; return prepared;},
    ledgerCapacity() {capacities++; return {};},
  }, value => {assert.strictEqual(value, checked); if (!current) throw new Error('CancelledOriginal'); return parent;});
  await assert.rejects(profile.prepare({preparedProgram: checked}), /CancelledOriginal/);
  assert.throws(() => profile.ledgerCapacity(prepared), /ForeignInstalledManagedSource/);
  assert.equal(capacities, 0);
});

test('Source preparation requires the same captured own checked Program across its original await', async () => {
  const original = {}, foreign = {}, parent = {}, prepared = {}; let calls = 0, reads = 0;
  const facts = {preparedProgram: original};
  const profile = bindInstalledManagedSources({managedCaptureCapacity() {},
    async prepare() {calls++; await Promise.resolve(); facts.preparedProgram = foreign; return prepared;},
    ledgerCapacity() {assert.fail('No association may be installed');},
  }, checked => {assert.strictEqual(checked, original); return parent;});
  await assert.rejects(profile.prepare(facts), /ForeignInstalledManagedSource/);
  await assert.rejects(profile.prepare(Object.create({preparedProgram: original})), /ForeignInstalledManagedSource/);
  await assert.rejects(profile.prepare({get preparedProgram() {reads++; return original;}}), /ForeignInstalledManagedSource/);
  assert.equal(calls, 1); assert.equal(reads, 0);
  assert.throws(() => profile.ledgerCapacity(prepared), /ForeignInstalledManagedSource/);
});

test('unmigrated and already managed Sources retain their selected preparation path', () => {
  const legacy = {prepareManagedRun() {}}, missing = {sources: [{managedCaptureCapacity() {}}, {}]};
  const forbidden = () => assert.fail('No alternate parent may be issued');
  assert.strictEqual(bindInstalledManagedSources(legacy, forbidden), legacy);
  assert.strictEqual(bindInstalledManagedSources(missing, forbidden), missing);
  assert.strictEqual(bindInstalledManagedSources(undefined, forbidden), undefined);
});

test('Source reauthorization preserves its original read and refuses foreign, concurrent and retired preparations', async () => {
  const text = readFileSync(new URL('./installed-row-source.mjs', import.meta.url), 'utf8');
  let node;
  visit(parse(text, {ecmaVersion: 'latest', sourceType: 'module'}), candidate => {
    if (candidate.type === 'FunctionDeclaration' && candidate.id?.name === 'prepare') node = candidate;
  });
  assert(node);
  // Execute the actual authority-transition boundary with explicit nominal
  // ports. Public recovery separately exercises the real Core and Site.
  const prepared = {}, program = {}, request = {}, run = {}, read = {}, access = {};
  const occurrence = {stage: 0, input: 0, task: 0};
  const original = Object.freeze({checkedOwner: program, requestIdentity: request,
    managedRun: run, originalRead: read, occurrence, effectful: false, access: {}});
  const preparations = new WeakMap([[prepared, original]]), pending = new Set([read]);
  let current = async () => {}, checks = 0;
  const ports = {immutableTargets: undefined, physicalTargetGeneration: undefined, directReadIdentity: undefined,
    preparations, preparingSourceReads: pending, reauthorizingPreparations: new WeakSet(),
    checked: value => value, fail: code => {throw new Error(code);},
    ordinaryRecoveryBinding(value) {assert.equal(value, prepared);},
    moon: {clientProgramInstalledSourceReadCheckCurrent(value) {assert.equal(value, read); checks++;}},
    currentRead(value, selected) {assert.equal(value, prepared); assert.equal(selected, access); return current();}};
  const prepare = new Function(...Object.keys(ports), `return ${text.slice(node.start, node.end)};`)(...Object.values(ports));
  const facts = {preparedProgram: program, requestIdentity: request, managedRun: run,
    preparedSource: prepared, sourceAccess: access, occurrence};
  assert.equal(await prepare(facts), prepared);
  const updated = preparations.get(prepared);
  assert.equal(updated.originalRead, read);
  assert.equal(updated.access, access);
  assert.equal(checks, 2, 'the same Core read is current before and after authorization');
  for (const changed of [{preparedSource: {...prepared}}, {preparedProgram: {}},
    {requestIdentity: {}}, {managedRun: {}}, {occurrence: {stage: 1, input: 0, task: 1}}]) {
    await assert.rejects(prepare({...facts, ...changed}), /InstalledSourcePreparationMismatch/);
  }
  const denied = new Error('same authority refusal');
  current = async () => {throw denied;};
  await assert.rejects(prepare(facts), error => error === denied);
  assert.equal(preparations.get(prepared), updated);
  let release;
  current = () => new Promise(resolve => {release = resolve;});
  const awaiting = prepare(facts);
  await assert.rejects(prepare(facts), /InstalledSourcePreparationMismatch/);
  pending.delete(read);
  release();
  await assert.rejects(awaiting, /InstalledSourcePreparationMismatch/);
  assert.equal(preparations.get(prepared), updated, 'retirement cannot revive the original preparation');
});

test('managed Source view preserves original physical and plural method receivers without changing their returns', () => {
  const child = {}, close = Promise.resolve({pending: true}), capture = {}, source = {
    managedCaptureCapacity() {}, prepare() {}, ledgerCapacity() {},
    open(value) {assert.strictEqual(this, source); assert.strictEqual(value, child); return child;},
    close() {assert.strictEqual(this, source); return close;},
    retainedCapture(value) {assert.strictEqual(this, source); assert.strictEqual(value, child); return capture;},
    admitsSource(value) {assert.strictEqual(this, source); return value === 'original';},
    retirePreparedSource(value) {assert.strictEqual(this, source); assert.strictEqual(value, child); return child;},
  };
  const profile = {sources: [source], close() {assert.strictEqual(this, profile); return close;},
    admitsSource(value) {assert.strictEqual(this, profile); return value === 'plural';}};
  const view = bindInstalledManagedSources(profile, () => assert.fail('Method forwarding does not issue a parent'));
  for (const name of ['open', 'close', 'retainedCapture', 'admitsSource', 'retirePreparedSource']) source[name] = () => assert.fail('Replaced child method');
  profile.close = profile.admitsSource = () => assert.fail('Replaced plural method');
  assert.strictEqual(view.sources[0].open(child), child);
  assert.strictEqual(view.sources[0].close(), close);
  assert.strictEqual(view.sources[0].retainedCapture(child), capture);
  assert.equal(view.sources[0].admitsSource('original'), true);
  assert.strictEqual(view.sources[0].retirePreparedSource(child), child);
  assert.strictEqual(view.close(), close);
  assert.equal(view.admitsSource('plural'), true);
});

test('DuckDB quotes its actual pending capture and physical transport without selecting or reading it', async () => {
  const text = readFileSync(new URL('./installed-duckdb-source.mjs', import.meta.url), 'utf8');
  const syntax = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
  const node = syntax.body.find(node => node.type === 'ExportNamedDeclaration' &&
    node.declaration?.type === 'FunctionDeclaration' && node.declaration.id.name === 'createInstalledDuckDBSource')?.declaration;
  assert(node);
  const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
  const requirement = {}, pending = {}, capacity = {}, calls = [];
  const authorization = Object.freeze({close() {assert.equal(this,authorization);calls.push('authorization-close');return true;}});
  const profile = {database: '/never-opened.duckdb', schema: 'main', table: 'four_rows', sourceRef: 'source:rows',
    environmentWire: '{"connector_catalogs":[]}',sourceAccess:{authorization}, transportLimits: {maxRows: 4, maxCells: 4,
      maxTransportBytes: 1024, maxSqlBytes: 4096, maxParameters: 0, maxColumns: 1, memoryBytes: 1048576, threads: 1}};
  const moon = {
    clientProgramQueryRequirementSourceRef(value) {return value === requirement ? profile.sourceRef : 'source:foreign';},
    clientProgramPrepareDuckDBCaptureCapacity(value, schema, table, ...contracts) {
      assert.strictEqual(value, requirement); assert.equal(schema, 'main'); assert.equal(table, 'four_rows');
      assert.deepEqual(contracts.map(body => JSON.parse(body).version),
        ['actql-query-acquisition-contract/0.1', 'actql-query-process-evidence-contract/0.1', 'actql-query-two-receipt-contract/0.1']);
      calls.push('pending'); return pending;
    },
    clientProgramInstalledPendingDuckDBCaptureCapacity(value) {assert.strictEqual(value, pending); calls.push('typed-capacity'); return capacity;},
  };
  const create = await new AsyncFunction('loadDuckDBNativeRuntime', 'readFile', 'checked',
    'computePhysicalCapacity', 'importMetaUrl', 'contentCid', 'duckDBPhysicalTarget',
    text.slice(node.start, node.end).replaceAll('import.meta.url', 'importMetaUrl') + ';return createInstalledDuckDBSource;')(
    async () => {}, readFile, value => value, computePhysicalCapacity, new URL('./installed-duckdb-source.mjs', import.meta.url).href,
    contentCid, duckDBPhysicalTarget);
  const adapter = await create(profile, moon, {root: '/unused', principalId: 'original'});
  const selection = adapter.managedEffectPlanSelection();
  const native = selection.nativeSource;
  assert.deepEqual([native.sourceRef, native.schema, native.table],
    [profile.sourceRef, profile.schema, profile.table]);
  assert(Object.isFrozen(selection)); assert(Object.isFrozen(native)); assert(Object.isFrozen(native.contracts));
  assert.deepEqual(native.contracts.map(body => JSON.parse(body).version),
    ['actql-query-acquisition-contract/0.1', 'actql-query-process-evidence-contract/0.1', 'actql-query-two-receipt-contract/0.1']);
  assert.equal(Object.hasOwn(selection, 'declaration'), false);
  assert.equal(Object.hasOwn(selection, 'provider'), false);
  assert.deepEqual(calls, [], 'selecting inert native inputs prepares no Query or capture');
  const result = adapter.managedCaptureCapacity(requirement), physical = computePhysicalCapacity(profile.transportLimits);
  assert.deepEqual([selection.transferBytes, selection.executionBytes], [physical.transferBytes, physical.executionBytes]);
  assert.deepEqual(result, {capacity, transferBytes: physical.transferBytes, executionBytes: physical.executionBytes});
  assert.deepEqual(calls, ['pending', 'typed-capacity']);
  assert.throws(() => adapter.managedCaptureCapacity({}), /InstalledSourceProgramMismatch/);
  assert.deepEqual(calls, ['pending', 'typed-capacity']);
  adapter.close();
  assert.deepEqual(calls, ['pending','typed-capacity','authorization-close']);
  assert.throws(() => adapter.managedCaptureCapacity(requirement), /InstalledSourceReaderNotCurrent/);
  assert.throws(() => adapter.managedEffectPlanSelection(), /InstalledSourceReaderNotCurrent/);
});


test('DuckDB bound recovery keeps the original preparation and selected installation', async () => {
  const text = readFileSync(new URL('./installed-duckdb-source.mjs', import.meta.url), 'utf8');
  const syntax = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
  const node = syntax.body.find(node => node.declaration?.id?.name === 'createInstalledDuckDBSource').declaration;
  const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
  const view = `sha256:${'a'.repeat(64)}`, authorization = {close() {return true;}};
  const profile = {database: '/never-opened.duckdb', schema: 'main', table: 'records',
    sourceRef: 'connector://fixture/records#v', sourceAccess: {authorization},
    environmentWire: JSON.stringify({connector_catalogs: [{connector_id: 'fixture',
      source_views: [{contract_cid: view}]}]})};
  const installation = Object.freeze({registration: 'builtin_source', revision: 'builtin_source/0.1'});
  const parent = {}, preparedProgram = {}, preparedEffect = {}, request = {}, requirement = {}, capacity = {};
  let next, getters = 0, effectGetters = 0, prepares = 0, originalIssue, forwardedCapture, forwardedContracts;
  const moon = {clientProgramInstalledManagedDuckDBCapture(run, program, identity, task) {
    assert.equal(this, moon); assert.equal(run, parent); assert.equal(program, preparedProgram);
    assert.equal(identity, request); assert.equal(task, 1); getters++; return {_0: requirement, _1: capacity};
  }, clientProgramInstalledEffectManagedDuckDBCapture(run, program, identity, task) {
    assert.equal(this, moon); assert.equal(run, parent); assert.equal(program, preparedEffect);
    assert.equal(identity, request); assert.equal(task, 1); effectGetters++;
    if (originalIssue !== undefined) throw originalIssue;
    return {_0: requirement, _1: capacity};
  }};
  const create = await new AsyncFunction('loadDuckDBNativeRuntime', 'readFile', 'checked',
    'contentCid', 'duckDBPhysicalTarget', 'validInstallationBinding', 'prepareCapturedDuckDBSource',
    'runtimeField', 'importMetaUrl', text.slice(node.start, node.end).replaceAll('import.meta.url', 'importMetaUrl') +
      ';return createInstalledDuckDBSource;')(async () => {}, readFile, value => value,
    contentCid, duckDBPhysicalTarget, validInstallationBinding, async options => {
      prepares++; forwardedCapture = options.originalCapture; forwardedContracts = options.originalContracts; return next;
    }, runtimeField,
    new URL('./installed-duckdb-source.mjs', import.meta.url).href);
  const adapter = await create(profile, moon, {root: '/same-root', principalId: 'same-principal', installation});
  next = Object.freeze({physicalBinding: duckDBPhysicalTarget(profile),
    checkedSource: Object.freeze({sourceRef: profile.sourceRef, sourceViewContractCid: view})});
  const prepared = await adapter.prepare({}), binding = adapter.ordinaryRecoveryBinding(prepared);
  assert.equal(validInstallationBinding(binding), true);
  assert.equal(binding.connectorId, 'fixture');
  assert.equal(binding.connectorRegistration, installation.registration);
  assert.equal(binding.connectorRevision, installation.revision);
  assert.equal(binding.bindingCid, adapter.connectorBindings[0].bindingCid);
  assert.equal(adapter.ordinaryRecoveryBinding(prepared), binding);
  assert.equal(forwardedCapture, undefined);
  const originalContracts = forwardedContracts;
  assert.equal(Object.isFrozen(originalContracts), true);
  assert.deepEqual(originalContracts.map(body => JSON.parse(body).version),
    ['actql-query-acquisition-contract/0.1', 'actql-query-process-evidence-contract/0.1', 'actql-query-two-receipt-contract/0.1']);
  assert.throws(() => adapter.ordinaryRecoveryBinding({...prepared}), /InstalledSourcePreparationMismatch/);
  await adapter.prepare({preparedProgram, requestIdentity: request, managedRun: parent, occurrence: {task: 1}});
  assert.equal(getters, 1);
  assert.equal(forwardedCapture.requirement, requirement);
  assert.equal(forwardedCapture.capacity, capacity);
  assert.equal(forwardedContracts, originalContracts);
  await adapter.prepare({preparedEffect, requestIdentity: request, managedRun: parent, occurrence: {task: 1}});
  assert.equal(effectGetters, 1); assert.equal(getters, 1);
  assert.equal(forwardedCapture.requirement, requirement);
  assert.equal(forwardedCapture.capacity, capacity);
  assert.equal(forwardedContracts, originalContracts);
  assert.equal(prepares, 3);
  originalIssue = new TypeError('ForeignOriginal');
  await assert.rejects(adapter.prepare({preparedEffect, requestIdentity: request,
    managedRun: parent, occurrence: {task: 1}}), error => error === originalIssue);
  assert.equal(prepares, 3, 'refused original never falls back to a fresh Query or physical preparation');
  await assert.rejects(adapter.prepare({preparedProgram, preparedEffect, requestIdentity: request,
    managedRun: parent, occurrence: {task: 1}}), /InstalledSourcePreparationMismatch/);
  const other = await create(profile, {}, {root: '/same-root', principalId: 'same-principal', installation});
  await assert.rejects(other.prepare({preparedEffect, requestIdentity: request,
    managedRun: parent, occurrence: {task: 1}}), /InstalledSourcePreparationMismatch/);
  assert.equal(prepares, 3);
  assert.throws(() => other.ordinaryRecoveryBinding(prepared), /InstalledSourcePreparationMismatch/);
  adapter.close();
  assert.throws(() => adapter.ordinaryRecoveryBinding(prepared), /InstalledSourceReaderNotCurrent/);
  other.close();
});

function hostManagedSources(onCheck = () => {}, inputField = 'preparedProgram') {
  let method;
  visit(ast, node => {
    if (node.type === 'Property' && node.method && node.key.name === 'bindManagedSources') method = node;
  });
  assert(method);
  const runtime = {}, checkedProgram = {}, parent = {}, request = {}, preparedSource = {};
  const record = {computeRuns: new WeakMap()}, originalInstallation = {};
  let preparations = 0, capacities = 0;
  const provider = {
    managedCaptureCapacity() {},
    async prepare(facts) {
      assert.strictEqual(this, provider); assert.strictEqual(facts[inputField], checkedProgram);
      preparations++; return preparedSource;
    },
    ledgerCapacity(value) {
      assert.strictEqual(this, provider); assert.strictEqual(value, preparedSource);
      capacities++; return {capacity: 'original-capacity'};
    },
  };
  const bind = new Function('moon', 'record', 'originalInstallation', 'bindInstalledManagedSources', `
    const clientOperationError=code=>Object.assign(new Error(code),{code});
    const checked=value=>value;
    return {${source.slice(method.start, method.end)}}.bindManagedSources;
  `)(runtime, record, originalInstallation, bindInstalledManagedSources);
  const selected = bind(runtime, provider);
  const run = {runtime, prepared: checkedProgram, sourceProfile: selected, request, value: parent,
    check(value, program, input) {
      assert.strictEqual(this, runtime); assert.strictEqual(value, parent);
      assert.strictEqual(program, checkedProgram); assert.strictEqual(input, request);
      onCheck({record, run, checkedProgram});
    }};
  record.computeRuns.set(checkedProgram, run);
  return {selected, checkedProgram, parent, preparedSource, run,
    counts: () => ({preparations, capacities})};
}

test('Host Source current callback cannot retire or replace its original parent before preparation', async () => {
  const changes = [
    ({run}) => {run.closed = true;},
    ({record, checkedProgram}) => {record.computeRuns.delete(checkedProgram);},
    ({record, run, checkedProgram}) => {record.computeRuns.set(checkedProgram, {...run});},
    ({run}) => {run.value = {};},
    ({run}) => {run.runtime = {};},
    ({run}) => {run.prepared = {};},
    ({run}) => {run.sourceProfile = {};},
  ];
  for (const change of changes) {
    const original = hostManagedSources(change);
    await assert.rejects(original.selected.prepare({preparedProgram: original.checkedProgram}),
      {code: 'ForeignInstalledSourcePreparation'});
    assert.deepEqual(original.counts(), {preparations: 0, capacities: 0});
  }
});

test('Host Source capacity lookup rechecks the original parent after its current callback', async () => {
  let retire = false;
  const original = hostManagedSources(({run}) => {if (retire) run.closed = true;});
  const prepared = await original.selected.prepare({preparedProgram: original.checkedProgram});
  assert.strictEqual(prepared, original.preparedSource);
  assert.strictEqual(original.selected.ledgerCapacity(prepared).managedRun, original.parent);
  assert.deepEqual(original.counts(), {preparations: 1, capacities: 1});
  retire = true;
  assert.throws(() => original.selected.ledgerCapacity(prepared), {code: 'ForeignInstalledSourcePreparation'});
  assert.deepEqual(original.counts(), {preparations: 1, capacities: 1});
});

test('Host Source current callback preserves the original newly recorded failure before preparation', async () => {
  const failure = new Error('OriginalCurrentFailure');
  const original = hostManagedSources(({run}) => {run.failure = failure;});
  await assert.rejects(original.selected.prepare({preparedProgram: original.checkedProgram}), error => error === failure);
  assert.deepEqual(original.counts(), {preparations: 0, capacities: 0});
});

// This is the real selected Source wrapper, with explicit nominal Run/service
// ports only. No second Ledger, physical reader or cleanup ACK is fabricated.
test('Pure Source preparation receives its same original managed Run before reader construction', async () => {
  const program = {}, originalRun = {}, selected = {}, calls = [];
  const facts = {preparedProgram: program, requestIdentity: {}};
  const source = {
    managedCaptureCapacity() {},
    async prepare(input) {
      assert.strictEqual(this, source);
      assert.strictEqual(input.preparedProgram, program);
      assert.strictEqual(input.requestIdentity, facts.requestIdentity);
      assert.strictEqual(input.managedRun, originalRun);
      calls.push('same-original-reader');
      return selected;
    },
    ledgerCapacity(value) {assert.strictEqual(this, source); assert.strictEqual(value, selected); return {};},
  };
  const bound = bindInstalledManagedSources(source, owner => {
    assert.strictEqual(owner, program); return originalRun;
  });
  assert.strictEqual(await bound.prepare(facts), selected);
  assert.deepEqual(calls, ['same-original-reader']);
  assert.strictEqual(bound.ledgerCapacity(selected).managedRun, originalRun);
});

test('Source reader facts retain one frozen original Run and method receiver for both compiler roles', async () => {
  for (const role of ['preparedProgram', 'preparedEffect']) {
    const owner = {}, run = {}, foreign = {}, prepared = {}; let calls = 0;
    const source = {managedCaptureCapacity() {},
      async prepare(facts) {
        assert.strictEqual(this, source); assert.equal(Object.isFrozen(facts), true);
        assert.strictEqual(facts[role], owner); assert.strictEqual(facts.managedRun, run);
        calls++; return prepared;
      }, ledgerCapacity() {return {};}};
    const bound = bindInstalledManagedSources(source, selected => {
      assert.strictEqual(selected, owner); return run;
    });
    source.prepare = () => assert.fail('Replaced provider callback is not an original');
    const facts = {[role]: owner, managedRun: foreign};
    assert.strictEqual(await bound.prepare(facts), prepared);
    assert.strictEqual(facts.managedRun, foreign);
    assert.strictEqual(bound.ledgerCapacity(prepared).managedRun, run);
    assert.equal(calls, 1);
  }
});

// Same actual Host selector as the Pure controls above. The selected Effect
// record carries its original bound Plan getter rather than a Pure check.
// Explicit service ports only; not Resource funding or ordinary acceptance.
test('Host Effect Source uses its original bound Plan getter without a Pure check', async () => {
  const f = hostManagedSources();
  const plan = {};
  let reads = 0;
  f.run.preparationKind = 'effect-plan';
  f.run.operationPlan = plan;
  delete f.run.check;
  f.run.readPlan = function(parent, prepared, request) {
    assert.strictEqual(this, f.run.runtime);
    assert.strictEqual(parent, f.parent);
    assert.strictEqual(prepared, f.checkedProgram);
    assert.strictEqual(request, f.run.request);
    reads++; return plan;
  };
  const source = await f.selected.prepare({preparedProgram: f.checkedProgram});
  assert.strictEqual(source, f.preparedSource);
  assert.equal(reads, 2, 'One getter before and one after the actual provider await');
  assert.strictEqual(f.selected.ledgerCapacity(source).managedRun, f.parent);
  assert.equal(reads, 3, 'One getter for the separate capacity read boundary');
});

for (const change of ['foreign-plan', 'replace-plan', 'replace-getter', 'replace-request', 'retire', 'failure']) {
  test(`Host Effect Source refuses ${change} at the same Plan getter boundary`, async () => {
    const f = hostManagedSources();
    const plan = {}, failure = new Error('OriginalEffectCurrentFailure');
    f.run.preparationKind = 'effect-plan'; f.run.operationPlan = plan;
    delete f.run.check;
    f.run.readPlan = function() {
      if (change === 'replace-plan') f.run.operationPlan = {};
      if (change === 'replace-getter') f.run.readPlan = () => plan;
      if (change === 'replace-request') f.run.request = {};
      if (change === 'retire') f.run.closed = true;
      if (change === 'failure') f.run.failure = failure;
      return change === 'foreign-plan' ? {} : plan;
    };
    await assert.rejects(f.selected.prepare({preparedEffect: f.checkedProgram}),
      error => change === 'failure' ? error === failure
        : error.code === 'ForeignInstalledSourcePreparation');
    assert.deepEqual(f.counts(), {preparations: 0, capacities: 0});
  });
}

test('Host Effect Source actual preparedEffect field retains the same Plan parent across provider await', async () => {
  const f = hostManagedSources(() => {}, 'preparedEffect'), plan = {};
  f.run.preparationKind = 'effect-plan'; f.run.operationPlan = plan;
  delete f.run.check;
  let reads = 0;
  f.run.readPlan = () => {reads++; return plan;};
  const original = await f.selected.prepare({preparedEffect: f.checkedProgram});
  assert.strictEqual(original, f.preparedSource);
  assert.equal(reads, 2);
  assert.strictEqual(f.selected.ledgerCapacity(original).managedRun, f.parent);
  assert.equal(reads, 3);
  assert.deepEqual(f.counts(), {preparations: 1, capacities: 1});
});


test('explicit Effect Host selects the same installed Site for its existing managed Plan callback', () => {
  let declaration;
  visit(ast, node => {if (node.type === 'FunctionDeclaration' && node.id?.name === 'selectedInstalledEffect') declaration = node;});
  assert(declaration);
  const prepared = {}, compilation = {}, plan = {}, calls = [];
  const original = Object.freeze({prepareManagedPlan() {return plan;}});
  const select = new Function('installedEffect', 'effectInstallation', 'updateTargetOriginals',
    'validateInstalledUpdateOwnerSelections', source.slice(declaration.start, declaration.end) + '\nreturn selectedInstalledEffect;')(
    undefined, original, undefined, (installation, selections, actual) => {
      assert.strictEqual(installation, original); assert.equal(selections, undefined);
      assert.strictEqual(actual, prepared); calls.push('same-owner-selection');
    });
  assert.strictEqual(select({prepared, compilation}), original);
  assert.deepEqual(calls, ['same-owner-selection']);
  assert.strictEqual(original.prepareManagedPlan(), plan);
});

test('dispatch retains an unreturned original Source preparation after physical cleanup', () => {
  const text = readFileSync(new URL('./client-dispatch-owner.mjs', import.meta.url), 'utf8');
  const syntax = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
  const functions = [];
  visit(syntax, node => {
    if (node.type === 'FunctionDeclaration' && ['retirementReady', 'retire'].includes(node.id.name)) functions.push(node);
  });
  assert.deepEqual(functions.map(node => node.id.name).sort(), ['retire', 'retirementReady']);
  // Keep the actual readiness predicate in the same scope as its caller.
  const declarations = functions.map(node => text.slice(node.start, node.end)).join('\n');
  let returns = 0;
  const entry = {settled: true, physicalStarted: false,
    sourcePreparations: [{original: 'same unreturned preparation'}],
    retirePreparation() {returns++;}};
  const entries = new Map([['original', entry]]);
  const retire = new Function('entries', 'keyOf',
    declarations + ';return retire;')(entries, () => 'original');
  retire(entry);
  assert.equal(returns, 0);
  assert.equal(entries.get('original'), entry);
  entry.sourcePreparations = undefined;
  retire(entry);
  assert.equal(returns, 1);
  assert.equal(entries.size, 0);
});

test('managed Source capture-only entry retains its original method and receiver', () => {
  const facts = {}, capture = {};
  const original = {managedCaptureCapacity() {}, prepare() {}, ledgerCapacity() {},
    openCapture(actual) {assert.strictEqual(this, original); assert.strictEqual(actual, facts); return capture;}};
  const wrapped = bindInstalledManagedSources(original, () => ({}));
  original.openCapture = () => assert.fail('a later function cannot replace the original capture entry');
  assert.strictEqual(wrapped.openCapture(facts), capture);
});


test('retained Source metadata forwards distinct original readonly and capture methods without a fresh Run lookup', () => {
  const facts = {}, metadata = {};
  const original = {managedCaptureCapacity() {}, prepare() {}, ledgerCapacity() {},
    prepareRetained(actual) {assert.equal(this, original); assert.equal(actual, facts); return metadata;},
    prepareRetainedCapture(actual) {assert.equal(this, original); assert.equal(actual, facts); return capture;}};
  const capture = {};
  const wrapped = bindInstalledManagedSources(original, () => assert.fail('No fresh ManagedRun for saved input'));
  original.prepareRetained = () => assert.fail('Use the captured original readonly method');
  assert.equal(wrapped.prepareRetained(facts), metadata);
  original.prepareRetainedCapture = () => assert.fail('Use the captured original restoration method');
  assert.equal(wrapped.prepareRetainedCapture(facts), capture);
  assert.throws(() => wrapped.ledgerCapacity(metadata), /ForeignInstalledManagedSource/u);
});

test('DuckDB readonly metadata and explicit retained capture keep original bindings without acquisition', async () => {
  const {prepareRetainedCapturedDuckDBSource, capturedDuckDBRequirement, openCapturedDuckDBSource} = await import('./captured-duckdb-source.mjs');
  const text = readFileSync(new URL('./installed-duckdb-source.mjs', import.meta.url), 'utf8');
  const node = parse(text, {ecmaVersion: 'latest', sourceType: 'module'}).body.find(node =>
    node.declaration?.type === 'FunctionDeclaration' && node.declaration.id.name === 'createInstalledDuckDBSource').declaration;
  const program = {}, request = {}, requirement = {}, occurrence = Object.freeze({stage: 3, input: 1, task: 0});
  let requirements = 0, capacities = 0;
  const pendingCapture = {}, captureCapacity = {};
  const profile = {database: '/UNOPENED/readonly.duckdb', schema: 'main', table: 'records', sourceRef: 'source:records',
    environmentWire: JSON.stringify({connector_catalogs: [{connector_id: 'fixture', source_views: [{contract_cid: 'view'}]}]}),
    transportLimits: {maxRows: 4, maxCells: 4, maxTransportBytes: 1024, maxSqlBytes: 4096,
      maxParameters: 0, maxColumns: 1, memoryBytes: 1048576, threads: 1},
    sourceAccess: {sourceRef: 'source:records', connection: 'original', resource: '/UNOPENED/readonly.duckdb',
      authorization: Object.freeze({close() {return true;}, authorize() {assert.fail('No new authorization');}})}};
  const moon = {
    clientProgramMatchesRequestIdentity: (p, r) => p === program && r === request,
    clientProgramQueryRequirementSourceRef(value) {assert.equal(value, requirement); return profile.sourceRef;},
    clientProgramPrepareDuckDBCaptureCapacity(value, schema, table, ...contracts) {
      assert.equal(value, requirement); assert.deepEqual([schema, table], [profile.schema, profile.table]);
      assert.equal(contracts.length, 3); assert(contracts.every(value => typeof value === 'string'));
      capacities++; return {$tag: 1, _0: pendingCapture};
    },
    clientProgramInstalledPendingDuckDBCaptureCapacity(value) {
      assert.equal(value, pendingCapture); return captureCapacity;
    },
    clientProgramPrepareLocalQueryRequirement(p, stage, input, ...contracts) {
      assert.equal(p, program); assert.deepEqual([stage, input], [3, 1]);
      assert.deepEqual(contracts, ['registry', 'values', 'fragment', 'ordered']); requirements++; return {$tag: 1, _0: requirement};
    },
    clientProgramQueryRequirementSourceEvidenceFacts: r => {assert.equal(r, requirement); return {$tag: 1, _0: [profile.sourceRef, 'contract', 'schema', 'policy', 'internal', 'view']};},
    clientProgramQueryRequirementCid: () => 'requirement', clientProgramQueryRequirementInputContractCid: () => 'input',
    clientProgramQueryRequirementOutputContractCid: () => 'output',
  };
  const ports = {loadDuckDBNativeRuntime() {}, readFile, contentCid, duckDBPhysicalTarget,
    validInstallationBinding, prepareRetainedCapturedDuckDBSource, capturedDuckDBRequirement,
    computePhysicalCapacity, checked: value => {assert.equal(value.$tag, 1); return value._0;}};
  const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
  const create = await new AsyncFunction(...Object.keys(ports), 'importMetaUrl',
    text.slice(node.start, node.end).replaceAll('import.meta.url', 'importMetaUrl') + ';return createInstalledDuckDBSource;')
    (...Object.values(ports), new URL('./installed-duckdb-source.mjs', import.meta.url).href);
  const adapter = await create(profile, moon, {root: '/UNOPENED/Host', principalId: 'principal',
    installation: {registration: 'fixture', revision: 'original'}});
  const facts = {preparedProgram: program, requestIdentity: request, occurrence,
    registry: 'registry', values: 'values', fragment: 'fragment', ordered: 'ordered'};
  assert.throws(() => adapter.prepareRetained({...facts, requestIdentity: {}}), /InstalledSourcePreparationMismatch/u);
  const prepared = adapter.prepareRetained(facts);
  assert.equal(requirements, 1); assert.equal(prepared.selection, undefined);
  assert.deepEqual(prepared.physicalBinding, duckDBPhysicalTarget(profile));
  assert.deepEqual(prepared.occurrence, occurrence); assert(Object.isFrozen(prepared.physicalPolicy));
  const binding = adapter.ordinaryRecoveryBinding(prepared); assert(validInstallationBinding(binding));
  assert.equal(binding.connectorRevision, 'original');
  assert.throws(() => adapter.ordinaryRecoveryBinding({...prepared}), /InstalledSourcePreparationMismatch/u);
  assert.throws(() => adapter.retainedCapture(prepared), /InstalledSourcePreparationMismatch/u);
  assert.equal(capacities, 0, 'Readonly metadata does not construct a capture capacity');
  assert.throws(() => adapter.prepareRetainedCapture({...facts, requestIdentity: {}}), /InstalledSourcePreparationMismatch/u);
  assert.equal(capacities, 0);
  const restored = adapter.prepareRetainedCapture(facts);
  assert.notEqual(restored, prepared); assert.equal(requirements, 2); assert.equal(capacities, 1);
  assert.deepEqual(adapter.retainedCapture(restored), {requirement, capacity: captureCapacity});
  await assert.rejects(openCapturedDuckDBSource({moon, preparedProgram: program, preparedSource: restored,
    requestIdentity: request, occurrence, registry: 'registry', values: 'values', fragment: 'fragment', ordered: 'ordered',
    database: profile.database, schema: profile.schema, table: profile.table, sourceAccess: profile.sourceAccess,
    transportLimits: profile.transportLimits}), error => error.cause?.message === 'InstalledSourcePreparationMismatch');
  assert.deepEqual(adapter.ordinaryRecoveryBinding(restored), adapter.ordinaryRecoveryBinding(prepared));
  assert.throws(() => adapter.retainedCapture(prepared), /InstalledSourcePreparationMismatch/u);
  adapter.close();
  assert.throws(() => adapter.ordinaryRecoveryBinding(prepared), /InstalledSourceReaderNotCurrent/u);
  assert.throws(() => adapter.prepareRetained(facts), /InstalledSourceReaderNotCurrent/u);
  assert.throws(() => adapter.prepareRetainedCapture(facts), /InstalledSourceReaderNotCurrent/u);
  assert.equal(capacities, 1);
});

test('common row Source publication retains its readonly metadata and retirement entries', async () => {
  const {types} = await import('node:util');
  const source = readFileSync(new URL('./installed-row-source.mjs', import.meta.url), 'utf8');
  const begin = source.indexOf('  let selectedSurface;'), end = source.indexOf('  let publicationFields', begin);
  const select = new Function('publicationSurface', 'nodeTypes', 'fail', source.slice(begin, end) + ';return selectedSurface;');
  const required = ['realizationKey','supportsRetainedRelationOutput','connectorRegistration','connectorRevision',
    'environmentWire','connectorBindings','readAuthorization','sourceAccess','sourceReadAccesses',
    'admitsSource','ledgerCapacity','prepare','open','close'];
  const original = Object.freeze(required);
  assert.deepEqual(select(original, types, code => {throw new Error(code);}), [...required, 'retirePreparedSource', 'prepareRetained']);
  assert.deepEqual(original, required, 'Do not mutate the original provider DATA selection');
});

test('DuckDB readonly and held-read preparations share their checked target and policy descriptor', async () => {
  const {prepareRetainedCapturedDuckDBSource, prepareCapturedDuckDBSource,
    capturedDuckDBConfiguration, capturedDuckDBPhysicalCapacity} = await import('./captured-duckdb-source.mjs');
  const program = {}, identity = {}, requirement = {};
  let authorizations = 0;
  const sourceAccess = {sourceRef: 'source:original', connection: 'original', resource: '/UNOPENED/rows.duckdb',
    authorization: {async authorize() {authorizations++; return {action: 'waiting'};}}};
  const moon = {
    clientProgramMatchesRequestIdentity: (p, r) => p === program && r === identity,
    clientProgramPrepareQueryAcquisition: () => ({$tag: 1, _0: {}}),
    clientProgramPrepareLocalQueryRequirement: () => ({$tag: 1, _0: requirement}),
    clientProgramQueryRequirementSourceEvidenceFacts: () => ({$tag: 1, _0: [sourceAccess.sourceRef, 'contract', 'schema', 'policy', 'internal', 'view']}),
    clientProgramQueryRequirementCid: () => 'requirement', clientProgramQueryRequirementInputContractCid: () => 'input',
    clientProgramQueryRequirementOutputContractCid: () => 'output',
    clientProgramPrepareDuckDBSourceEvidenceContext: () => ({$tag: 1, _0: {}}),
    clientProgramPrepareDuckDBCaptureCapacity: () => ({$tag: 1, _0: {}}),
  };
  const options = {moon, preparedProgram: program, requestIdentity: identity, sourceAccess,
    registry: {}, values: 'values', fragment: 'fragment', ordered: 'ordered',
    database: '/UNOPENED/rows.duckdb', schema: 'main', table: 'records', occurrence: {stage: 0, input: 0, task: 0},
    transportLimits: {maxRows: 4, maxCells: 4, maxTransportBytes: 1024, maxSqlBytes: 4096,
      maxParameters: 0, maxColumns: 1, memoryBytes: 1048576, threads: 1}};
  const retained = prepareRetainedCapturedDuckDBSource(options);
  assert.equal(authorizations, 0);
  assert.throws(() => capturedDuckDBConfiguration(retained), /InstalledSourceSelectionRequired/u);
  assert.throws(() => capturedDuckDBPhysicalCapacity(retained), /InstalledSourcePreparationMismatch/u);
  const original = await prepareCapturedDuckDBSource(options);
  assert.deepEqual(retained, original, 'The same immutable descriptor rules apply to both purposes');
  assert.equal(authorizations, 1, 'Only ordinary held-read preparation observes authorization');
});
