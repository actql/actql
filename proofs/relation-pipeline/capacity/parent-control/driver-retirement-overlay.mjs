import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {hash} from '../../inventory.mjs';
import {blockAfter,checkDriverRetirementSource,driverPath} from './driver-retirement-source.mjs';
export const retirementHelper='src/connectors/local/driver/driver_retirement_native.mbt';
export const retirementStub='src/connectors/local/driver/driver_retirement_stub.c';
export const retirementFixture='src/query_integration/driver_retirement_native_wbtest.mbt';
const hostPath='src/query_integration/graph_host_custody_wbtest.mbt';
const pkg='src/connectors/local/driver/moon.pkg';
export const retirementPaths=[driverPath,pkg,hostPath,'src/query_integration/moon.pkg'];
const once=(s,from,to)=>{assert.equal(s.split(from).length,2,'Changed retirement observation attachment');return s.replace(from,to);};
export function retirementOverlay(read,source) {
  checkDriverRetirementSource(read);
  let driver=read(driverPath).toString();
  const body=blockAfter(driver,'let release_provider_scratch = fn()');
  let observed=once(body,'None => true','None => { println(driver_retirement_probe(provider_execution, 0, 4))\n true }');
  observed=once(observed,'          return false','          println(driver_retirement_probe(provider_execution, 0, 2))\n          return false');
  observed=once(observed,'        provider_execution.val = None','        provider_execution.val = None\n        println(driver_retirement_probe(provider_execution, 0, 3))');
  driver=once(driver,body,observed);
  driver=once(driver,'  let retired_carriers :','  println(driver_retirement_probe(provider_execution, setup.task, 0))\n  let retired_carriers :');
  driver=once(driver,'            provider_execution.val = Some(started)','            provider_execution.val = Some(started)\n            println(driver_retirement_probe(provider_execution, setup.task, 1))');
  let host=read(hostPath).toString();
  const helper=blockAfter(host,'fn retry_graph_host_match_cleanup(');
  const emit=(name,value)=>`  println("ACTQL_DRIVER_LEDGER:{\\"phase\\":\\"${name}\\",\\"execution\\":" + ${value}.reserved_execution_bytes.to_string() + ",\\"retention\\":" + ${value}.reserved_retention_bytes.to_string() + ",\\"held\\":" + ${value}.held_bytes.to_string() + ",\\"transfer\\":" + ${value}.transferred_bytes.to_string() + "}")\n`;
  let h=once(helper,'  let work =',emit('pending','pending')+'  let work =');
  h=once(h,'  assert_true(\n    cleaned.reserved_execution_bytes',emit('cleaned','cleaned')+'  assert_true(\n    cleaned.reserved_execution_bytes');
  h=once(h,'  assert_eq(attempts.val, 3)\n  assert_eq(','  assert_eq(attempts.val, 3)\n'+emit('repeated','@resources.ledger_usage(@strategy.captured_dag_ledger(run))')+'  assert_eq(');
  host=once(host,helper,h);
  const overlay={[driverPath]:driver,[pkg]:read(pkg).toString()+'\noptions("native-stub": ["driver_retirement_stub.c"], targets: {"driver_retirement_native.mbt": ["native"]})\n',
    [hostPath]:host,[retirementHelper]:readFileSync(new URL('./driver-retirement-observe.mbt',import.meta.url),'utf8'),
    [retirementStub]:readFileSync(new URL('./driver-retirement-reader.c',import.meta.url),'utf8'),
    [retirementFixture]:readFileSync(new URL('./driver-retirement-fixture.mbt',import.meta.url),'utf8')};
  // The generated fixture is selected only on Native; no other backend gains
  // a declaration referencing the Native-only borrowed observer.
  overlay['src/query_integration/moon.pkg']=once(read('src/query_integration/moon.pkg').toString(), 'options(\n', 'options(\n  targets: {"driver_retirement_native_wbtest.mbt": ["native"]},\n');
  const boundary={sourceDigest:source.digest,target:'native',command:['moon','test','--target','native',retirementFixture,'--deny-warn'],
    observationInputs:Object.fromEntries(Object.entries(overlay).map(([p,t])=>[p,hash(t)]))};
  const buildIdentity=hash(JSON.stringify(boundary));
  overlay[retirementFixture]=once(overlay[retirementFixture],'  for variant','  println("ACTQL_DRIVER_BUILD:'+buildIdentity+'")\n  for variant');
  return {overlay,boundary,buildIdentity};
}
