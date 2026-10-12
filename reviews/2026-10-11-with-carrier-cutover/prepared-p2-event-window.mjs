import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const files = ['src/query_program/event_window_source_test.mbt','src/query_syntax/event_window_role_test.mbt'];
const generators = ['compilation-manifests','event-window-identity-oracle','update-document-metadata',
  'check-actql-spec-family','check-canonical-json'];
const steps = process.argv.includes('--normative-write')
  ? generators.map(name => ({name:'Existing generator or independent oracle '+name,command:'node',args:['scripts/'+name+'.mjs','--write']}))
  : process.argv.includes('--format')
  ? [{name:'Format authored event window connection and controls',command:'moon',args:['fmt',...files,
    'src/query_program/query_script_carriers.mbt','src/query_syntax/sga_call.mbt','src/query_syntax/sga_argument_roles.mbt']}]
  : [{name:'Independent common windows and authored source counterexamples',command:'node',
    args:['--input-type=module','-e',runner,'moon','--target','js',...files]}];
process.exitCode=await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
