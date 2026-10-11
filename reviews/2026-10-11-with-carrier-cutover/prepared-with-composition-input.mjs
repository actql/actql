import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const files = ['src/query_program/composition_controls_test.mbt','src/query_program/infer_input_field_test.mbt'];
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
 timeoutSeconds:60,graceSeconds:5,steps:process.argv.includes('--format') ? [{
 name:'Format changed WITH composition and input callers',command:'moon',args:['fmt',...files],
 }] : [{name:'WITH original Source predicate JOIN ceiling INFER input contract and unchanged Effect controls',command:'node',
 args:['--input-type=module','-e',runner,'moon','--target','js',...files]}]});
