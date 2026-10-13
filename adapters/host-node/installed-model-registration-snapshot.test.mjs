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
  assert.equal(installed.bindingOriginals.configuration.wire,original);
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

test('invalid first quantity or mode refuses before constructing a Provider',()=>{
  for(const change of [entry=>{entry.entryPersistence='unknown';},
    entry=>{entry.quantityCapacity={...capacity(),perAttempt:{tokens:-1n,costUnits:0n,durationMs:1n}};}]) {
    const {entry,moon,calls}=fixture();change(entry);
    assert.throws(()=>installModelProviders(moon,()=>[entry]),/InvalidInstalledModel/u);
    assert.deepEqual(calls,[]);
  }
});
