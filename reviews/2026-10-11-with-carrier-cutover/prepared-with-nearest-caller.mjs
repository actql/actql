import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
  timeoutSeconds:60,graceSeconds:5,steps:process.argv.includes('--format') ? [{
    name:'Format changed WITH nearest callers and descriptions',command:'moon',
    args:['fmt','src/query_program/nearest_script_test.mbt','src/query_program/nearest_script_inputs.mbt','src/query_program/compile.mbt'],
  }] : [{name:'Original nearest complete Program, KEEP, shared pair keys and public WITH compile',command:'node',
    args:['--input-type=module','-e',runner,'moon','--target','js','src/query_program/nearest_script_test.mbt']} ]});
