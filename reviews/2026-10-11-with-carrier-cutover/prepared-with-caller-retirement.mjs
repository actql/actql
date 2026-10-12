import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const moonFiles = ['src/query_program/with_cte_composition_test.mbt',
  'src/query_program/with_set_composition_test.mbt',
  'src/source_frontend/graph_union_test.mbt',
  'src/source_frontend/graph_subtraction_test.mbt'];
const nodeFiles = ['scripts/array-literal-source-input.test.mjs',
  'scripts/group-by-all-source-input.test.mjs'];
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const step = (name,kind,args) => ({name,command:'node',
  args:['--input-type=module','-e',runner,kind,...args]});
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,
  timeoutSeconds:60,graceSeconds:5,steps:process.argv.includes('--format') ? [{
    name:'Format only retired WITH caller files',command:'moon',
    args:['fmt',...moonFiles,'src/query_program/query_script_set.mbt'],
  }] : [step('WITH CTE/set and Graph caller semantics','moon',['--target','js',...moonFiles]),
    step('Existing independent ARRAY/GROUP public fixture obligations','node',nodeFiles)]});
