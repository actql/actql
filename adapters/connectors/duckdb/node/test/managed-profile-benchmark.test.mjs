import test from 'node:test';
import assert from 'node:assert/strict';
import {managedProfileInput} from '../bench/managed-profile-case.mjs';
import {exampleDatabaseMemoryBytes} from
  '../examples/physical-strategy.mjs';
import {managedCaseConfiguration} from
  '../../../../../benchmarks/retained-results/managed-configuration.mjs';
import {retainedCase, workloads} from
  '../../../../../benchmarks/retained-results/fixtures.mjs';

test('managed profile keeps Acquisition old-contract and changes Compute', () => {
  const fixture = retainedCase(workloads[2], 'narrow', 100);
  const configured = managedCaseConfiguration(
    fixture,
    {},
    '/source',
    '/store',
  );
  const input = managedProfileInput(configured);
  assert.equal(input.retainedOutput, undefined);
  assert.equal(input.localImportWorkMilliseconds, undefined);
  assert.equal(input.localExportWorkMilliseconds, undefined);
  assert.equal(
    input.acquisitionRetainedOutput,
    configured.input.retainedOutput,
  );
  assert.equal(input.managedOutput, configured.input.retainedOutput);
  assert(Object.isFrozen(input));
  assert.equal(
    exampleDatabaseMemoryBytes(
      configured.input.dataProfile,
      configured.limits,
      input.managedOutput,
    ),
    2147483648,
  );
  assert.equal(
    exampleDatabaseMemoryBytes(
      configured.input.dataProfile,
      configured.limits,
      undefined,
    ),
    128 * 1024 * 1024,
  );
  assert.throws(
    () => exampleDatabaseMemoryBytes(
      configured.input.dataProfile,
      {...configured.limits, execution_bytes: 1n},
      input.managedOutput,
    ),
    /Invalid execution memory limit/,
  );
});
