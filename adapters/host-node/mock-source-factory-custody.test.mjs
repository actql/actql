import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import test from 'node:test';
import {parse} from 'acorn';

const source=readFileSync(new URL('../local-node/installed-project-mock.mjs',import.meta.url),'utf8');
const ast=parse(source,{ecmaVersion:'latest',sourceType:'module'}),nodes=[];
function collect(node){
  if(node===null||typeof node!=='object')return;nodes.push(node);
  for(const value of Object.values(node)){
    if(Array.isArray(value))value.forEach(collect);
    else if(value!==null&&typeof value==='object')collect(value);
  }
}
collect(ast);
const select=(type,name)=>{
  const found=nodes.filter(node=>node.type===type&&(node.id?.name??node.key?.name)===name);
  assert.equal(found.length,1);return source.slice(found[0].start,found[0].end);
};
const make=compileFunction(`
  const {sourceManaged,moon,declaration}=input,index=0;
  const records=new Map(input.record ? [[input.record.prepared,input.record]] : []);
  const originalReads=new WeakMap();
  const effectReads=new Set(),effectRuns=new WeakMap();
  const current=()=>sourceManaged.assertCurrent();
  const sameRun=prepared=>{current();const run=records.get(prepared);
    if(run===undefined)fail('NodeManagedRunAdmissionUnavailable');return run;};
  ${select('FunctionDeclaration','prepareManagedRun')}
  ${select('FunctionDeclaration','closeSource')}
  ${select('FunctionDeclaration','closeRead')}
  ${select('FunctionDeclaration','closePhysicalRead')}
  const reader={${select('Property','prepareSourceRead')}};
  return {prepareManagedRun,reader,closeSource,held:()=>records.values().next().value};`,['input','checked','fail']);
const fail=code=>{throw Object.assign(new Error(code),{code});};

// Execute actual installed caller statements with explicit stopping Resource,
// Core and physical-close ports. No scalar Ledger or capacity is supplied.
test('same Source child and close are held before post-factory current refusal and Core use stays zero',async()=>{
  const failure=new Error('OriginalGenerationChanged');let current=true,closes=0,core=0;
  const declaration={},prepared={},record={prepared,original:{},value:{},effectful:false,reads:[]};
  const raw={close(){assert.strictEqual(this,raw);closes++;return {pending:false};},
    readOriginalBytes(){assert.fail('No physical read');}};
  const sourceManaged={assertCurrent(){if(!current)throw failure;},prepareRead(){current=false;return raw;}};
  const f=make({sourceManaged,declaration,record,moon:{
    clientProgramAcquisitionCount(){return 1;},
    clientProgramInstalledManagedRunSourceRead(){core++;assert.fail('No stale Core use');}}},value=>value,fail);
  assert.throws(()=>f.reader.prepareSourceRead({checkedOwner:prepared,effectful:false,
    declaration,occurrence:{stage:0,input:0}}),error=>error===failure);
  assert.strictEqual(record.reads[0].raw,raw);assert.equal(core,0);
  raw.close=()=>assert.fail('Replacement close must not run');
  await f.closeSource(0);assert.equal(closes,1);assert.equal(record.reads[0].closed,true);
});

test('same Host Run is retained before post-factory current refusal and independent typed start stays zero', () => {
  const failure = new Error('OriginalRunGenerationChanged');
  let f;
  f = requestSourceFixture((facts, record) => {
    f.sourceManaged.assertCurrent = () => {throw failure;};
    return record;
  });
  assert.throws(() => f.run({preparedProgram: f.prepared, requestIdentity: f.request}), error => error === failure);
  assert.strictEqual(f.effectRuns.get(f.prepared).deref(), f.record);
});

test('foreign Source occurrence still refuses before acquiring any child',()=>{
  let acquisitions=0;const declaration={},prepared={},record={prepared,original:{},value:{},effectful:false,reads:[]};
  const f=make({declaration,record,sourceManaged:{assertCurrent(){},prepareRead(){acquisitions++;}},moon:{clientProgramAcquisitionCount(){return 1;}}},value=>value,fail);
  for(const facts of [{declaration:{},occurrence:{stage:0,input:0}},
    {declaration,occurrence:{stage:1,input:0}},{declaration,occurrence:{stage:0,input:1}}]){
    assert.throws(()=>f.reader.prepareSourceRead({checkedOwner:prepared,effectful:false,...facts}),
      {code:'InstalledSourcePreparationMismatch'});
  }
  assert.equal(acquisitions,0);assert.equal(record.reads[0],undefined);
});


