import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const focused = (name, target, args) => ({name, command:'node', args:['--input-type=module','-e',runner,target,...args]});
const steps = [
  focused('Adopted OutputName counterexamples and existing finite P2 common controls', 'moon', ['--target','js',
    'src/query_syntax/sga_output_name_test.mbt', 'src/query_syntax/graph_match_binding_vocabulary_test.mbt',
    'src/query_program/sga_output_name_lowering_test.mbt', 'src/query_syntax/sga_role_contract_test.mbt',
    'src/query_syntax/producer_scope_wbtest.mbt', 'src/query_program/sga_role_lowering_test.mbt',
    'src/run_publication_host/client_values_run_materials_wbtest.mbt']),
  focused('Changed grammar canonical consumer only', 'moon', ['--target','js',
    'src/canonical_json/identity_vectors.generated_test.mbt','--filter','contract spec/manifests/actql-grammar-0.1.json#']),
  focused('Existing finite independent normative controls and prepared public fixture preservation', 'node', [
    'scripts/sga-signature-role-identity.test.mjs','scripts/sga-query-call-contract.test.mjs',
    'scripts/compilation-manifests.test.mjs','scripts/client-values-run-materials-vector.test.mjs',
    'scripts/frontend-profile.test.mjs','scripts/sga-output-name-source.test.mjs',
    'scripts/sga-public-role-preservation.test.mjs','scripts/graph-match-binding-vocabulary.test.mjs']),
  ...['compilation-manifests','update-document-metadata','check-actql-spec-family','check-canonical-json']
    .map(name => ({name:'Read-only '+name,command:'node',args:['scripts/'+name+'.mjs']})),
];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
