import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files = ['src/query_program/event_window_source_test.mbt'];
const steps = process.argv.includes('--format')
  ? [{name:'Format authored event window controls',command:'moon',args:['fmt',...files]}]
  : [{name:'Independent common windows and authored source counterexamples',command:'node',
    args:['--input-type=module','-e',runner,'moon','--target','js',...files]}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
