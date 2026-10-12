import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner='import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const steps=[{name:'Actual SQL AQL-text and JSON preparation/common contracts',command:'node',
  args:['--input-type=module','-e',runner,'moon','--target','js',
    'src/query_program/carrier_continuation_public_fixture_test.mbt',
    'src/query_program/explicit_graph_expectation_test.mbt',
    'src/query_program/graph_carrier_continuation_test.mbt']},
  {name:'Independent oracles, selected driver and isolated import closure',command:'node',
    args:['--input-type=module','-e',runner,'node','scripts/carrier-continuation-public-input.test.mjs',
      'scripts/sga-output-name-source.test.mjs','scripts/public-query-profiles.test.mjs']},
  {name:'Read-only generated declared inputs',command:'node',args:['scripts/carrier-continuation-fixtures.mjs']},
  ...['scripts/test-packed-public-query.mjs','scripts/fixtures/packed-public-query.mjs'].map(file=>({
    name:`Syntax ${file}`,command:'node',args:['--check',file]})),
  {name:'Whitespace',command:'git',args:['diff','--check']},
];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
