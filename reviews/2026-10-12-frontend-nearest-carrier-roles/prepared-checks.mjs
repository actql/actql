import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const mode = process.argv[2] ?? '--tests';
const files = [
  'src/query_program/nearest_carrier_roles_test.mbt',
  'src/query_program/nearest_composite_roles_wbtest.mbt',
  'src/query_syntax/nearest_optional_roles_test.mbt',
  'src/query_program/nearest_test.mbt',
];
let steps;
if (mode === '--tests') {
  steps = [{name:'NEAREST typed operand roles and existing Relation control',command:'node',args:['--input-type=module','-e',runner,'moon','--target','js',...files]}];
} else if (mode === '--interfaces') {
  steps = [{name:'Generate affected query interfaces',command:'moon',args:['info','--target','js','src/query_syntax','src/query_program']}];
} else if (mode === '--format') {
  const changed = [...files,
    'src/query_program/nearest_program.mbt',
    'src/query_program/nearest_carrier_program.mbt',
    'src/query_program/query_script_program.mbt',
    'src/query_program/query_script_carriers.mbt',
    'src/query_syntax/query.mbt',
    'src/query_syntax/producer_primary.mbt',
    'src/query_syntax/nearest_test.mbt'];
  steps = changed.map(file => ({name:`Format ${file}`,command:'moonfmt',args:['-w',file]}));
} else {
  throw new Error(`Unknown selection: ${mode}`);
}
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
