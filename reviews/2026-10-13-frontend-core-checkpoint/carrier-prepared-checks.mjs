import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files=['carrier_work','dag_result_work','carrier_analytic_shape','acquired_relation_branch','graph_plan'].map(name=>'src/query_integration/'+name+'_wbtest.mbt');
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps:[
  {name:'Original Carrier checkpoint controls',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files]},
  {name:'Independent normative contract preimage',command:'node',args:['--input-type=module','-e',runner,'node','reviews/2026-10-13-frontend-core-checkpoint/carrier-contract-preimage.test.mjs']},
]});
