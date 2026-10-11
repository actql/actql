import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';

// These are the existing bounded wrappers, not another test or runtime owner.
const runner = 'import {runFocusedTests} from "./scripts/test-execution.mjs"; process.exitCode=runFocusedTests(process.argv[1],process.argv.slice(2),{cwd:process.cwd()});';
const step = (name, kind, args) => ({name, command: 'node',
  args: ['--input-type=module', '-e', runner, kind, ...args]});
const repairedOnly = process.argv.includes('--repaired-callers');
process.exitCode = await runLocalCheck({root: process.cwd(), heavy: false,
  timeoutSeconds: 60, graceSeconds: 5,
  steps: repairedOnly ? [step('Corrected WITH static Graph callers', 'moon', [
    '--target', 'js', 'src/query_program/graph_diagnostics_test.mbt',
    'src/query_program/traversal_nodes_test.mbt',
  ])] : [
    step('WITH operation independent caller obligations', 'node', [
      'scripts/with-graph-operation-caller.test.mjs',
      'scripts/graph-shortest-source-input.test.mjs',
      'scripts/graph-refusal-classification-source-input.test.mjs',
    ]),
    step('WITH Graph lowering and E public diagnostic callers', 'moon', [
      '--target', 'js', 'src/query_program/graph_diagnostics_test.mbt',
      'src/query_program/traversal_nodes_test.mbt',
      'src/query_program/traverse_hop_vocabulary_test.mbt',
      'src/query_program/traversal_join_input_test.mbt',
      'src/query_program/graph_shortest_source_test.mbt',
      'src/connectors_builtin_node/client_source_preparation_wbtest.mbt',
      'src/connectors_builtin_node/client_check_binding_preparation_wbtest.mbt',
    ]),
  ]});
