import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,
steps: [{name:'Remaining current caller complete independent preimage preservation',command:'node',args:['--input-type=module','-e',runner,'node','scripts/with-remaining-public-fixtures.test.mjs']}]});
