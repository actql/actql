import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files=['join_current_row_prefix','join_pipe_edits','join_pipe_limit_tail','join_pipe_distinct','pipe_set_target_scope','pipe_rename_target_scope'].map(name=>'src/query_program/'+name+'_test.mbt');
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps:[
 {name:'Original JOIN continuation and refusal controls',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files]},
 {name:'Independent complete control preservation',command:'node',args:['--input-type=module','-e',runner,'node','reviews/2026-10-13-frontend-core-checkpoint/join-continuation-oracle.test.mjs']},
]});
