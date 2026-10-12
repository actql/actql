import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const mode = process.argv[2] ?? '--tests';
const files = [
  'src/query_program/nearest_carrier_roles_test.mbt',
  'src/query_program/nearest_composite_roles_wbtest.mbt',
  'src/query_syntax/nearest_optional_roles_test.mbt',
  'src/query_program/nearest_test.mbt',
];
let steps;
if (mode === '--tests') {
  steps = [{name:'NEAREST typed operand roles and existing Relation control',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files]}];
} else if (mode === '--interfaces') {
  steps = [{name:'Generate affected query interfaces',command:'moon',args:['info','--target','js','src/query_syntax','src/query_program']}];
} else if (mode === '--format') {
  const changed = [...files,
    'src/query_program/nearest_program.mbt',
    'src/query_program/nearest_carrier_program.mbt',
    'src/query_program/query_script_program.mbt',
    'src/query_program/query_script_carriers.mbt',
    'src/query_syntax/query.mbt',
    'src/query_syntax/producer_primary.mbt',
    'src/query_syntax/nearest_test.mbt',
    'src/run_publication_host/client_values_run_materials_wbtest.mbt'];
  steps = changed.map(file => ({name:`Format ${file}`,command:'moonfmt',args:['-w',file]}));
} else if (mode === '--pins') {
  steps = ['compilation-manifests','update-document-metadata','check-actql-spec-family','check-canonical-json']
    .map(script => ({name:`Generate ${script}`,command:'node',args:[`scripts/${script}.mjs`,'--write']}));
} else if (mode === '--freshness') {
  steps = ['compilation-manifests','update-document-metadata','check-actql-spec-family','check-canonical-json']
    .map(script => ({name:`Read-only ${script}`,command:'node',args:[`scripts/${script}.mjs`]}));
} else if (mode === '--identity-tests') {
  steps = [{name:'Independent identity history and affected manifest consumers',command:'node',args:['--input-type=module','-e',runner,'node',
    'scripts/nearest-carrier-identity.test.mjs','scripts/lag-identity.test.mjs',
    'scripts/compilation-manifests.test.mjs','scripts/sga-query-call-contract.test.mjs',
    'scripts/client-values-run-materials-vector.test.mjs',
    'scripts/nearest-carrier-public-input.test.mjs']}];
} else if (mode === '--callers') {
  steps = [{name:'Affected WITH carrier and Run identity callers',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',
    'src/query_program/carrier_peer_scope_test.mbt',
    'src/query_program/with_vectors_events_test.mbt',
    'src/run_publication_host/client_values_run_materials_wbtest.mbt']}];
} else if (mode === '--caller-compile') {
  steps = ['js','wasm','native'].map(target => ({name:`Affected Query API consumption on ${target}`,command:'moon',
    args:['check','--target',target,'src/query_syntax','src/query_program','src/source_frontend']}));
} else if (mode === '--final') {
  steps = [
    {name:'F04 and affected WITH/Run identity callers',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files,
      'src/query_program/carrier_peer_scope_test.mbt','src/query_program/with_vectors_events_test.mbt',
      'src/run_publication_host/client_values_run_materials_wbtest.mbt']},
    {name:'Independent identities and prepared public fixture contracts',command:'node',args:['--input-type=module','-e',runner,'node',
      'scripts/nearest-carrier-identity.test.mjs','scripts/lag-identity.test.mjs',
      'scripts/compilation-manifests.test.mjs','scripts/sga-query-call-contract.test.mjs',
      'scripts/client-values-run-materials-vector.test.mjs','scripts/nearest-carrier-public-input.test.mjs']},
    ...['compilation-manifests','update-document-metadata','check-actql-spec-family','check-canonical-json']
      .map(script => ({name:`Read-only ${script}`,command:'node',args:[`scripts/${script}.mjs`]})),
    ...['js','wasm','native'].map(target => ({name:`Affected Query API consumption on ${target}`,command:'moon',
      args:['check','--target',target,'src/query_syntax','src/query_program','src/source_frontend']})),
    {name:'Whitespace',command:'git',args:['diff','--check']},
  ];
} else {
  throw new Error(`Unknown selection: ${mode}`);
}
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
