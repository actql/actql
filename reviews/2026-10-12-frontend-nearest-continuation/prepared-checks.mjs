import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files=['src/query_program/nearest_pipe_continuation_test.mbt'];
if(process.argv.includes('--callers')) files.push(
  'src/query_program/nearest_carrier_roles_test.mbt',
  'src/query_program/nearest_test.mbt',
  'src/query_program/carrier_peer_scope_test.mbt',
  'src/query_program/graph_rows_set_continuation_test.mbt',
);
const steps=[{name:'NEAREST ordinary Relation continuation and unique set owner',command:'node',
  args:['--input-type=module','-e',runner,'moon','--target','js',...files]}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
