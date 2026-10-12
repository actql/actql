import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {canonicalText} from './check-canonical-json.mjs';
import {decisionVectors} from './decision-vectors.mjs';

const hash=value=>'sha256:'+createHash('sha256').update(canonicalText(value)).digest('hex');
const literal=value=>JSON.stringify(canonicalText(value));
const destination='src/model_execution/native_decision_projection_fixture.generated_wbtest.mbt';
export function nativeDecisionProjectionFixture(){
  const {corpus}=decisionVectors();
  const body={version:'actql-check-environment/0.1',command_contracts:[],
    connector_capabilities:[],connector_catalogs:[],contract_registry:[],
    host_policy_profile:{},mapping_contracts:[],model_task_contracts:[corpus.task],
    schema_snapshots:[],source_views:[]};
  const environment={...body,evidence_bundle_cid:hash(body)};
  const source=`// Generated original fixture; existing independent Decision bytes/CIDs unchanged.

///|
fn native_decision_projection_fixture(state_wire : String) -> (AdmittedModelProvider, ModelRequest, () -> Int) {
  let limits : @environment.Limits = {max_bytes:100000,max_nodes:10000,max_depth:100,max_members:10}
  let env = @environment.read(@utf8.encode(${literal(environment)}),${JSON.stringify(environment.evidence_bundle_cid)},limits).unwrap()
  let tasks = @environment.check_model_tasks(env,{bodies:limits,contracts:{max_nodes:1000,max_depth:50,max_text_bytes:10000},max_work:1000000}).unwrap()
  let task = @environment.resolve_model_task(tasks,"model-task:decision-fixture").unwrap()
  let execution = @environment.read_model_execution_contract(task,@utf8.encode(${literal(corpus.execution)}),${JSON.stringify(corpus.execution.self_cid)},limits,1000000).unwrap()
  let dependencies = @environment.read_single_attempt_model_dependencies(execution,
    Some(@utf8.encode(${literal(corpus.prompt)})),Some(@utf8.encode(${literal(corpus.retry)})),Some(@utf8.encode(${literal(corpus.backoff)})),limits,1000000).unwrap()
  let mut calls = 0
  let provider = install_model_provider("models/fixture",_ => {calls += 1;Err(Cancelled)}).unwrap()
  let admitted = admit_model_provider(provider,execution,dependencies,(_,_) => true).unwrap()
  let value_limits : @admitted.Limits = {max_nodes:1000,max_depth:50,max_text_bytes:10000}
  let (literal,_,_) = @admitted.admit_json_literal(state_wire,value_limits).unwrap()
  let state = @admitted.recheck_runtime_value(literal.value,@contract.primitive(JsonType,nullable=true),value_limits).unwrap()
  let request : ModelRequest = {task,slot:0,slot_cid:"sha256:"+"1".repeat(64),fixed_request_cid:"sha256:"+"2".repeat(64),key:[],inputs:[("state",state)]}
  (admitted,request,() => calls)
}
`;
  return execFileSync(process.env.MOON_HOME?join(process.env.MOON_HOME,'bin/moonfmt'):'moonfmt',
    ['-'],{input:source,encoding:'utf8'});
}
export function checkNativeDecisionProjectionFixture(){
  assert.equal(readFileSync(destination,'utf8'),nativeDecisionProjectionFixture());
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  if(process.argv.includes('--write'))writeFileSync(destination,nativeDecisionProjectionFixture());
  checkNativeDecisionProjectionFixture();
}
