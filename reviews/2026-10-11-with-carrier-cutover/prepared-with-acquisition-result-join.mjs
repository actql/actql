import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const files = ['src/query_program/with_result_owners_test.mbt','src/query_program/with_acquisition_test.mbt','src/query_program/with_join_test.mbt'];
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
  timeoutSeconds:60,graceSeconds:5,steps:process.argv.includes('--format') ? [{
    name:'Format changed WITH acquisition Result and JOIN callers',command:'moon',args:['fmt',...files,'src/query_program/join_chain_test.mbt','src/query_program/pipe_join_ranges_test.mbt','src/query_program/pipe_join_input_test.mbt'],
  }] : [{name:'WITH capture Result and JOIN independent complete Programs and static refusals',command:'node',
    args:['--input-type=module','-e',runner,'moon','--target','js',...files]}]});
