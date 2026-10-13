import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files=process.argv.slice(2);
if(files.length===0) throw new Error('Explicit focused files are required');
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps:[{name:'Frontend checkpoint selected counterexamples',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files]}]});
