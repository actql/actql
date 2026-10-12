import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files=['src/query_program/event_dedupe_source_test.mbt'];
const product=['src/query_syntax/sga_call.mbt','src/query_syntax/sga_argument_roles.mbt','src/query_program/query_script_carriers.mbt','src/query_program/query_script_inputs.mbt','src/query_program/traversal_nodes_program.mbt'];
const steps=process.argv.includes('--info')
  ? [{name:'Generate affected syntax interface',command:'moon',args:['info','--target','js','src/query_syntax']}]
  : process.argv.includes('--format')
  ? [{name:'Format authored dedupe controls',command:'moon',args:['fmt',...product,...files]}]
  : [{name:'Independent event dedupe controls and source counterexamples',command:'node',args:[
    '--input-type=module','-e',runner,'moon','--target','js',...files]}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
