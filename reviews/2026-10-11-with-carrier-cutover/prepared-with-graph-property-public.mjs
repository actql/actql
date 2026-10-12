import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const format = process.argv.includes('--format');
const nodeOnly = process.argv.includes('--node-only');
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,
 steps:format ? [{name:'Format exact authored WITH Graph/property callers',command:'moon',args:['fmt','src/query_syntax/with_graph_property_public_callers_test.mbt','src/query_program/with_property_public_callers_test.mbt']}]
 : nodeOnly ? [{name:'Independent fixture preservation and consuming acceptance controls',command:'node',args:['--input-type=module','-e',runner,'node','scripts/with-graph-property-public-fixtures.test.mjs','scripts/acquired-data-acceptance.test.mjs','scripts/distinct-order-member-source-input.test.mjs','scripts/distinct-order-receiver-source-input.test.mjs']}]
 : [{name:'Exact public Parser sources',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js','src/query_syntax/with_graph_property_public_callers_test.mbt']},{name:'Source-free public lowering and normal common static check',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js','src/query_program/with_property_public_callers_test.mbt']}]});