test('repeated Source slots hold distinct children and close only their original Source',async()=>{
  const declaration={},prepared={},record={prepared,original:{},value:{},effectful:false,reads:[]};
  const acquired=[],retired=[];
  const sourceManaged={assertCurrent(){},prepareRead(owner,selected,original){
    assert.equal(owner,prepared);assert.equal(selected,declaration);assert.equal(original,record.original);
    const raw={closed:0,close(){assert.equal(this,raw);raw.closed++;return {pending:false};},
      readOriginalBytes(){assert.fail('No physical read');}};
    acquired.push(raw);return raw;
  }};
  const f=make({sourceManaged,declaration,record,moon:{clientProgramAcquisitionCount(){return 2;},
    clientProgramInstalledManagedRunSourceRead(run,slot){assert.equal(run,record.value);return {slot};},
    clientProgramInstalledSourceReadRetire(value){retired.push(value.slot);}}},value=>value,fail);
  const prepare=stage=>f.reader.prepareSourceRead({checkedOwner:prepared,effectful:false,
    declaration,occurrence:{stage,input:0}});
  assert.equal(prepare(1).slot,1);assert.equal(prepare(0).slot,0);
  assert.throws(()=>prepare(1),{code:'InstalledSourcePreparationMismatch'});
  assert.equal(acquired.length,2);
  await f.closeSource(1);assert.deepEqual(acquired.map(raw=>raw.closed),[0,0]);
  await f.closeSource(0);assert.deepEqual(acquired.map(raw=>raw.closed),[1,1]);
  await f.closeSource(0);assert.deepEqual(acquired.map(raw=>raw.closed),[1,1]);
  assert.deepEqual(retired,[0,1]);
});

// Execute the original Mock Run constructor. A retired Effect discriminator
// must refuse before current callbacks, an independent quote or any Core use.
test('retired Mock Effect discriminator cannot enter the Pure Run constructor', () => {
  let current = 0, factories = 0;
  const sourceManaged = {assertCurrent() {current++;},
    prepareRun() {factories++; assert.fail('No replacement Pure Root');},
    prepareEffectRun() {factories++; assert.fail('No legacy Effect Root');}};
  const f = make({sourceManaged, moon: {}}, value => value, fail);
  assert.throws(() => f.prepareManagedRun({}, {}, undefined, true),
    {code: 'InvalidInstalledManagedRunRequest'});
  assert.equal(current, 0); assert.equal(factories, 0); assert.equal(f.held(), undefined);
});

test('foreign Mock Effect read context refuses before acquiring any Source child', () => {
  let current = 0, acquisitions = 0;
  const f = make({sourceManaged: {assertCurrent() {current++;},
    prepareRead() {acquisitions++; assert.fail('No legacy Effect Source child');}}, moon: {}},
    value => value, fail);
  assert.throws(() => f.reader.prepareSourceRead({checkedOwner: {}, effectful: true,
    declaration: {}, occurrence: {stage: 0, input: 0}}), {code: 'NodeManagedRunAdmissionUnavailable'});
  assert.equal(current, 1); assert.equal(acquisitions, 0);
});

