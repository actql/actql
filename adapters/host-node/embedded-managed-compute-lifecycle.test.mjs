import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {installedHostShutdown} from './embedded-local-lifecycle.mjs';
import {bindInstalledManagedSources} from './installed-managed-source.mjs';
import {finishInstalledEffectModelScope, prepareInstalledEffectManagedPlanRun} from './installed-effect-managed-run.mjs';

// Selected actual Host statements/methods with explicit original ports. These
// counters prove consumer order/custody, not physical admission or a full Host.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const declared = name => {
  const matches = ast.body.map(node => node.type === 'ExportNamedDeclaration' ? node.declaration : node)
    .filter(node => node?.type === 'FunctionDeclaration' && node.id.name === name);
  assert.equal(matches.length, 1, name);
  return matches[0];
};
const text = node => source.slice(node.start, node.end);
const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
function visit(node, callback) {
  if (node === null || typeof node !== 'object') return;
  if (typeof node.type === 'string') callback(node);
  for (const child of Object.values(node)) {
    if (Array.isArray(child)) for (const value of child) visit(value, callback);
    else if (child && typeof child === 'object') visit(child, callback);
  }
}
function opening() {
  let statements;
  visit(declared('openInstalledHost').body, node => {
    if (node.type !== 'BlockStatement') return;
    const index = node.body.findIndex(value => value.type === 'ExpressionStatement' &&
      value.expression.type === 'AssignmentExpression' && value.expression.left.name === 'journal' &&
      value.expression.right.type === 'AwaitExpression' &&
      value.expression.right.argument.callee?.name === 'openHostRequestJournal');
    if (index >= 0) statements = node.body.slice(index, index + 3);
  });
  assert(statements);
  assert.equal(statements[1].type, 'IfStatement');
  assert.equal(statements[2].declarations[0].id.name, 'originalRequestPreparation');
  return new AsyncFunction('preparation', 'originalSourcePreparation', 'openHostRequestJournal',
    'journalOptions', 'let journal;' + statements.map(text).join('\n') +
    ';return {journal, originalRequestPreparation};');
}

function preparedEnvironmentLifetime({missing = false, retire = () => {},
  consumerRetire = () => {}, install = true, preparation} = {}) {
  const opening = declared('openInstalledHost');
  assert.deepEqual(opening.params.map(node => node.name), ['originalInstallation', 'preparation']);
  const functions = new Map(opening.body.body.filter(node => node.type === 'FunctionDeclaration')
    .map(node => [node.id.name,node]));
  const retirement = functions.get('retireModelPreparationReferences');
  assert(retirement);
  let capture, installation, retain, consumerCapture;
  visit(opening.body,node => {
    if (node.type === 'VariableDeclaration' && node.declarations.length === 1) {
      if (node.declarations[0].id.name === 'sourceEnvironmentOriginal') capture = node;
      if (node.declarations[0].id.name === 'prepareSubmit') installation = node;
    }
    if (node.type === 'IfStatement' && text(node.test) === 'sourceEnvironmentOriginal !== undefined') retain = node;
    if (node.type === 'ExpressionStatement' && node.expression.type === 'AssignmentExpression' &&
        node.expression.left.name === 'clientProgramPreparationReferences' &&
        node.expression.right.type === 'CallExpression') consumerCapture = node;
  });
  assert(capture && retain && installation);
  const original = {host:{},moon:{},environment:{},publication:{},preparedEnvironment:{}};
  let reads = 0, retirements = 0;
  const sourceAliasPublicationOriginal = (moon,environment,publication) => {
    assert.strictEqual(moon,original.moon);assert.strictEqual(environment,original.environment);
    assert.strictEqual(publication,original.publication);reads++;
    return missing ? undefined : Object.freeze({wire:'{}',preparedEnvironment:original.preparedEnvironment});
  };
  const retireSourceAliasPublicationOriginal = (moon,environment,publication) => {
    assert.strictEqual(moon,original.moon);assert.strictEqual(environment,original.environment);
    assert.strictEqual(publication,original.publication);retirements++;retire();
  };
  const consumer = {calls:0,retained:true,retire:consumerRetire};
  const create = new Function('original','sourceAliasPublicationOriginal','retireSourceAliasPublicationOriginal','consumer','preparation',`
    const host=original.host,moon=original.moon;
    let environment=original.environment,sourcePublication=original.publication;
    let preparedSourceEnvironment,clientProgramPreparationReferences,modelRuntimeClosing=false;
    let modelSdkStaticOriginals,originalInstallation={},registerModelProviders,modelProviders;
    const installationServices={},environmentWire='{}';
    const completeInstalledSourceInitialization=(services,installation,prepared,wire)=>{
      if(services!==installationServices||installation!==originalInstallation||
          prepared!==original.preparedEnvironment||wire!==environmentWire)throw Error('ForeignSourceInitialization');
    };
    let projectTasks,projectProfile,projectRuntime,project;
    const mockEffectRuns=new Map(),localFileEffectRuns=new Map();
    let mockEffectOriginals,localFileEffectOriginals,localFileEffectInstallation;
    let mockEffectObservation,mockEffectObservationMethods,localSigningMetadata,localCheckpointAnswer;
    let mockAccount,standardAccountPreparation;
    const retireInstalledProjectConfiguration=()=>{throw new Error('UnexpectedProject');};
    const clientOperationError=code=>Object.assign(new Error(code),{code});
    const valuesMaxRows=undefined,retainedRelationOutput=false,check=()=>{},verifyRequestValuePolicy=()=>{};
    const updateTargetOriginals={restorePrepared:()=>{}},control={},calendarArtifact=undefined;
    const effectInstallation=undefined;
    const installNodeClientProgramPreparation=options=>{
      const holder=Object.assign(function(){},options);
      holder.retireReferences=function(){
        if(this!==holder)throw new Error('ForeignPreparationReceiver');
        consumer.calls++;consumer.retire();consumer.retained=false;
      };
      return holder;
    };
    ${text(retirement)}
    ${text(capture)}
    ${text(retain)}
    let selectedPreparation;
    ${install ? `{${text(installation)}\n${consumerCapture === undefined ? '' : text(consumerCapture)}\nselectedPreparation=prepareSubmit;}` : ''}
    return {retire:retireModelPreparationReferences,
      get slot(){return preparedSourceEnvironment;},options:selectedPreparation,
      stop(){modelRuntimeClosing=true;},replaceEnvironment(value){environment=value;},
      replacePublication(value){sourcePublication=value;}};
  `);
  return {fixture:create(original,sourceAliasPublicationOriginal,retireSourceAliasPublicationOriginal,consumer,preparation),original,consumer,
    get reads(){return reads;},get retirements(){return retirements;}};
}

test('Host prepared Environment keeps one original and execution forwards only the Request owner', () => {
  const f = preparedEnvironmentLifetime();
  assert.equal(f.reads,1);
  assert.equal(Object.hasOwn(f.fixture.options, 'getPreparedSourceEnvironment'), false);
  assert.equal(typeof f.fixture.options.getFundedPreparation, 'function', 'The actual execution caller always selects its original Request owner');
  assert.strictEqual(f.fixture.slot.preparedEnvironment, f.original.preparedEnvironment);
  assert.equal(f.reads,1,'unchanged Host use does not re-read, encode or prepare its publication');
  assert.equal(f.retirements,0);
  const legacy = preparedEnvironmentLifetime({missing:true});
  assert.equal(Object.hasOwn(legacy.fixture.options,'getPreparedSourceEnvironment'),false);
});

test('Host prepared Environment waits for the original child shutdown before cutting its aliases', async () => {
  const f = preparedEnvironmentLifetime(),marker=new Error('OriginalJournalClosePending');
  let closes=0,storeCloses=0;
  const host={stopModelRuntime:f.fixture.stop,dispatchOwner:{drain(){}},retireTerminalEffects(){},
    journal:{close(){if(++closes===1)throw marker;}},store:{close(){storeCloses++;}},
    retireModelRuntime:f.fixture.retire};
  const shutdown=installedHostShutdown(host);
  await assert.rejects(shutdown.close(),error=>error.code==='InstalledHostCleanupPending');
  assert.equal(closes,1);assert.equal(storeCloses,1,'independent Store cleanup is still attempted');
  assert.equal(f.retirements,0);assert.ok(f.fixture.slot);
  assert.ok(f.fixture.slot, 'A pending original cleanup retains its original material');
  await shutdown.close();
  assert.equal(f.retirements,1);assert.equal(f.fixture.slot,undefined);
  assert.equal(closes,2);assert.equal(storeCloses,1);
  await shutdown.close();assert.equal(f.retirements,1);
});

test('Host prepared Environment refuses changed originals and retires only its captured association', () => {
  const marker=new Error('OriginalAssociationRetirement');let attempts=0;
  const f=preparedEnvironmentLifetime({retire(){if(++attempts===1)throw marker;}});
  f.fixture.replaceEnvironment({});
  assert.strictEqual(f.fixture.slot.preparedEnvironment, f.original.preparedEnvironment, 'Changing an unrelated binding does not reissue the original material');
  f.fixture.replacePublication({});
  assert.strictEqual(f.fixture.slot.preparedEnvironment, f.original.preparedEnvironment, 'Changing an unrelated binding does not reissue the original material');
  assert.throws(f.fixture.retire,error=>error===marker);
  assert.ok(f.fixture.slot,'a failed reference-cut callback retains the same original for retry');
  f.fixture.retire();assert.equal(f.fixture.slot,undefined);assert.equal(f.retirements,2);
  assert.equal(f.reads,1);
});

test('Host consumer preparation retains aliases until original shutdown and releases the captured receiver', async () => {
  const f=preparedEnvironmentLifetime();let closes=0,replacementCalls=0;
  f.fixture.options.retireReferences=()=>{replacementCalls++;};
  const shutdown=installedHostShutdown({stopModelRuntime:f.fixture.stop,
    dispatchOwner:{drain(){}},retireTerminalEffects(){},
    journal:{close(){if(++closes===1)throw new Error('OriginalJournalPending');}},
    store:{close(){}},retireModelRuntime:f.fixture.retire});
  await assert.rejects(shutdown.close(),{code:'InstalledHostCleanupPending'});
  assert.equal(f.consumer.calls,0);assert.equal(f.consumer.retained,true);
  assert.ok(f.fixture.slot);
  await shutdown.close();
  assert.equal(f.consumer.calls,1);assert.equal(f.consumer.retained,false);
  assert.equal(replacementCalls,0);assert.equal(f.fixture.slot,undefined);
  await shutdown.close();assert.equal(f.consumer.calls,1);
});

test('Host consumer preparation retains its original release retry and handles earlier initialization', () => {
  const marker=new Error('OriginalConsumerRetirement');let attempts=0;
  const f=preparedEnvironmentLifetime({consumerRetire(){if(++attempts===1)throw marker;}});
  assert.throws(f.fixture.retire,error=>error===marker);
  assert.equal(f.consumer.retained,true);assert.equal(f.consumer.calls,1);
  assert.equal(f.retirements,0);assert.ok(f.fixture.slot);
  f.fixture.retire();
  assert.equal(f.consumer.calls,2);assert.equal(f.consumer.retained,false);
  assert.equal(f.retirements,1);assert.equal(f.fixture.slot,undefined);
  f.fixture.retire();assert.equal(f.consumer.calls,2);
  const early=preparedEnvironmentLifetime({install:false});
  early.fixture.retire();
  assert.equal(early.consumer.calls,0);assert.equal(early.retirements,1);
});

test('actual Host acquires its same Journal before Compute and before publishing the SDK receiver', async () => {
  const journal = {}, receiver = {}, options = {}, log = [];
  const preparation = {
    async prepareResultPublication() {assert.deepEqual(log, ['journal']); log.push('result');},
    async prepareManagedCompute() {assert.deepEqual(log, ['journal', 'result']); log.push('compute');},
    requestPreparation() {assert.deepEqual(log, ['journal', 'result', 'compute']); log.push('receiver'); return receiver;},
  };
  const result = await opening()(preparation, undefined,
    async value => {assert.strictEqual(value, options); log.push('journal'); return journal;}, options);
  assert.strictEqual(result.journal, journal);
  assert.strictEqual(result.originalRequestPreparation, receiver);
  assert.deepEqual(log, ['journal', 'result', 'compute', 'receiver']);
});

test('legacy unprepared and existing Mock Source entries do not acquire a Compute replacement', async () => {
  const journal = {}, source = {}, open = opening();
  assert.deepEqual(await open(undefined, undefined, async () => journal, {}),
    {journal, originalRequestPreparation: undefined});
  const preparation = {
    prepareResultPublication() {},
    prepareManagedCompute() {assert.fail('Source must retain its original joint purpose');},
    requestPreparation() {return source;},
  };
  const result = await open(preparation, source, async () => journal, {});
  assert.strictEqual(result.originalRequestPreparation, source);
});

