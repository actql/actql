import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,
steps: process.argv.includes('--format') ? [{name:'Format changed current source parser tests',command:'moon',args:['fmt','src/query_syntax/with_remaining_public_callers_test.mbt']}]
: process.argv.includes('--parser-only') ? [{name:'Parse exact changed current Graph and Relation successes',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js','src/query_syntax/with_remaining_public_callers_test.mbt']}]
: [{name:'Remaining current caller complete independent preimage preservation',command:'node',args:['--input-type=module','-e',runner,'node','scripts/with-remaining-public-fixtures.test.mjs']}]});
