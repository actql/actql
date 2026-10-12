import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files=['src/query_program/graph_row_carrier_refusal_test.mbt','src/query_program/graph_union_source_test.mbt','src/query_program/graph_subtraction_source_test.mbt','src/query_program/graph_delta_source_test.mbt','src/query_program/graph_profile_test.mbt','src/query_program/subgraph_source_test.mbt','src/source_frontend/lower_test.mbt','src/query_program/graph_refusal_classification_test.mbt','src/query_program/graph_carrier_continuation_test.mbt','src/query_program/carrier_peer_scope_test.mbt'];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps:[
  {name:'Graph row refusal and existing Carrier callers',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files]},
  {name:'Original missing-Graph compile caller',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js','src/query_program/compile_test.mbt','--filter','query-only context refuses Graph lowering without a current definition']},
  {name:'Whitespace',command:'git',args:['diff','--check']},
]});
