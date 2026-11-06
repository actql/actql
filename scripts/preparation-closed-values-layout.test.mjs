import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import test from 'node:test';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
async function fields(file, name) {
  const source = await readFile(path.join(root, 'src', file), 'utf8');
  const match = source.match(new RegExp(`(?:priv |pub(?:\\(all\\))? )?struct ${name} \\{([\\s\\S]*?)^\\}`, 'm'));
  assert.ok(match, `missing original constructor ${name}`);
  return [...match[1].matchAll(/^\s*(?:mut\s+)?([a-z_]+)\s*:/gm)].map(item => item[1]);
}

test('Closed Values layout names the exact original literal and lowering owner fields', async () => {
  assert.deepEqual(await fields('relation_values/types.mbt', 'CheckedValues'),
    ['source','schema','rows','pending','binding_cells','usage']);
  assert.deepEqual(await fields('relation_values/types.mbt', 'Row'), ['source','cells']);
  assert.deepEqual(await fields('value_admission/types.mbt', 'CheckedValue'), ['contract','value']);
  // One admission-owned measurement is shared by child Cursors; no reparse or
  // per-node preparation owner is introduced by this retained field.
  assert.deepEqual(await fields('decode_core/types.mbt', 'Cursor'), ['tree','index','usage','preparation']);
  assert.deepEqual(await fields('lowering_relation/prepare.mbt', 'Prepared'),
    ['owner','nodes','input_ids','input_schemas','input_carriers','usage']);
  assert.deepEqual(await fields('lowering_relation/prepare.mbt', 'PreparedNode'),
    ['id','projection_id','order_id','aggregation_id','nest_expansion','vector_expansion',
      'payload','inputs','input_targets','output_schema','output_carrier','source']);
  assert.deepEqual(await fields('lowering_relation/bindings.mbt', 'BoundPrepared'),
    ['prepared','bindings','by_name','expression_profiles','expression_context','text_time_policy']);
});

test('Closed Values checker and DAG layout refuses silent owner-field drift', async () => {
  assert.deepEqual(await fields('program_check/check.mbt', 'CheckedProgram'),
    ['source','completion_free_audit','local_completion_free_audit','local_legacy_audit_prepared',
      'has_effects','keyed_input_proofs','nest_limits','traversal_limits','sequence_limits',
      'interval_search_limits','asof_search_limits','window_limits','input_completeness',
      'expression_profiles','catalog_references','identity','requirements','gates','contracts',
      'units','group_limits','analytic_limits','group_string_limits','analytic_string_limits',
      'numeric_slots','analytic_numeric_slots','pivot_numeric_slots','model_tasks']);
  assert.deepEqual(await fields('physical_strategy/graph.mbt', 'CheckedDAG'),
    ['program','source_free_root','captured_prefix','original_tasks','original_task_count','owners',
      'stage_tasks','targets','input_counts','selected_steps','prefix_ends','data','supplied_slots',
      'control','operations','numeric','results']);
  assert.deepEqual(await fields('pipeline_typing/types.mbt', 'CheckedPipeline'),
    ['input_orders','produced_inputs','logical_orders','serialization_completions','lag_orders',
      'analytic_orders','graph_counts','join_evidence','row_counts','ranked_inputs','ranked_steps',
      'keyed_inputs','keyed_steps','literal_inputs','literal_steps','delta_inputs','delta_steps',
      'source','initial_from','inputs','input_contracts','steps','names','current','output','parameters','usage']);
});

test('Closed Values Result owner layout distinguishes projection and publication records', async () => {
  assert.deepEqual(await fields('relation_results/ports.mbt', 'ResultPort'), ['orders','index','publication']);
  assert.deepEqual(await fields('relation_results/ports.mbt', 'ResultPorts'), ['orders','entries','usage']);
  assert.deepEqual(await fields('pipeline_typing/produced_input.mbt', 'ProducedInput'),
    ['pipeline','target','carrier','rows','graph','keys','literals','ranking','order','window','delta','projection']);
  assert.deepEqual(await fields('relation_typing/types.mbt', 'CheckedOperation'),
    ['operation','form','source','input','output','parameters','bindings','projection','row_operation',
      'reshape','group','pivot','analytic','pending','work_used','text_bytes_used','nodes_used','tokens_used']);
});

