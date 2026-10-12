import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const files = ['src/query_program/graph_delta_source_test.mbt','src/query_program/graph_delta_json_source_test.mbt','src/query_program/bounded_graph_modes_test.mbt'];
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
 timeoutSeconds:60,graceSeconds:5,steps:process.argv.includes('--format') ? [{
 name:'Format changed WITH Delta and path mode callers',command:'moon',args:['fmt',...files],
 }] : [{name:'WITH Delta typed JSON independent Programs bounded path modes and common refusals',command:'node',
 args:['--input-type=module','-e',runner,'moon','--target','js',...files]}]});
