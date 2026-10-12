import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const focused = (name, target, args) => ({name, command:'node', args:['--input-type=module','-e',runner,target,...args]});
const generators = ['compilation-manifests','vector-pool-identity-oracle',
  'update-document-metadata','check-actql-spec-family','check-canonical-json'];
const steps = process.argv.includes('--normative-write')
  ? generators.map(name => ({name:'Existing generator or independent oracle '+name,
    command:'node',args:['scripts/'+name+'.mjs','--write']}))
  : process.argv.includes('--format')
  ? [{name:'Format only vector pooling source adapter and controls',command:'moon',args:['fmt',
    'src/query_syntax/sga_call.mbt','src/query_syntax/sga_argument_roles.mbt',
    'src/query_program/query_script_carriers.mbt','src/query_syntax/vector_pool_role_test.mbt',
    'src/query_program/vector_pool_source_test.mbt']}]
  : [focused('Vector pool authored role counterexamples and independent common controls', 'moon', ['--target','js',
    'src/query_syntax/vector_pool_role_test.mbt','src/query_program/vector_pool_source_test.mbt',
    'src/query_program/with_vectors_events_test.mbt','src/run_publication_host/client_values_run_materials_wbtest.mbt']),
  focused('Changed grammar canonical consumer only', 'moon', ['--target','js',
    'src/canonical_json/identity_vectors.generated_test.mbt','--filter','contract spec/manifests/actql-grammar-0.1.json#']),
  focused('Independent current pool and retained SGA preimages', 'node', [
    'scripts/vector-pool-identity.test.mjs','scripts/sga-signature-role-identity.test.mjs',
    'scripts/client-values-run-materials-vector.test.mjs','scripts/compilation-manifests.test.mjs',
    'scripts/frontend-profile.test.mjs']),
  ...generators.filter(name => name !== 'vector-pool-identity-oracle')
    .map(name => ({name:'Read-only '+name,command:'node',args:['scripts/'+name+'.mjs']}))];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
