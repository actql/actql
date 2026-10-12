import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const steps = process.argv.includes('--format')
  ? [{name:'Format only vector pooling source adapter and controls',command:'moon',args:['fmt',
    'src/query_syntax/sga_call.mbt','src/query_syntax/sga_argument_roles.mbt',
    'src/query_program/query_script_carriers.mbt','src/query_syntax/vector_pool_role_test.mbt',
    'src/query_program/vector_pool_source_test.mbt']}]
  : [{name:'Vector pool authored role counterexamples and independent common controls',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',
    'src/query_syntax/vector_pool_role_test.mbt','src/query_program/vector_pool_source_test.mbt',
    'src/query_program/with_vectors_events_test.mbt']}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
