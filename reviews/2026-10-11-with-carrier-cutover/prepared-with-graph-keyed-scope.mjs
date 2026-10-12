import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const files = ['src/query_program/graph_program_wbtest.mbt', 'src/query_program/keyed_graph_program_wbtest.mbt', 'src/query_program/graph_definition_scope_wbtest.mbt'];
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
 timeoutSeconds:60,graceSeconds:5,steps:process.argv.includes('--format') ? [{
 name:'Format changed WITH keyed Graph scope callers',command:'moon',args:['fmt',...files],
 }] : [{name:'WITH keyed Graph scope property alignment parallel definitions and independent Programs',command:'node',
 args:['--input-type=module','-e',runner,'moon','--target','js',...files]}]});
