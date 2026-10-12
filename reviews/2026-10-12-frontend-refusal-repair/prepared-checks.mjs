import {existsSync} from 'node:fs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const format = ['--format','--format-write'].includes(process.argv[2]);
const write = process.argv[2] === '--format-write';
const selectedCase = process.argv[2] === '--case' ? process.argv[3] : null;
const files = process.argv.slice(format ? 3 : selectedCase ? 4 : 2);
if (!files.length || files.some(file => !existsSync(file))) throw new Error('Explicit existing focused files are required');
const steps = format
  ? [{name:'Read-only changed fixture formatting',command:'moon',args:['fmt',...(write ? [] : ['--check']),...files]}]
  : [{name:'Explicit focused frontend cases',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files,...(selectedCase ? ['--filter',selectedCase] : [])]}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
