import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const capturedOnly = process.argv.includes('--captured-only');
const fixturesOnly = process.argv.includes('--fixtures-only');
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,
 steps:process.argv.includes('--format') ? [{name:'Format exact changed WITH expansion source callers',command:'moon',args:['fmt','src/query_program/with_expansion_public_fixture_test.mbt']}]
 : [...(fixturesOnly ? [] : [{name:'Exact submitted WITH expansion sources through public frontend and common static bindings',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js','src/query_program/with_expansion_public_fixture_test.mbt',...(capturedOnly ? ['--filter','*joined-unnest-star-acquired-data*'] : [])]}]),
 ...(capturedOnly ? [] : [{name:'Independent UNNEST and tuple full fixture preservation and ordinary registration',command:'node',args:['--input-type=module','-e',runner,'node','scripts/with-expansion-public-fixtures.test.mjs','scripts/unpivot-multicolumn-source-input.test.mjs','scripts/unnest-source-input.test.mjs','scripts/unnest-join-source-input.test.mjs','scripts/correlated-unnest-source-input.test.mjs','scripts/joined-unnest-star-source-input.test.mjs','scripts/correlated-unnest-star-source-input.test.mjs']}]) ]});
