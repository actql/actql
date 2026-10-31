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
  const current=()=>sourceManaged.assertCurrent();
  const sameRun=prepared=>{current();return records.get(prepared);};
  ${select('FunctionDeclaration','prepareManagedRun')}
  ${select('FunctionDeclaration','closeSource')}
  ${select('FunctionDeclaration','closeRead')}
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

test('same managed Run original is retained before post-factory current refusal and typed start stays zero',()=>{
  const failure=new Error('OriginalRunGenerationChanged'),original={};let current=true,starts=0;
  const sourceManaged={assertCurrent(){if(!current)throw failure;},prepareRun(){current=false;return original;}};
  const f=make({sourceManaged,moon:{clientProgramNodeManagedRunPrepare(){starts++;assert.fail('No stale start');}}},value=>value,fail);
  const prepared={},request={};
  assert.throws(()=>f.prepareManagedRun(prepared,request),error=>error===failure);
  assert.strictEqual(f.held().original,original);assert.strictEqual(f.held().failure,failure);
  assert.equal(f.held().admission,undefined);assert.equal(starts,0);
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
    {code: 'InstalledEffectPlanUnavailable'});
  assert.equal(current, 0); assert.equal(factories, 0); assert.equal(f.held(), undefined);
});

test('retired Mock Effect read context refuses before Source custody or current callbacks', () => {
  let current = 0, acquisitions = 0;
  const f = make({sourceManaged: {assertCurrent() {current++;},
    prepareRead() {acquisitions++; assert.fail('No legacy Effect Source child');}}, moon: {}},
    value => value, fail);
  assert.throws(() => f.reader.prepareSourceRead({checkedOwner: {}, effectful: true,
    declaration: {}, occurrence: {stage: 0, input: 0}}), {code: 'InstalledEffectPlanUnavailable'});
  assert.equal(current, 0); assert.equal(acquisitions, 0);
});

// Same actual Source child and Host retirement bodies. The native retirement
// and raw close ports are explicit: this counter proves JS alias lifetime,
// never a real Resource/FD ACK, normal admission or a capacity recipe.
function effectReadRetirementFixture() {
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
  const run = {prepared, request, value: native, preparationKind: 'effect-plan',
    preparationFunded: true, original: {}, closed: false};
  const record = {computeRuns: new WeakMap([[prepared, run]]), computeLiveRuns: new Set([run])};
  let nativePending = false, physicalPending = false, severFailure, onNative;
  const pending = Object.assign(new Error('OriginalNativePending'), {code: 'OriginalNativePending'});
  const raw = {close() {assert.equal(this, raw); events.push('physical'); return {pending: physicalPending};},
    readOriginalBytes() {assert.fail('No Source I/O in retirement counter');}};
  const moon = {clientProgramEffectAcquisitionCount: () => 1,
    clientProgramInstalledPreparationPayloadSevered: () => false};
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
    assert.equal(p, prepared); assert.equal(selected, declaration); assert.equal(value, native); return raw;
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
  reader.prepareSourceRead({checkedOwner: prepared, effectful: true, declaration,
    occurrence: {stage: 0, input: 0}, managedRun: native, originalRead});
  const read = run.mockSourceReads[0];
  return {run, record, prepared, request, native, originalRead, read, raw,
    reader, retire: () => retire(prepared), events, effectReads, effectRuns, originalReads, pending,
    nativePending(value) {nativePending = value;}, physicalPending(value) {physicalPending = value;},
    failSever(value) {severFailure = value;}, onNative(callback) {onNative = callback;}};
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
