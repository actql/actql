import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, readFileSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const script = join(root, 'scripts/check-local-resource-accounting.mjs');
const source = join(
  root,
  'docs/reviews/2026-09-23-local-resource-accounting-audit.json',
);

function run(mutator, routeMutator) {
  const manifest = JSON.parse(readFileSync(source, 'utf8'));
  mutator?.(manifest);
  const directory = mkdtempSync(join(tmpdir(), 'actql-resource-audit-'));
  if (routeMutator) {
    const routes = JSON.parse(readFileSync(join(
      root, manifest.production_routes,
    ), 'utf8'));
    routeMutator(routes);
    const routesTarget = join(directory, 'routes.json');
    writeFileSync(routesTarget, JSON.stringify(routes));
    manifest.production_routes = routesTarget;
  }
  const target = join(directory, 'manifest.json');
  writeFileSync(target, JSON.stringify(manifest));
  try {
    return execFileSync(process.execPath, [script], {
      cwd: root,
      env: {...process.env, ACTQL_LOCAL_RESOURCE_AUDIT: target},
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (error) {
    return String(error.stderr);
  }
}

test('resource gate accepts every normative Local operation', () => {
  assert.match(run(), /68 operations, 5 implementation profiles, 68 production routes gated/);
});

test('resource gate rejects an omitted operation', () => {
  assert.match(run(value => {
    value.bindings[0].operations.pop();
  }), /authoritative inventories/);
});

test('resource gate rejects a profile without allocation evidence', () => {
  assert.match(run(value => {
    value.profiles.sga_graph.evidence =
      value.profiles.sga_graph.evidence.filter(item =>
        !item.facets.includes('admission_before_allocation'));
  }), /missing admission_before_allocation evidence/);
});

test('resource gate rejects an omitted execution phase', () => {
  assert.match(run(value => {
    delete value.profiles.rela_rows.phase_inventory.value_construction;
  }), /missing specific value_construction phase accounting/);
});

test('resource gate rejects a missing fixture', () => {
  assert.match(run(value => {
    value.profiles.tea_events.evidence[0].fixture = 'missing fixture';
  }), /missing fixture/);
});

test('resource gate rejects an unknown implementation profile', () => {
  assert.match(run(value => {
    value.bindings[0].profile = 'unknown';
  }), /unknown profile/);
});

test('resource gate rejects an operation without a production route', () => {
  assert.match(run(undefined, value => {
    value.routes = value.routes.filter(entry =>
      entry.operation !== 'shortest_path');
  }), /production routes must exactly preserve/);
});

test('resource gate rejects a foreign production entrypoint', () => {
  assert.match(run(undefined, value => {
    value.routes.find(entry => entry.operation === 'shortest_path')
      .entrypoint.symbol = 'missing_shortest_entrypoint';
  }), /SGA shortest_path: production entrypoint symbol is missing/);
});

test('resource gate rejects a bypassed provider call', () => {
  assert.match(run(undefined, value => {
    value.routes.find(entry => entry.operation === 'shortest_path')
      .dispatch.marker = '@sga.start_shortest_bypass(';
  }), /SGA shortest_path: dispatch marker does not reach production source/);
});

test('resource gate refuses a test fixture as the production entrypoint', () => {
  assert.match(run(undefined, value => {
    value.routes.find(entry => entry.operation === 'shortest_path')
      .entrypoint.path = 'src/query_integration/local_carrier_graph_wbtest.mbt';
  }), /SGA shortest_path: entrypoint must bind a production source/);
});

test('resource gate rejects a reviewed operation without its exact boundary fixture', () => {
  assert.match(run(undefined, value => {
    value.routes.find(entry => entry.operation === 'apply_graph_delta')
      .boundary_tests.shift();
  }), /SGA apply_graph_delta: reviewed exact\/cancel boundary fixture is missing/);
});
