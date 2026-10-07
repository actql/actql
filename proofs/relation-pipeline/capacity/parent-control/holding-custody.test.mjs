import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {snapshot} from '../../inventory.mjs';
import {retirementOverlay} from './driver-retirement-overlay.mjs';
import {blockAfter} from './driver-retirement-source.mjs';
import {checkHoldingCustodySource} from './holding-custody-source.mjs';
import {inspectHoldingCustody,custodyPhases} from './holding-custody-inspect.mjs';
const root=fileURLToPath(new URL('../../../../',import.meta.url));
const read=p=>readFileSync(root+p);
test('source guards and Native-only observation attach without changing existing Host assertions',()=>{
  checkHoldingCustodySource(read);
  const path='src/query_integration/graph_host_custody_wbtest.mbt';
  const {overlay,boundary}=retirementOverlay(read,snapshot(root),{holdingCustody:true});
  assert.equal(boundary.holdingCustody,true);
  assert.match(overlay['src/physical_resources/moon.pkg'],/holding_custody_native.mbt.*native/);
  assert.match(overlay['src/physical_strategy/moon.pkg'],/holding_custody_native.mbt.*native/);
  const anchor='fn run_current_host_graph_relation_path(';
  assert.equal((blockAfter(overlay[path],anchor).match(/assert_(?:true|eq|false)\(/g)??[]).length,
    (blockAfter(read(path).toString(),anchor).match(/assert_(?:true|eq|false)\(/g)??[]).length);
  for (const phase of custodyPhases) assert(overlay[path].includes('"'+phase+'"'));
});
for (const [name,path,from,to] of [
  ['consumer parent condition removed','src/physical_strategy/retention.mbt','child.parents.contains(task)','false'],
  ['running dependency removed','src/physical_strategy/retention.mbt','edge.consumer == active && edge.producer == task','false'],
  ['physical release ignored','src/physical_strategy/retention.mbt','!needed && (resource.release_confirmed)()','!needed'],
  ['release check removed','src/physical_resources/ledger.mbt','if !holding.live {','if false {'],
  ['holding liveness retained','src/physical_resources/ledger.mbt','holding.live = false','holding.live = true'],
  ['wrong source allocation bytes','src/physical_strategy/task_completion.mbt','owned.bytes == storage_bytes','true'],
  ['owner token left live','src/physical_strategy/task_completion.mbt','owned.live = false','owned.live = true'],
]) test('reviewed source refuses '+name,()=>{
  const s=read(path).toString();assert(s.includes(from));
  assert.throws(()=>checkHoldingCustodySource(p=>p===path?s.replace(from,to):read(p)));
});
function records() {
  return ['current_filter','current_edge_filter'].flatMap(variant=>[
    'ACTQL_DRIVER_CASE:'+variant,
    ...custodyPhases.map((phase,i)=>'ACTQL_HOLDING_CUSTODY:'+JSON.stringify({phase,task:4,serial:7,reservationSerial:9,bytes:40,
      ownerMatches:true,available:i<4,resourcePresent:i<4,sameToken:i<4,slotMatches:i===0,portLive:i===0,pins:0,
      children:i===0||i===2||i===3?1:0,runningConsumer:i===1,schedulerGeneration:i<2?5:6,outputAvailable:i<3,outputBytes:i<3?40:-1,
      heldBytes:i<2?100:i<4?120:60})),
    'ACTQL_DRIVER_CASE_DONE:'+variant]);
}
test('finite traces retain exact holding through active and completed consumer, then revoke it',()=>{
  const r=inspectHoldingCustody(records().join('\n'));assert.equal(r.cases.length,2);assert.equal(r.physicalGCDestruction,false);
});
for (const [name,index,patch] of [
  ['early release',2,{available:false}],['same-sized replacement',3,{sameToken:false}],
  ['foreign owner',4,{ownerMatches:false}],['reservation substitution',3,{reservationSerial:10}],
  ['wrong output bytes',1,{outputBytes:39}],['missing running consumer',2,{runningConsumer:false}],
  ['missing retained child',4,{children:0}],['premature credit',4,{heldBytes:80}],
  ['no allocation retirement',5,{available:true}],['duplicate credit',6,{heldBytes:59}],
  ['false scheduler/allocation identity',3,{schedulerGeneration:5}],['reopened public slot',4,{portLive:true}],
  ['read permission confused with allocation release',4,{available:false,outputAvailable:false,outputBytes:-1}],
]) test('consumer rejects '+name,()=>{
  const a=records();const prefix='ACTQL_HOLDING_CUSTODY:';
  a[index]=prefix+JSON.stringify({...JSON.parse(a[index].slice(prefix.length)),...patch});
  assert.throws(()=>inspectHoldingCustody(a.join('\n')));
});
test('consumer rejects missing and cross-case observations',()=>{
  const a=records();a.splice(3,1);assert.throws(()=>inspectHoldingCustody(a.join('\n')));
  assert.throws(()=>inspectHoldingCustody(records().slice(1).join('\n')));
});
