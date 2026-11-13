import test from 'node:test';
import assert from 'node:assert/strict';
import {installModelProviders} from './installed-model.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';

function fixture() {
  const calls=[];
  const entry={providerId:'models/fixture',invoke(){assert.fail('No Provider I/O');},
    validatePrompt:()=>true};
  const moon={
    clientProgramInstallModelProvider(id,invoke){calls.push(['sync',id]);return {id,invoke};},
    clientProgramInstallAsyncModelProvider(id){calls.push(['async',id]);return {id};},
  };
  return {entry,moon,calls};
}
const capacity=()=>({limits:{tokens:1n,costUnits:0n,durationMs:1n},
  perAttempt:{tokens:1n,costUnits:0n,durationMs:1n}});
function asyncEntry(entry) {
  delete entry.invoke;
  Object.assign(entry,{entryPersistence:'async',physicalPreflight(){assert.fail('No preflight');},
    quantityCapacity:capacity(),bindingOriginals:providerBindingOriginals('models/fixture'),
    rawCaptureSelection:{profile:{},probability:undefined,
      installation:{sdk:null},retention:{},metadata:{},clock:{},data:{},
      selectedAt:'original',availableUntil:'availability',deleteBy:'deletion',
      extensionCeilingAt:'ceiling',metadataDeleteBy:'metadata',selectionAvailable:()=>true}});
  return entry;
}

// Actual installed registration boundary; Common constructors are explicit
// counters, not original profile admission, a grant, startup or Provider send.
test('registration retains one provider ID for validation constructor and installed key',()=>{
  const {entry,moon,calls}=fixture();let reads=0;
  Object.defineProperty(entry,'providerId',{enumerable:true,
    get(){return ++reads%2 ? 'models/fixture' : 'models/foreign';}});
  const installed=installModelProviders(moon,()=>[entry]);
  assert.deepEqual([...installed.keys()],['models/fixture']);
  assert.deepEqual(calls,[['sync','models/fixture']]);
  assert.equal(reads,1);
});

test('validated async registration cannot turn into a synchronous constructor on a later mode read',()=>{
  const {entry,moon,calls}=fixture();asyncEntry(entry);let reads=0;
  Object.defineProperty(entry,'entryPersistence',{enumerable:true,
    get(){return ++reads<=6 ? 'async' : undefined;}});
  const installed=installModelProviders(moon,()=>[entry]).get('models/fixture');
  assert.deepEqual(calls,[['async','models/fixture']]);
  assert.equal(installed.entryPersistence,'async');
  assert.equal(reads,1);
});

test('quantity fields use the same exact BigInt for validation and retained snapshot',()=>{
  const {entry,moon}=fixture();entry.quantityCapacity=capacity();let reads=0;
  Object.defineProperty(entry.quantityCapacity.perAttempt,'tokens',{enumerable:true,
    get(){return ++reads===1 ? 1n : -1n;}});
  const installed=installModelProviders(moon,()=>[entry]).get('models/fixture');
  assert.equal(installed.quantityCapacity.perAttempt.tokens,1n);
  assert.equal(reads,1);
});

test('quantity scope is read once rather than replacing the already checked amount object',()=>{
  const {entry,moon}=fixture();entry.quantityCapacity=capacity();let reads=0;
  const original=entry.quantityCapacity.limits;
  Object.defineProperty(entry.quantityCapacity,'limits',{enumerable:true,
    get(){return ++reads===1 ? original : {...original,tokens:-1n};}});
  const installed=installModelProviders(moon,()=>[entry]).get('models/fixture');
  assert.deepEqual(installed.quantityCapacity.limits,original);
  assert.equal(reads,1);
});

test('bounded binding wire is the same original inspected before retention',()=>{
  const {entry,moon}=fixture();entry.bindingOriginals=providerBindingOriginals('models/fixture');
  const original=entry.bindingOriginals.configuration.wire;
  let reads=0;
  const oversized='x'.repeat(256*1024+1);
  Object.defineProperty(entry.bindingOriginals.configuration,'wire',{enumerable:true,
    get(){return ++reads<=3 ? original : oversized;}});
  const installed=installModelProviders(moon,()=>[entry]).get('models/fixture');
  assert.ok(installed.bindingOriginals.configuration.wire===original,
    'Retain the same bounded original, not an oversized second value');
  assert.equal(reads,1);
});

test('installed egress observer keeps its selected function and original receiver',()=>{
  const {entry,moon}=fixture();let observed=0;
  entry.observeEgress=function(){assert.strictEqual(this,entry);observed++;return 'original';};
  const installed=installModelProviders(moon,()=>[entry]).get('models/fixture');
  entry.observeEgress=()=> 'substituted';
  assert.equal(installed.observeEgress(),'original');
  assert.equal(observed,1);
});

