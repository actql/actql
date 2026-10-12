import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const files = ['src/query_program/graph_property_predicate_test.mbt', 'src/query_program/graph_hop_node_predicate_test.mbt', 'src/query_program/graph_edge_predicate_test.mbt'];
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
 timeoutSeconds:60,graceSeconds:5,steps:process.argv.includes('--format') ? [{
 name:'Format changed WITH Graph predicate callers',command:'moon',args:['fmt',...files],
 }] : [{name:'WITH Graph property node hop and edge predicates common refusals and independent Programs',command:'node',
 args:['--input-type=module','-e',runner,'moon','--target','js',...files]}]});
