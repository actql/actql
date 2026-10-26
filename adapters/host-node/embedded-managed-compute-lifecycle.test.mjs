import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {installedHostShutdown} from './embedded-local-lifecycle.mjs';
import {bindInstalledManagedSources} from './installed-managed-source.mjs';

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
  consumerRetire = () => {}, install = true} = {}) {
  const opening = declared('openInstalledHost');
  const functions = new Map(opening.body.body.filter(node => node.type === 'FunctionDeclaration')
    .map(node => [node.id.name,node]));
  let getter;
  visit(opening.body,node => {
    if (node.type === 'FunctionDeclaration' && node.id.name === 'getPreparedSourceEnvironment') {
      assert.equal(getter,undefined);
      getter = node;
    }
  });
  const retirement = functions.get('retireModelPreparationReferences');
  assert(getter && retirement);
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
  const create = new Function('original','sourceAliasPublicationOriginal','retireSourceAliasPublicationOriginal','consumer',`
    const host=original.host,moon=original.moon,preparation=undefined;
    let environment=original.environment,sourcePublication=original.publication;
    let preparedSourceEnvironment,clientProgramPreparationReferences,modelRuntimeClosing=false;
    let modelSdkStaticOriginals,originalInstallation={},registerModelProviders,modelProviders;
    let projectTasks,projectProfile,projectRuntime,project;
    const mockEffectRuns=new Map(),localFileEffectRuns=new Map();
    let mockEffectOriginals,localFileEffectOriginals,localFileEffectInstallation;
    let mockEffectObservation,mockEffectObservationMethods,localSigningMetadata,localCheckpointAnswer;
    let mockAccount,standardAccountPreparation;
    const retireInstalledProjectConfiguration=()=>{throw new Error('UnexpectedProject');};
    const clientOperationError=code=>Object.assign(new Error(code),{code});
    const valuesMaxRows=undefined,check=()=>{},verifyRequestValuePolicy=()=>{};
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
    ${text(getter)}
    ${text(retirement)}
    ${text(capture)}
    ${text(retain)}
    let selectedPreparation;
    ${install ? `{${text(installation)}\n${consumerCapture === undefined ? '' : text(consumerCapture)}\nselectedPreparation=prepareSubmit;}` : ''}
    return {get:getPreparedSourceEnvironment,retire:retireModelPreparationReferences,
      get slot(){return preparedSourceEnvironment;},options:selectedPreparation,
      stop(){modelRuntimeClosing=true;},replaceEnvironment(value){environment=value;},
      replacePublication(value){sourcePublication=value;}};
  `);
  return {fixture:create(original,sourceAliasPublicationOriginal,retireSourceAliasPublicationOriginal,consumer),original,consumer,
    get reads(){return reads;},get retirements(){return retirements;}};
}

test('Host prepared Environment keeps one original and forwards only its cheap lifetime getter', () => {
  const f = preparedEnvironmentLifetime();
  assert.equal(f.reads,1);
  assert.strictEqual(f.fixture.options.getPreparedSourceEnvironment,f.fixture.get);
  for (let index=0;index<8;index++) assert.strictEqual(f.fixture.get(),f.original.preparedEnvironment);
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
  assert.throws(f.fixture.get,{code:'ClientHostClosing'});
  await shutdown.close();
  assert.equal(f.retirements,1);assert.equal(f.fixture.slot,undefined);
  assert.equal(closes,2);assert.equal(storeCloses,1);
  await shutdown.close();assert.equal(f.retirements,1);
});

