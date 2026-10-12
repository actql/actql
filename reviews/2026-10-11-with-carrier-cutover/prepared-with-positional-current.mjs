import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const files = ['src/query_program/positional_window_duplicates_test.mbt','src/query_program/positional_aggregate_duplicates_test.mbt','src/query_program/positional_duplicate_columns_test.mbt','src/query_program/parenthesized_positional_output_test.mbt','src/query_program/positional_anonymous_window_test.mbt','src/query_program/positional_join_set_test.mbt'];
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,
 steps:process.argv.includes('--format') ? [{name:'Format changed WITH positional callers',command:'moon',args:['fmt',...files]}]
 : [{name:'WITH positional set aggregate window ordinals and immutable range callers',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files]}]});
