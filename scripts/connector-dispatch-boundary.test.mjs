import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {connectorDispatchViolations, checkConnectorDispatchBoundary, isConnectorTestFixture} from './check-connector-dispatch-boundary.mjs';

const names = ['local', 'duckdb', 'mock', 'reference_compute'];
test('native DATA keys remain distinct from registered connector keys and selector sentinels', () => {
  const source = readFileSync(new URL('../adapters/host-node/host-journal-directory.mjs', import.meta.url), 'utf8');
  const start = source.indexOf('export function hostJournalDirectoryNative(inspector)');
  assert.ok(start >= 0);
  const declaration = source.slice(start);
  for (const path of ['adapters/host-node/host-journal-directory.mjs', 'adapters/host-common/unrelated.mjs']) {
    assert.deepEqual(connectorDispatchViolations(declaration, names, path), []);
    for (const dispatch of [
      "if (provider === 'native') dispatch();",
      'match placement { Native(value) => execute(value) }',
      'const handlers = {local: execute};',
      String.raw`registry.get('d\u0075ckdb')`,
    ]) assert.ok(connectorDispatchViolations(declaration + '\n' + dispatch, names, path).length > 0);
  }
  // A real registration named native still has the same closed key rule.
  assert.ok(connectorDispatchViolations('const handlers = {native: execute};',
    [...names, 'native']).length > 0);
});

test('common implementation files reject concrete dispatch identities', () => {
  assert.ok(checkConnectorDispatchBoundary(process.cwd()) > 0);
});

test('concrete comparisons variants and dispatch tables are rejected', () => {
  for (const source of [
    'if id == "duckdb" { run() }',
    'if (id === "local") run();',
    'switch (id) { case "duckdb": return run(); }',
    'match implementation { Native(value) => execute(value); Local(value) => execute(value) }',
    'enum Placement { Local; DuckDB }',
    'const handlers = { duckdb: execute, local: evaluate };',
    'new Map([["reference_compute", run]])',
    'registry.get("duckdb")',
    'registry.get("DuckDB")',
    'if (placement === "native") execute();',
    String.raw`if (id === "d\u0075ckdb") run();`,
    String.raw`if (id === 'd\x75ckdb') run();`,
    'switch (id) { case `duckdb`: run(); }',
  ]) assert.ok(connectorDispatchViolations(source, names).length > 0, source);
});

test('opaque lookup identity checks and transported labels are allowed', () => {
  for (const source of [
    'const implementation = installed.get(registration); implementation.run(task);',
    '@connector.capability_implementation(entries, registration)',
    'if (expected === actual) return output;',
    'return {label: description.name, reason: rejection};',
    '// DuckDB Local Native "duckdb"\ninstalled.get(id);',
    '/* case "duckdb": Local(value) */ installed.get(id);',
  ]) assert.deepEqual(connectorDispatchViolations(source, names), [], source);
});

test('measurement Host admission allows only the closed refusal checks in their owners', () => {
  for (const [path, source] of [
    ['src/physical_strategy_host/operational_conditions.mbt', `
      if value.host != "native" || value.concurrency != 1 || value.input_rows < 1 ||
        !["off", "metadata-only", "evidence-enabled"].contains(value.capture_mode) ||
        !["fresh", "resident"].contains(value.realization) { raise PolicyWireStop }
    `],
    ['src/physical_strategy_host/operational_estimates.mbt', `
      if !["off", "metadata-only", "evidence-enabled"].contains(
        policy_wire_text(conditions, "captureMode"),
      ) || !["fresh", "resident"].contains(
        policy_wire_text(conditions, "realization"),
      ) || policy_wire_text(conditions, "host") != "native" ||
        policy_wire_int(conditions, "concurrency") != 1 ||
        policy_wire_int(conditions, "inputRows") < 1 { raise PolicyWireStop }
    `],
  ]) {
    assert.deepEqual(connectorDispatchViolations(source, names, path), []);
    assert.equal(connectorDispatchViolations(source, names, 'src/physical_strategy/dispatch.mbt').length, 1);
    assert.equal(connectorDispatchViolations(source.replace('raise PolicyWireStop', 'dispatch()'), names, path).length, 1);
    assert.equal(connectorDispatchViolations(source.replace('!= "native"', '== "native"'), names, path).length, 1);
    assert.equal(connectorDispatchViolations(source + '\nif id == "native" { dispatch() }', names, path).length, 1);
  }
});

