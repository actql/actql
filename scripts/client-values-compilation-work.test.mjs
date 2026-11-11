import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {tokens} from './portable-core.mjs';

// Source-level construction ceilings, not sampled CPU or runtime invocation
// counts. Real compiler tests independently check the retained parts and bytes.
function body(file, name) {
  const input=tokens(readFileSync(new URL(`../src/run_publication_host/${file}.mbt`,import.meta.url),'utf8'),true);
  const start=input.findIndex((token,index)=>token.value==='fn' && input[index+1]?.value===name);
  assert(start>=0,`Missing existing compiler operation ${name}`);
  let index=start+2;
  while(index<input.length && input[index].value!=='{') index++;
  assert(index<input.length);
  const selected=[];
  for(let depth=1;++index<input.length;) {
    if(input[index].value==='{') depth++;
    if(input[index].value==='}' && --depth===0) return selected;
    // Closing a nested body changes depth only once.
    if(input[index].value==='}' && depth<0) assert.fail('Unbalanced source');
    selected.push(input[index]);
  }
  assert.fail(`Unclosed compiler operation ${name}`);
}
function calls(input,name) {
  return input.filter((token,index)=>token.kind==='word' && token.value===name &&
    input[index+1]?.value==='(').length;
}

test('Values compilation constructs its private parts once and never reissues them in final assembly',()=>{
  const entry=body('client_values_compilation','issue_prepared_client_values_compilation');
  assert.equal(calls(entry,'issue_prepared_client_values_compilation_owned'),1);
  assert.equal(calls(entry,'issue_prepared_client_values_executable_plan_parts'),0);
  const owned=body('client_values_compilation','issue_prepared_client_values_compilation_owned');
  assert.equal(calls(owned,'issue_prepared_client_values_executable_plan_parts'),1);
  assert.equal(calls(owned,'issue_client_values_compilation_with_parts'),1);
  for(const name of ['issue_prepared_client_values_execution_material',
    'issue_prepared_client_values_aoa_identity','issue_prepared_client_values_fragment',
    'admit_run_evidence_value']) {
    assert.equal(calls(entry,name),0,name);
    assert.equal(calls(owned,name),0,name);
  }
  const finish=body('client_values_compilation','issue_client_values_compilation_with_parts');
  for(const name of ['issue_prepared_client_values_execution_material',
    'issue_prepared_client_values_aoa_identity','issue_prepared_client_values_fragment',
    'admit_run_evidence_value']) assert.equal(calls(finish,name),0,name);
});

test('Values private construction emits one graph, template, execution material and AoA',()=>{
  const plan=body('client_values_executable_plan','issue_prepared_client_values_executable_plan_parts');
  for(const name of ['issue_prepared_client_values_plan_graph_parts',
    'issue_source_free_client_bound_template_from_aoa',
    'issue_prepared_client_execution_material_with_template',
    'issue_prepared_client_executable_plan_with_parts']) assert.equal(calls(plan,name),1,name);
  const graph=body('client_values_plan_graph','issue_prepared_client_values_plan_graph_parts');
  assert.equal(calls(graph,'issue_client_values_fragment_parts_graph'),1);
  const fragment=body('client_values_fragment','issue_client_values_fragment_parts_graph');
  assert.equal(calls(fragment,'issue_client_values_aoa_parts_graph'),1);
  assert.equal(calls(fragment,'parse_plan_identity_value'),0);
  const template=body('client_bound_template','issue_source_free_client_bound_template_from_aoa');
  for(const name of ['issue_prepared_client_values_plan_graph',
    'issue_prepared_client_values_aoa_identity','parse_plan_identity_value']) {
    assert.equal(calls(template,name),0,name);
  }
});
