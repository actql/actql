import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const files = ['src/query_program/graph_rows_join_input_test.mbt','src/query_program/subgraph_source_test.mbt','src/query_program/subgraph_public_source_test.mbt'];
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
 timeoutSeconds:60,graceSeconds:5,steps:process.argv.includes('--format') ? [{
 name:'Format changed WITH Graph selector and JOIN callers',command:'moon',args:['fmt',...files],
 }] : [{name:'WITH Graph rows JOIN selectors Subgraph independent Programs and scoped refusals',command:'node',
 args:['--input-type=module','-e',runner,'moon','--target','js',...files]}]});
