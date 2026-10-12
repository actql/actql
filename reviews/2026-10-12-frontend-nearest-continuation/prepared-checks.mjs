import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files=['src/query_program/nearest_pipe_continuation_test.mbt'];
if(process.argv.includes('--callers')) files.push(
  'src/query_program/nearest_carrier_roles_test.mbt',
  'src/query_program/nearest_test.mbt',
  'src/query_program/carrier_peer_scope_test.mbt',
  'src/query_program/graph_rows_set_continuation_test.mbt',
  'src/query_program/nearest_composite_roles_wbtest.mbt',
);
let steps;
if(process.argv.includes('--format')) {
  steps=['compile','nearest_program','nearest_script_inputs','query_script_program','query_script_carriers',
    'query_script_set','nearest_pipe_continuation_test','nearest_composite_roles_wbtest']
    .map(name=>({name:`Format ${name}`,command:'moonfmt',args:['-w',`src/query_program/${name}.mbt`]}));
} else {
  steps=[{name:'NEAREST ordinary Relation continuation and unique set owner',command:'node',
    args:['--input-type=module','-e',runner,'moon','--target','js',...files]}];
  if(process.argv.includes('--final')) {
    steps[0].args.push('src/query_program/nearest_carrier_roles_test.mbt',
      'src/query_program/nearest_test.mbt','src/query_program/carrier_peer_scope_test.mbt',
      'src/query_program/graph_rows_set_continuation_test.mbt','src/query_program/nearest_composite_roles_wbtest.mbt',
      'src/run_publication_host/client_values_run_materials_wbtest.mbt');
    steps.push({name:'Independent current and parent identity/caller tests',command:'node',args:['--input-type=module','-e',runner,'node',
      'scripts/nearest-continuation-identity.test.mjs','scripts/nearest-carrier-identity.test.mjs',
      'scripts/lag-identity.test.mjs','scripts/compilation-manifests.test.mjs',
      'scripts/sga-query-call-contract.test.mjs','scripts/client-values-run-materials-vector.test.mjs',
      'scripts/nearest-carrier-public-input.test.mjs']});
    steps.push(...['compilation-manifests','update-document-metadata','check-actql-spec-family','check-canonical-json']
      .map(script=>({name:`Read-only ${script}`,command:'node',args:[`scripts/${script}.mjs`]})));
    steps.push(...['js','wasm','native'].map(target=>({name:`Affected query API compile ${target}`,command:'moon',
      args:['check','--target',target,'src/query_program','src/source_frontend']})));
    steps.push({name:'Whitespace',command:'git',args:['diff','--check']});
  }
}
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
