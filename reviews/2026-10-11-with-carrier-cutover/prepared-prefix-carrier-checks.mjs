import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests("moon",process.argv.slice(1),{cwd:process.cwd()});';
const selected = process.argv.includes('--vectors-events-only')
  ? ['src/query_program/with_vectors_events_test.mbt']
  : ['src/query_program/with_vectors_events_test.mbt',
    'src/query_program/with_binding_preparation_test.mbt',
    'src/query_program/with_binding_static_order_gap_test.mbt',
    'src/query_program/source_member_test.mbt',
    'src/query_program/graph_projection_property_test.mbt',
    'src/query_program/graph_member_test.mbt',
    'src/query_program/quoted_graph_macro_test.mbt',
    'src/query_program/grouped_graph_macro_test.mbt'];
const steps = process.argv.includes('--info') ? [{
  name:'Generate actual WITH Carrier syntax and lowering interfaces',
  command:'moon',args:['info','--target','js','src/query_syntax','src/query_program'],
}] : process.argv.includes('--coherence') ? [{
  name:'Independent WITH grammar/profile and complete historical Run preimages',
  command:'node',args:['--input-type=module','-e',
    'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests("node",process.argv.slice(1),{cwd:process.cwd()});',
    '--','scripts/frontend-profile.test.mjs','scripts/sga-query-call-contract.test.mjs',
    'scripts/client-values-run-materials-vector.test.mjs'],
}, ...['compilation-manifests','update-document-metadata','check-actql-spec-family',
  'check-canonical-json'].map(name => ({name:`Read-only ${name}`,
    command:'node',args:[`scripts/${name}.mjs`]}))] : process.argv.includes('--format') ? [{
  name:'Format only WITH Carrier frontend and independent controls',
  command:'moon',args:['fmt',
    'src/query_syntax/sga_call.mbt',
    'src/query_program/query_binding_check.mbt',
    'src/query_program/member_program_prefix.mbt',
    'src/query_program/member_resolution.mbt',
    'src/query_program/query_script_carriers.mbt',
    'src/query_program/query_script_inputs.mbt',
    'src/query_program/query_script_program.mbt',
    'src/query_program/query_binding_program.mbt',
    'src/query_program/traversal_nodes_program.mbt',
    'src/query_program/with_vectors_events_test.mbt',
    'src/query_program/graph_projection_property_test.mbt',
    'src/query_program/source_member_test.mbt',
    'src/run_publication_host/client_values_run_materials_wbtest.mbt'],
}] : [{
    name:'WITH actual prefixes and strict common Source/type/order callers',
    command:'node',args:['--input-type=module','-e',runner,'--','--target','js',...selected],
  }];
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
  timeoutSeconds:60,graceSeconds:5,steps});
