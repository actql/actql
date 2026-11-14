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

// Reviewed Source fixtures: injected Host/Native ports and fresh POSIX/stdlib
// SQLite state. These do not execute an installed Core or Native component.
export const sourceLocalPythonClientTests = Object.freeze([
  'test_local_import.py',
  'test_local_public_factory.py',
  'test_local_client_transport.py',
  'test_local_submission_failure_custody.py',
  'test_local_project_connection.py',
  'test_local_project_files.py',
  'test_local_check_ports.py',
  'test_local_sdk_response.py',
  'test_local_storage.py',
  'test_local_storage_fenced.py',
  'test_local_storage_readonly_span.py',
  'test_local_storage_batch.py',
  'test_local_storage_capacity.py',
  'test_local_reader_facts.py',
  'test_local_submission.py',
  'test_local_host_files.py',
  'test_local_file_reader.py',
  'test_local_original_files.py',
  'test_local_native_runtime.py',
  'test_local_native_image.py',
  'test_local_native_image_close.py',
  'test_local_native_store.py',
  'test_local_native_original_read.py',
  'test_local_native_read_crypto.py',
  'test_local_native_domain_borrow.py',
]);

export function pythonClientSteps(python, {remoteOnly = false, sourceOnly = false} = {}) {
  if (remoteOnly && sourceOnly) throw new Error('Select one Python test scope');
  const selected = sourceOnly ? [...remotePythonClientTests, ...sourceLocalPythonClientTests]
    : remoteOnly ? remotePythonClientTests : undefined;
  return [
    {name: 'Python contract generation', command: process.execPath, args: ['scripts/generate-python-client-wire.mjs', '--check']},
    ...(selected ? selected.map(pattern => ({
      name: `Python ${sourceLocalPythonClientTests.includes(pattern) ? 'Local source' : 'SDK/Remote'} ${pattern}`, command: python,
      args: ['-B', 'packages/python-sdk/tests/run.py', '--pattern', pattern],
      ...(sourceOnly && sourceLocalPythonClientTests.includes(pattern) ? {
        env: {PYTHONPATH: fileURLToPath(new URL('../packages/python-product/src', import.meta.url))},
      } : {}),
    })) : [
      {name: 'Python client boundary tests', command: python, args: ['packages/python-sdk/tests/run.py']},
      {name: 'Python public API type checks', command: python, args: ['-m', 'mypy', '--config-file', 'packages/python-sdk/pyproject.toml', 'scripts/fixtures/python-client-types.py']},
    ]),
  ];
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  if (args.length > 1 || (args.length === 1 && !['--remote-only', '--source-only'].includes(args[0]))) {
    throw new Error('Usage: node scripts/check-python-client.mjs [--remote-only|--source-only]');
  }
  const python = process.env.ACTQL_PYTHON ?? 'python3';
  process.exitCode = await runLocalCheck({root, heavy: false, timeoutSeconds: 180, graceSeconds: 5,
    steps: pythonClientSteps(python, {remoteOnly: args[0] === '--remote-only', sourceOnly: args[0] === '--source-only'})});
}
