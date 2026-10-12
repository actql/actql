import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const mode=process.argv[2]??'--focused';
const files=['src/query_syntax/sga_call.mbt','src/query_syntax/sga_argument_roles.mbt','src/query_syntax/query.mbt','src/query_program/query_script_carriers.mbt','src/query_program/temporal_join_program.mbt','src/query_program/temporal_join_source_test.mbt','src/run_publication_host/client_values_run_materials_wbtest.mbt'];
let steps;
if(mode==='--pins') {
  steps=['compilation-manifests','update-document-metadata','check-actql-spec-family','check-canonical-json']
    .map(script=>({name:`Generate ${script}`,command:'node',args:[`scripts/${script}.mjs`,'--write']}));
} else if(mode==='--format') {
  steps=files.map(file=>({name:`Format ${file}`,command:'moonfmt',args:['-w',file]}));
} else {
  if(!['--focused','--final'].includes(mode)) throw new Error(`Unknown mode ${mode}`);
  steps=[{name:'Temporal roles, common controls and original Carrier consumers',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',
    'src/query_program/temporal_join_source_test.mbt',...(mode==='--final'?[
      'src/query_program/lag_source_test.mbt','src/query_program/carrier_peer_scope_test.mbt',
      'src/query_program/graph_carrier_continuation_test.mbt','src/run_publication_host/client_values_run_materials_wbtest.mbt']:[])]}];
  if(mode==='--final') {
    steps.push({name:'Independent grammar/Run preimages and public registration',command:'node',args:['--input-type=module','-e',runner,'node',
      'scripts/temporal-join-identity.test.mjs','scripts/temporal-join-source-input.test.mjs',
      'scripts/nearest-join-identity.test.mjs','scripts/nearest-continuation-identity.test.mjs',
      'scripts/compilation-manifests.test.mjs','scripts/sga-query-call-contract.test.mjs',
      'scripts/client-values-run-materials-vector.test.mjs','scripts/public-query-profiles.test.mjs']});
    steps.push(...['compilation-manifests','update-document-metadata','check-actql-spec-family','check-canonical-json']
      .map(script=>({name:`Read-only ${script}`,command:'node',args:[`scripts/${script}.mjs`]})));
    steps.push(...['js','wasm','native'].map(target=>({name:`Affected Query API compile ${target}`,command:'moon',args:['check','--target',target,'src/query_program','src/source_frontend']})));
    steps.push({name:'Whitespace',command:'git',args:['diff','--check']});
  }
}
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
