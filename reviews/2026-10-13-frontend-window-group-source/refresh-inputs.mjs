import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const refresh = String.raw`import {readFileSync,writeFileSync} from 'node:fs';
import {registeredPublicQueryInventory} from './scripts/public-query-inventory.mjs';
import {sequenceIdentityOracle} from './scripts/sequence-identity-oracle.mjs';
const before=JSON.parse(readFileSync('reviews/2026-10-13-frontend-window-group-source/preimages/parent-values-identities.json','utf8'));
const after=sequenceIdentityOracle();
// Only current literal expectations move. The complete parent preimages and
// their old CID are retained separately, never overwritten by product output.
for(const path of ['src/run_publication_host/client_values_run_materials_wbtest.mbt','scripts/client-values-run-materials-vector.test.mjs']) {
 let text=readFileSync(path,'utf8');
 for(const [part,field] of [['template','bound_invocation_template_cid'],['executable','executable_plan_cid'],['compiled','compiled_plan_cid'],['run','run_definition_cid']])
  text=text.replaceAll(before.run_preimages[part][field],after.run_preimages[part][field]);
 writeFileSync(path,text);
}
const old=JSON.parse(readFileSync('scripts/fixtures/pre-window-group-public-query-inventory.json','utf8'));
const next=await registeredPublicQueryInventory();
writeFileSync('scripts/fixtures/public-query-inventory.json',JSON.stringify({version:old.version,sourceBaseline:old.sourceBaseline,...next},null,2)+'\n');
console.log(JSON.stringify({cases:next.totalCases,inventory:next.inventorySha256,Run:after.run_preimages.run.run_definition_cid}));`;
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps:([
 {name:'Existing source compilation manifest generator',command:'node',args:['scripts/compilation-manifests.mjs','--write']},
 {name:'Independent current Values and Run preimage refresh',command:'node',args:['scripts/sequence-identity-oracle.mjs','--write']},
 {name:'Independent registration and current Run literals',command:'node',args:['--input-type=module','-e',refresh]},
 {name:'Existing document metadata generator',command:'node',args:['scripts/update-document-metadata.mjs','--write']},
 {name:'Existing family registration generator',command:'node',args:['scripts/check-actql-spec-family.mjs','--write']},
 {name:'Existing canonical fixture generator',command:'node',args:['scripts/check-canonical-json.mjs','--write']},
 ...['src/query_syntax/sga_call.mbt','src/query_syntax/sga_argument_roles.mbt','src/query_syntax/window_group_expression_test.mbt','src/query_program/query_script_carriers.mbt','src/query_program/window_group_program.mbt','src/query_program/window_group_source_test.mbt','src/run_publication_host/client_values_run_materials_wbtest.mbt'].map(path=>({name:'Pinned formatter '+path,command:'moonfmt',args:['-w',path]})),
]).slice(process.argv.includes('--remaining')?2:0)});
