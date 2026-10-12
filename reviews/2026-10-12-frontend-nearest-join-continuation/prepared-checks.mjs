import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files=['src/query_program/nearest_join_continuation_test.mbt'];
let steps;
if(process.argv.includes('--format')) {
  steps=['src/query_program/query_join_bindings.mbt','src/query_program/query_join_chain.mbt',
    ...files,'src/run_publication_host/client_values_run_materials_wbtest.mbt']
    .map(file=>({name:`Format ${file}`,command:'moonfmt',args:['-w',file]}));
} else if(process.argv.includes('--pins')) {
  steps=['compilation-manifests','update-document-metadata','check-actql-spec-family','check-canonical-json']
    .map(script=>({name:`Generate ${script}`,command:'node',args:[`scripts/${script}.mjs`,'--write']}));
} else {
  if(process.argv.includes('--final')) files.push('src/query_program/nearest_pipe_continuation_test.mbt',
    'src/query_program/pipe_join_input_test.mbt','src/query_program/join_chain_test.mbt',
    'src/query_program/nearest_carrier_roles_test.mbt','src/query_program/nearest_test.mbt',
    'src/query_program/graph_rows_set_continuation_test.mbt',
    'src/run_publication_host/client_values_run_materials_wbtest.mbt');
  steps=[{name:'JOIN NEAREST roles and existing Pipe/Graph/Run consumers',command:'node',
    args:['--input-type=module','-e',runner,'moon','--target','js',...files]}];
  if(process.argv.includes('--final')) {
    steps.push({name:'Independent current and retained identities',command:'node',args:['--input-type=module','-e',runner,'node',
      'scripts/nearest-join-identity.test.mjs','scripts/nearest-continuation-identity.test.mjs',
      'scripts/nearest-carrier-identity.test.mjs','scripts/lag-identity.test.mjs',
      'scripts/compilation-manifests.test.mjs','scripts/sga-query-call-contract.test.mjs',
      'scripts/client-values-run-materials-vector.test.mjs','scripts/nearest-carrier-public-input.test.mjs']});
    steps.push(...['compilation-manifests','update-document-metadata','check-actql-spec-family','check-canonical-json']
      .map(script=>({name:`Read-only ${script}`,command:'node',args:[`scripts/${script}.mjs`]})));
    steps.push(...['js','wasm','native'].map(target=>({name:`Affected query API compile ${target}`,command:'moon',
      args:['check','--target',target,'src/query_program','src/source_frontend']})));
    steps.push({name:'Whitespace',command:'git',args:['diff','--check']});
  }
}
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