function lifecycle({factory, beforeChild, beforeChildClose, current = () => {}, retire = () => {},
  runtime = {}, source, capturePlan = () => assert.fail('No capture Plan constructor selected'),
  originalRequest = value => value, controlClose = async () => ({pending: false}), invocationControl}) {
  const declarations = declared('connectEmbeddedLocal').body.body
    .filter(node => node.type === 'VariableDeclaration').flatMap(node => node.declarations);
  const initial = declarations.find(node => node.id.name === 'initialControl');
  const preparation = declarations.find(node => node.id.name === 'preparation');
  assert(initial && preparation);
  const properties = preparation.init.arguments[0].properties;
  const names = ['prepareManagedCompute', 'requestPreparation', 'sourcePreparation',
    'bindSourceRequest', 'prepareManagedComputeRun', 'bindManagedComputeRunObservation',
    'managedComputeUsageReader', 'isOriginalManagedComputePreparationRefusal', 'fundedPreparation',
    'bindManagedSources', 'managesInstalledSources', 'prepareManagedSourceRun',
    'prepareManagedEffectPlanRun', 'retireManagedComputeRun', 'managedComputeInvocationOriginal'];
  const methods = names.map(name => {
    const property = properties.find(node => node.key.name === name); assert(property, name); return text(property);
  });
  const originals = {host: {}, installation: {retainedRelationOutput: false}, generation: {}, supplier: {}, moduleLifetime: {}};
  const ports = {
    prepareManagedComputeInstallation: held => {assert.strictEqual(held, originals); return factory();},
    assertInitialControlHostPreparation: held => {assert.strictEqual(held, originals); current();},
    assertManagedComputeInstallationCurrent: (value, held) => {assert.strictEqual(held, originals); current(value);},
    assertSourceManagedInstallationCurrent: (value, held) => {
      assert.strictEqual(value, source); assert.strictEqual(held, originals); current(value);
    },
    clientOperationError: code => Object.assign(new Error(code), {code}),
    retirePreparationReferences: retire, controlClose, originals, runtime,
    checked: value => value, finishInstalledEffectModelScope, prepareInstalledEffectManagedPlanRun,
    managedPreparationRetirementContinuation: new Function('checked', 'return ' +
      text(declared('managedPreparationRetirementContinuation')))(value => value),
    bindInstalledManagedSources,
    prepareManagedComputeCapturePlan(held, run, invocation) {
      assert.strictEqual(held, originals); return capturePlan(run, invocation);
    },
    originalSourceManagedHostRequest(held, value) {assert.strictEqual(held, originals); return originalRequest(value);},
    prepareInstalledSequenceContractOriginal(held) {assert.strictEqual(held, originals); return {admission: held.installation.sequenceContracts};},
    runtimeCore(actual) {assert.equal(actual,runtime);return {publicationControl:invocationControl};},
    beforeChild, beforeChildClose, source,
  };
  return new Function(...Object.keys(ports), `
    let computeManaged, computeManagedClose, computeManagedFlight, observedClose;
    let resultPublication, resultPublicationClose, resultPublicationFlight;
    let sourceManaged=source??beforeChild, sourceManagedClose=source?.close??beforeChildClose, hostJournal;
    let moon=runtime, mockPreparation=source===undefined?undefined:{}, projectSourcePreparation;
    let control={}, duty, hostInitialization, originalInstallation=originals.installation;
    const host=originals.host, record={}, adopted=true;
    const profiles={bindSourceRequest(...args){record.lineage=args;}};
    const initialControl=${text(initial.init)};
    const preparation={${methods.join(',\n')}};
    return {preparation,initialControl,record,originals};
  `)(...Object.values(ports));
}

function sourceFreeRequestCaller(runtime, prepared) {
  let request, originals, identity;
  visit(declared('openInstalledHost').body, node => {
    if (node.type !== 'VariableDeclaration') return;
    for (const declaration of node.declarations) {
      if (declaration.id.name === 'requestOf') request = declaration;
      if (declaration.id.name === 'sourceFreeRequestIdentities') originals = declaration;
      if (declaration.id.name === 'originalSourceFreeRequest') identity = declaration;
    }
  });
  assert(request);
  Object.assign(runtime, {
    clientProgramAcquisitionCount: value => {assert.strictEqual(value, prepared);return 0;},
    clientProgramComposedInferOccurrences: () => [],
    clientProgramSourceFreeInputIntentCid: () => 'original-input-intent',
    clientProgramResultCount: () => 1,
    clientProgramResultName: () => 'answer',
  });
  const ports = {moon: runtime, authorityScopeCid: 'original-authority',
    prepareSubmit: {assertOwned: value => assert.strictEqual(value, prepared),
      kindOf: () => 'effect_free'}, earlyContentPlans: new WeakMap(),
    inferSelections: new WeakMap(), runtimeIsOkRequired: () => true,
    runtimeField: value => value,
    prepareInferSelection: (_prepared, occurrence) => assert.equal(occurrence, undefined),
    clientOperationError: code => Object.assign(new Error(code), {code})};
  return new Function(...Object.keys(ports),
    (originals === undefined ? '' : `const ${text(originals)};`) +
    `const ${text(identity)};` +
    `const ${text(request)};return requestOf;`)(...Object.values(ports));
}

test('ordinary preadmission and submission reuse the same original Request identity', async () => {
  const p = managedRunPorts(), prepared = {}, original = {};
  let identityCalls = 0, runPreparations = 0;
  p.runtime.clientProgramRequestIdentity = (value, authority, requestId, input) => {
    assert.strictEqual(value, prepared);assert.equal(authority, 'original-authority');
    assert.equal(input, 'original-input-intent');identityCalls++;
    return Object.freeze({requestId});
  };
  const requestOf = sourceFreeRequestCaller(p.runtime, prepared);
  const raw = {prepareRun(value) {
    assert.strictEqual(value, prepared);runPreparations++;return original;
  }, close: () => ({pending: false})};
  const f = lifecycle({runtime: p.runtime, factory: async () => raw});
  await f.preparation.prepareManagedCompute();
  const first = requestOf({preparedProgram: prepared, requestId: 'original-request'});
  assert.strictEqual(f.preparation.prepareManagedComputeRun(p.runtime, prepared, first.requested), p.value);
  // The actual two Host entrances use separate submission wrappers but the
  // same Prepared and original requestId, without another compiler/parent.
  const second = requestOf({preparedProgram: prepared, requestId: 'original-request'});
  assert.strictEqual(f.preparation.prepareManagedComputeRun(p.runtime, prepared, second.requested), p.value);
  assert.strictEqual(second.requested, first.requested);
  assert.equal(identityCalls, 1);assert.equal(runPreparations, 1);
  await f.initialControl.close();
});

test('ordinary Request identity retention refuses another requestId without replacing its original', () => {
  const runtime = {}, prepared = {};
  let calls = 0;
  runtime.clientProgramRequestIdentity = (_prepared, _authority, requestId) => {
    calls++;return Object.freeze({requestId});
  };
  const requestOf = sourceFreeRequestCaller(runtime, prepared);
  const first = requestOf({preparedProgram: prepared, requestId: 'original-request'});
  assert.throws(() => requestOf({preparedProgram: prepared, requestId: 'another-request'}),
    {code: 'ForeignInstalledComputeRun'});
  assert.strictEqual(requestOf({preparedProgram: prepared, requestId: 'original-request'}).requested,
    first.requested);
  assert.equal(calls, 1);
});

test('ordinary Request identity retention never accepts a missing Core identity', () => {
  const runtime = {}, prepared = {};
  let calls = 0;
  runtime.clientProgramRequestIdentity = () => {calls++;return undefined;};
  const requestOf = sourceFreeRequestCaller(runtime, prepared);
  assert.throws(() => requestOf({preparedProgram: prepared, requestId: 'original-request'}),
    {code: 'ClientProgramNeedsInputs'});
  assert.equal(calls, 1);
});

test('actual Host forwards the selected async manager result once without an optional raw fallback', async () => {
  const request={},environment={},result={};let calls=0;
  const raw={fundedPreparation(value,selected){
    assert.strictEqual(this,raw);assert.strictEqual(value,request);assert.strictEqual(selected,environment);
    calls++;return Promise.resolve(result);
  },close(){return {pending:false};}};
  const f=lifecycle({factory:async()=>raw});
  await f.preparation.prepareManagedCompute();
  assert.strictEqual(await f.preparation.fundedPreparation(request,environment),result);
  assert.equal(calls,1);
  delete raw.fundedPreparation;
  assert.throws(()=>f.preparation.fundedPreparation(request,environment),TypeError);
  assert.equal(calls,1);
  await f.initialControl.close();
});

test('funded policy Host keeps its original context before snapshot instead of suppressing the owner', () => {
  const moon = {}, control = {}, environment = {}, preparedEnvironment = {};
  const original = Object.freeze({runtime: moon, control, environment, preparedEnvironment,
    retainedRelationOutput: false, valuesMaxRows: 2});
  const installation = {projectRuntime: moon, initialControl: control,
    sequenceContractOriginal: {}, retainedRelationOutput: false, valuesMaxRows: 2,
    verifyRequestValuePolicy() {}, closedValuesPreparationContext: original};
  const read = new Function('assertSourceManagedHostPreparation', 'clientOperationError',
    text(declared('readLocalPreparationContext')) + ';return readLocalPreparationContext;')(
    value => assert.strictEqual(value.installation, installation),
    code => Object.assign(new Error(code), {code}));
  assert.strictEqual(read({installation}), original);
  installation.closedValuesPreparationContext = Object.freeze({...original, valuesMaxRows: 3});
  assert.throws(() => read({installation}), {code: 'NodeLocalPreparationAdmissionUnavailable'});
  installation.closedValuesPreparationContext = Object.freeze({...original, runtime: {}});
  assert.equal(read({installation}), undefined, 'A foreign runtime cannot acquire the original context');
});

test('funded policy installer forwards the exact verifier to its original preparation', async () => {
  const request = {}, environment = {}, result = {}, signal = new AbortController().signal;
  let calls = 0, expectedVerifier;
  const preparation = {fundedPreparation(actual, selected, verifier, actualSignal) {
    assert.strictEqual(this, preparation);
    assert.strictEqual(actual, request);
    assert.strictEqual(selected, environment);
    assert.strictEqual(verifier, expectedVerifier);
    assert.strictEqual(actualSignal, signal);
    calls++;
    return Promise.resolve(result);
  }};
  const f = preparedEnvironmentLifetime({preparation});
  expectedVerifier = f.fixture.options.verifyRequestValuePolicy;
  assert.equal(typeof expectedVerifier, 'function');
  assert.strictEqual(await f.fixture.options.getFundedPreparation(request, environment, expectedVerifier, signal), result);
  assert.equal(calls, 1);
  f.fixture.retire();
});

test('funded policy manager forwarding preserves the same callback and original request mapping', async () => {
  const request = {}, originalRequest = {}, environment = {}, verifier = () => {}, result = {};
  const signal = new AbortController().signal;
  let calls = 0, mappings = 0;
  const manager = {fundedPreparation(actual, selected, originalVerifier, actualSignal) {
    assert.strictEqual(this, manager);
    assert.strictEqual(actual, originalRequest);
    assert.strictEqual(selected, environment);
    assert.strictEqual(originalVerifier, verifier);
    assert.strictEqual(actualSignal, signal);
    calls++;
    return Promise.resolve(result);
  }, close() {return {pending: false};}};
  const f = lifecycle({factory: async () => manager, originalRequest(value) {
    assert.strictEqual(value, request); mappings++; return originalRequest;
  }});
  await f.preparation.prepareManagedCompute();
  assert.strictEqual(await f.preparation.fundedPreparation(request, environment, verifier, signal), result);
  assert.equal(calls, 1);
  assert.equal(mappings, 1);
  await f.initialControl.close();
});

test('managed usage reader selects only the same admitted Run and releases its installation alias', () => {
  const runtime = {}, f = lifecycle({factory() {}, runtime});
  const prepared = {}, value = {}, foreign = {}, first = {namespaceId:'n',authorityScopeCid:'a',runDefinitionCid:'r'};
  let reads = 0;
  const usage = [1n,2n,3n,4n,5n,6n,7n,8n,9n,10n,11n,12n,13n,14n,15n,16n];
  runtime.clientProgramInstalledManagedRunAccounting = function(actual) {
    assert.strictEqual(this,runtime); assert.strictEqual(actual,value); reads++; return usage;
  };
  f.record.computeRuns = new Map([[prepared,{runtime,prepared,value,closed:false}]]);
  assert.equal(f.preparation.managedComputeUsageReader(first),undefined);
  f.preparation.bindManagedComputeRunObservation(foreign,first);
  assert.equal(f.preparation.managedComputeUsageReader(first),undefined);
  f.preparation.bindManagedComputeRunObservation(prepared,first);
  const read = f.preparation.managedComputeUsageReader({...first});
  assert.equal(reads,0,'Capturing correlation does not sample or admit');
  assert.equal(f.preparation.managedComputeUsageReader({...first,authorityScopeCid:'foreign'}),undefined);
  assert.strictEqual(read(),usage); assert.equal(reads,1);
  runtime.clientProgramInstalledManagedRunAccounting=()=>{throw new Error('Replacement must not run');};
  assert.strictEqual(read(),usage); assert.equal(reads,2,'Same original callback and receiver');
  f.record.computeRunObservations=undefined;
  assert.equal(read(),undefined,'A retired installation bag retains no Core original');
  assert.equal(reads,2);
});

test('installed static contract aliases survive pending child cleanup and cut at actual retirement', async () => {
  const connect = declared('connectEmbeddedLocal');
  const retirement = connect.body.body.find(node => node.type === 'FunctionDeclaration' &&
    node.id.name === 'retirePreparationReferences');
  assert(retirement);
  const retire = new Function('originalInstallation', `
    let referencesRetired=false,moon,project,projectProfile,mockPreparation,projectSourcePreparation;
    let mockAnswers,mockModelProfile,mockModelProfileRetire,mockModelFlight,referenceRetirement,duty;
    const host={},record={},profiles={retainedMockPreparation:()=>undefined};
    ${text(retirement)};return retirePreparationReferences;
  `);
  let closes = 0, f;
  const raw = {close() {closes++; return {pending: closes === 1};}};
  f = lifecycle({factory: async () => raw,
    retire: () => retire(f.originals.installation)()});
  await f.preparation.prepareManagedCompute();
  const strings = Object.freeze({values: '{}', expression: '{}', ordered: '{}'});
  f.originals.installation.managedRunContracts = strings;
  await assert.rejects(f.initialControl.close(), {code: 'InstalledComputePreparationCleanupPending'});
  assert.strictEqual(f.originals.installation.managedRunContracts, strings);
  await f.initialControl.close();
  assert.equal(closes, 2);
  assert.equal(f.originals.installation.managedRunContracts, undefined);
  await f.initialControl.close();
  assert.equal(closes, 2, 'Reference retirement does not repeat an acknowledged native close');
});

test('same Host Compute preparation is one sticky flight and retains its original before current refusal', async () => {
  let factoryCalls = 0, closes = 0, controls = 0;
  const marker = new Error('OriginalCurrentRefusal');
  const raw = {close() {assert.strictEqual(this, raw); closes++; return {pending: false};}};
  const f = lifecycle({factory: async () => {factoryCalls++; return raw;},
    current: value => {if (value === raw) throw marker;}, controlClose: () => {controls++; return {pending: false};}});
  const first = f.preparation.prepareManagedCompute(), second = f.preparation.prepareManagedCompute();
  assert.strictEqual(first, second);
  await assert.rejects(first, error => error === marker);
  assert.strictEqual(f.record.computeManaged, raw);
  assert.strictEqual(f.preparation.prepareManagedCompute(), first);
  assert.equal(factoryCalls, 1);
  await f.initialControl.close();
  assert.equal(closes, 1); assert.equal(controls, 1);
});