test('Host prepared Environment refuses changed originals and retires only its captured association', () => {
  const marker=new Error('OriginalAssociationRetirement');let attempts=0;
  const f=preparedEnvironmentLifetime({retire(){if(++attempts===1)throw marker;}});
  f.fixture.replaceEnvironment({});
  assert.throws(f.fixture.get,{code:'InstalledPublicSourceEnvironmentChanged'});
  f.fixture.replacePublication({});
  assert.throws(f.fixture.get,{code:'InstalledPublicSourceEnvironmentChanged'});
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
  runtime = {}, source, controlClose = async () => ({pending: false})}) {
  const declarations = declared('connectEmbeddedLocal').body.body
    .filter(node => node.type === 'VariableDeclaration').flatMap(node => node.declarations);
  const initial = declarations.find(node => node.id.name === 'initialControl');
  const preparation = declarations.find(node => node.id.name === 'preparation');
  assert(initial && preparation);
  const properties = preparation.init.arguments[0].properties;
  const names = ['prepareManagedCompute', 'requestPreparation', 'sourcePreparation',
    'bindSourceRequest', 'prepareManagedComputeRun', 'bindManagedComputeRunObservation',
    'managedComputeUsageReader', 'isOriginalManagedComputePreparationRefusal',
    'bindManagedSources', 'managesInstalledSources', 'prepareManagedSourceRun'];
  const methods = names.map(name => {
    const property = properties.find(node => node.key.name === name); assert(property, name); return text(property);
  });
  const originals = {host: {}, installation: {}, generation: {}, supplier: {}, moduleLifetime: {}};
  const ports = {
    prepareManagedComputeInstallation: held => {assert.strictEqual(held, originals); return factory();},
    assertInitialControlHostPreparation: held => {assert.strictEqual(held, originals); current();},
    assertManagedComputeInstallationCurrent: (value, held) => {assert.strictEqual(held, originals); current(value);},
    assertSourceManagedInstallationCurrent: (value, held) => {
      assert.strictEqual(value, source); assert.strictEqual(held, originals); current(value);
    },
    clientOperationError: code => Object.assign(new Error(code), {code}),
    retirePreparationReferences: retire, controlClose, originals, runtime,
    checked: value => value,
    bindInstalledManagedSources,
    originalSourceManagedHostRequest(held, value) {assert.strictEqual(held, originals); return value;},
    beforeChild, beforeChildClose, source,
  };
  return new Function(...Object.keys(ports), `
    let computeManaged, computeManagedClose, computeManagedFlight, observedClose;
    let resultPublication, resultPublicationClose, resultPublicationFlight;
    let sourceManaged=source??beforeChild, sourceManagedClose=source?.close??beforeChildClose, hostJournal;
    let moon=runtime, mockPreparation=source===undefined?undefined:{}, projectSourcePreparation;
    let control={}, duty, originalInstallation=originals.installation;
    const host=originals.host, record={}, adopted=true;
    const profiles={bindSourceRequest(...args){record.lineage=args;}};
    const initialControl=${text(initial.init)};
    const preparation={${methods.join(',\n')}};
    return {preparation,initialControl,record,originals};
  `)(...Object.values(ports));
}

