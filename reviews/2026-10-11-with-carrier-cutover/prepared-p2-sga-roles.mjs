import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const steps = process.argv.includes('--info') ? [{name:'Generate actual changed SGA syntax interfaces',command:'moon',args:['info','--target','js','src/query_syntax','src/query_program']}]
 : process.argv.includes('--format') ? [{name:'Format only SGA role adapter and independent counterexamples',command:'moon',args:['fmt','src/query_syntax/sga_call.mbt','src/query_syntax/sga_argument_roles.mbt','src/query_syntax/sga_role_contract_test.mbt','src/query_program/traversal_nodes_program.mbt','src/query_program/graph_match_rows_program.mbt']}]
 : [{name:'Independent SGA role boundary counterexamples',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js','src/query_syntax/sga_role_contract_test.mbt']}];
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