test('captured Compute close cannot be replaced during a preceding child await', async () => {
  let release, entered, replacementCalls = 0, originalCloses = 0;
  const wait = new Promise(resolve => {release = resolve;});
  const enteredFlight = new Promise(resolve => {entered = resolve;});
  const raw = {close() {assert.strictEqual(this, raw); originalCloses++; return {pending: false};}};
  const f = lifecycle({factory: async () => raw, beforeChild: {},
    beforeChildClose: async () => {entered(); await wait; return {pending: false};}});
  await f.preparation.prepareManagedCompute();
  const closing = f.initialControl.close();
  await enteredFlight;
  raw.close = () => {replacementCalls++; return {pending: false};};
  release(); await closing;
  assert.equal(originalCloses, 1); assert.equal(replacementCalls, 0);
});

test('unobserved close getter failure retains the original and permits its same cleanup retry', async () => {
  const marker = new Error('UnobservedClose'); let reads = 0, closes = 0;
  const raw = {get close() {
    if (++reads === 1) throw marker;
    return function() {assert.strictEqual(this, raw); closes++; return {pending: false};};
  }};
  const f = lifecycle({factory: async () => raw});
  await assert.rejects(f.preparation.prepareManagedCompute(), error => error === marker);
  assert.strictEqual(f.record.computeManaged, raw);
  await f.initialControl.close();
  assert.equal(reads, 2); assert.equal(closes, 1);
});

test('pending Compute close retains its original and blocks final control retirement', async () => {
  let closes = 0, controls = 0;
  const raw = {close() {closes++; return {pending: closes === 1};}};
  const f = lifecycle({factory: async () => raw, controlClose: () => {controls++; return {pending: false};}});
  await f.preparation.prepareManagedCompute();
  await assert.rejects(f.initialControl.close(), error => error.code === 'InstalledComputePreparationCleanupPending');
  assert.equal(controls, 0); assert.strictEqual(f.record.computeManaged, raw);
  await f.initialControl.close();
  assert.equal(closes, 2); assert.equal(controls, 1);
});

test('Compute SDK lineage is the same view while Mock Source selection stays absent', async () => {
  const raw = {close: () => ({pending: false})};
  const f = lifecycle({factory: async () => raw});
  await f.preparation.prepareManagedCompute();
  assert.strictEqual(f.preparation.requestPreparation(), raw);
  assert.strictEqual(f.preparation.sourcePreparation(), undefined);
  const original = {}, derived = {};
  f.preparation.bindSourceRequest(original, derived);
  assert.strictEqual(f.record.lineage[3], original);
  assert.strictEqual(f.record.lineage[4], derived);
  await f.initialControl.close();
  assert.throws(() => f.preparation.requestPreparation(), error => error.code === 'NodeManagedRunAdmissionUnavailable');
});

function managedRunPorts(overrides = {}) {
  const admission = {}, value = {}, log = [], manifests = {}, contracts = {};
  const runtime = {
    clientPrepareInstalledCompilationManifests() {assert.strictEqual(this, runtime); return manifests;},
    clientPrepareInstalledSequenceContracts() {assert.strictEqual(this, runtime); return contracts;},
    clientProgramNodeManagedRunPrepare(original, prepared) {log.push(['prepare', original, prepared]); return admission;},
    clientProgramInstalledManagedSourceFreeBegin(held, prepared, request) {
      assert.strictEqual(held, admission); log.push(['begin', prepared, request]); return value;
    },
    clientProgramInstalledManagedRunCheck(held, prepared, request) {
      assert.strictEqual(held, value); log.push(['check', prepared, request]);
    },
    clientProgramInstalledManagedRunRetire(held) {assert.strictEqual(held, value); log.push(['retire']);},
    clientProgramNodeManagedRunCleanup(held) {assert.strictEqual(held, admission); log.push(['cleanup']);},
    ...overrides,
  };
  return {runtime, admission, value, log, manifests, contracts};
}

test('generic Source service begins once on the existing Host Run inventory and never coerces to source-free', async () => {
  const p = managedRunPorts(), prepared = {}, request = {}, original = {}, log = [];
  p.runtime.clientProgramInstalledManagedSourceFreeBegin = () => assert.fail('Source-empty coercion');
  p.runtime.clientProgramInstalledManagedRunBegin = (admission, value, identity) => {
    assert.strictEqual(admission, p.admission); assert.strictEqual(value, prepared);
    assert.strictEqual(identity, request); log.push('source-begin'); return p.value;
  };
  let f;
  const manager = {prepareRun(value) {
    assert.strictEqual(value, prepared);
    assert.strictEqual(f.originals.installation.computeRuns, f.record.computeRuns);
    assert.strictEqual(f.record.computeRuns.get(prepared).sourceProfile, profile);
    log.push('same-manager'); return original;
  }, close: () => ({pending: false})};
  f = lifecycle({runtime: p.runtime, factory: async () => manager});
  const profile = f.preparation.bindManagedSources(p.runtime, {managedCaptureCapacity() {},
    async prepare() {return {};}, ledgerCapacity() {return {};}});
  await f.preparation.prepareManagedCompute();
  assert.strictEqual(f.preparation.prepareManagedSourceRun(p.runtime, prepared, request, profile), p.value);
  assert.strictEqual(f.preparation.prepareManagedSourceRun(p.runtime, prepared, request, profile), p.value);
  assert.deepEqual(log, ['same-manager', 'source-begin']);
  assert.throws(() => f.preparation.prepareManagedSourceRun(p.runtime, prepared, request, {...profile}),
    {code: 'ForeignInstalledSourcePreparation'});
  assert.throws(() => f.preparation.prepareManagedComputeRun(p.runtime, prepared, request),
    {code: 'ForeignInstalledComputeRun'});
});

function installedSequencePorts(runtime) {
  const manifests = {}, admission = {}, calls = [];
  const aoa = '{"execution_contracts":{"REL.values":{},"ACTQL.expression_fragment/0.1":{},"REL.derive.ordered":{}}}';
  runtime.clientPrepareInstalledCompilationManifests = function(...args) {
    assert.strictEqual(this, runtime); assert.deepEqual(args, []);
    calls.push('manifests'); return manifests;
  };
  runtime.clientPrepareInstalledSequenceContracts = function(...args) {
    assert.strictEqual(this, runtime); assert.equal(calls.at(-1), 'manifests');
    assert.deepEqual(args, ['registry-original', '{}', '{}', '{}']);
    calls.push('sequence'); return admission;
  };
  return {manifests, admission, calls, asset(_control, _originals, path) {
    assert(['spec/contracts/actql-aoa.json', 'spec/dependencies/aoa-pipeline-registry.json'].includes(path));
    return path === 'spec/contracts/actql-aoa.json' ? aoa : 'registry-original';
  }};
}

test('actual requirements and begin share the retained typed original before Resource admission', async () => {
  const p = managedRunPorts(), original = {}, sequences = {}, prepared = {}, request = {};
  let f, sequencePreparations = 0;
  const installed = installedSequencePorts(p.runtime);
  const read = new Function('assertSourceManagedHostPreparation', 'originalSourceManagedHostRequest',
    'readInitialControlInstallationAsset', 'checked', 'clientOperationError', 'runtimeIsError',
    text(declared('installedManagedRunContracts')) + '\n' +
    text(declared('prepareInstalledSequenceContractOriginal')) + '\n' +
    text(declared('readManagedComputeRunRequirements')) + ';return readManagedComputeRunRequirements;')(
    held => assert.strictEqual(held, f.originals),
    (held, value) => {assert.strictEqual(held, f.originals); assert.strictEqual(value, prepared); return request;},
    installed.asset,
    value => value, code => Object.assign(new Error(code), {code}), () => false);
  p.runtime.clientProgramInstalledManagedRunIssueIsUnsupported = () => false;
  p.runtime.clientProgramInstalledManagedRunRequirements = () => assert.fail('No regeneration');
  p.runtime.clientProgramPrepareInstalledManagedSourceFreeWithContracts = (...args) => {
    assert.strictEqual(args[0], prepared); assert.strictEqual(args[1], installed.admission);
    assert.deepEqual(args.slice(2), ['{}', '{}', '{}', false]);
    sequencePreparations++; return sequences;
  };
  p.runtime.clientProgramPreparedInstalledManagedSourceFreeRequirements = held => {
    assert.strictEqual(held, sequences);
    assert.strictEqual(f.record.computeRuns.get(prepared).preparedSequences, sequences);
    return [7n, 2n, 3n, 0n, 32n, 64n];
  };
  p.runtime.clientProgramInstalledManagedSourceFreeBegin = function(admission, value, requested, held) {
    assert.strictEqual(this, p.runtime); assert.strictEqual(admission, p.admission);
    assert.strictEqual(value, prepared); assert.strictEqual(requested, request); assert.strictEqual(held, sequences);
    assert.strictEqual(f.record.computeRuns.get(prepared).admission, p.admission);
    return p.value;
  };
  const raw = {prepareRun(value) {
    assert.strictEqual(value, prepared);
    assert.strictEqual(f.originals.installation.computeRuns, f.record.computeRuns);
    read(f.originals, prepared); return original;
  }, close: () => ({pending: false})};
  f = lifecycle({runtime: p.runtime, factory: async () => raw});
  Object.assign(f.originals.installation, {initialControl: {}, projectRuntime: p.runtime});
  await f.preparation.prepareManagedCompute();
  assert.strictEqual(f.preparation.prepareManagedComputeRun(p.runtime, prepared, request), p.value);
  assert.strictEqual(f.preparation.prepareManagedComputeRun(p.runtime, prepared, request), p.value);
  assert.equal(sequencePreparations, 1);
  assert.deepEqual(installed.calls, ['manifests', 'sequence']);
  assert.strictEqual(f.originals.installation.sequenceContractOriginal.admission, installed.admission);
  assert.strictEqual(f.record.computeRuns.get(prepared).original, original);
  assert.strictEqual(f.record.computeRuns.get(prepared).preparedSequences, undefined);
  await f.initialControl.close();
});

test('actual preparation binds one original Run and closes it before its same Root', async () => {
  const p = managedRunPorts(), original = {}, prepared = {}, request = {};
  let preparations = 0;
  const raw = {prepareRun(value) {assert.strictEqual(value, prepared); preparations++; return original;},
    close() {assert.deepEqual(p.log.at(-1), ['retire']); return {pending: false};}};
  const f = lifecycle({runtime: p.runtime, factory: async () => raw});
  await f.preparation.prepareManagedCompute();
  const value = f.preparation.prepareManagedComputeRun(p.runtime, prepared, request);
  assert.strictEqual(value, p.value);
  assert.strictEqual(f.preparation.prepareManagedComputeRun(p.runtime, prepared, request), value);
  assert.equal(preparations, 1);
  assert.strictEqual(f.record.computeRuns.get(prepared).original, original);
  assert.throws(() => f.preparation.prepareManagedComputeRun({}, prepared, request),
    error => error.code === 'ForeignInstalledComputePreparation');
  // Cleanup is the captured original, not the later property value.
  p.runtime.clientProgramInstalledManagedRunRetire = () => assert.fail('replacement retire');
  await f.initialControl.close();
  assert.equal(preparations, 1);
});

test('failed begin retains the admission and original cleanup through Unknown without reissuing', async () => {
  const marker = new Error('OriginalBeginUnknown'), pending = new Error('OriginalCleanupPending');
  const p = managedRunPorts({clientProgramInstalledManagedSourceFreeBegin() {throw marker;}});
  let preparations = 0, rootCloses = 0, cleanups = 0;
  p.runtime.clientProgramNodeManagedRunCleanup = function(value) {
    assert.strictEqual(this, p.runtime); assert.strictEqual(value, p.admission);
    if (++cleanups === 1) throw pending;
  };
  const raw = {prepareRun() {preparations++; return {};}, close() {rootCloses++; return {pending: false};}};
  const f = lifecycle({runtime: p.runtime, factory: async () => raw});
  await f.preparation.prepareManagedCompute();
  const prepared = {}, request = {};
  assert.throws(() => f.preparation.prepareManagedComputeRun(p.runtime, prepared, request), error => error === marker);
  assert.strictEqual(f.record.computeRuns.get(prepared).admission, p.admission);
  assert.throws(() => f.preparation.prepareManagedComputeRun(p.runtime, prepared, request), error => error === marker);
  p.runtime.clientProgramNodeManagedRunCleanup = () => assert.fail('replacement cleanup');
  await assert.rejects(f.initialControl.close(), error => error === pending);
  assert.equal(rootCloses, 0); assert.equal(preparations, 1);
  await f.initialControl.close();
  assert.equal(rootCloses, 1); assert.equal(preparations, 1); assert.equal(cleanups, 2);
});

