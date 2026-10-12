import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files = process.argv.slice(2);
if (!files.length) throw new Error('Explicit focused test files are required');
const steps = files.map(file => ({name:file,command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',file]}));
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
