import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const mode=process.argv[2]??'--final';
let steps;
if(mode==='--pins') {
  steps=['compilation-manifests','update-document-metadata','check-actql-spec-family','check-canonical-json']
    .map(script=>({name:`Generate ${script}`,command:'node',args:[`scripts/${script}.mjs`,'--write']}));
} else if(mode==='--interfaces') {
  steps=[{name:'Generate affected Query interfaces',command:'moon',args:['info','--target','js','src/query_syntax','src/query_program']}];
} else if(mode==='--format') {
  steps=['src/query_syntax/query.mbt','src/query_syntax/sga_call.mbt','src/query_syntax/producer_primary.mbt',
    'src/query_program/query_script_program.mbt','src/query_program/query_binding_program.mbt',
    'src/query_program/query_script_inputs.mbt','src/query_program/relation_generator_program.mbt',
    'src/query_program/time_series_primary_test.mbt','src/query_syntax/time_series_primary_test.mbt','src/run_publication_host/client_values_run_materials_wbtest.mbt']
    .map(file=>({name:`Format ${file}`,command:'moonfmt',args:['-w',file]}));
} else {
  if(mode!=='--final') throw new Error(`Unknown mode: ${mode}`);
  steps=[{name:'Time-series and affected Graph/Run consumers',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',
    'src/query_program/time_series_primary_test.mbt','src/query_syntax/time_series_primary_test.mbt','src/query_program/graph_mean_source_test.mbt',
    'src/query_program/explicit_graph_expectation_test.mbt','src/query_program/inline_graph_current_test.mbt',
    'src/run_publication_host/client_values_run_materials_wbtest.mbt']},
    {name:'Independent preimages and actual public recipe/import inventory',command:'node',args:['--input-type=module','-e',runner,'node',
      'scripts/time-series-primary-identity.test.mjs','scripts/nearest-join-identity.test.mjs',
      'scripts/nearest-continuation-identity.test.mjs','scripts/nearest-carrier-identity.test.mjs',
      'scripts/compilation-manifests.test.mjs','scripts/sga-query-call-contract.test.mjs',
      'scripts/client-values-run-materials-vector.test.mjs','scripts/time-series-primary-source-input.test.mjs',
      'scripts/sga-output-name-source.test.mjs','scripts/public-query-profiles.test.mjs']},
    ...['compilation-manifests','update-document-metadata','check-actql-spec-family','check-canonical-json']
      .map(script=>({name:`Read-only ${script}`,command:'node',args:[`scripts/${script}.mjs`]})),
    ...['js','wasm','native'].map(target=>({name:`Affected Query API compile ${target}`,command:'moon',
      args:['check','--target',target,'src/query_program','src/source_frontend']})),
    {name:'Whitespace',command:'git',args:['diff','--check']},
  ];
}
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