test('pure preparation refusal belongs only to its original pre-Resource Run holder', async () => {
  const p = managedRunPorts(), prepared = {}, request = {}, issue = {}, result = {};
  let f, failure, preparations = 0, current = true;
  const installed = installedSequencePorts(p.runtime);
  const read = new Function('assertSourceManagedHostPreparation', 'originalSourceManagedHostRequest',
    'readInitialControlInstallationAsset', 'checked', 'clientOperationError', 'runtimeIsError', 'runtimeField',
    text(declared('installedManagedRunContracts')) + '\n' +
    text(declared('prepareInstalledSequenceContractOriginal')) + '\n' + text(declared('readManagedComputeRunRequirements')) +
    ';return readManagedComputeRunRequirements;')(
    held => {assert.strictEqual(held, f.originals); assert(current);},
    (held, value) => {assert.strictEqual(held, f.originals); assert.strictEqual(value, prepared); return request;},
    installed.asset,
    value => {assert(value === installed.manifests || value === installed.admission); return value;},
    (code, cause) => Object.assign(new Error(code, {cause}), {code}),
    value => {assert.strictEqual(value, result); return true;},
    (value, index) => {assert.strictEqual(value, result); assert.equal(index, 0); return issue;});
  p.runtime.clientProgramInstalledManagedRunRequirements = () => assert.fail('No second preparation');
  p.runtime.clientProgramPrepareInstalledManagedSourceFreeWithContracts = (...args) => {
    assert.strictEqual(args[0], prepared); assert.strictEqual(args[1], installed.admission);
    assert.deepEqual(args.slice(2), ['{}', '{}', '{}', false]);
    preparations++; return result;
  };
  p.runtime.clientProgramInstalledManagedRunIssueIsUnsupported = value => {
    assert.strictEqual(value, issue); return true;
  };
  p.runtime.clientProgramPreparedInstalledManagedSourceFreeRequirements = () => assert.fail('No scalar quote');
  const raw = {prepareRun(value) {assert.strictEqual(value, prepared); read(f.originals, prepared);
    assert.fail('No Resource original after a pure refusal');}, close: () => ({pending: false})};
  f = lifecycle({runtime: p.runtime, factory: async () => raw, current: () => assert(current)});
  Object.assign(f.originals.installation, {initialControl: {}, projectRuntime: p.runtime});
  await f.preparation.prepareManagedCompute();
  assert.throws(() => f.preparation.prepareManagedComputeRun(p.runtime, prepared, request), error => {
    failure = error; return error.code === 'ClientProgramUnsupported' && error.cause === issue;
  });
  const project = (error = failure, value = prepared, requested = request) =>
    f.preparation.isOriginalManagedComputePreparationRefusal(error, value, requested);
  assert.equal(project(), true);
  assert.equal(project(Object.assign(new Error('same code'), {code: failure.code})), false);
  assert.equal(project(failure, {}, request), false);
  assert.equal(project(failure, prepared, {}), false);
  const run = f.record.computeRuns.get(prepared), control = f.originals.installation.initialControl;
  f.originals.installation.initialControl = {}; assert.equal(project(), false);
  f.originals.installation.initialControl = control;
  for (const key of ['original', 'admission', 'value']) {
    run[key] = {}; assert.equal(project(), false); run[key] = undefined;
  }
  failure.cleanupPending = true; assert.equal(project(), false); delete failure.cleanupPending;
  failure.cleanupHandle = {}; assert.equal(project(), false); delete failure.cleanupHandle;
  current = false; assert.throws(() => project()); current = true;
  assert.equal(project(), true);
  assert.throws(() => f.preparation.prepareManagedComputeRun(p.runtime, prepared, request), error => error === failure);
  assert.equal(preparations, 1); assert.deepEqual(p.log, []);
  assert.deepEqual(installed.calls, ['manifests', 'sequence']);
  assert.strictEqual(f.originals.installation.sequenceContractOriginal.admission, installed.admission);
  await f.initialControl.close();
  assert.equal(project(), false, 'Actual successful retirement cuts the nominal refusal holder');
});

test('same ordinary Host retains separate Run records for successive prepared requests', async () => {
  const a = {}, b = {}, requests = new Map([[a, {}], [b, {}]]), retired = [];
  const runtime = {
    clientProgramNodeManagedRunPrepare(original, prepared) {assert.strictEqual(original, prepared); return prepared;},
    clientProgramInstalledManagedSourceFreeBegin(admission, prepared, request) {
      assert.strictEqual(admission, prepared); assert.strictEqual(request, requests.get(prepared)); return prepared;
    },
    clientProgramInstalledManagedRunCheck(run, prepared, request) {
      assert.strictEqual(run, prepared); assert.strictEqual(request, requests.get(prepared));
    },
    clientProgramInstalledManagedRunRetire(run) {retired.push(run);},
    clientProgramNodeManagedRunCleanup() {assert.fail('No failed admission');},
  };
  const raw = {prepareRun: prepared => prepared, close: () => ({pending: false})};
  const f = lifecycle({runtime, factory: async () => raw});
  await f.preparation.prepareManagedCompute();
  for (const prepared of [a, b, a]) assert.strictEqual(
    f.preparation.prepareManagedComputeRun(runtime, prepared, requests.get(prepared)), prepared);
  assert(f.record.computeRuns instanceof WeakMap);
  const first = f.record.computeRuns.get(a), second = f.record.computeRuns.get(b);
  assert.notStrictEqual(first, second);
  assert.equal(f.record.computeLiveRuns.size, 2);
  assert(f.record.computeLiveRuns.has(first) && f.record.computeLiveRuns.has(second));
  await f.initialControl.close();
  assert.deepEqual(retired, [a, b]);
});

test('Source Host opens a source-free Run on its same joint parent and retires it before Root close', async () => {
  const p = managedRunPorts(), original = {}, prepared = {}, request = {};
  let preparations = 0, rootCloses = 0;
  const source = {prepareRun(value) {assert.strictEqual(value, prepared); preparations++; return original;},
    close() {assert.strictEqual(this, source); assert.deepEqual(p.log.at(-1), ['retire']);
      rootCloses++; return {pending: false};}};
  const f = lifecycle({runtime: p.runtime, source,
    factory: () => assert.fail('No replacement Compute installation')});
  assert.strictEqual(f.preparation.requestPreparation(), source);
  assert.strictEqual(f.preparation.sourcePreparation(), source);
  assert.strictEqual(f.preparation.prepareManagedComputeRun(p.runtime, prepared, request), p.value);
  assert.strictEqual(f.preparation.prepareManagedComputeRun(p.runtime, prepared, request), p.value);
  assert.equal(preparations, 1);
  await f.initialControl.close();
  assert.equal(rootCloses, 1);
});

test('Source Host retains failed source-free start cleanup without replacing its original parent', async () => {
  const marker = new Error('OriginalSourceHostBeginUnknown');
  const p = managedRunPorts({clientProgramInstalledManagedSourceFreeBegin() {throw marker;}});
  let cleanups = 0, rootCloses = 0, ready = false;
  p.runtime.clientProgramNodeManagedRunCleanup = function(admission) {
    assert.strictEqual(this, p.runtime); assert.strictEqual(admission, p.admission); cleanups++;
    if (!ready) throw marker;
  };
  const source = {prepareRun: () => ({}), close() {rootCloses++; return {pending: false};}};
  const f = lifecycle({runtime: p.runtime, source}), prepared = {}, request = {};
  assert.throws(() => f.preparation.prepareManagedComputeRun(p.runtime, prepared, request), error => error === marker);
  await assert.rejects(f.initialControl.close(), error => error === marker);
  assert.equal(rootCloses, 0);
  ready = true;
  await f.initialControl.close();
  assert.equal(cleanups, 2); assert.equal(rootCloses, 1);
});

const dispatchSource = readFileSync(new URL('./client-dispatch-owner.mjs', import.meta.url), 'utf8');
const dispatchAst = parse(dispatchSource, {ecmaVersion: 'latest', sourceType: 'module'});
function sourceFreeOpening() {
  const matches = [];
  visit(dispatchAst, node => {
    if (node.type === 'IfStatement' && dispatchSource.slice(node.test.start, node.test.end) ===
        '!acquiring && !inferring && !serializing') matches.push(node);
  });
  assert.equal(matches.length, 1);
  const helper = name => {
    const matches = dispatchAst.body.filter(node => node.type === 'FunctionDeclaration' && node.id.name === name);
    assert.equal(matches.length, 1, name);
    return dispatchSource.slice(matches[0].start, matches[0].end);
  };
  return new Function('held', 'moon', 'preparedProgram', 'requested', 'retainedRelationOutput', 'checked', 'preparationLease', `
    ${helper('releaseDispatchPreparationHost')}
    ${helper('retainDispatchPreparationHost')}
    const acquiring=false, inferring=false, serializing=false;
    const managedComputeRequired=true;
    const registry='registry',values='values',fragment='fragment',ordered='ordered',entry={};let setup;
    ${dispatchSource.slice(matches[0].start, matches[0].end)}
    return {setup,entry,release:()=>releaseDispatchPreparationHost(entry)};`);
}

test('actual dispatcher opens its opaque Run without the legacy accounting constructor', () => {
  const original = {}, prepared = {}, request = {}, setup = {}, open = sourceFreeOpening();
  for (const retained of [false, true]) {
    const moon = {clientProgramOpenInstalledManagedSourceFreeHost(...args) {
      assert.deepEqual(args, [original, prepared, request, 'registry', 'values', 'fragment', 'ordered', retained]);
      return setup;
    }, clientProgramOpenSourceFreeLocalHost() {assert.fail('accounting fallback');},
    clientProgramOpenSourceFreeLocalRetainedHost() {assert.fail('accounting fallback');}};
    const result = open({managedRun: original}, moon, prepared, request, retained, value => value);
    assert.strictEqual(result.setup, setup); assert.strictEqual(result.entry.pendingSetup, setup);
  }
});

test('actual dispatcher propagates missing/foreign/parked original refusal without fallback', () => {
  const marker = new Error('OriginalResourceParked'), original = {}, open = sourceFreeOpening();
  const legacy = () => assert.fail('accounting fallback');
  assert.throws(() => open({}, {clientProgramOpenSourceFreeLocalHost: legacy}, {}, {}, false,
    value => value), /InstalledManagedComputeRunUnavailable/);
  assert.throws(() => open({managedRun: original}, {clientProgramOpenSourceFreeLocalHost: legacy}, {}, {}, false,
    value => value), /InstalledManagedComputeHostUnavailable/);
  assert.throws(() => open({managedRun: original}, {clientProgramOpenSourceFreeLocalHost: legacy,
    clientProgramOpenInstalledManagedSourceFreeHost() {throw marker;}}, {}, {}, false, value => value),
    error => error === marker);
});

function singleSourceOpening() {
  const matches = [];
  visit(dispatchAst, node => {
    if (node.type === 'IfStatement' && node.test.type === 'Identifier' &&
        node.test.name === 'singleAccounted' && dispatchSource.slice(node.start, node.end)
          .includes('clientProgramPrepareSingleCapturedLocalInstalledLedger')) matches.push(node);
  });
  assert.equal(matches.length, 1);
  return new AsyncFunction('installedSource', 'moon', 'preparedProgram', 'requested', 'checked', 'managedRun', `
    const singleAccounted=true, checkpoints=undefined, submission={},held={preparedSource:{},managedRun};
    const prepareAcquisition=()=>held.preparedSource;
    const registry='registry',values='values',fragment='fragment',ordered='ordered',entry={};let ledger;
    ${dispatchSource.slice(matches[0].start, matches[0].end)}
    return {ledger,entry};`);
}

test('single Source dispatcher keeps the original managed parent and singleton capacity arrays', async () => {
  const run = {}, capacity = {}, prepared = {}, request = {}, ledger = {}, open = singleSourceOpening();
  const source = {ledgerCapacity: () => ({managedRun: run, capacity, transferBytes: 3n, executionBytes: 5n})};
  const result = await open(source, {clientProgramInstalledManagedRunPrepareLedger(...args) {
    assert.deepEqual(args, [run, prepared, request, [capacity], [3n], [5n],
      'registry', 'values', 'fragment', 'ordered']); return ledger;
  }, clientProgramPrepareSingleCapturedLocalInstalledLedger() {assert.fail('Accounting fallback');}},
  prepared, request, value => value, run);
  assert.strictEqual(result.ledger, ledger); assert.strictEqual(result.entry.acquisitionLedger, ledger);
});

test('single Source dispatcher preserves managed missing/parked refusal instead of scalar fallback', async () => {
  const open = singleSourceOpening(), marker = new Error('OriginalResourceParked');
  const run = {}, source = {ledgerCapacity: () => ({managedRun: run, capacity: {}, transferBytes: 3n, executionBytes: 5n})};
  const legacy = () => assert.fail('Accounting fallback');
  await assert.rejects(open(source, {clientProgramPrepareSingleCapturedLocalInstalledLedger: legacy},
    {}, {}, value => value, run), /InstalledSingleSourceOriginalRunUnavailable/u);
  await assert.rejects(open(source, {clientProgramPrepareSingleCapturedLocalInstalledLedger: legacy,
    clientProgramInstalledManagedRunPrepareLedger() {throw marker;}}, {}, {}, value => value, run),
  error => error === marker);
  await assert.rejects(open(source, {
    clientProgramInstalledManagedRunPrepareLedger() {assert.fail('No foreign parent may reach Core');},
    clientProgramPrepareSingleCapturedLocalInstalledLedger: legacy}, {}, {}, value => value, {}),
  /InstalledSingleSourceOriginalRunUnavailable/u);
});

test('unprepared single Source retains its existing accounting constructor and argument shape', async () => {
  const open = singleSourceOpening(), capacity = {}, prepared = {}, ledger = {};
  const source = {ledgerCapacity: () => ({capacity, transferBytes: 3n, executionBytes: 5n})};
  const result = await open(source, {clientProgramPrepareSingleCapturedLocalInstalledLedger(...args) {
    assert.deepEqual(args, [prepared, capacity, 3n, 5n, 'registry', 'values', 'fragment', 'ordered']);
    return ledger;
  }, clientProgramInstalledManagedRunPrepareLedger() {assert.fail('No managed original');}},
  prepared, {}, value => value);
  assert.strictEqual(result.ledger, ledger);
});


test('actual dispatcher retains only the same preparation borrow and unwinds missing or foreign custody', () => {
  // Explicit Common ports test the actual dispatch statement and its helper;
  // these opaque fixture objects are not operational Resource issuers.
  for (const mode of ['owned', 'missing-custody', 'foreign-prepared', 'read-failure']) {
    const original = {}, prepared = {}, request = {}, holder = {}, setup = {}, lease = {};
    const failure = new Error('OriginalBorrowReadFailure');
    let returned = 0, opened = 0;
    const moon = {
      clientProgramInstalledManagedPreparationBorrow(run, value, selected) {
        assert.strictEqual(this, moon); assert.strictEqual(run, original);
        assert.strictEqual(value, prepared); assert.strictEqual(selected, request); return holder;
      },
      clientProgramPreparationBorrowRead(value) {
        assert.strictEqual(this, moon); assert.strictEqual(value, holder);
        if (mode === 'read-failure') throw failure;
        return mode === 'foreign-prepared' ? {} : prepared;
      },
      clientProgramPreparationBorrowReturn(value) {
        assert.strictEqual(this, moon); assert.strictEqual(value, holder); returned++;
      },
      clientProgramOpenInstalledManagedSourceFreeHost() {opened++; return setup;},
    };
    const open = () => sourceFreeOpening()({managedRun: original}, moon, prepared,
      request, false, value => value, mode === 'missing-custody' ? undefined : lease);
    if (mode === 'owned') {
      const result = open();
      assert.strictEqual(result.setup, setup);
      assert.strictEqual(result.entry.preparationHostBorrow, holder);
      assert.equal(returned, 0); assert.equal(opened, 1);
      result.release(); result.release(); assert.equal(returned, 1);
    } else {
      assert.throws(open, mode === 'read-failure'
        ? error => error === failure : /ForeignPreparationHostCustody/);
      assert.equal(returned, 1); assert.equal(opened, 0);
    }
  }
});

