import test from 'node:test';
import assert from 'node:assert/strict';
import {inspectPreparationChainCustody} from './current-inspect.mjs';
import {inspectPreparationStorage} from './preparation-arrays.mjs';

// Independent fixed-edge correspondence inputs, not Native receipts. Offsets
// and role tokens are authored here rather than imported from the inspector.
function fixture() {
  const record=(id,bytes,fields)=>({id,requestedBytes:bytes,
    captures:fields.map(([offset,id])=>({offset,id}))});
  const prep=(id,inputs,selected,read)=>record(id,104,
    [[0,'100'],[16,inputs],[24,'102'],[32,selected],[40,'103'],[48,'104'],[72,null],[80,read]]);
  const read=(id,bound,columns,name,actual)=>record(id,96,
    [[0,bound],[8,'105'],[16,columns],[64,name],[72,actual]]);
  const pending={phase:0,preparation:prep('110','101','111','112'),read:read('112','113','114','115','116')};
  const cleared=structuredClone(pending);cleared.phase=1;
  cleared.preparation.captures.at(-1).id=null;
  const transferred={phase:2,preparation:prep('120','121','122',null),
    read:read('123','124','125','126','127'),
    transferred:record('128',40,[[0,'124'],[8,'105'],[16,'125']])};
  const array=(owner,backing,length,slots,width,first)=>({owner,backing,length,slots,
    elementBytes:width,ownerBytes:24,backingBytes:8+width*slots,
    staticBacking:slots===0,firstInitialized:first});
  for(const f of [pending,cleared])Object.assign(f,{ports:1,fields:1,
    selected:array('111','117',0,0,8,null),columns:array('114','118',f.phase===0?1:0,8,4,0),
    transferred:null,transferredColumns:null});
  Object.assign(transferred,{ports:1,fields:1,selected:array('122','129',1,8,8,'130'),
    columns:array('125','131',1,8,4,0),transferredColumns:'125'});
  const retired=structuredClone(transferred);retired.phase=3;
  retired.selected.length=0;
  const phases=Array.from({length:7},(_,phase)=>({kind:'phase',phase}));
  Object.assign(phases[1],{preparation:structuredClone(pending.preparation),
    read:structuredClone(pending.read),completed:{id:'102'}});
  const records=[{kind:'startup',roots:{sequence:'100',inputs:'101'}},...phases];
  return {records,facts:[pending,cleared,transferred,retired]};
}
const at=(r,offset)=>r.captures.find(c=>c.offset===offset);
test('joins real chain roots and permits a fresh binding for repeated edge preparation',()=>{
  const {records,facts}=fixture(),result=inspectPreparationChainCustody(records,facts);
  assert.notEqual(at(facts[0].read,0).id,at(facts[2].read,0).id);
  assert.equal(result.exactPendingCursor,true);assert.equal(result.exactTransferredBinding,true);
  assert.equal(result.actualStoragePoints,4);assert.equal(result.completePhysicalLifetimeUpper,false);
});
test('rejects a detached pending census with identical extents',()=>{
  for(const key of ['preparation','read']) {
    const {records,facts}=fixture();facts[0][key].id='999';
    assert.throws(()=>inspectPreparationChainCustody(records,facts),/different chain/);
  }
});
test('rejects substituted sequence, completed container, receiving owner and node',()=>{
  for(const offset of [0,24,40,48]) {
    const {records,facts}=fixture();at(facts[2].preparation,offset).id='999';
    assert.throws(()=>inspectPreparationChainCustody(records,facts),/Preparation/);
  }
});
test('rejects lost pending inputs or binding during cleanup',()=>{
  const changes=[f=>at(f[1].preparation,16).id='999',f=>at(f[1].read,0).id='999'];
  for(const change of changes) {const {records,facts}=fixture();change(facts);
    assert.throws(()=>inspectPreparationChainCustody(records,facts),/Pending/);}
});
test('rejects a detached or unretired metadata cursor',()=>{
  for(const phase of [0,1,2,3]) {const {records,facts}=fixture();at(facts[phase].preparation,80).id='999';
    assert.throws(()=>inspectPreparationChainCustody(records,facts),/cursor|different chain preparation/);}
});
test('same-size sequence and binding substitutions pass storage alone but fail joined custody',()=>{
  const positive=fixture();assert.equal(inspectPreparationStorage(positive.facts).columnsTransferCopies,0);
  for(const change of [f=>at(f.preparation,0).id='999',f=>at(f.transferred,0).id='999']) {
    const {records,facts}=fixture();change(facts[2]);change(facts[3]);
    assert.deepEqual(inspectPreparationStorage(facts),inspectPreparationStorage(positive.facts));
    assert.throws(()=>inspectPreparationChainCustody(records,facts),/sequence|binding/);
  }
});
test('rejects binding or schema substitution at transfer despite the same columns owner',()=>{
  for(const offset of [0,8]) {const {records,facts}=fixture();at(facts[2].transferred,offset).id='999';
    assert.throws(()=>inspectPreparationChainCustody(records,facts),/Transfer substitutes/);}
});
test('rejects changed receiving schema and retained matched input after transfer',()=>{
  const changes=[f=>at(f[2].read,8).id='999',f=>at(f[3].preparation,72).id='999'];
  for(const change of changes) {const {records,facts}=fixture();change(facts);
    assert.throws(()=>inspectPreparationChainCustody(records,facts),/schema|matched input/);}
});
test('rejects missing, repeated, partial-layout or unordered observation points',()=>{
  const changes=[f=>f.pop(),f=>f[1].phase=0,f=>f[2].read.captures.push({offset:24,id:'999'}),
    f=>f[2].preparation.requestedBytes=96,f=>f.reverse(),
    f=>f[2].transferred.captures.push({offset:0,id:'999'}),f=>f[2].transferred.requestedBytes=48];
  for(const change of changes) {const {records,facts}=fixture();change(facts);
    assert.throws(()=>inspectPreparationChainCustody(records,facts));}
});
