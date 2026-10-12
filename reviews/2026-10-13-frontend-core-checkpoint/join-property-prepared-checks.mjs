import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files=['unnest_scalar_receiver_precedence','join_range_property','join_property_paths','join_order','join_implicit_property'].map(name=>'src/query_program/'+name+'_test.mbt');
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps:[
 {name:'Original JOIN receiver property and ORDER controls',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files]},
 {name:'Independent nullable property and source preservation',command:'node',args:['--input-type=module','-e',runner,'node','reviews/2026-10-13-frontend-core-checkpoint/join-property-oracle.test.mjs']},
]});
