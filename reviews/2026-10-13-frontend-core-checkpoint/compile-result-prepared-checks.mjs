import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files=['pipe_result','order_ordinal','order_input_classification','join_star','join_select_window','join_parenthesized_key'].map(name=>'src/query_program/'+name+'_test.mbt');
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps:[
 {name:'Existing compile JOIN CTE Result boundary',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js','src/query_program/compile_test.mbt','--index','24-43']},
 {name:'Existing ordinal DISTINCT star window key and Result controls',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files]},
 {name:'Independent source and full oracle preservation',command:'node',args:['--input-type=module','-e',runner,'node','reviews/2026-10-13-frontend-core-checkpoint/compile-result-oracle.test.mjs']},
]});
