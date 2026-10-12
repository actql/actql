import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const files = ['src/query_program/graph_match_rows_test.mbt','src/query_program/sga_script_test.mbt','src/query_program/traversal_paths_test.mbt','src/query_program/graph_match_paths_integration_test.mbt'];
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
  timeoutSeconds:60,graceSeconds:5,steps:process.argv.includes('--format') ? [{
    name:'Format changed WITH Graph match and path callers',command:'moon',args:['fmt',...files],
  }] : [{name:'WITH Graph match, normalization and path independent Programs and authored refusals',command:'node',
    args:['--input-type=module','-e',runner,'moon','--target','js',...files]}]});
