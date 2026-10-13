import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const flags = process.argv.slice(2);
const allowed = ['--format', '--bridgegen', '--info', '--api-js', '--api-wasm', '--api-native'];
if (flags.length > 1 || flags.some(flag => !allowed.includes(flag))) throw new Error('Unsupported Calendar admission selection');
const focused = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const target = flags.find(flag => flag.startsWith('--api-'))?.slice('--api-'.length);
const steps = flags.includes('--format') ? [
  'src/program_check/calendar_environment.mbt', 'src/program_check/calendar_environment_wbtest.mbt',
  'src/connectors_builtin_node/client_program_bridge.mbt', 'src/connectors_builtin_node/client_calendar_environment_wbtest.mbt',
].map(file => ({name: 'Format Calendar admission ' + file, command: 'moonfmt', args: ['-w', file]})) : flags.includes('--bridgegen') ? [
  {name: 'Regenerate the common RelA checker bridge through its existing generator', command: 'node', args: ['--input-type=module', '-e', 'import {checkRelaNodeAssembly} from "./scripts/connector-node-bundles.mjs"; console.log(checkRelaNodeAssembly(process.cwd(),true));']},
] : flags.includes('--info') ? [
  {name: 'Generate the admitted-checker API with the pinned compiler', command: 'moon', args: ['info', '--target', 'js', 'src/program_check', 'src/connectors_builtin_node', 'src/connectors_builtin_node_rela']},
] : target ? [
  {name: 'Compile affected checker consumers on ' + target, command: 'moon', args: ['check', '--target', target, 'src/program_check', 'src/client_source_publication', 'src/client_local_preparation']},
] : [
  {name: 'Selected Calendar artifact stays with ordinary checking and source owners', command: 'node', args: ['--input-type=module', '-e', focused, 'moon', '--target', 'js', 'src/program_check/calendar_environment_wbtest.mbt', 'src/query_program/calendar_source_test.mbt', 'src/connectors_builtin_node/client_calendar_environment_wbtest.mbt']},
];
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false, timeoutSeconds: 60, graceSeconds: 5, steps});
