import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const moonFiles = ['src/query_program/with_positional_set_test.mbt',
  'src/query_syntax/composition_controls_test.mbt'];
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
  timeoutSeconds:60,graceSeconds:5,steps:process.argv.includes('--format') ? [{
    name:'Format only positional and composition WITH callers',command:'moon',args:['fmt',...moonFiles],
  }] : [{name:'Positional set contracts and unchanged composition controls',command:'node',
    args:['--input-type=module','-e',runner,'moon','--target','js',...moonFiles]},
  {name:'Existing independent full JOIN and public fixture contracts',command:'node',
    args:['--input-type=module','-e',runner,'node','scripts/public-query-cases.test.mjs']} ]});
