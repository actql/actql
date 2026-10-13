import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const mode=process.argv[2]??'--focused';
const files=['src/query_syntax/sga_call.mbt','src/query_syntax/sga_argument_roles.mbt','src/query_syntax/sga_predicate.mbt','src/query_syntax/sequence_predicate_test.mbt','src/query_program/query_script_carriers.mbt','src/query_program/traversal_nodes_program.mbt','src/query_program/sequence_program.mbt','src/query_program/sequence_source_test.mbt','src/run_publication_host/client_values_run_materials_wbtest.mbt'];
let steps;
if(mode==='--pins') {
 steps=['compilation-manifests','update-document-metadata','check-actql-spec-family','check-canonical-json'].map(script=>({name:`Generate ${script}`,command:'node',args:[`scripts/${script}.mjs`,'--write']}));
} else if(mode==='--oracles') {
 steps=[{name:'Independent current Sequence grammar and Values preimages',command:'node',args:['scripts/sequence-identity-oracle.mjs','--write']},
 {name:'Independent declared public inventory including preserved sibling cohorts',command:'node',args:['--input-type=module','-e',`import {registeredPublicQueryInventory} from './scripts/public-query-inventory.mjs';import {readFileSync,writeFileSync} from 'node:fs';const path='scripts/fixtures/public-query-inventory.json';const prior=JSON.parse(readFileSync(path,'utf8'));const current=await registeredPublicQueryInventory();writeFileSync(path,JSON.stringify({...prior,...current},null,2)+'\\n');console.log(JSON.stringify({total:current.totalCases,counts:current.counts,profiles:current.profiles}));`]}];
} else if(mode==='--interfaces') {
 steps=[{name:'Generate changed source-role interface',command:'moon',args:['info','--target','js','src/query_syntax','src/query_program']}];
} else if(mode==='--format') {
 steps=files.map(file=>({name:`Format ${file}`,command:'moonfmt',args:['-w',file]}));
} else {
 if(!['--focused','--final','--static'].includes(mode)) throw new Error(`Unknown mode ${mode}`);
 steps=[{name:'Sequence original expressions and common Carrier controls',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',
   'src/query_program/sequence_source_test.mbt','src/query_syntax/sequence_predicate_test.mbt',...(mode!=='--focused'?['src/query_syntax/sga_role_contract_test.mbt','src/query_program/lag_source_test.mbt','src/query_program/graph_carrier_continuation_test.mbt','src/query_program/traversal_nodes_test.mbt','src/query_program/traversal_paths_test.mbt','src/run_publication_host/client_values_run_materials_wbtest.mbt']:[])]}];
 if(mode!=='--focused') {
  steps.push({name:'Independent grammar/Run preimages and public Source matrix',command:'node',args:['--input-type=module','-e',runner,'node',
    'scripts/sequence-identity.test.mjs','scripts/sequence-source-input.test.mjs',
    'scripts/nearest-join-identity.test.mjs','scripts/nearest-continuation-identity.test.mjs',
    'scripts/compilation-manifests.test.mjs','scripts/sga-query-call-contract.test.mjs','scripts/client-values-run-materials-vector.test.mjs','scripts/public-query-profiles.test.mjs']});
  steps.push(...['compilation-manifests','update-document-metadata','check-actql-spec-family','check-canonical-json'].map(script=>({name:`Read-only ${script}`,command:'node',args:[`scripts/${script}.mjs`]})));
  if(mode==='--final') steps.push(...['js','wasm','native'].map(target=>({name:`Affected Query API compile ${target}`,command:'moon',args:['check','--target',target,'src/query_program','src/source_frontend']})));
  steps.push({name:'Whitespace',command:'git',args:['diff','--check']});
 }
}
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
