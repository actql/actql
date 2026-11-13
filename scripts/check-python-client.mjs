import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {runLocalCheck} from './local-checks-guard.mjs';
const root = fileURLToPath(new URL('../', import.meta.url));

// Explicit source-only callers, inspected for transport doubles and pinned SDK
// dependencies. This is not installed Local, Native or live-service acceptance.
// wait_since also includes one source-only Local refusal double, not a runtime.
export const remotePythonClientTests = Object.freeze([
  'test_boundaries.py',
  'test_bounded_text.py',
  'test_check_reason_presentation.py',
  'test_checkpoint_convenience.py',
  'test_checkpoints.py',
  'test_connection_string.py',
  'test_domain_carrier_presentation.py',
  'test_effect_review_integrity.py',
  'test_named_submission.py',
  'test_public_aql_format.py',
  'test_public_check_observation.py',
  'test_public_run_state.py',
  'test_requested_stop.py',
  'test_result_schema.py',
  'test_source_query.py',
  'test_wait_since.py',
]);

export function pythonClientSteps(python, {remoteOnly = false} = {}) {
  return [
    {name: 'Python contract generation', command: process.execPath, args: ['scripts/generate-python-client-wire.mjs', '--check']},
    ...(remoteOnly ? remotePythonClientTests.map(pattern => ({
      name: `Python SDK/Remote ${pattern}`, command: python,
      args: ['-B', 'packages/python-sdk/tests/run.py', '--pattern', pattern],
    })) : [
      {name: 'Python client boundary tests', command: python, args: ['packages/python-sdk/tests/run.py']},
      {name: 'Python public API type checks', command: python, args: ['-m', 'mypy', '--config-file', 'packages/python-sdk/pyproject.toml', 'scripts/fixtures/python-client-types.py']},
    ]),
  ];
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args.length > 1 || (args.length === 1 && args[0] !== '--remote-only')) {
    throw new Error('Usage: node scripts/check-python-client.mjs [--remote-only]');
  }
  const python = process.env.ACTQL_PYTHON ?? 'python3';
  process.exitCode = await runLocalCheck({root, heavy: false, timeoutSeconds: 180, graceSeconds: 5,
    steps: pythonClientSteps(python, {remoteOnly: args.length === 1})});
}
