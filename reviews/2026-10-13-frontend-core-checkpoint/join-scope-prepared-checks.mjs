import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files=['src/query_program/single_join_group_test.mbt','src/query_program/right_join_test.mbt','src/source_frontend/join_set_compaction_test.mbt','src/source_frontend/cte_value_table_scope_test.mbt'];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps:[
 {name:'Original JOIN and public scope controls',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files]},
 {name:'Independent original operator preservation',command:'node',args:['--input-type=module','-e',runner,'node','reviews/2026-10-13-frontend-core-checkpoint/join-group-oracle.test.mjs']},
]});