// Independent structural walker: it observes actual live LIFO frontier sizes
// of generated authored objects, rather than recomputing a cost formula.
function walkExtent(root) {
  const stack = [root];
  let pending = 1, children = 0, names = 0;
  while (stack.length) {
    const value = stack.pop();
    if (Array.isArray(value)) {
      children = Math.max(children, value.length);
      for (const item of value) { stack.push(item); pending = Math.max(pending, stack.length); }
    } else if (value !== null && typeof value === 'object') {
      const keys = Object.keys(value);
      names = Math.max(names, keys.length);
      for (const key of keys) { stack.push(value[key]); pending = Math.max(pending, stack.length); }
    }
  }
  return {pending, children, names};
}

test('original closed Values permutations fit the pending and current-child bounds', () => {
  let cases = 0;
  for (const width of [1,2,3,7,8,9,16,31,100]) for (const count of [0,1,2,3,8,9,31,99]) {
    for (const reverseFields of [false,true]) for (const schemaFirst of [false,true]) {
      const fields = Array.from({length:width}, (_,i)=>`v${i}`);
      if (reverseFields) fields.reverse();
      const schema = Object.fromEntries(fields.map(name=>[name,{type:'number',nullable:false}]));
      const rows = Array.from({length:count}, (_,r)=>Object.fromEntries(fields.map((name,i)=>[name,r+i])));
      const values = schemaFirst ? {schema,rows} : {rows,schema};
      const result = {r:{from:'v',fields}};
      for (const root of [values,result,...Object.values(schema)]) {
        const actual = walkExtent(root);
        assert.ok(actual.pending <= count+width+2, JSON.stringify({width,count,actual}));
        assert.ok(actual.children <= Math.max(count,width), JSON.stringify({width,count,actual}));
        assert.ok(actual.names <= Math.max(width,3), JSON.stringify({width,count,actual}));
      }
      cases++;
    }
  }
  assert.equal(cases,288);
  assert.deepEqual(walkExtent({schema:{x:{type:'number',nullable:false}},rows:[{x:1}]}),
    {pending:2,children:1,names:2});
});

test('Closed Values topology retains empty original parameters and strict ancestry without field drift', async () => {
  for (const [file,name,expected] of [
    // Retain the same original declaration limits and optional binding reader.
    ['stage_parameters/source.mbt','Source',['program','prefix','stages','declarations','declaration_limits','binding_read']],
    ['parameter_binding/types.mbt','Declarations',['entries','usage']],
    ['parameter_binding/types.mbt','BoundValues',['declarations','entries','usage']],
    ['stage_parameters/source.mbt','CollectedStage',['source','stage_index','collection','work']],
    ['stage_parameters/operations.mbt','CollectedOperations',['source','stages','index','usage']],
    ['stage_parameters/bindings.mbt','BoundOperations',['operations','program','stages','usage']],
    ['stage_results/imports.mbt','StagePorts',['stage','ports','table_inputs']],
    ['stage_results/imports.mbt','ResultImports',['source','stage','entries','work','text_bytes']],
    ['stage_results/imports.mbt','AttachedImports',['imports','stage','work']],
    ['stage_results/wiring.mbt','ResultWiring',['source','stages','imports','exports','work','text_bytes','local_inputs','local_environment','reconciled_inputs','preparation_usage']],
    ['stage_results/local_source.mbt','PreparedLocalSource',['source','values','wiring','operations','results','usage','context_prefix']],
    ['stage_results/check.mbt','Checked',['operations','stages','table_inputs','usage']],
  ]) assert.deepEqual(await fields(file,name),expected,name);
  const stages=await readFile(path.join(root,'src/stage_syntax/stages.mbt'),'utf8');
  assert.match(stages,/pub fn stages\(program : Program\) -> Array\[Stage\] \{\s*program.stages.copy\(\)/);
  const source=await readFile(path.join(root,'src/stage_parameters/source.mbt'),'utf8');
  assert.match(source,/match @pipeline.parameters\(pipeline\) \{\s*Some\(d\)/);
  assert.match(source,/None => return Err\(ForeignDeclarations\)/);
});