// Same actual Source child and Host retirement bodies. The native retirement
// and raw close ports are explicit: this counter proves JS alias lifetime,
// never a real Resource/FD ACK, normal admission or a capacity recipe.
function effectReadRetirementFixture(count = 1, effectful = true) {
  const hostSource = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  let retirement;
  function find(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key?.name === 'retireManagedComputeRun') retirement = node;
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(find);
      else if (value && typeof value === 'object') find(value);
    }
  }
  find(parse(hostSource, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert(retirement);
  const prepared = {}, request = {}, native = {}, declaration = {}, events = [];
  const run = {prepared, request, value: native, preparationKind: effectful ? 'effect-plan' : undefined,
    preparationFunded: true, original: {}, closed: false};
  const record = {computeRuns: new WeakMap([[prepared, run]]), computeLiveRuns: new Set([run])};
  let nativePending = false, physicalPending = false, severFailure, onNative, payloadSevered = false, observations = 0;
  const pending = Object.assign(new Error('OriginalNativePending'), {code: 'OriginalNativePending'});
  const raws = [];
  const moon = {clientProgramEffectAcquisitionCount: () => count, clientProgramAcquisitionCount: () => count,
    clientProgramInstalledPreparationPayloadSevered() {observations++; return payloadSevered;}};
  run.runtime = moon;
  run.retire = function(value) {
    assert.equal(this, moon); assert.equal(value, native); events.push('native'); onNative?.();
    return nativePending ? {$tag: 0, _0: pending} : {$tag: 1};
  };
  run.manager = {severPreparation(p, original) {
    assert.equal(p, prepared); assert.equal(original, run.original); events.push('parent');
    if (severFailure) {const error = severFailure; severFailure = undefined; throw error;}
  }};
  const originalReads = new WeakMap(), effectRuns = new WeakMap([[prepared, new WeakRef(run)]]);
  const effectReads = new Set(), records = new Map();
  const sourceManaged = {assertCurrent() {}, prepareRead(p, selected, value) {
    assert.equal(p, prepared); assert.equal(selected, declaration); assert.equal(value, native);
    const raw = {close() {assert.equal(this, raw); events.push('physical'); return {pending: physicalPending};},
      readOriginalBytes() {assert.fail('No Source I/O in retirement counter');}};
    raws.push(raw); return raw;
  }};
  const optionalRelease = nodes.find(node => node.type === 'FunctionDeclaration' &&
    node.id?.name === 'releaseEffectSourceAliases');
  const reader = compileFunction(`
    const index=0;
    ${optionalRelease ? source.slice(optionalRelease.start, optionalRelease.end) : ''}
    ${select('FunctionDeclaration', 'closePhysicalRead')}
    ${select('FunctionDeclaration', 'closeRead')}
    ${select('FunctionDeclaration', 'closeSource')}
    return {${select('Property', 'prepareSourceRead')},
      ${select('Property', 'closeSourceRead')}, closeSource};`,
    ['sourceManaged', 'moon', 'declaration', 'sameRun', 'originalReads', 'effectReads', 'effectRuns', 'records', 'checked', 'fail'])(
      sourceManaged, moon, declaration, p => {assert.equal(p, prepared); return run;},
      originalReads, effectReads, effectRuns, records,
      value => {if (value.$tag !== 1) throw value._0; return value._0;}, fail);
  const retire = compileFunction(`return ({${hostSource.slice(retirement.start, retirement.end)}}).retireManagedComputeRun;`,
    ['record', 'moon', 'checked', 'finishInstalledEffectModelScope', 'clientOperationError',
      'managedPreparationRetirementContinuation'])(record, moon,
      value => {if (value.$tag !== 1) throw value._0; return value._0;}, () => {},
      code => Object.assign(new Error(code), {code}), () => () => {});
  const originalRead = {};
  reader.prepareSourceRead({checkedOwner: prepared, effectful, declaration,
    occurrence: {stage: 0, input: 0}, managedRun: native, originalRead});
  const read = run.mockSourceReads[0];
  return {run, record, prepared, request, native, declaration, originalRead, read, raw: raws[0], raws,
    reader, retire: () => retire(prepared), events, effectReads, effectRuns, originalReads, pending,
    nativePending(value) {nativePending = value;}, physicalPending(value) {physicalPending = value;},
    failSever(value) {severFailure = value;}, onNative(callback) {onNative = callback;},
    payloadSevered(value) {payloadSevered = value;}, observations: () => observations};
}

test('same acknowledged Effect Run releases installation-held Source read aliases before parent return', async () => {
  const f = effectReadRetirementFixture();
  assert.equal(f.effectReads.size, 1);
  assert.equal(f.originalReads.get(f.originalRead).read, f.read);
  await f.reader.closeSourceRead(f.originalRead);
  assert.equal(f.read.physicalClosed, true);
  assert.equal(f.effectReads.size, 1, 'Physical close alone is not native retirement');
  f.retire();
  assert.equal(f.effectReads.size, 0, 'Per-Run retirement must not wait for installation close');
  assert.equal(f.effectRuns.has(f.prepared), false);
  assert.equal(f.originalReads.has(f.originalRead), false);
  for (const key of ['raw', 'close', 'bytes', 'observedBytes', 'value']) assert.equal(f.read[key], undefined, key);
  assert.equal(f.run.mockSourceReads, undefined);
  assert.equal(f.run.releaseMockSourceAliases, undefined);
  assert.deepEqual(f.events, ['physical', 'native', 'parent']);
});

test('pending original native retirement keeps every Mock Source alias and installation record', async () => {
  const f = effectReadRetirementFixture();
  await f.reader.closeSourceRead(f.originalRead);
  f.nativePending(true);
  assert.throws(f.retire, error => error === f.pending);
  assert.equal(f.effectReads.has(f.read), true);
  assert.equal(f.read.raw, f.raw);
  assert.equal(f.originalReads.get(f.originalRead).read, f.read);
  assert.equal(f.effectRuns.get(f.prepared).deref(), f.run);
  assert.equal(f.run.closed, false);
  f.nativePending(false); f.retire();
  assert.equal(f.effectReads.size, 0);
  assert.deepEqual(f.events, ['physical', 'native', 'native', 'parent']);
});

test('pending original physical close cannot release Mock Source aliases through native retirement', async () => {
  const f = effectReadRetirementFixture(), bytes = Buffer.from('original shared document');
  f.read.observedBytes = bytes;
  f.physicalPending(true);
  await assert.rejects(f.reader.closeSourceRead(f.originalRead), {code: 'InstalledMockSourceCleanupPending'});
  assert.throws(f.retire, {code: 'InstalledMockSourceCleanupPending'});
  assert.equal(f.read.raw, f.raw); assert.equal(f.read.observedBytes, bytes);
  assert.equal(f.effectReads.size, 1); assert.equal(f.run.closed, false);
  f.physicalPending(false); await f.reader.closeSourceRead(f.originalRead); f.retire();
  assert.equal(f.effectReads.size, 0); assert.equal(f.read.observedBytes, undefined);
  assert.deepEqual(f.events, ['physical', 'native', 'physical', 'native', 'parent']);
});

test('consumed parent return cannot retain or reissue retired Mock Source aliases', async () => {
  const f = effectReadRetirementFixture(), failure = new Error('same consumed parent return');
  await f.reader.closeSourceRead(f.originalRead);
  f.failSever(failure);
  assert.throws(f.retire, error => error === failure);
  assert.equal(f.effectReads.size, 0); assert.equal(f.read.raw, undefined);
  assert.equal(f.originalReads.has(f.originalRead), false);
  assert.equal(f.run.releaseMockSourceAliases, undefined);
  await assert.rejects(f.reader.closeSourceRead(f.originalRead), {code: 'InstalledSourcePreparationMismatch'});
  f.retire();
  assert.equal(f.run.closed, true);
  assert.deepEqual(f.events, ['physical', 'native', 'parent', 'native', 'parent']);
});

test('Mock Source native retirement callback cannot reenter retirement or acquire another child', async () => {
  const f = effectReadRetirementFixture();
  await f.reader.closeSourceRead(f.originalRead);
  f.onNative(() => {
    assert.throws(f.retire, {code: 'InstalledMockSourceCleanupPending'});
    assert.throws(() => f.reader.prepareSourceRead({checkedOwner: f.prepared, effectful: true,
      declaration: f.declaration, occurrence: {stage: 0, input: 0}, managedRun: f.native, originalRead: {}}),
    {code: 'InstalledMockSourceCleanupPending'});
  });
  f.retire();
  assert.equal(f.effectReads.size, 0);
  assert.deepEqual(f.events, ['physical', 'native', 'parent']);
});

test('Mock Source retirement rejects a replaced Host original without cutting the original read', async () => {
  const f = effectReadRetirementFixture();
  await f.reader.closeSourceRead(f.originalRead);
  f.onNative(() => f.record.computeRuns.set(f.prepared, {...f.run}));
  assert.throws(f.retire, {code: 'ForeignInstalledEffectManagedRun'});
  assert.equal(f.effectReads.size, 1); assert.equal(f.read.raw, f.raw);
  assert.equal(f.originalReads.get(f.originalRead).read, f.read);
  assert.equal(f.effectRuns.get(f.prepared).deref(), f.run);
  assert.deepEqual(f.events, ['physical', 'native']);
});

test('Mock Source retirement keeps sibling document correspondence until every original child closes', async () => {
  const f = effectReadRetirementFixture(2), secondOriginal = {}, bytes = Buffer.from('same retained document');
  f.reader.prepareSourceRead({checkedOwner: f.prepared, effectful: true, declaration: f.declaration,
    occurrence: {stage: 1, input: 0}, managedRun: f.native, originalRead: secondOriginal});
  const second = f.run.mockSourceReads[1];
  assert.notEqual(second.raw, f.read.raw);
  f.read.observedBytes = bytes;
  await f.reader.closeSourceRead(f.originalRead);
  assert.throws(f.retire, {code: 'InstalledMockSourceCleanupPending'});
  assert.equal(f.effectReads.size, 2); assert.equal(f.read.observedBytes, bytes);
  assert.equal(f.read.raw, f.raws[0]); assert.equal(second.raw, f.raws[1]);
  await f.reader.closeSourceRead(secondOriginal); f.retire();
  assert.equal(f.effectReads.size, 0); assert.equal(f.originalReads.has(secondOriginal), false);
  assert.equal(f.read.observedBytes, undefined); assert.equal(second.raw, undefined);
  assert.deepEqual(f.events, ['physical', 'native', 'physical', 'native', 'parent']);
});

test('Mock Source aliases consume only the existing failed-return payload-sever observation', async () => {
  const f = effectReadRetirementFixture();
  await f.reader.closeSourceRead(f.originalRead);
  f.nativePending(true); f.payloadSevered(true); f.retire();
  assert.equal(f.observations(), 1); assert.equal(f.effectReads.size, 0);
  const g = effectReadRetirementFixture();
  await g.reader.closeSourceRead(g.originalRead); g.retire();
  assert.equal(g.observations(), 0, 'Successful Unit adds no currentness/retirement callback');
  assert.equal(g.effectReads.size, 0);
});


// The installed profile consumes the actual Host record, not a third positional
// Model argument or another Connector-issued Node admission.
function requestSourceFixture(prepareRequestSource) {
  const prepared = {}, request = {}, value = {}, calls = [], effectRuns = new WeakMap();
  const record = {prepared, request, value, runtime: {}, closed: false};
  const moon = record.runtime;
  const sourceManaged = {assertCurrent() {calls.push('current');},
    prepareRun() {assert.fail('No Connector-owned Root or admission');}};
  const run = compileFunction(`
    const current = () => sourceManaged.assertCurrent();
    const records = new Map();
    const sameRun = owner => {const selected = effectRuns.get(owner)?.deref();
      if (selected === undefined || selected.closed) fail('NodeManagedRunAdmissionUnavailable'); return selected;};
    ${select('FunctionDeclaration', 'prepareManagedRun')}
    return prepareManagedRun;`, ['sourceManaged', 'moon', 'prepareRequestSource', 'effectRuns', 'fail'])(
      sourceManaged, moon, facts => prepareRequestSource(facts, record, calls), effectRuns, fail);
  return {prepared, request, record, value, calls, effectRuns, sourceManaged, run};
}

test('Mock Source uses the named same-Request Host Run and never issues another admission', () => {
  const invocation = () => assert.fail('Only the Host may construct the invocation');
  const f = requestSourceFixture((facts, record, calls) => {
    assert.deepEqual(Object.keys(facts), ['preparedProgram', 'requestIdentity', 'prepareInvocation']);
    assert.strictEqual(facts.preparedProgram, record.prepared);
    assert.strictEqual(facts.requestIdentity, record.request);
    assert.strictEqual(facts.prepareInvocation, invocation);
    calls.push('same-host-original'); return record;
  });
  const facts = {preparedProgram: f.prepared, requestIdentity: f.request, prepareInvocation: invocation};
  assert.strictEqual(f.run(facts), f.value);
  assert.strictEqual(f.effectRuns.get(f.prepared).deref(), f.record);
  assert.strictEqual(f.run(facts), f.value);
  assert.equal(f.calls.filter(value => value === 'same-host-original').length, 2);
});

test('Mock Source preserves the Host refusal and rejects a foreign returned Run', () => {
  const refusal = new Error('OriginalHostPreparationRefused');
  const f = requestSourceFixture(() => {throw refusal;});
  assert.throws(() => f.run({preparedProgram: f.prepared, requestIdentity: f.request}), error => error === refusal);
  assert.equal(f.effectRuns.get(f.prepared), undefined);
  const other = requestSourceFixture((facts, record) => ({...record, request: {}}));
  assert.throws(() => other.run({preparedProgram: other.prepared, requestIdentity: other.request}),
    {code: 'ForeignInstalledSourcePreparation'});
  assert.equal(other.effectRuns.get(other.prepared), undefined);
});


test('Request-owned ordinary Mock Source closes and retires through the same existing Host record', async () => {
  const f = effectReadRetirementFixture(1, false);
  assert.strictEqual(f.run.mockSourceReads[0].value, f.originalRead);
  await f.reader.closeSourceRead(f.originalRead);
  f.retire();
  assert.equal(f.effectReads.size, 0); assert.equal(f.effectRuns.has(f.prepared), false);
  assert.equal(f.originalReads.has(f.originalRead), false);
  assert.deepEqual(f.events, ['physical', 'native', 'parent']);
});

test('Host-backed Row Source capture capacity retains its checked acquisition and existing bounds', () => {
  const row = readFileSync(new URL('./installed-row-source.mjs', import.meta.url), 'utf8');
  const found = [];
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'FunctionDeclaration' && node.id.name === 'managedProviderCaptureCapacity') found.push(node);
    for (const child of Object.values(node)) if (Array.isArray(child)) child.forEach(visit);
    else if (child && typeof child === 'object') visit(child);
  })(parse(row, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.equal(found.length, 1);
  const requirement = {}, acquisition = {}, capacity = {}, calls = [];
  const create = compileFunction('return ' + row.slice(found[0].start, found[0].end),
    ['originalReader', 'prepareSourceRead', 'prepareOriginalAcquisition', 'moon',
      'maxTransferBytes', 'limits', 'fail']);
  const invoke = create(undefined, () => assert.fail('Capacity is not a read'), actual => {
    assert.strictEqual(actual, requirement); calls.push('original-acquisition'); return acquisition;
  }, {clientProgramInstalledRowCaptureCapacity(actual) {
    assert.strictEqual(actual, acquisition); calls.push('original-capacity'); return capacity;
  }}, 1048576n, {maxPageBytes: 1048576}, fail);
  assert.deepEqual(invoke(requirement), {capacity, transferBytes: 1048576n, executionBytes: 1048576n});
  assert.deepEqual(calls, ['original-acquisition', 'original-capacity']);
  assert.throws(() => create(undefined, undefined, () => assert.fail('No unsupported constructor'),
    {}, 0n, {}, fail)(requirement), {code: 'InstalledSourceCapacityUnavailable'});
});


