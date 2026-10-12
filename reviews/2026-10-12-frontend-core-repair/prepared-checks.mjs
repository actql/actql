import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const format = process.argv[2] === '--format';
const files = process.argv.slice(format ? 3 : 2);
if (!files.length) throw new Error('Explicit focused test files are required');
const steps = format
  ? [{name:'Read-only changed fixture formatting',command:'moon',args:['fmt','--check',...files]}]
  : [{name:'Explicit focused frontend cases',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files]}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
