import assert from 'node:assert/strict';
import {currentSlotsCeiling} from '../backing/model.mjs';
import {arrayStorageExtent} from '../backing/native-array.mjs';
import {reviewedFunction} from './provider-construction-source-review.mjs';

// These are source premises for two selected containers, not a complete
// lifetime analysis, allocation graph or replacement for the reservation.
export function checkPreparationArraySource(read) {
  const chain=read('src/connectors/local/relation_chain_input_preparation.mbt').toString();
  const producer=read('src/execution_relation/producer_read_preparation.mbt').toString();
  const start=reviewedFunction(chain,'start_relation_chain_inputs');
  assert(start.includes('selected: []') && start.includes('port: 0'));
  const advance=reviewedFunction(chain,'advance_relation_chain_inputs');
  assert(advance.includes('if cursor.port == @lower.node_input_count(cursor.node)'));
  assert.equal(advance.split('cursor.selected.push(').length,3,'Changed selected growth sites');
  assert.equal(advance.split('cursor.port += 1').length,3,'Changed per-port selection cardinality');
  assert(advance.includes('cursor.selected.push(input)\n        cursor.matched = None\n        cursor.port += 1'));
  assert(advance.includes('cursor.selected.push(RelationInput(read))\n          cursor.read = None\n          cursor.port += 1'));
  const begin=reviewedFunction(producer,'start_prepare_producer_read');
  assert(begin.includes('let count = @schema.field_count(schema)'));
  assert(begin.includes('if count > max_entries {') && begin.includes('columns: [],'));
  const step=reviewedFunction(producer,'advance_prepare_producer_read');
  assert.equal(step.split('cursor.columns.push(').length,2,'Changed columns growth sites');
  assert(step.includes('cursor.columns.push(cursor.column)\n          cursor.field += 1'));
  assert(step.includes('if cursor.field == @schema.field_count(cursor.schema)'));
  assert(step.includes('columns: cursor.columns,'),'Columns transfer must not copy storage');
  const cancel=reviewedFunction(producer,'cancel_prepare_producer_read');
  assert(cancel.includes('if !cursor.terminal {\n    cursor.columns.clear()'));
  assert(reviewedFunction(chain,'cancel_relation_chain_inputs').includes('cursor.selected.clear()'));
  return {selectedHighWater:'checked receiving node input count',columnsHighWater:'checked receiving schema field count, admitted by max_entries',
    emptyInitialCapacity:0,transfer:'same Array owner/backing; no implicit copy',clear:'visible length only; retained backing and initialized slots remain charged',completeLifetimeUpper:false};
}
export function preparationStorageEnvelope(ports,fields) {
  for(const value of [ports,fields])assert(Number.isSafeInteger(value) && value>=0 && value<=2147483647,'Outside admitted Int32 metadata dimension');
  const selectedSlots=currentSlotsCeiling(ports),columnsSlots=currentSlotsCeiling(fields);
  // One owner for each Array, and at most old/new buffers during growth.
  const bytes=80n+16n*selectedSlots+8n*columnsSlots;
  return {ports,fields,selectedSlots,columnsSlots,bytes,
    scope:'two preparation Array owners and conditional old/new backing overlap only',
    premises:['source cardinality and zero-capacity constructors','pinned Array growth/ABI','at most two growth buffers per Array, with no escaped view'],
    completeParentUpper:false};
}
const token=id=>assert(typeof id==='string' && /^[1-9][0-9]*$/.test(id) && BigInt(id)<=18446744073709551615n,'Invalid borrowed array identity');
const pointer=(r,offset)=>r.captures.find(c=>c.offset===offset)?.id;
export function inspectPreparationStorage(facts) {
  assert.deepEqual(facts.map(f=>f.phase),[0,1,2,3],'Missing ordered preparation storage points');
  const summaries=[];
  for(const f of facts) {
    assert.equal(f.ports,1);assert.equal(f.fields,1);token(f.preparation.id);token(f.read.id);
    assert.equal(f.preparation.requestedBytes,112);assert.equal(f.read.requestedBytes,96);
    assert.equal(pointer(f.preparation,32),f.selected.owner,'Selected Array detached from real preparation');
    assert.equal(pointer(f.read,16),f.columns.owner,'Columns Array detached from real metadata');
    const bound=preparationStorageEnvelope(f.ports,f.fields),unique=new Map();
    let upper=0n;
    for(const [name,element,ceiling] of [['selected','reference',bound.selectedSlots],['columns','int',bound.columnsSlots]]) {
      const a=f[name];token(a.owner);token(a.backing);
      assert(Number.isSafeInteger(a.length) && a.length>=0 && a.length<=1);
      assert(Number.isSafeInteger(a.slots) && a.slots>=a.length && BigInt(a.slots)<=ceiling);
      assert.equal(a.elementBytes,element==='int'?4:8);assert.equal(a.ownerBytes,24);
      assert.equal(a.backingBytes,Number(arrayStorageExtent(element,a.slots)-24n));
      assert.equal(a.staticBacking,a.slots===0);
      assert(a.owner!==a.backing);assert(a.owner!==f.preparation.id && a.owner!==f.read.id);
      const add=(id,bytes,immortal)=>{const old=unique.get(id);if(old)assert.deepEqual(old,{bytes,immortal},'Aliased identity has inconsistent storage');else unique.set(id,{bytes,immortal});};
      add(a.owner,24n,false);add(a.backing,BigInt(a.backingBytes),a.staticBacking);
      upper+=arrayStorageExtent(element,Number(ceiling));
    }
    assert(f.selected.owner!==f.columns.owner && f.selected.backing!==f.columns.backing,'Different typed containers alias');
    let dynamic=0n,staticBytes=0n;for(const a of unique.values())if(a.immortal)staticBytes+=a.bytes;else dynamic+=a.bytes;
    assert(dynamic+staticBytes<=upper && upper<=bound.bytes);
    summaries.push({phase:f.phase,dynamicRequestedBytes:dynamic.toString(),staticStorageBytes:staticBytes.toString(),
      pointStorageBound:upper.toString(),conditionalGrowthOverlapBound:bound.bytes.toString()});
  }
  const [pending,cleared,transfer,retired]=facts;
  assert.equal(pending.selected.length,0);assert.equal(pending.columns.length,1);assert.equal(pending.columns.firstInitialized,0);
  assert.equal(cleared.preparation.id,pending.preparation.id);assert.equal(cleared.read.id,pending.read.id);
  for(const name of ['selected','columns'])assert.deepEqual({...cleared[name],length:pending[name].length},pending[name],'Unfinished cleanup must not claim discarded backing');
  assert.equal(cleared.columns.length,0);
  for(const f of [pending,cleared]) {assert.equal(f.transferred,null);assert.equal(f.transferredColumns,null);}
  for(const f of [transfer,retired]) {
    token(f.transferred.id);assert.equal(f.transferred.requestedBytes,40);
    assert.equal(pointer(f.transferred,16),f.columns.owner,'Transferred ProducerRead copied or lost the columns Array');
    assert.equal(f.transferredColumns,f.columns.owner);
    assert.equal(f.columns.length,1);assert.equal(f.columns.firstInitialized,0);
    token(f.selected.firstInitialized);
  }
  assert.equal(transfer.selected.length,1);assert.equal(retired.selected.length,0);
  assert.equal(retired.preparation.id,transfer.preparation.id);assert.equal(retired.read.id,transfer.read.id);
  assert.deepEqual(retired.transferred,transfer.transferred);
  assert.deepEqual(retired.columns,transfer.columns,'Cancellation of completed cursor must preserve published columns');
  assert.deepEqual({...retired.selected,length:1},transfer.selected,'Clear must retain charged storage and the initialized reference');
  return {summaries,scope:'one pending cursor and one completed transfer of the same input occurrence; initialized slots remain retained after clear',
    columnsTransferCopies:0,completeLifetimeUpper:false,completeParentUpper:false,
    excluded:['selected input wrapper/ProducerRead/binding referents','shared schema and payload','escaped views and arbitrary external holders','allocator overhead and GC destruction']};
}
