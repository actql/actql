import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const flags = process.argv.slice(2);
if (flags.length > 1 || flags.some(flag => !['--manifest','--metadata','--node','--info','--format','--freshness'].includes(flag))) throw new Error('Unsupported selection');
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const script = (name, file, args = []) => ({name,command:'node',args:[file,...args]});
const focused = (name, kind, args) => ({name,command:'node',args:['--input-type=module','-e',runner,kind,...args]});
const steps = flags.includes('--manifest') ? [
  script('Update reviewed grammar hashes and the generated compiler pin', 'scripts/compilation-manifests.mjs', ['--write']),
  script('Write independent retained and authored Calendar Values preimages', 'scripts/calendar-source-identity-oracle.mjs', ['--write']),
] : flags.includes('--metadata') ? [
  script('Apply the reviewed grammar pin and its four document imports', 'scripts/update-document-metadata.mjs', ['--write']),
  script('Project the existing spec-family registry', 'scripts/check-actql-spec-family.mjs', ['--write']),
  script('Project changed current contract pins into canonical tests', 'scripts/check-canonical-json.mjs', ['--write']),
] : flags.includes('--node') ? [
  focused('Calendar independent identities and retained vector-score caller', 'node', ['scripts/calendar-source.test.mjs','scripts/vector-score-literal-source.test.mjs']),
] : flags.includes('--info') ? [
  {name:'Generate affected JS interfaces with the pinned compiler',command:'moon',args:['info','--target','js','src/query_syntax','src/query_program','src/source_frontend','src/program_check']},
] : flags.includes('--format') ? [
  'src/program_check/check_input.mbt', 'src/query_program/calendar_source_test.mbt',
  'src/query_program/compile.mbt', 'src/query_program/compile_test.mbt',
  'src/query_program/graph_program_wbtest.mbt', 'src/query_program/query_binding_check.mbt',
  'src/query_program/query_script_carriers.mbt', 'src/query_program/relation_generator_program.mbt',
  'src/query_program_test_bridge/bridge.mbt', 'src/query_syntax/query.mbt',
  'src/query_syntax/sga_argument_roles.mbt', 'src/query_syntax/sga_call.mbt',
  'src/source_frontend/lower.mbt', 'src/source_frontend/lower_test.mbt',
  'src/client_source_publication/publication.mbt', 'src/client_local_preparation/preparation.mbt',
].map(file => ({name:'Format affected source ' + file,command:'moonfmt',args:['-w',file]})) : flags.includes('--freshness') ? [
  script('Grammar manifest freshness', 'scripts/compilation-manifests.mjs'),
  script('Document metadata freshness', 'scripts/update-document-metadata.mjs'),
  script('Spec-family projection freshness', 'scripts/check-actql-spec-family.mjs'),
  script('Canonical vector freshness', 'scripts/check-canonical-json.mjs'),
] : [focused('Calendar text and selected profile cross the ordinary checker and public preparation', 'moon', ['--target','js','src/query_program/calendar_source_test.mbt'])];
process.exitCode = await runLocalCheck({root:process.cwd(),heavy:false,timeoutSeconds:60,graceSeconds:5,steps});
