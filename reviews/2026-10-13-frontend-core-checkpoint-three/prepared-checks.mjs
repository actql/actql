import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const format = process.argv.slice(2);
if (format.length > 1 || format.some(value => value !== '--format')) throw new Error('Unsupported selection');
const files = ['src/query_program/set_join_entry_test.mbt', 'src/query_program/positional_join_set_test.mbt', 'src/query_integration/standard_subset_wbtest.mbt'];
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps:format.length ? files.map(file => ({name:'Format ' + file,command:'moonfmt',args:['-w',file]})) : [
  {name:'The three reported checkpoint boundaries',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js','src/query_program/set_join_entry_test.mbt','src/query_program/positional_join_set_test.mbt','src/query_integration/standard_subset_wbtest.mbt']},
]});
