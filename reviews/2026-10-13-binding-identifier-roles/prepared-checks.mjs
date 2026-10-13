import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const steps = [
  {name: 'Ordinary identifier roles and affected parser/Program controls', command: 'node', args: [
    '--input-type=module', '-e', runner, 'moon', '--target', 'js',
    'src/query_syntax/binding_identifier_roles_test.mbt',
    'src/query_syntax/quoted_source_alias_test.mbt',
    'src/query_syntax/with_binding_origin_test.mbt',
    'src/query_syntax/sga_output_name_test.mbt',
    'src/query_syntax/sequence_predicate_test.mbt',
    'src/query_syntax/unnest_source_test.mbt',
    'src/query_syntax/unpivot_test.mbt',
    'src/query_program/binding_identifier_roles_test.mbt',
    'src/query_program/quoted_identifier_test.mbt',
  ]},
  {name: 'Independent role fixtures and unchanged quoted-name controls', command: 'node', args: [
    '--input-type=module', '-e', runner, 'node',
    'scripts/binding-identifier-roles.test.mjs',
    'scripts/quoted-identifier-canonicalization.test.mjs',
  ]},
  {name: 'Whitespace', command: 'git', args: ['diff', '--check']},
];
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 60, graceSeconds: 5, steps});
