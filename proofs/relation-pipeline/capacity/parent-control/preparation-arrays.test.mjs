import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {checkPreparationArraySource,preparationStorageEnvelope,inspectPreparationStorage} from './preparation-arrays.mjs';
const read=p=>readFileSync(new URL('../../../../'+p,import.meta.url));

// Independent validator inputs, not Native execution receipts. Each component
// has a distinct identity; only the published columns owner is deliberately
// shared. The real observer is accepted separately from its archived log.
function fixture() {
  const record=(id,bytes,captures)=>({id,requestedBytes:bytes,captures});
  const array=(owner,backing,length,slots,width,first)=>({owner,backing,length,slots,
    elementBytes:width,ownerBytes:24,backingBytes:8+width*slots,staticBacking:slots===0,firstInitialized:first});
  const point=(phase,prep,readId,selected,columns,transferred=null)=>({phase,ports:1,fields:1,
    preparation:record(prep,112,[{offset:32,id:selected.owner}]),
    read:record(readId,96,[{offset:16,id:columns.owner}]),selected,columns,
    transferred,transferredColumns:transferred?columns.owner:null});
  const pending=point(0,'101','102',array('103','104',0,0,8,null),array('105','106',1,8,4,0));
  const cleared=structuredClone(pending);cleared.phase=1;cleared.columns.length=0;
  const transfer=point(2,'201','202',array('203','204',1,8,8,'207'),array('205','206',1,8,4,0),
    record('208',40,[{offset:16,id:'205'}]));
  const retired=structuredClone(transfer);retired.phase=3;retired.selected.length=0;
  return [pending,cleared,transfer,retired];
}
test('source guards bind cardinality, zero initial capacity and same-owner transfer',()=>{
  assert.equal(checkPreparationArraySource(read).completeLifetimeUpper,false);
  const cases=[
    ['src/connectors/local/relation_chain_input_preparation.mbt','selected: []','selected: Array::make(2, inputs[0])'],
    ['src/connectors/local/relation_chain_input_preparation.mbt','cursor.port += 1','cursor.port += 0'],
    ['src/execution_relation/producer_read_preparation.mbt','if count > max_entries','if count > max_entries + 1'],
    ['src/execution_relation/producer_read_preparation.mbt','cursor.field += 1','cursor.field += 0'],
    ['src/execution_relation/producer_read_preparation.mbt','columns: cursor.columns','columns: cursor.columns.copy()'],
    ['src/execution_relation/producer_read_preparation.mbt','if !cursor.terminal {','if cursor.terminal {'],
  ];
  for(const [file,before,after] of cases)assert.throws(()=>checkPreparationArraySource(p=>
    p===file?read(p).toString().replace(before,after):read(p)));
});
test('conditional storage uses admitted dimensions and includes old/new overlap',()=>{
  assert.equal(preparationStorageEnvelope(1,1).bytes,272n);
  assert.equal(preparationStorageEnvelope(0,0).bytes,80n);
  assert.equal(preparationStorageEnvelope(9,10).bytes,528n);
  assert.equal(preparationStorageEnvelope(2147483647,2147483647).bytes,103079215136n);
  for(const n of [-1,1.5,2147483648,NaN])assert.throws(()=>preparationStorageEnvelope(n,1));
});
test('point observations retain cleared backing and charge transferred columns once',()=>{
  const result=inspectPreparationStorage(fixture());
  assert.equal(result.completeLifetimeUpper,false);
  assert.equal(result.columnsTransferCopies,0);
  assert.deepEqual(result.summaries.map(f=>f.dynamicRequestedBytes),['88','88','160','160']);
});
test('reject copied transfer, lost initialized slots, discarded backing and invented dimensions',()=>{
  const changes=[
    f=>f[2].transferred.captures[0].id='999',
    f=>f[3].selected.firstInitialized=null,
    f=>{f[1].columns.backing='999';f[1].columns.slots=0;f[1].columns.backingBytes=8;f[1].columns.staticBacking=true;},
    f=>f[3].columns.length=0,
    f=>f[2].fields=2,
    f=>f[0].columns.slots=16,
    f=>f[0].read.captures[0].id='999',
    f=>f.pop(),
  ];
  for(const change of changes){const facts=fixture();change(facts);assert.throws(()=>inspectPreparationStorage(facts));}
});