test('Mock Source keeps an explicit undefined Host failure sticky without publishing its Run', () => {
  const f = requestSourceFixture((facts, record) => {record.failure = undefined; return record;});
  let thrown = false;
  try {f.run({preparedProgram: f.prepared, requestIdentity: f.request});}
  catch (error) {thrown = true; assert.strictEqual(error, undefined);}
  assert.equal(thrown, true); assert.equal(f.effectRuns.has(f.prepared), false);
});

test('actual Mock installer captures the same Host Source method before returning its named profile', async () => {
  const host = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
  let method;
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key?.name === 'installMockSources') {
      assert.equal(method, undefined); method = node;
    }
    for (const child of Object.values(node)) if (Array.isArray(child)) child.forEach(visit);
    else if (child && typeof child === 'object') visit(child);
  })(parse(host, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert(method);
  const moon = {}, prepared = {}, request = {}, value = {}, profile = {}, invocation = () => {};
  const run = {prepared, request, value, runtime: moon, sourceProfile: profile, closed: false};
  const record = {computeRuns: new WeakMap([[prepared, run]])}, installation = {};
  let supplied, calls = 0;
  const preparation = {prepareManagedSourceRun(...args) {
    assert.strictEqual(this, preparation);
    assert.deepEqual(args, [moon, prepared, request, profile, invocation]); calls++; return value;
  }};
  const ports = {moon, mockPreparation: {}, sourceManaged: {}, originals: {}, record,
    originalInstallation: installation, control: {}, preparation,
    assertSourceManagedInstallationCurrent() {},
    installPreparedProjectMockSources(options) {supplied = options.prepareManagedSourceRun; return profile;},
    readInitialControlInstallationAsset() {assert.fail('No source I/O');},
    retainInstalledHostInitializationFailure() {assert.fail('No failed initialization');},
    clientOperationError: code => Object.assign(new Error(code), {code})};
  const install = compileFunction('return ({' + host.slice(method.start, method.end) + '}).installMockSources;',
    Object.keys(ports))(...Object.values(ports));
  assert.strictEqual(await install(moon, '{}', () => {}), profile);
  assert.strictEqual(record.managedSourceProfile, profile);
  assert.strictEqual(installation.managedSourceProfile, profile);
  preparation.prepareManagedSourceRun = () => assert.fail('No changed Host implementation');
  assert.strictEqual(supplied({preparedProgram: prepared, requestIdentity: request, prepareInvocation: invocation}), run);
  assert.equal(calls, 1);
  record.computeRuns.set(prepared, {...run, request: {}});
  assert.throws(() => supplied({preparedProgram: prepared, requestIdentity: request, prepareInvocation: invocation}),
    {code: 'ForeignInstalledSourcePreparation'});
});
