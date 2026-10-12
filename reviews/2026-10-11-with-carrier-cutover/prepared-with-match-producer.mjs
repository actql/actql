import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,
 steps:process.argv.includes('--format') ? [{name:'Format WITH projected MATCH caller',command:'moon',args:['fmt','src/query_program/match_with_producer_test.mbt']}]
 : [{name:'WITH projected MATCH independent Programs and nested scope',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js','src/query_program/match_with_producer_test.mbt']},
 {name:'WITH MATCH public fixture independent controls and packed registration',command:'node',args:['--input-type=module','-e',runner,'node','scripts/match-with-producer-source-input.test.mjs']} ]});
