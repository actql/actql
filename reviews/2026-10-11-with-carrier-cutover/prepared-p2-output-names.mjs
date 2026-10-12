import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const steps = process.argv.includes('--format')
  ? [{name:'Format only the declared OutputName boundary and counterexamples',command:'moon',args:['fmt','src/query_syntax/query.mbt','src/query_syntax/query_identifier_roles.mbt','src/query_syntax/sga_call.mbt','src/query_syntax/sga_output_name_test.mbt','src/query_program/sga_output_name_lowering_test.mbt']}]
  : [{name:'SGA output name admission and unchanged common MATCH controls',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js','src/query_syntax/sga_output_name_test.mbt','src/query_syntax/graph_match_binding_vocabulary_test.mbt','src/query_program/sga_output_name_lowering_test.mbt']}];
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