test('reused Source admission refuses retirement replacement and original failure from its captured current check', async t => {
  const observations = [];
  for (const kind of ['closed', 'replacement', 'failure']) {
    const p = managedRunPorts(), prepared = {}, request = {}, original = {}, replacement = {};
    const marker = new Error('OriginalReusedSourceCurrentFailure');
    let f, armed = false, prepares = 0, begins = 0;
    p.runtime.clientProgramInstalledManagedSourceFreeBegin = () => assert.fail('No Source-empty coercion');
    p.runtime.clientProgramInstalledManagedRunBegin = (admission, value, identity) => {
      assert.strictEqual(admission, p.admission);
      assert.strictEqual(value, prepared); assert.strictEqual(identity, request);
      begins++; return p.value;
    };
    // Capture this exact callback before first begin; only its next check reenters.
    p.runtime.clientProgramInstalledManagedRunCheck = function(value, program, identity) {
      assert.strictEqual(this, p.runtime); assert.strictEqual(value, p.value);
      assert.strictEqual(program, prepared); assert.strictEqual(identity, request);
      if (!armed) return;
      const run = f.record.computeRuns.get(prepared);
      if (kind === 'closed') run.closed = true;
      if (kind === 'replacement') run.value = replacement;
      if (kind === 'failure') run.failure = marker;
    };
    const manager = {prepareRun(value) {
      assert.strictEqual(value, prepared); prepares++; return original;
    }, close: () => ({pending: false})};
    f = lifecycle({runtime: p.runtime, factory: async () => manager});
    const profile = f.preparation.bindManagedSources(p.runtime, {
      managedCaptureCapacity() {}, async prepare() {return {};}, ledgerCapacity() {return {};},
    });
    await f.preparation.prepareManagedCompute();
    assert.strictEqual(f.preparation.prepareManagedSourceRun(p.runtime, prepared, request, profile), p.value);
    armed = true;
    let returned, failure, threw = false;
    try {returned = f.preparation.prepareManagedSourceRun(p.runtime, prepared, request, profile);}
    catch (cause) {threw = true; failure = cause;}
    assert.equal(prepares, 1); assert.equal(begins, 1, 'Refusal cannot issue another admission');
    observations.push({kind, refused: threw && failure instanceof Error &&
      (kind !== 'failure' || failure === marker),
      returned: threw ? 'none' : returned === p.value ? 'original' : returned === replacement ? 'replacement' : 'other',
      markerRecorded: f.record.computeRuns.get(prepared)?.failure === marker,
      prepares, begins});
  }
  t.diagnostic(`source-reuse-current ${JSON.stringify(observations)}`);
  assert.deepEqual(observations.map(({kind, refused, prepares, begins}) =>
    ({kind, refused, prepares, begins})), ['closed', 'replacement', 'failure'].map(kind =>
    ({kind, refused: true, prepares: 1, begins: 1})));
});

test('reused Source retains same-map membership and the original Host current failure', async () => {
  for (const kind of ['map', 'live', 'request', 'host', 'failure-priority']) {
    const p = managedRunPorts(), prepared = {}, request = {}, original = {};
    const marker = new Error('OriginalHostCurrentFailure');
    let f, armed = false, currentFails = false, prepares = 0, begins = 0;
    p.runtime.clientProgramInstalledManagedRunBegin = () => {begins++; return p.value;};
    p.runtime.clientProgramInstalledManagedRunCheck = () => {
      if (!armed) return;
      const run = f.record.computeRuns.get(prepared);
      if (kind === 'map') f.record.computeRuns = new WeakMap([[prepared, {...run}]]);
      if (kind === 'live') f.record.computeLiveRuns.delete(run);
      if (kind === 'request') run.request = {};
      if (kind === 'host') currentFails = true;
      if (kind === 'failure-priority') {run.failure = marker; run.value = {};}
    };
    const manager = {prepareRun() {prepares++; return original;}, close: () => ({pending: false})};
    f = lifecycle({runtime: p.runtime, factory: async () => manager,
      current() {if (currentFails) throw marker;}});
    const profile = f.preparation.bindManagedSources(p.runtime, {
      managedCaptureCapacity() {}, async prepare() {return {};}, ledgerCapacity() {return {};},
    });
    await f.preparation.prepareManagedCompute();
    assert.strictEqual(f.preparation.prepareManagedSourceRun(p.runtime, prepared, request, profile), p.value);
    armed = true;
    assert.throws(() => f.preparation.prepareManagedSourceRun(p.runtime, prepared, request, profile),
      error => ['host', 'failure-priority'].includes(kind) ? error === marker :
        error?.code === 'ForeignInstalledComputeRun');
    assert.equal(prepares, 1); assert.equal(begins, 1);
  }
});


test('managed accounting refuses old Usage capability before any sample', () => {
  const runtime = {}, f = lifecycle({factory() {}, runtime});
  const prepared = {}, value = {}, original = {namespaceId:'n',authorityScopeCid:'a',runDefinitionCid:'r'};
  let oldReads = 0;
  runtime.clientProgramInstalledManagedRunUsage = () => {oldReads++; return Array(19).fill(0n);};
  f.record.computeRuns = new Map([[prepared,{runtime,prepared,value,closed:false}]]);
  f.preparation.bindManagedComputeRunObservation(prepared,original);
  const read = f.preparation.managedComputeUsageReader(original);
  assert.equal(typeof read,'function');
  assert.equal(read(),undefined,'An older same-size layout cannot be interpreted by the new capability');
  assert.equal(oldReads,0,'No legacy fallback or speculative second sample');
});


test('actual dispatcher retains and returns the captured original preparation borrow', () => {
  const managedRun = {}, prepared = {}, request = {}, holder = {}, lease = {}, setup = {}, calls = [];
  const moon = {
    clientProgramInstalledManagedPreparationBorrow(run, value, requested) {
      assert.strictEqual(this, moon); assert.strictEqual(run, managedRun);
      assert.strictEqual(value, prepared); assert.strictEqual(requested, request);
      calls.push('borrow'); return holder;
    },
    clientProgramPreparationBorrowRead(value) {
      assert.strictEqual(this, moon); assert.strictEqual(value, holder);
      calls.push('read'); return prepared;
    },
    clientProgramPreparationBorrowReturn(value) {
      assert.strictEqual(this, moon); assert.strictEqual(value, holder); calls.push('return');
    },
    clientProgramOpenInstalledManagedSourceFreeHost() {calls.push('open'); return setup;},
  };
  const result = sourceFreeOpening()({managedRun}, moon, prepared, request, false, value => value, lease);
  assert.strictEqual(result.setup, setup); assert.strictEqual(result.entry.preparationHostBorrow, holder);
  assert.strictEqual(result.entry.preparationHostRuntime, moon);
  moon.clientProgramPreparationBorrowReturn = () => assert.fail('No replacement return receiver');
  result.release(); result.release();
  assert.deepEqual(calls, ['borrow', 'read', 'open', 'return']);
  assert.equal(result.entry.preparationHostBorrow, undefined);
  assert.equal(result.entry.preparationHostReturn, undefined);
  assert.equal(result.entry.preparationHostRuntime, undefined);
});

test('actual dispatcher refuses foreign or missing preparation custody and returns only its same borrow', () => {
  for (const hasLease of [false, true]) {
    const managedRun = {}, prepared = {}, request = {}, holder = {}, calls = [];
    const moon = {
      clientProgramInstalledManagedPreparationBorrow(run, value, requested) {
        assert.strictEqual(this, moon); assert.strictEqual(run, managedRun);
        assert.strictEqual(value, prepared); assert.strictEqual(requested, request);
        calls.push('borrow'); return holder;
      },
      clientProgramPreparationBorrowRead(value) {
        assert.strictEqual(this, moon); assert.strictEqual(value, holder);
        calls.push('read'); return {}; // Another prepared original cannot borrow this owner.
      },
      clientProgramPreparationBorrowReturn(value) {
        assert.strictEqual(this, moon); assert.strictEqual(value, holder); calls.push('return');
      },
      clientProgramOpenInstalledManagedSourceFreeHost() {assert.fail('No Host open after custody refusal');},
    };
    assert.throws(() => sourceFreeOpening()({managedRun}, moon, prepared, request, false,
      value => value, hasLease ? {} : undefined), /ForeignPreparationHostCustody/u);
    assert.deepEqual(calls, hasLease ? ['borrow', 'read', 'return'] : ['borrow', 'return']);
  }
});


