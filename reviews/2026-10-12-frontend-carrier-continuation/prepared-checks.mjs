import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files = [
  'src/query_program/explicit_graph_expectation_test.mbt',
  'src/query_program/with_graph_binding_test.mbt',
  'src/query_program/with_graph_range_alias_test.mbt',
  'src/query_program/with_vectors_events_test.mbt',
  'src/source_frontend/graph_expectation_origin_test.mbt',
];
if (process.argv.includes('--diagnostics')) {
  files.splice(0, files.length,
    'src/connectors_builtin_node/graph_expectation_public_check_wbtest.mbt',
    'src/connectors_builtin_node/client_source_preparation_wbtest.mbt');
}
const steps = [{name:'Explicit Graph type expectation and original authored origin',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files]}];
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
