import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const file = 'src/source_frontend/unified_dependency_test.mbt';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
  timeoutSeconds:60,graceSeconds:5,steps:process.argv.includes('--format') ? [{
    name:'Format changed unified Source caller',command:'moon',args:['fmt',file],
  }] : [{name:'Unified WITH Source and original Graph argument/location controls',command:'node',
    args:['--input-type=module','-e',runner,'moon','--target','js',file]}]});
