// Focused common-boundary diagnostic; no package producer or public campaign.
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(), heavy:false,
  timeoutSeconds:60, graceSeconds:5, steps:[{
    name:'Original Vector fixture common declaration and actual row admission',
    command:'node', args:['--input-type=module','-e',runner,'moon','--target','js',
      'src/client_row_source_host/vector_relation_wbtest.mbt'],
  }]});