test('managed usage reader selects only the same admitted Run and releases its installation alias', () => {
  const runtime = {}, f = lifecycle({factory() {}, runtime});
  const prepared = {}, value = {}, foreign = {}, first = {namespaceId:'n',authorityScopeCid:'a',runDefinitionCid:'r'};
  let reads = 0;
  const usage = [1n,2n,3n,4n,5n,6n,7n,8n,9n,10n,11n,12n,13n,14n,15n,16n];
  runtime.clientProgramInstalledManagedRunUsage = function(actual) {
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
  runtime.clientProgramInstalledManagedRunUsage=()=>{throw new Error('Replacement must not run');};
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

test('actual requirements and begin share the retained typed original before Resource admission', async () => {
  const p = managedRunPorts(), original = {}, sequences = {}, prepared = {}, request = {};
  let f, sequencePreparations = 0;
  const read = new Function('assertSourceManagedHostPreparation', 'originalSourceManagedHostRequest',
    'readInitialControlInstallationAsset', 'checked', 'clientOperationError', 'runtimeIsError',
    text(declared('prepareInstalledSequenceContractOriginal')) + '\n' +
    text(declared('installedManagedRunContracts')) + '\n' +
    text(declared('readManagedComputeRunRequirements')) + ';return readManagedComputeRunRequirements;')(
    held => assert.strictEqual(held, f.originals),
    (held, value) => {assert.strictEqual(held, f.originals); assert.strictEqual(value, prepared); return request;},
    () => '{"execution_contracts":{"REL.values":{},"ACTQL.expression_fragment/0.1":{},"REL.derive.ordered":{}}}',
    value => value, code => Object.assign(new Error(code), {code}), () => false);
  p.runtime.clientProgramInstalledManagedRunIssueIsUnsupported = () => false;
  p.runtime.clientProgramInstalledManagedRunRequirements = () => assert.fail('No regeneration');
  p.runtime.clientProgramPrepareInstalledManagedSourceFreeWithContracts = (value, contracts) => {
    assert.strictEqual(contracts, p.contracts);
    assert.strictEqual(value, prepared); sequencePreparations++; return sequences;
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
  const read = new Function('assertSourceManagedHostPreparation', 'originalSourceManagedHostRequest',
    'readInitialControlInstallationAsset', 'checked', 'clientOperationError', 'runtimeIsError', 'runtimeField',
    text(declared('prepareInstalledSequenceContractOriginal')) + '\n' +
    text(declared('installedManagedRunContracts')) + '\n' + text(declared('readManagedComputeRunRequirements')) +
    ';return readManagedComputeRunRequirements;')(
    held => {assert.strictEqual(held, f.originals); assert(current);},
    (held, value) => {assert.strictEqual(held, f.originals); assert.strictEqual(value, prepared); return request;},
    () => '{"execution_contracts":{"REL.values":{},"ACTQL.expression_fragment/0.1":{},"REL.derive.ordered":{}}}',
    value => {
      assert(value === p.manifests || value === p.contracts,
        'Only fixed installation admissions may complete before typed Unsupported');
      return value;
    },
    (code, cause) => Object.assign(new Error(code, {cause}), {code}),
    value => {assert.strictEqual(value, result); return true;},
    (value, index) => {assert.strictEqual(value, result); assert.equal(index, 0); return issue;});
  p.runtime.clientProgramInstalledManagedRunRequirements = () => assert.fail('No second preparation');
  p.runtime.clientProgramPrepareInstalledManagedSourceFreeWithContracts = (value, contracts) => {
    assert.strictEqual(contracts, p.contracts);
    assert.strictEqual(value, prepared); preparations++; return result;
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
  const helpers = dispatchAst.body.filter(node => node.type === 'FunctionDeclaration' &&
    ['retainDispatchPreparationHost', 'releaseDispatchPreparationHost'].includes(node.id.name));
  assert.equal(helpers.length, 2);
  return new Function('held', 'moon', 'preparedProgram', 'requested', 'retainedRelationOutput', 'checked', 'preparationLease', `
    ${helpers.map(node => dispatchSource.slice(node.start, node.end)).join('\n')}
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
  return new AsyncFunction('installedSource', 'moon', 'preparedProgram', 'requested', 'checked', `
    const singleAccounted=true, checkpoints=undefined, submission={},held={preparedSource:{}};
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
  prepared, request, value => value);
  assert.strictEqual(result.ledger, ledger); assert.strictEqual(result.entry.acquisitionLedger, ledger);
});

test('single Source dispatcher preserves managed missing/parked refusal instead of scalar fallback', async () => {
  const open = singleSourceOpening(), marker = new Error('OriginalResourceParked');
  const source = {ledgerCapacity: () => ({managedRun: {}, capacity: {}, transferBytes: 3n, executionBytes: 5n})};
  const legacy = () => assert.fail('Accounting fallback');
  await assert.rejects(open(source, {clientProgramPrepareSingleCapturedLocalInstalledLedger: legacy},
    {}, {}, value => value), /InstalledSingleSourceOriginalRunUnavailable/u);
  await assert.rejects(open(source, {clientProgramPrepareSingleCapturedLocalInstalledLedger: legacy,
    clientProgramInstalledManagedRunPrepareLedger() {throw marker;}}, {}, {}, value => value),
  error => error === marker);
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
