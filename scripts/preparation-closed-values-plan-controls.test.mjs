import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import test from 'node:test';
const root=process.env.ACTQL_CORE ?? path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
async function fields(file,name){
  const selected=file==='client_local_host/installed_managed_run.mbt' ? process.env.ACTQL_INSTALLED_SOURCE ?? root : root;
  const source=await readFile(path.join(selected,'src',file),'utf8');
  const body=source.match(new RegExp(`struct ${name} \\{([\\s\\S]*?)^\\}`,'m'))?.[1];
  assert.ok(body,name);
  return [...body.matchAll(/^\s*(?:mut\s+)?([a-z_]+)\s*:/gm)].map(m=>m[1]);
}
test('installed Values plan fixed inventory follows current nominal owner fields',async()=>{
  // The Plan retains the original typed contracts, optional bound QueryTime
  // and completed compilation/configuration, rather than raw registry aliases.
  assert.deepEqual(await fields('client_local_host/installed_managed_run.mbt','ClientInstalledManagedSourceFreePreparation'),[
    'owner','_observed_query_time','installed_contracts','values_body','fragment_body','ordered_body',
    'sequences','capacity_plan','configuration','compilation','limits','provider_retained_bytes','provider_execution_bytes']);
  // Original schema/value demand and metadata refusal state belong to the
  // same capacity Plan; this field census is not an allocation quote.
  assert.deepEqual(await fields('client_local_host/capacity_plan.mbt','ClientLocalCapacityPlan'),[
    'sequences','admitted_rows','resource_policy','dispatch_entries','dispatch_name_bytes','graph',
    'graph_offset','_retained_result_envelope','publication','schema_inventory','demand_inventory',
    'value_node_demand','scalar_demand','values','execution','measurement','max_value_bytes','imports','exports',
    'metadata','metadata_retained_bytes','metadata_quote']);
  assert.deepEqual(await fields('run_publication_host/client_program.mbt','ClientFullSequence'),['task','limits','sequence']);
});
test('generated Values sequence retains exactly its original lower owner and control arrays',async()=>{
  assert.deepEqual(await fields('execution_relation/generated_sequence.mbt','GeneratedSequence'),[
    'contracts','sequence','selected_steps','selected_prefix_end','contexts','retained_ids',
    'join_ceilings','expansion_ceilings','session_output_ceilings','calendar_output_ceilings',
    'traversal_ceilings','interval_search_ceilings','asof_search_ceilings','sequence_match_ceilings',
    'aggregate_outputs','analytic_envelopes','nest_item_ceilings','nest_grouped_byte_ceilings',
    'nest_attached_byte_ceilings','query_time','numeric','working']);
  assert.deepEqual(await fields('lowering_relation/sequence.mbt','PreparedSequence'),['owner','steps']);
  assert.deepEqual(await fields('lowering_relation/values_encode.mbt','PreparedValues'),['owner','node','values']);
});