test('test workers are excluded but a common implementation cannot import their custody', () => {
  assert.equal(isConnectorTestFixture('adapters/host-node/process.fixture.mjs'), true);
  assert.equal(isConnectorTestFixture('adapters/host-node/fixtures/process.mjs'), true);
  assert.equal(isConnectorTestFixture('adapters/host-node/finalizer-fixture.mjs'), true);
  assert.equal(isConnectorTestFixture('adapters/host-node/fixture-owner.mjs'), false);
  const root = mkdtempSync(join(tmpdir(), 'actql-dispatch-boundary-'));
  try {
    for (const directory of ['src/connectors/local', 'src/connector_sdk',
      'src/query_planning', 'src/physical_host', 'src/physical_host_dispatch', 'src/physical_strategy', 'src/physical_strategy_host',
      'src/physical_resources', 'src/physical_cost', 'adapters/host-node/fixtures',
      'adapters/host-common', 'scripts/templates']) mkdirSync(join(root, directory), {recursive: true});
    writeFileSync(join(root, 'adapters/host-node/worker.fixture.mjs'), 'connect({mode: "local"})');
    writeFileSync(join(root, 'adapters/host-node/fixtures/process.mjs'), 'connect({mode: "local"})');
    const implementation = join(root, 'adapters/host-common/strategy.mjs');
    writeFileSync(implementation, 'installed.get(registration)');
    assert.equal(checkConnectorDispatchBoundary(root), 1);
    for (const statement of [
      "import {run} from '../host-node/worker.fixture.mjs';",
      "import '../host-node/fixtures/process.mjs';",
      "const run = await import('../host-node/worker.fixture.mjs');",
      "import {finalizerCase} from '../host-node/finalizer-fixture.mjs';",
    ]) {
      writeFileSync(implementation, statement);
      assert.throws(() => checkConnectorDispatchBoundary(root), /test fixture imported by common implementation/);
    }
  } finally {
    rmSync(root, {recursive: true, force: true});
  }
});

test('observation scope defaults cannot hide concrete dispatch in the same owner', () => {
  const path = 'adapters/host-common/observation.mjs';
  const defaults = `const {deliver, currentContext,
    scope = 'local', revision = 'metadata/0.1', limits = {},
    include = [...operations], exclude = [], correlation = true} = options;`;
  assert.deepEqual(connectorDispatchViolations(defaults, names, path), []);
  assert.equal(connectorDispatchViolations(defaults, names, 'adapters/host-common/strategy.mjs').length, 1);
  assert.equal(connectorDispatchViolations(defaults + "if (scope === 'local') dispatch();", names, path).length, 1);
  assert.equal(connectorDispatchViolations("const registration = 'local'; installed.get(registration);", names, path).length, 1);
});


test('fixed native filesystem intrinsic captures are not connector selectors', () => {
  const names = ['mock', 'local', 'duckdb'];
  const statements = [
    ['adapters/host-node/client-request-journal.mjs', `
      const facilityDescriptor = Object.getOwnPropertyDescriptor;
      const facilityRealpath = realpathSync;
      const facilityNativeRealpath = facilityDescriptor(facilityRealpath, 'native')?.value;
    `, 'facilityDescriptor(facilityRealpath', 'otherDescriptor(facilityRealpath'],
    ['adapters/host-common/sqlite-format-inspection.mjs', `
      const originalRealpath = realpathSync;
      const originalNativeRealpath = Object.getOwnPropertyDescriptor(originalRealpath, 'native')?.value;
    `, 'Object.getOwnPropertyDescriptor(originalRealpath', 'Object.otherDescriptor(originalRealpath'],
  ];
  for (const [path, source, callee, changedCallee] of statements) {
    assert.deepEqual(connectorDispatchViolations(source, names, path), []);
    for (const changed of [
      source.replace(callee, changedCallee),
      source.replace('= realpathSync;', '= otherRealpath;'),
      source.replace("'native'", "'local'"),
      source + "\nif (provider === 'native') selectNative();",
    ]) assert.ok(connectorDispatchViolations(changed, names, path).length > 0);
    assert.ok(connectorDispatchViolations(source, names, 'adapters/host-common/unrelated.mjs').length > 0);
  }
});
