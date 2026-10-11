import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const tests = ['src/query_program/with_cte_composition_test.mbt',
  'src/query_program/with_binding_preparation_test.mbt',
  'src/query_program/with_binding_static_order_gap_test.mbt',
  'src/query_program/with_binding_demand_test.mbt'];
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
  timeoutSeconds:60,graceSeconds:5,steps:process.argv.includes('--format') ? [{
    name:'Format finite removed CTE branch and public caller',command:'moon',
    args:['fmt','src/query_program/compile.mbt','src/query_program/with_cte_composition_test.mbt'],
  }] : [{name:'Existing unified WITH public entry and unused binding obligations',command:'node',
    args:['--input-type=module','-e',runner,'moon','--target','js',...tests]}]});
