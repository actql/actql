import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {checkDriverRetirementSource, driverPath, strategyPath} from './driver-retirement-source.mjs';
import {retirementOverlay} from './driver-retirement-overlay.mjs';
import {inspectDriverRetirement} from './driver-retirement-inspect.mjs';
const root = fileURLToPath(new URL('../../../../',import.meta.url));
const read = p => readFileSync(root+p);
const changed = (path, from, to) => {
  const original = read(path).toString();
  assert.equal(original.split(from).length,2,'Mutation must reach unique actual boundary');
  return p => p === path ? original.replace(from,to) : read(p);
};
test('current driver/common owner source and additive Native overlay are admitted', () => {
  assert.equal(checkDriverRetirementSource(read).clearsProviderAfterCleanupSuccess,true);
  const {overlay} = retirementOverlay(read,{digest:'a'.repeat(64)});
  assert.match(overlay[driverPath],/println\(driver_retirement_probe\(provider_execution, setup.task, 3\)\)/);
  assert.equal((overlay[driverPath].match(/cleanup_managed_provider\(active\)/g)??[]).length,
    (read(driverPath).toString().match(/cleanup_managed_provider\(active\)/g)??[]).length);
  assert.equal(overlay['src/query_integration/moon.pkg'].split('options(').length,2, 'Reuse existing package options');
  assert.match(overlay['src/query_integration/moon.pkg'], /cc-link-flags/);
  const host = 'src/query_integration/graph_host_custody_wbtest.mbt';
  assert.equal((overlay[host].match(/assert_(?:true|eq)\(/g)??[]).length,
    (read(host).toString().match(/assert_(?:true|eq)\(/g)??[]).length);
});
for (const [name,path,from,to] of [
  ['ignore cleanup error',driverPath,'!@local.cleanup_managed_provider(active).unwrap_or(false)','false'],
  ['ignore physical stop',driverPath,'!@local.managed_provider_stopped(active) ||','false ||'],
  ['retain provider forever',driverPath,'        provider_execution.val = None','        provider_execution.val = Some(active)'],
  ['drop root before pending return',driverPath,'          return false\n        }\n        final_provider_work.val','          provider_execution.val = None\n          return false\n        }\n        final_provider_work.val'],
  ['scratch witness accepts live root',driverPath,'scratch_uses.val == 0 && provider_execution.val is None','scratch_uses.val == 0'],
  ['reservation returned before scratch',strategyPath,'remaining_execution=if scratch_released { 0L } else { execution.scratch }','remaining_execution=0L'],
  ['ignore retention release',strategyPath,'if !scratch_released || !task_execution_retention_released(execution) {','if !scratch_released {'],
]) test('source rejects '+name,()=>assert.throws(()=>checkDriverRetirementSource(changed(path,from,to))));

function records() {
  return ['current_filter','current_edge_filter'].flatMap((variant,i)=> {
    const root=String(100+i),provider=String(900+i);
    const rootRecord=(phase,p)=>'ACTQL_DRIVER_ROOT:'+JSON.stringify({task:3,phase,root,rootRequestedBytes:16,provider:p});
    const ledger=(phase,execution)=>'ACTQL_DRIVER_LEDGER:'+JSON.stringify({phase,execution,retention:20,held:40,transfer:0});
    return ['ACTQL_DRIVER_CASE:'+variant,rootRecord(0,null),rootRecord(1,provider),
      rootRecord(2,provider),rootRecord(2,provider),ledger('pending',100),rootRecord(3,null),
      ledger('cleaned',60),rootRecord(4,null),ledger('repeated',60),'ACTQL_DRIVER_CASE_DONE:'+variant];
  });
}
test('two complete finite Host traces retain pending root and return scratch once',()=>{
  const result=inspectDriverRetirement(records().join('\n'));
  assert.equal(result.cases.length,2);assert.equal(result.physicalGCDestruction,false);
});
for (const [name,mutate] of [
  ['early root release',a=>{a[3]=a[3].replace('"provider":"900"','"provider":null');}],
  ['replacement provider identity',a=>{a[4]=a[4].replace('"900"','"901"');}],
  ['missing pending error',a=>{a.splice(4,1);}],
  ['missing successful clear',a=>{a.splice(6,1);}],
  ['same-size replacement root',a=>{a[6]=a[6].replace('"root":"100"','"root":"101"');}],
  ['duplicate scratch credit',a=>{a[9]=a[9].replace('"execution":60','"execution":59');}],
  ['unrelated holding release',a=>{a[7]=a[7].replace('"held":40','"held":39');}],
  ['missing second Host completion',a=>{a.pop();}],
  ['wrong ABI extent',a=>{a[1]=a[1].replace('"rootRequestedBytes":16','"rootRequestedBytes":24');}],
]) test('observation rejects '+name,()=>{
  const a=records();mutate(a);assert.throws(()=>inspectDriverRetirement(a.join('\n')));
});
