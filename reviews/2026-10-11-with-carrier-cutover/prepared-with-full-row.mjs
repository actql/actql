import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const files = ['src/query_program/full_select_scope_test.mbt', 'src/query_program/full_join_scope_test.mbt', 'src/query_program/joined_row_range_test.mbt'];
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
 timeoutSeconds:60,graceSeconds:5,steps:process.argv.includes('--format') ? [{
 name:'Format changed WITH FULL JOIN and row scope callers',command:'moon',args:['fmt',...files],
 }] : [{name:'WITH FULL JOIN independent Programs key premises and row scopes',command:'node',
 args:['--input-type=module','-e',runner,'moon','--target','js',...files]}]});