test('actual installed Effect Host forwards original Request input and joins typed retirement before manager close', async () => {
  const prepared = {}, identity = {}, requestInput = {}, plan = {}, parent = {}, original = {}, log = [];
  let retireCalls = 0;
  const runtime = {
    clientProgramEffectAcquisitionCount() {return 0;},
    clientProgramInstalledEffectOperationControlConstructionBegin() {return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationControlConstructionComplete() {return {$tag:1,_0:undefined};},
    clientProgramInstalledEffectOperationControlsRetain() {return plan;},
    clientProgramInstalledManagedRunRetire(value) {
      assert.equal(this, runtime); assert.equal(value, parent); log.push('retire');
      if (++retireCalls === 1) throw new Error('OriginalBorrowPending');
    },
    clientProgramInstalledPreparationPayloadSevered(value, actualIdentity) {
      assert.equal(value, parent); assert.equal(actualIdentity, identity); return true;
    },
    clientProgramInstalledEffectManagedOperationPlan(value, p, actualIdentity) {
      assert.equal(value, parent); assert.equal(p, prepared); assert.equal(actualIdentity, identity); return plan;
    },
  };
  const manager = {
    adoptEffectPreparation(p, input, actualIdentity, selected) {
      assert.equal(this, manager); assert.equal(p, prepared); assert.equal(input, requestInput);
      assert.equal(actualIdentity, identity); assert.equal(selected, plan); log.push('adopt');
      return {original, value: parent, operationPlan: plan};
    },
    severPreparation(p, actual) {assert.equal(p, prepared); assert.equal(actual, original); log.push('return-original-borrow');},
    retireSeveredPreparation(actual) {assert.equal(actual, original); log.push('retire-original');},
    close() {log.push('manager-close'); return {pending: false};},
  };
  const f = lifecycle({runtime, factory: async () => manager, originalRequest(value) {
    assert.equal(value, prepared); return requestInput;
  }});
  await f.preparation.prepareManagedCompute();
  const facts = Object.freeze({prepared, identity, compilation: {}, allowed: {}, definition: {},
    queryTimePreparation: undefined, modelCompiled: undefined}), inputs = {};
  const selection = Object.freeze({prepareManagedPlan(actual, selectedInputs) {
    assert.equal(actual, facts);
    assert.deepEqual(selectedInputs, {...inputs, queryContract:undefined, evidenceContract:undefined,
      installedContracts:f.originals.installation.sequenceContracts});
    return plan;
  }});
  assert.equal(f.preparation.prepareManagedEffectPlanRun(runtime, facts, selection, inputs), parent);
  await f.initialControl.close();
  assert.deepEqual(log, ['adopt', 'retire', 'return-original-borrow', 'retire', 'retire-original', 'manager-close']);
  assert.equal(f.record.computeLiveRuns.size, 0);
});


test('ordinary captured Source Host adopts its same Request Plan without detached admission ports', async () => {
  const prepared = {}, request = {}, input = {}, original = {}, parent = {}, plan = {}, profile = {};
  const calls = [];
  const runtime = {
    clientProgramInstalledManagedRunRetire() {},
    clientProgramInstalledManagedRunCheck(value, actualPrepared, actualRequest) {
      assert.equal(this, runtime); assert.equal(value, parent);
      assert.equal(actualPrepared, prepared); assert.equal(actualRequest, request); calls.push('current');
    },
  };
  const manager = {
    adoptPreparation() {assert.fail('captured Source cannot select Source-free adoption');},
    prepareRun() {assert.fail('the original Request must not mint a separate Resource Run');},
    adoptCapturePreparation(value, receipt, identity, construct) {
      assert.equal(this, manager); assert.equal(value, prepared); assert.equal(receipt, input); assert.equal(identity, request);
      assert.equal(construct(), plan); calls.push('adopt'); return {original, value: parent};
    }, close: async () => ({pending: false}),
  };
  const f = lifecycle({runtime, factory: async () => manager,
    originalRequest(value) {assert.equal(value, prepared); return input;},
    capturePlan(run) {
      assert.equal(run.prepared, prepared); assert.equal(run.request, request); assert.equal(run.sourceProfile, profile);
      calls.push('same-plan'); return plan;
    }});
  await f.preparation.prepareManagedCompute();
  assert.equal(f.preparation.prepareManagedComputeRun(runtime, prepared, request, profile), parent);
  assert.equal(f.record.computeRuns.get(prepared).preparationFunded, true);
  assert.equal(f.preparation.prepareManagedComputeRun(runtime, prepared, request, profile), parent);
  assert.deepEqual(calls, ['same-plan', 'adopt', 'current', 'current']);
  assert.throws(() => f.preparation.prepareManagedComputeRun(runtime, prepared, {}, profile),
    {code: 'ForeignInstalledComputeRun'});
  assert.equal(calls.filter(value => value === 'same-plan').length, 1);
});

test('captured Source Host retains an original undefined constructor failure without retry or another Root', async () => {
  const prepared = {}, request = {}, profile = {}; let calls = 0;
  const runtime = {clientProgramInstalledManagedRunRetire() {}, clientProgramInstalledManagedRunCheck() {}};
  const manager = {
    prepareRun() {assert.fail('no replacement Root after original failed construction');},
    adoptCapturePreparation(value, _input, identity, construct) {
      assert.equal(value, prepared); assert.equal(identity, request); return construct();
    }, close: async () => ({pending: false}),
  };
  const f = lifecycle({runtime, factory: async () => manager, capturePlan() {calls++; throw undefined;}});
  await f.preparation.prepareManagedCompute();
  for (let attempt = 0; attempt < 2; attempt++) {
    let threw = false;
    try {f.preparation.prepareManagedComputeRun(runtime, prepared, request, profile);}
    catch (cause) {threw = true; assert.equal(cause, undefined);}
    assert.equal(threw, true);
  }
  assert.equal(calls, 1);
  assert.equal(Object.hasOwn(f.record.computeRuns.get(prepared), 'failure'), true);
  assert.equal(f.record.computeRuns.get(prepared).value, undefined);
});


function capturePlanConstructor({queryTime, count, retained}) {
  const prepared = {}, request = {}, plan = {}, profile = {}, admission = {}, calls = [];
  const requirements = Array.from({length: count}, (_, index) => ({source: `source-${index}`}));
  const capacities = requirements.map(() => ({}));
  const contracts = {values: 'values-original', expression: 'fragment-original', ordered: 'ordered-original'};
  const requirementAt = (p, stage, input, originalTime, identity, registry, values, fragment, ordered) => {
    assert.equal(p, prepared); assert.equal(input, 0); assert.equal(registry, admission);
    assert.equal(values, contracts.values); assert.equal(fragment, contracts.expression); assert.equal(ordered, contracts.ordered);
    assert.equal(originalTime, queryTime); if (queryTime !== undefined) assert.equal(identity, request);
    calls.push(`requirement-${stage}`); return requirements[stage];
  };
  const runtime = {
    clientProgramSelectInstalledSourceInput(p, identity, stage, input) {
      assert.equal(p, prepared); assert.equal(identity, request); assert.equal(input, 0); return requirements[stage];
    },
    clientProgramSelectedSourceInputKind(selection) {assert.ok(requirements.includes(selection)); return 'query';},
    clientProgramSelectedSourceInputRef(selection) {assert.ok(requirements.includes(selection)); return selection.source;},
    clientProgramAcquisitionCount(p) {assert.equal(p, prepared); calls.push('inventory'); return count;},
    clientProgramPrepareLocalQueryRequirement(...args) {
      assert.equal(queryTime, undefined, 'retained QueryTime must not select the context-free requirement');
      return requirementAt(...args.slice(0, 3), undefined, undefined, ...args.slice(3));
    },
    clientProgramPrepareLocalQueryRequirementAtQueryTime(...args) {return requirementAt(...args);},
    clientProgramQueryRequirementSourceRef(requirement) {return requirement.source;},
    clientProgramInstalledManagedCaptureRunRequirements() {assert.fail('no independent Run requirements quote');},
    clientProgramInstalledManagedCapturePlanPrepare(p, identity, capture, transfer, execution, registry, values, fragment, ordered, mode, time) {
      assert.equal(this, runtime); assert.equal(p, prepared); assert.equal(identity, request);
      assert.deepEqual(capture, capacities); assert.deepEqual(transfer, capacities.map((_, i) => 7n + BigInt(i)));
      assert.deepEqual(execution, capacities.map((_, i) => 11n + BigInt(i))); assert.equal(registry, admission);
      assert.equal(values, contracts.values); assert.equal(fragment, contracts.expression); assert.equal(ordered, contracts.ordered);
      assert.equal(mode, retained); assert.equal(time, queryTime); calls.push('plan'); return plan;
    },
  };
  const adapters = requirements.map((requirement, index) => ({managedCaptureCapacity(original) {
    assert.equal(this, adapters[index]); assert.equal(original, requirement); calls.push(`capture-${index}`);
    return {capacity: capacities[index], transferBytes: 7n + BigInt(index), executionBytes: 11n + BigInt(index)};
  }}));
  const run = {runtime, prepared, request, sourceProfile: profile, closed: false, queryTimePreparation: queryTime};
  const originals = {installation: {projectRuntime: runtime, retainedRelationOutput: retained,
    managedSourceProfile: profile, computeRuns: new WeakMap([[prepared, run]])}};
  const ports = {installedManagedRunContracts(value) {assert.equal(value, originals); return contracts;},
    prepareInstalledSequenceContractOriginal(value) {assert.equal(value, originals); return {admission};},
    installedSourceFor(value, ref) {assert.equal(value, profile); return adapters[requirements.findIndex(x => x.source === ref)];},
    clientOperationError: code => Object.assign(new Error(code), {code}), checked: value => value};
  const prepare = new Function(...Object.keys(ports), text(declared('retainedManagedCaptureInventory')) +
    '\n' + text(declared('prepareManagedComputeCapturePlan')) + '\nreturn prepareManagedComputeCapturePlan;')(...Object.values(ports));
  assert.equal(prepare(originals, run), plan);
  assert.equal(Object.isFrozen(run.sourceCapacities), true);
  assert.equal(calls.filter(value => value === 'inventory').length, 1);
  assert.equal(calls.filter(value => value === 'plan').length, 1);
  for (let index = 0; index < count; index++) {
    assert.equal(calls.filter(value => value === `requirement-${index}`).length, 1);
    assert.equal(calls.filter(value => value === `capture-${index}`).length, 1);
  }
}

test('captured Host constructor forwards its same Source inventory and installed output mode once', () => {
  capturePlanConstructor({count: 2, retained: true});
});

test('captured Host constructor keeps the same QueryTime requirement without context substitution', () => {
  capturePlanConstructor({count: 1, retained: false, queryTime: {}});
});


// Actual extracted Host retirement/initial close and actual Model Run helper.
// Model/Scope/manager/native retirement are explicit ports; no physical ACK,
// installed Account, Model provider or complete normal backing is issued here.
async function modelEffectLifecycle({failure} = {}) {
  const prepared = {}, identity = {}, requestInput = {}, plan = {}, parent = {}, original = {}, scope = {}, demand = {};
  const model = Object.freeze({kind: 'local-mock', compiled: {}, definition: {}, occurrence: {}, graph: {}});
  const facts = Object.freeze({prepared, identity, compilation: {}, allowed: {}, definition: model.definition,
    modelCompiled: model.compiled, queryTimePreparation: undefined});
  const calls = []; let pending = true, f;
  const runtime = {
    clientProgramInstalledEffectModelDemandPrepare() {return demand;},
    clientProgramInstalledEffectPlanMatchesModelDemand(p, selected) {return p === plan && selected === demand;},
    clientProgramInstalledEffectOperationControlsBegin() {return plan;},
    clientProgramInstalledEffectManagedOperationPlan(value, actual, request) {
      assert.equal(value, parent); assert.equal(actual, prepared); assert.equal(request, identity); return plan;
    },
    clientProgramFinishInferOriginalReadScope(value, compiled, definition, graph, complete) {
      assert.equal(this, runtime); assert.equal(value, scope); assert.equal(compiled, model.compiled);
      assert.equal(definition, model.definition); assert.equal(graph, model.graph); assert.equal(complete, true);
      calls.push('scope'); return !pending;
    },
    clientProgramInstalledManagedRunRetire(value) {assert.equal(value, parent); assert.equal(pending, false); calls.push('retire-parent');},
  };
  const manager = {
    adoptEffectModelPreparation(actual, input, request, selected, run) {
      assert.equal(this, manager); assert.equal(actual, prepared); assert.equal(input, requestInput);
      assert.equal(request, identity); assert.equal(selected, plan); assert.equal(run, f.record.computeRuns.get(prepared));
      run.original = original; run.modelScope = scope; calls.push('adopt');
      if (failure !== undefined) throw failure;
      return {original, operationPlan: plan, value: parent};
    },
    severPreparation(actual, selected) {
      assert.equal(actual, prepared); assert.equal(selected, original);
      const run = f.record.computeRuns.get(prepared);
      for (const field of ['modelScope', 'model', 'modelDemand', 'definitionOriginal', 'operationPlan', 'requestInput', 'selection']) {
        assert.equal(run[field], undefined, field);
      }
      calls.push('return-original-input');
    },
    retireSeveredPreparation(selected) {assert.equal(selected, original); calls.push('retire-original');},
    retireRun() {assert.fail('partial same Request has no separate manager Run');},
    close() {assert.equal(pending, false); calls.push('manager-close'); return {pending: false};},
  };
  f = lifecycle({runtime, factory: async () => manager,
    originalRequest(value) {assert.equal(value, prepared); return requestInput;}});
  await f.preparation.prepareManagedCompute();
  const selected = Object.freeze({prepareManagedPlan(actual, inputs) {
    assert.equal(actual, facts); assert.equal(inputs.modelDemand, demand); return plan;
  }});
  return {...f, calls, prepared, parent, runtime, facts, selected, model,
    settle() {pending = false;}};
}

test('Host Model Request retirement waits for Scope then cuts compiler aliases before original input return', async () => {
  const f = await modelEffectLifecycle();
  assert.equal(f.preparation.prepareManagedEffectPlanRun(f.runtime, f.facts, f.selected, {}, f.model), f.parent);
  await assert.rejects(f.initialControl.close(), {code: 'InstalledEffectModelScopeCleanupPending'});
  assert.deepEqual(f.calls, ['adopt', 'scope']);
  f.settle(); await f.initialControl.close();
  assert.deepEqual(f.calls, ['adopt', 'scope', 'scope', 'retire-parent', 'return-original-input',
    'retire-parent', 'retire-original', 'manager-close']);
  assert.equal(f.record.computeLiveRuns.size, 0);
});

test('Host partial Model Request finishes only its Scope and leaves original parent cleanup to manager', async () => {
  const failure = new Error('OriginalModelAdoptionFailure'), f = await modelEffectLifecycle({failure});
  assert.throws(() => f.preparation.prepareManagedEffectPlanRun(f.runtime, f.facts, f.selected, {}, f.model), cause => cause === failure);
  await assert.rejects(f.initialControl.close(), {code: 'InstalledEffectModelScopeCleanupPending'});
  f.settle(); await f.initialControl.close();
  assert.deepEqual(f.calls, ['adopt', 'scope', 'scope', 'manager-close']);
  assert.equal(f.record.computeLiveRuns.size, 0);
});

// Actual pre-Plan Host functions with explicit typed selection/capacity ports.
// This does not execute a compiled Common ABI, physical Source or ordinary Run.
function wholeSourcePlanConstructor({capacityFailure, invalidate = false} = {}) {
  const prepared = {}, request = {}, plan = {}, profile = {}, admission = {}, selection = {}, capacity = {};
  const calls = [], contracts = {values: 'same-values', expression: 'same-fragment', ordered: 'same-ordered'};
  const run = {prepared, request, sourceProfile: profile, closed: false};
  const runtime = {
    clientProgramAcquisitionCount(value) {assert.equal(value, prepared); calls.push('original-prefix'); return 1;},
    clientProgramSelectInstalledSourceInput(value, identity, stage, input) {
      assert.equal(value, prepared); assert.equal(identity, request); assert.equal(stage, 0); assert.equal(input, 0);
      calls.push('select-original'); return selection;
    },
    clientProgramSelectedSourceInputKind(value) {assert.equal(value, selection); return 'whole-input';},
    clientProgramSelectedSourceInputRef(value) {assert.equal(value, selection); return 'same-source';},
    clientProgramPrepareLocalQueryRequirement() {assert.fail('Whole input must not fabricate a Query requirement');},
    clientProgramInstalledManagedCapturePlanPrepare() {assert.fail('Whole capacity must not be cast to a Query capacity array');},
    clientProgramPrepareInstalledManagedWholeSourcePlan(value, identity, selected, transfer, execution,
      registry, values, fragment, ordered, retained) {
      assert.equal(this, runtime); assert.equal(value, prepared); assert.equal(identity, request); assert.equal(selected, capacity);
      assert.equal(transfer, 17n); assert.equal(execution, 29n); assert.equal(registry, admission);
      assert.equal(values, contracts.values); assert.equal(fragment, contracts.expression); assert.equal(ordered, contracts.ordered);
      assert.equal(retained, true); calls.push('whole-plan'); return plan;
    },
  };
  run.runtime = runtime;
  const originals = {installation: {projectRuntime: runtime, retainedRelationOutput: true,
    managedSourceProfile: profile, computeRuns: new WeakMap([[prepared, run]])}};
  const adapter = {managedWholeSourceCapacity(facts) {
    assert.equal(this, adapter); assert.equal(facts.preparedProgram, prepared);
    assert.equal(facts.sourceSelection, selection); assert.equal(facts.installedContracts, admission);
    calls.push('whole-capacity'); if (capacityFailure !== undefined) throw capacityFailure;
    if (invalidate) run.closed = true;
    return Object.freeze({capacity, wholeInput: true, transferBytes: 17n, executionBytes: 29n});
  }, managedCaptureCapacity() {assert.fail('No Query fallback after a whole-input refusal');}};
  const ports = {installedManagedRunContracts(value) {assert.equal(value, originals); return contracts;},
    prepareInstalledSequenceContractOriginal(value) {assert.equal(value, originals); return {admission};},
    installedSourceFor(value, ref) {assert.equal(value, profile); assert.equal(ref, 'same-source'); return adapter;},
    clientOperationError: code => Object.assign(new Error(code), {code}), checked: value => value};
  const prepare = new Function(...Object.keys(ports), text(declared('retainedManagedCaptureInventory')) +
    '\n' + text(declared('prepareManagedComputeCapturePlan')) + '\nreturn prepareManagedComputeCapturePlan;')(...Object.values(ports));
  return {prepare: invocation => prepare(originals, run, invocation), calls, plan, run, runtime,
    expectedArgs: [prepared,request,capacity,17n,29n,admission,contracts.values,contracts.expression,contracts.ordered,true]};
}

test('whole Source Host constructor retains the original typed input without a Query or zero-prefix classifier', () => {
  const f = wholeSourcePlanConstructor();
  assert.equal(f.prepare(), f.plan);
  assert.deepEqual(f.calls, ['original-prefix', 'select-original', 'whole-capacity', 'whole-plan']);
  assert.equal(Object.isFrozen(f.run.sourceCapacities), true);
  assert.equal(f.run.sourceCapacities[0].kind, 'whole-input');
});

test('whole Source Host constructor keeps the original refusal and post-capacity retirement without fallback', () => {
  const original = new Error('original selected capacity refused');
  const refused = wholeSourcePlanConstructor({capacityFailure: original});
  assert.throws(refused.prepare, error => error === original);
  assert.equal(refused.run.sourceCapacities, undefined);
  assert.equal(refused.calls.includes('whole-plan'), false);
  const retired = wholeSourcePlanConstructor({invalidate: true});
  assert.throws(retired.prepare, {code: 'ForeignInstalledComputeRun'});
  assert.equal(retired.calls.includes('whole-plan'), false);
});

function wholeSourceDispatchBlock(ports) {
  const actual = readFileSync(new URL('./client-dispatch-owner.mjs', import.meta.url), 'utf8');
  const tree = parse(actual, {ecmaVersion: 'latest', sourceType: 'module'});
  const matches = [];
  visit(tree, node => {
    if (node.type === 'IfStatement' && node.test.type === 'Identifier' && node.test.name === 'singleAccounted' &&
        actual.slice(node.consequent.start, node.consequent.end).includes('const capture = entry.sourceCapture.capture;')) {
      matches.push(node.consequent);
    }
  });
  assert.equal(matches.length, 1);
  return new Function(...Object.keys(ports), 'let setup;\n' +
    actual.slice(matches[0].start, matches[0].end) + '\nreturn setup;')(...Object.values(ports));
}

test('whole Source dispatch opens its adopted Plan before binding the same capture to its retained Compute', () => {
  const parent = {}, prepared = {}, request = {}, sourceOriginal = {}, setup = {}, dag = {}, order = [];
  const entry = {};
  const capture = {source: () => sourceOriginal, retainTask(actual, task) {
    assert.equal(actual, dag); assert.equal(task, 0); assert.equal(entry.pendingSetup, setup);
    order.push('bind-original');
  }};
  entry.sourceCapture = {capture};
  const moon = {clientProgramOpenInstalledManagedCaptureHost(owner, p, r, captures) {
    assert.equal(this, moon); assert.equal(owner, parent); assert.equal(p, prepared); assert.equal(r, request);
    assert.deepEqual(captures, [sourceOriginal]); order.push('open-adopted'); return setup;
  }, strategyHostRun(value) {assert.equal(value, setup); return dag;},
  clientProgramOpenSingleCapturedLocalHost() {assert.fail('No independent captured Host/compiler');}};
  const ports = {entry, moon, held: {managedRun: parent}, preparedProgram: prepared, requested: request,
    preparationLease: {}, checked: value => value,
    retainDispatchPreparationHost(actual, runtime, owner, p, r, custody) {
      assert.equal(actual, entry); assert.equal(runtime, moon); assert.equal(owner, parent);
      assert.equal(p, prepared); assert.equal(r, request); assert.equal(custody, true); order.push('retain-original');
    }};
  assert.equal(wholeSourceDispatchBlock(ports), setup);
  assert.equal(entry.borrowedSources, true);
  assert.deepEqual(order, ['retain-original', 'open-adopted', 'bind-original']);
});

test('whole Source dispatch preserves the same opener refusal without legacy construction or fabricated pending setup', () => {
  const original = new Error('actual adopted Plan refused');
  const entry = {sourceCapture: {capture: {source: () => ({}), retainTask() {assert.fail('No bind after refusal');}}}};
  const ports = {entry, moon: {clientProgramOpenInstalledManagedCaptureHost() {throw original;},
    clientProgramOpenSingleCapturedLocalHost() {assert.fail('No legacy fallback');}},
    held: {managedRun: {}}, preparedProgram: {}, requested: {}, preparationLease: {},
    checked: value => value, retainDispatchPreparationHost() {}};
  assert.throws(() => wholeSourceDispatchBlock(ports), error => error === original);
  assert.equal(entry.pendingSetup, undefined);
  delete ports.moon.clientProgramOpenInstalledManagedCaptureHost;
  assert.throws(() => wholeSourceDispatchBlock(ports), {message: 'InstalledManagedComputeHostUnavailable'});
  assert.equal(entry.pendingSetup, undefined);
});

test('whole Source submission retains its returned same-parent Run before preparing physical Source inputs', () => {
  const matches = [];
  visit(ast, node => {
    if (node.type !== 'BlockStatement') return;
    const index = node.body.findIndex(statement => statement.type === 'VariableDeclaration' &&
      statement.declarations.some(value => value.id.name === 'managedSourceRun'));
    if (index >= 0) matches.push(node.body.slice(index, index + 3));
  });
  assert.equal(matches.length, 1);
  const prepared = {}, request = {}, profile = {}, runtime = {}, original = {}, calls = [];
  const preparation = {prepareManagedSourceRun(moon, p, r, sourceProfile) {
    assert.equal(moon, runtime); assert.equal(p, prepared); assert.equal(r, request); assert.equal(sourceProfile, profile);
    calls.push('adopt-original'); return original;
  }, prepareManagedComputeRun() {assert.fail('Whole Source must not select Source-free adoption');}};
  const ports = {preparation, selectedModel: undefined, acquisitionCount: 1, sourceProfile: profile,
    submission: {preparedProgram: prepared}, requested: request, inferSelections: new WeakMap(),
    moon: {clientProgramSerializationOccurrences: () => []},
    prepareTimedRunInvocation: () => assert.fail('No untimed clock or invocation construction')};
  // The exact original runtime argument remains distinct from constructor DATA.
  ports.moon = runtime; runtime.clientProgramSerializationOccurrences = () => [];
  const result = new Function(...Object.keys(ports), matches[0].map(text).join('\n') + '\nreturn managedRun;')(...Object.values(ports));
  assert.equal(result, original); assert.deepEqual(calls, ['adopt-original']);
});

test('native Source submission retains the original Run returned by its installed profile', () => {
  const matches=[];
  visit(ast,node=>{
    if(node.type!=='BlockStatement')return;
    const index=node.body.findIndex(statement=>statement.type==='VariableDeclaration'&&
      statement.declarations.some(value=>value.id.name==='managedSourceRun'));
    if(index>=0)matches.push(node.body.slice(index,index+3));
  });
  assert.equal(matches.length,1);
  const prepared={},request={},original={},invocation=()=>{},calls=[];
  const profile={prepareManagedRun(p,r,sample){
    assert.strictEqual(this,profile);assert.strictEqual(p,prepared);
    assert.strictEqual(r,request);assert.strictEqual(sample,invocation);
    calls.push('same-profile-original');return original;
  }};
  const runtime={clientProgramSerializationOccurrences:()=>[]};
  const ports={preparation:{
    prepareManagedSourceRun(){assert.fail('No second Host constructor');},
    prepareManagedComputeRun(){assert.fail('No Source-free substitution');},
  },selectedModel:undefined,acquisitionCount:1,sourceProfile:profile,
  submission:{preparedProgram:prepared},requested:request,inferSelections:new WeakMap(),
  moon:runtime,prepareTimedRunInvocation:invocation};
  const invoke=new Function(...Object.keys(ports),matches[0].map(text).join('\n')+'\nreturn managedRun;');
  assert.strictEqual(invoke(...Object.values(ports)),original);
  assert.deepEqual(calls,['same-profile-original']);
  const failure=new Error('OriginalNativeSourceParentRefused');
  profile.prepareManagedRun=function(){assert.strictEqual(this,profile);throw failure;};
  assert.throws(()=>invoke(...Object.values(ports)),error=>error===failure);
});

async function wholeSourceLedgerBlock({foreign = false, missing = false, currentFailure} = {}) {
  const actual = readFileSync(new URL('./client-dispatch-owner.mjs', import.meta.url), 'utf8');
  const tree = parse(actual, {ecmaVersion: 'latest', sourceType: 'module'});
  const matches = [];
  visit(tree, node => {
    if (node.type === 'IfStatement' && node.test.type === 'Identifier' && node.test.name === 'singleAccounted' &&
        actual.slice(node.consequent.start, node.consequent.end).includes('const capacity = installedSource.ledgerCapacity(')) {
      matches.push(node.consequent);
    }
  });
  assert.equal(matches.length, 1);
  const parent = {}, prepared = {}, request = {}, selected = {}, ledger = {}, access = {}, preparedSource = {}, entry = {}, calls = [];
  const moon = {clientProgramInstalledManagedWholeSourceLedger(owner, p, r, capacity, transfer, execution) {
    assert.equal(this, moon); assert.equal(owner, parent); assert.equal(p, prepared); assert.equal(r, request);
    assert.equal(capacity, selected); assert.equal(transfer, 19n); assert.equal(execution, 31n);
    calls.push('same-whole-ledger'); if (currentFailure !== undefined) throw currentFailure; return ledger;
  }, clientProgramInstalledManagedRunPrepareLedger() {assert.fail('Whole capacity is not an array of Query capacities');},
  clientProgramPrepareSingleCapturedLocalInstalledLedger() {assert.fail('No legacy scalar or replacement Ledger');}};
  if (missing) delete moon.clientProgramInstalledManagedWholeSourceLedger;
  const ports = {entry, moon, checkpoints: undefined, submission: {requestId: 'same-request'},
    installedSource: {sourceAccess: access, ledgerCapacity(value) {
      assert.equal(value, preparedSource); return {managedRun: foreign ? {} : parent, wholeInput: true,
        capacity: selected, transferBytes: 19n, executionBytes: 31n};
    }}, held: {managedRun: parent, preparedSourceAccess: access, preparedSource},
    preparedProgram: prepared, requested: request, checked: value => value};
  const result = await new AsyncFunction(...Object.keys(ports), 'let ledger;\n' +
    actual.slice(matches[0].start, matches[0].end) + '\nreturn ledger;')(...Object.values(ports));
  assert.equal(result, ledger); assert.equal(entry.acquisitionLedger, ledger);
  assert.deepEqual(calls, ['same-whole-ledger']);
}

test('whole Source ledger selection consumes only its same original Run and typed capacity with current refusal intact', async () => {
  await wholeSourceLedgerBlock();
  for (const options of [{foreign: true}, {missing: true}]) {
    await assert.rejects(wholeSourceLedgerBlock(options), {message: 'InstalledSingleSourceOriginalRunUnavailable'});
  }
  const original = new Error('original current refused');
  await assert.rejects(wholeSourceLedgerBlock({currentFailure: original}), error => error === original);
});

test('whole Source Result-placement guard reads only its original adopted physical Plan and preserves refusal', () => {
  const actual = readFileSync(new URL('./client-dispatch-owner.mjs', import.meta.url), 'utf8');
  const tree = parse(actual, {ecmaVersion: 'latest', sourceType: 'module'}), matches = [];
  visit(tree, node => {
    if (node.type === 'IfStatement' && actual.slice(node.consequent.start, node.consequent.end)
      .includes('const requiresAcquisitionResult =')) matches.push(node);
  });
  assert.equal(matches.length, 1);
  const owner = {}, prepared = {}, request = {}, original = new Error('original Plan current refused');
  const moon = {clientProgramInstalledManagedRequiresAcquisitionResultPublication(parent, p, r) {
    assert.equal(this, moon); assert.equal(parent, owner); assert.equal(p, prepared); assert.equal(r, request); return false;
  }, clientProgramRequiresAcquisitionResultPublication() {assert.fail('Original prefix1 is not the selected whole Plan graph');}};
  const ports = {inferring: false, serializing: false, generatingContent: false,
    held: {managedRun: owner}, moon, preparedProgram: prepared, requested: request, checked: value => value};
  const run = () => new Function(...Object.keys(ports), actual.slice(matches[0].start, matches[0].end))(...Object.values(ports));
  run();
  moon.clientProgramInstalledManagedRequiresAcquisitionResultPublication = () => true;
  assert.throws(run, {message: 'InstalledAcquisitionResultPublicationUnsupported'});
  moon.clientProgramInstalledManagedRequiresAcquisitionResultPublication = () => {throw original;};
  assert.throws(run, error => error === original);
  delete moon.clientProgramInstalledManagedRequiresAcquisitionResultPublication;
  assert.throws(run, {message: 'InstalledManagedSourcePlanUnavailable'});
});

test('whole Source capacity facade captures the original method and receiver without issuing a new Run', () => {
  const selection = {}, prepared = {}, contracts = {}, selected = {};
  const facts = {preparedProgram: prepared, sourceSelection: selection, installedContracts: contracts};
  const source = {prepare() {}, ledgerCapacity() {}, managedCaptureCapacity() {},
    managedWholeSourceCapacity(value) {assert.equal(this, source); assert.equal(value, facts); return selected;}};
  const bound = bindInstalledManagedSources(source, () => assert.fail('Pre-Plan capacity cannot issue/adopt a Run'));
  source.managedWholeSourceCapacity = () => assert.fail('Original fixed method must be retained');
  assert.equal(bound.managedWholeSourceCapacity(facts), selected);
});

test('funded policy Source original preserves the same request verifier and signal without compute fallback', async () => {
  const request = {}, originalRequest = {}, environment = {}, result = {}, verifier = () => {};
  const signal = new AbortController().signal, events = [];
  const source = {fundedPreparation(value, selected, callback, actualSignal) {
    assert.equal(this, source); assert.equal(value, originalRequest); assert.equal(selected, environment);
    assert.equal(callback, verifier); assert.equal(actualSignal, signal); events.push('source');
    return Promise.resolve(result);
  }, close() {return {pending: false};}};
  const compute = {fundedPreparation() {assert.fail('The original Source manager must not fall through to compute');},
    close() {return {pending: false};}};
  const f = lifecycle({source, factory: async () => compute,
    originalRequest(value) {assert.equal(value, request); events.push('same-request'); return originalRequest;},
    current(manager) {if (manager !== undefined) events.push(manager === source ? 'source-current' : 'compute-current');}});
  // Actual Source mode already has its original manager and refuses opening a separate compute manager.
  events.length = 0;
  try {
    assert.equal(await f.preparation.fundedPreparation(request, environment, verifier, signal), result);
    assert.deepEqual(events, ['source-current', 'same-request', 'source']);
  } finally {await f.initialControl.close();}
});

test('funded policy Source current refusal keeps its original cause before mapping or compute fallback', async () => {
  const cause = new Error('original Source installation is no longer current');
  let refuse = false, mapped = 0, calls = 0;
  const source = {fundedPreparation() {calls++; assert.fail('A refused Source cannot enter preparation');},
    close() {return {pending: false};}};
  const compute = {fundedPreparation() {assert.fail('A current Source refusal is not optional compute selection');},
    close() {return {pending: false};}};
  const f = lifecycle({source, factory: async () => compute,
    originalRequest() {mapped++; assert.fail('Refuse before original request projection');},
    current(manager) {if (refuse && manager === source) throw cause;}});
  refuse = true;
  try {
    assert.throws(() => f.preparation.fundedPreparation({}, {}, () => {}, undefined), error => error === cause);
    assert.equal(mapped, 0); assert.equal(calls, 0);
  } finally {refuse = false; await f.initialControl.close();}
});


async function timedInstallingFixture({captured=false,failRetire=false,failConstruction=false,failSever=false}={}){
  const p=managedRunPorts(),prepared={},request={},sdkRequest={},artifact={},original={},time={},context={},scope={},option=new Proxy({}, {get(){assert.fail('opaque Core Option inspected');}});
  let view;const events=[];
  let f,retireAttempts=0,severAttempts=0;
  const marker=Object.assign(Error('original pending retirement'),{cleanupPending:true});
  p.runtime.clientProgramInstalledManagedRunRetire=function(actual){assert.equal(this,p.runtime);assert.equal(actual,p.value);events.push('retire');if(failRetire&&++retireAttempts===1)throw marker;};
  p.runtime.clientProgramInstalledPreparationPayloadSevered=()=>false;
  const manager={
    adoptPreparation(p,r,id,construct){assert.equal(p,prepared);assert.equal(r,sdkRequest);assert.equal(id,request);assert.equal(construct(artifact),option);if(failConstruction)throw marker;events.push('adopt');return {original,value:pRuntimeValue()};},
    adoptCapturePreparation(p,r,id,plan,construct){assert.equal(p,prepared);assert.equal(r,sdkRequest);assert.equal(id,request);assert.equal(construct(artifact),option);assert.equal(plan(),scope);if(failConstruction)throw marker;events.push('adopt');return {original,value:pRuntimeValue()};},
    severPreparation(p,r){assert.equal(p,prepared);assert.equal(r,original);events.push('sever');if(failSever&&++severAttempts===1){events.push('consume-holder');throw marker;}},
    retireSeveredPreparation(r){assert.equal(r,original);events.push('finish');},
    close(){return {pending:false};},
  };
  function pRuntimeValue(){return p.value;}
  f=lifecycle({runtime:p.runtime,factory:async()=>manager,originalRequest:value=>{assert.equal(value,prepared);return sdkRequest;},capturePlan(run){assert.equal(run.queryTimePreparation,time);assert.equal(run.queryInvocation,view);events.push('capture-plan');return scope;},invocationControl:{checkedClientManagedQueryInvocationOriginal(actual,p,retained){assert.equal(actual,pRuntimeValue());assert.equal(p,prepared);assert.equal(retained,view);events.push('read-original');return retained;}}});
  await f.preparation.prepareManagedCompute();
  const factory=(p,r,a,retained)=>{assert.equal(p,prepared);assert.equal(r,request);assert.equal(a,artifact);assert.equal(f.record.computeRuns.get(prepared).queryInvocation,retained);view=Object.freeze(Object.assign(retained,{queryTimePreparation:time,queryTime:context,compiled:{},runDefinition:{}}));events.push('construct');return Object.freeze({original:option,retained:view});};
  const begin=fn=>f.preparation.prepareManagedComputeRun(p.runtime,prepared,request,captured?scope:undefined,fn);
  return {...f,p,prepared,request,get view(){return view;},events,scope,marker,begin,factory};
}

test('timed installing caller retains first view before captured Plan and never retains Option carrier',async()=>{
  for(const captured of [false,true]){
    const f=await timedInstallingFixture({captured});assert.equal(f.begin(f.factory),f.p.value);
    const run=f.record.computeRuns.get(f.prepared);assert.equal(run.queryInvocation,f.view);assert.equal(run.queryTimePreparation,f.view.queryTimePreparation);assert.equal(Object.hasOwn(run,'prepareInvocation'),false);
    assert.equal(Object.hasOwn(run.queryInvocation,'original'),false);assert.equal(Object.hasOwn(run.queryInvocation,'invocationOriginal'),false);
    assert.equal(f.begin(()=>assert.fail('replacement constructor must not run')),f.p.value);
    assert.equal(f.preparation.managedComputeInvocationOriginal(f.p.runtime,f.prepared),f.view);
    assert.deepEqual(f.events,['construct',...(captured?['capture-plan']:[]),'adopt','read-original']);
    const finish=f.preparation.retireManagedComputeRun(f.prepared);assert.equal(run.queryInvocation,undefined);assert.equal(run.queryTimePreparation,undefined);finish();await f.initialControl.close();
  }
});

test('timed installing caller keeps immutable view through pending retirement then clears at original sever',async()=>{
  const f=await timedInstallingFixture({failRetire:true});f.begin(f.factory);const run=f.record.computeRuns.get(f.prepared);
  assert.throws(()=>f.preparation.retireManagedComputeRun(f.prepared),e=>e===f.marker);assert.equal(run.queryInvocation,f.view);assert.equal(run.closed,false);
  const finish=f.preparation.retireManagedComputeRun(f.prepared);assert.equal(run.queryInvocation,undefined);assert.equal(run.closed,true);
  assert.throws(()=>f.preparation.managedComputeInvocationOriginal(f.p.runtime,f.prepared),{code:'NodeManagedRunRuntimeUnavailable'});finish();await f.initialControl.close();
  assert.equal(f.events.filter(e=>e==='construct').length,1);assert.equal(f.events.filter(e=>e==='sever').length,1);
});

test('timed installing caller retains failed original construction and never invokes another factory',async()=>{
  const f=await timedInstallingFixture({failConstruction:true});
  for(let n=0;n<2;n++)assert.throws(()=>f.begin(f.factory),e=>e===f.marker);
  assert.equal(f.events.filter(e=>e==='construct').length,1);const run=f.record.computeRuns.get(f.prepared);assert.equal(run.queryInvocation,f.view);
  assert.throws(()=>f.preparation.managedComputeInvocationOriginal(f.p.runtime,f.prepared),{code:'NodeManagedRunRuntimeUnavailable'});
  // This explicit component manager owns no admitted Core value on failure.
  // Its original close is selected; no physical acknowledgement is inferred.
  await f.initialControl.close();
});

test('timed installing fixed Host callback forwards actual Request header and original compiler exactly once',()=>{
  let declaration;visit(declared('openInstalledHost').body,node=>{if(node.type==='VariableDeclarator'&&node.id?.name==='prepareTimedRunInvocation')declaration=node;});assert(declaration);
  const prepared={},request={},artifact={},control={},retained={runDefinition:{wire:'saved-original-header'}},calls=[];
  let captured=false,task=false;
  const namespaceId='namespace',authorityScopeCid='authority',now=()=>assert.fail('only original callee samples');
  const moon={clientProgramAcquisitionCount:p=>{assert.equal(p,prepared);return captured?1:0;},clientProgramRequiresTaskCompilation:p=>{assert.equal(p,prepared);return task;}};
  const journal={resolveDefinition(r,scope,m,c){assert.equal(r,request);assert.deepEqual(scope,{namespaceId});assert.equal(m,moon);assert.equal(c,control);calls.push('lookup-original');return retained;}};
  const callback=Function('journal','namespaceId','moon','control','prepareTimedClientInvocation','authorityScopeCid','now','return '+text(declaration.init))(journal,namespaceId,moon,control,options=>{assert.equal(options.control,control);assert.equal(options.preparedProgram,prepared);assert.equal(options.requestIdentity,request);assert.equal(options.compilationOriginal,artifact);assert.equal(options.now,now);assert.equal(options.retainedDefinitionWire,retained.runDefinition.wire);return options;},authorityScopeCid,now);
  assert.equal(callback(prepared,request,artifact).kind,'values');task=true;assert.equal(callback(prepared,request,artifact).kind,'tasks');task=false;captured=true;assert.equal(callback(prepared,request,artifact).kind,'tasks');assert.equal(calls.length,3);
});


test('timed whole Source caller uses the exact transient Core Option at the matching typed port',()=>{
  const f=wholeSourcePlanConstructor(),time={},opaque=new Proxy({}, {get(){assert.fail('opaque Option inspected');}});
  f.run.queryTimePreparation=time;
  f.runtime.clientProgramPrepareInstalledManagedWholeSourcePlan=()=>assert.fail('No legacy whole plan for timed input');
  f.runtime.clientProgramPrepareInstalledManagedWholeSourcePlanAtQueryTime=function(...args){
    assert.equal(this,f.runtime);assert.equal(args.length,11);assert.deepEqual(args.slice(0,10),f.expectedArgs);assert.equal(args[10],opaque);
    f.calls.push('timed-whole-plan');return f.plan;
  };
  assert.equal(f.prepare(opaque),f.plan);assert.equal(f.run.queryTimePreparation,time);
  assert.equal(Object.values(f.run).includes(opaque),false);
  assert.deepEqual(f.calls,['original-prefix','select-original','whole-capacity','timed-whole-plan']);
});

test('timed whole Source caller refuses an absent typed port and retains exact Core refusal or retirement',()=>{
  const unavailable=wholeSourcePlanConstructor();unavailable.run.queryTimePreparation={};
  unavailable.runtime.clientProgramPrepareInstalledManagedWholeSourcePlan=()=>assert.fail('No old whole or Query fallback');
  assert.throws(()=>unavailable.prepare({}),{code:'NodeManagedRunRuntimeUnavailable'});
  for(const retired of [false,true]){
    const f=wholeSourcePlanConstructor(),opaque={},original=Object.assign(Error('same typed constructor refusal'),{cleanupPending:true});f.run.queryTimePreparation={};
    f.runtime.clientProgramPrepareInstalledManagedWholeSourcePlan=()=>assert.fail('No old fallback');
    f.runtime.clientProgramPrepareInstalledManagedWholeSourcePlanAtQueryTime=function(...args){assert.equal(this,f.runtime);assert.equal(args[10],opaque);if(retired){f.run.closed=true;return f.plan;}throw original;};
    if(retired)assert.throws(()=>f.prepare(opaque),{code:'ForeignInstalledComputeRun'});
    else assert.throws(()=>f.prepare(opaque),e=>e===original);
  }
});

test('timed whole Source installing closure forwards manager Option transiently without retaining a second carrier',async()=>{
  const p=managedRunPorts(),prepared={},request={},sdkRequest={},artifact={},original={},scope={},time={},view=Object.freeze({queryTimePreparation:time}),opaque=new Proxy({}, {get(){assert.fail('opaque Option inspected');}});
  let planCalls=0;
  const manager={adoptCapturePreparation(a,b,c,plan,construct){assert.equal(a,prepared);assert.equal(b,sdkRequest);assert.equal(c,request);const invocation=construct(artifact);assert.equal(invocation,opaque);assert.equal(plan(invocation),scope);return {original,value:p.value};},severPreparation(){},retireSeveredPreparation(){},close(){return {pending:false};}};
  const f=lifecycle({runtime:p.runtime,factory:async()=>manager,originalRequest:a=>{assert.equal(a,prepared);return sdkRequest;},capturePlan(run,invocation){planCalls++;assert.equal(run.queryTimePreparation,time);assert.equal(invocation,opaque);return scope;}});
  await f.preparation.prepareManagedCompute();
  assert.equal(f.preparation.prepareManagedComputeRun(p.runtime,prepared,request,scope,(a,b,c)=>{assert.equal(a,prepared);assert.equal(b,request);assert.equal(c,artifact);return {original:opaque,retained:view};}),p.value);
  const run=f.record.computeRuns.get(prepared);assert.equal(run.queryInvocation,view);assert.equal(Object.values(run).includes(opaque),false);assert.equal(planCalls,1);
  const finish=f.preparation.retireManagedComputeRun(prepared);assert.equal(run.queryInvocation,undefined);finish();await f.initialControl.close();
});


test('timed installing Host retains partial original carrier before a throwing invocation issuer',async()=>{
  const f=await timedInstallingFixture();let carrier;const compiled={},primary=Object.freeze(Error('partial first invocation'));
  const construct=(prepared,request,artifact,held)=>{
    assert.equal(prepared,f.prepared);assert.equal(request,f.request);
    assert.equal(f.record.computeRuns.get(f.prepared).queryInvocation,held);
    carrier=held;held.compiled=compiled;throw primary;
  };
  assert.throws(()=>f.begin(construct),error=>error===primary);
  const run=f.record.computeRuns.get(f.prepared);assert.equal(run.failure,primary);
  assert.equal(run.queryInvocation,carrier);assert.equal(carrier.compiled,compiled);
  assert.throws(()=>f.begin(()=>assert.fail('no replacement issuer')),error=>error===primary);
  await f.initialControl.close();
});

test('timed installing caller cuts invocation aliases before consumed parent settlement can throw',async()=>{
  const f=await timedInstallingFixture({failSever:true});f.begin(f.factory);
  const run=f.record.computeRuns.get(f.prepared),originalView=f.view;
  assert.equal(run.queryInvocation,originalView);
  assert.throws(()=>f.preparation.retireManagedComputeRun(f.prepared),error=>error===f.marker);
  assert.equal(run.queryInvocation,undefined);assert.equal(run.queryTimePreparation,undefined);
  assert.equal(run.prepared,f.prepared);assert.equal(run.closed,false);
  const finish=f.preparation.retireManagedComputeRun(f.prepared);
  assert.equal(run.prepared,undefined);assert.equal(run.closed,true);
  assert.equal(f.events.filter(event=>event==='consume-holder').length,1);
  assert.equal(f.events.filter(event=>event==='construct').length,1);
  finish();await f.initialControl.close();
});
