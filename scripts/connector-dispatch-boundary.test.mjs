import assert from 'node:assert/strict';
import test from 'node:test';
import {connectorDispatchViolations, checkConnectorDispatchBoundary} from './check-connector-dispatch-boundary.mjs';

const names = ['local', 'duckdb', 'mock', 'reference_compute'];
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
