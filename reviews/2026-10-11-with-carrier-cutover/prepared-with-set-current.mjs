import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const files = ['src/query_program/set_member_scope_test.mbt','src/query_program/set_member_public_source_test.mbt','src/query_program/set_corresponding_test.mbt','src/query_program/set_inner_by_name_test.mbt','src/query_program/set_by_name_list_test.mbt','src/query_program/set_projection_compaction_test.mbt','src/query_program/set_window_private_scope_test.mbt'];
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,
 steps:process.argv.includes('--format') ? [{name:'Format changed WITH set callers',command:'moon',args:['fmt',...files]}]
 : [{name:'WITH set alignment member scope independent Programs and static Append refusals',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files]},
 {name:'WITH set public fixture independent controls and registration',command:'node',args:['--input-type=module','-e',runner,'node','scripts/set-by-name-list-source-input.test.mjs','scripts/set-inner-by-name-source-input.test.mjs','scripts/set-corresponding-source-input.test.mjs']} ]});