test('egress invocation uses the selected callback rather than its mutable call property',()=>{
  const {entry,moon}=fixture();let observed=0;
  entry.observeEgress=function(){assert.strictEqual(this,entry);observed++;return 'original';};
  entry.observeEgress.call=()=> 'substituted';
  const installed=installModelProviders(moon,()=>[entry]).get('models/fixture');
  assert.equal(installed.observeEgress(),'original');
  assert.equal(observed,1);
});

test('invalid first quantity or mode refuses before constructing a Provider',()=>{
  for(const change of [entry=>{entry.entryPersistence='unknown';},
    entry=>{entry.quantityCapacity={...capacity(),perAttempt:{tokens:-1n,costUnits:0n,durationMs:1n}};}]) {
    const {entry,moon,calls}=fixture();change(entry);
    assert.throws(()=>installModelProviders(moon,()=>[entry]),/InvalidInstalledModel/u);
    assert.deepEqual(calls,[]);
  }
});

test('quantity amount rejects a combined own key with inherited expected fields',()=>{
  const {entry,moon,calls}=fixture();entry.quantityCapacity=capacity();
  entry.quantityCapacity.perAttempt=Object.assign(Object.create({
    tokens:1n,costUnits:0n,durationMs:1n}),{'costUnits,durationMs,tokens':1n});
  assert.throws(()=>installModelProviders(moon,()=>[entry]),
    /InvalidInstalledModelQuantityCapacity/u);
  assert.deepEqual(calls,[]);
});

test('quantity scope rejects a combined own key with inherited expected fields',()=>{
  const {entry,moon,calls}=fixture();
  entry.quantityCapacity=Object.assign(Object.create(capacity()),{'limits,perAttempt':1n});
  assert.throws(()=>installModelProviders(moon,()=>[entry]),
    /InvalidInstalledModelQuantityCapacity/u);
  assert.deepEqual(calls,[]);
});

test('binding original rejects a combined own key with inherited cid and wire',()=>{
  const {entry,moon,calls}=fixture();
  entry.bindingOriginals=providerBindingOriginals('models/fixture');
  entry.bindingOriginals.configuration=Object.assign(
    Object.create(entry.bindingOriginals.configuration),{'cid,wire':'not two own fields'});
  assert.throws(()=>installModelProviders(moon,()=>[entry]),
    /InvalidInstalledModelProviderBindingOriginals/u);
  assert.deepEqual(calls,[]);
});

test('binding wrapper rejects a combined own key with inherited originals',()=>{
  const {entry,moon,calls}=fixture();
  entry.bindingOriginals=Object.assign(Object.create(providerBindingOriginals('models/fixture')),
    {'configuration,configurationContract,installationRevision':'not three own fields'});
  assert.throws(()=>installModelProviders(moon,()=>[entry]),
    /InvalidInstalledModelProviderBindingOriginals/u);
  assert.deepEqual(calls,[]);
});

test('installed table checks the same Host before and after its registration callback',()=>{
  const {entry,moon}=fixture();const events=[];
  const installed=installModelProviders(moon,()=>{
    events.push('register');return [entry];
  },()=>events.push('host'));
  assert.deepEqual(events,['host','register','host']);
  installed.get('models/fixture').assertTrustedRuntime();
  assert.deepEqual(events,['host','register','host','host']);
});

test('original Host registration retains every Provider beyond128 without invoking transport',()=>{
  const {entry,moon,calls}=fixture();let checks=0,registrations=0;
  const entries=Array.from({length:129},(_,index)=>({...entry,providerId:`models/fixture-${index}`}));
  const installed=installModelProviders(moon,()=>{registrations++;return entries;},()=>checks++);
  assert.equal(registrations,1);assert.equal(installed.size,129);
  assert.deepEqual(calls,entries.map(value=>['sync',value.providerId]));
  for(const original of entries){
    const retained=installed.get(original.providerId);
    assert.ok(retained);retained.assertTrustedRuntime();
  }
  assert.equal(checks,131,'Existing Host checks remain before/after registration and each original use');
  const original=installed.get(entries.at(-1).providerId);
  installed.set(entries.at(-1).providerId,{...original});
  assert.throws(()=>original.assertTrustedRuntime(),{code:'InferTrustedRuntimeOriginalChanged'});
});

test('a registration callback cannot make a closing Host current',()=>{
  const {entry,moon,calls}=fixture();let closing=false;
  const stopped=Object.assign(new Error('ClientHostClosing'),{code:'ClientHostClosing'});
  assert.throws(()=>installModelProviders(moon,()=>{closing=true;return [entry];},()=>{
    if(closing)throw stopped;
  }),error=>error===stopped);
  assert.deepEqual(calls,[]);
});

test('a copied table member cannot borrow the original runtime association',()=>{
  const {entry,moon}=fixture();let checks=0;
  const installed=installModelProviders(moon,()=>[entry],()=>checks++);
  const retained=installed.get('models/fixture');
  retained.assertTrustedRuntime();
  installed.set('models/fixture',{...retained});
  assert.throws(()=>retained.assertTrustedRuntime(),
    {code:'InferTrustedRuntimeOriginalChanged'});
  assert.equal(checks,4);
});
