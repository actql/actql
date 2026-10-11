import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests("moon",process.argv.slice(1),{cwd:process.cwd()});';
const selected = process.argv.includes('--vectors-events-only')
  ? ['src/query_program/with_vectors_events_test.mbt']
  : ['src/query_program/with_vectors_events_test.mbt',
    'src/query_program/with_binding_preparation_test.mbt',
    'src/query_program/with_binding_static_order_gap_test.mbt',
    'src/query_program/source_member_test.mbt'];
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
  timeoutSeconds:60,graceSeconds:5,steps:[{
    name:'WITH actual prefixes and strict common Source/type/order callers',
    command:'node',args:['--input-type=module','-e',runner,'--','--target','js',...selected],
  }]});
