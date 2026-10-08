// The distribution job has already built the Node runtimes. OTel remains an
// optional package; neither the SDK nor a normal Local install needs its deps.
import './prepare-otel-node-tests.mjs';
import {runFocusedTests} from './test-execution.mjs';
process.exitCode = runFocusedTests('node', [
  'packages/sdk/trace-context.test.mjs',
  'adapters/host-common/observation.test.mjs',
  'adapters/host-node/client-observation-journal.test.mjs',
  'packages/otel-node/configuration.test.mjs',
  'packages/otel-node/environment.test.mjs',
  'packages/otel-node/transport.test.mjs',
  'packages/otel-node/index.test.mjs',
  'packages/otel-node/public-host.test.mjs',
  'packages/otel-node/recovery.test.mjs',
], {timeout: 240000});
