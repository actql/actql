import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs";process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files = ['src/query_program/graph_carrier_continuation_test.mbt','src/query_program/graph_rows_test.mbt','src/query_program/graph_rows_program_wbtest.mbt','src/query_program/with_graph_binding_test.mbt','src/query_syntax/sga_call_test.mbt'];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps:[{name:'F02 exact consumed prefix and existing Graph row caller regressions',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files]}]});
