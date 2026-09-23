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

function run(mutator, routeMutator, args = []) {
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
    return execFileSync(process.execPath, [script, ...args], {
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
  assert.match(run(), /68 operations, 5 implementation profiles, 68 production routes mapped, 8 with operation-specific boundary records, 3 with complete boundary assurance; full boundary completion is not asserted/);
});

test('resource completion rejects every unassured operation', () => {
  assert.match(run(undefined, undefined, ['--require-boundary-complete']),
    /RelA rename: boundary assurance is missing/);
});

test('resource gate rejects a false in-flight assurance', () => {
  assert.match(run(undefined, value => {
    const filter = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'filter');
    filter.boundary_assurance.in_flight_cancel = 'filter_cancel_cleanup';
  }), /RelA filter: in_flight_cancel does not bind an executable fixture/);
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

test('resource gate rejects an ordered take without its cancellation fixture', () => {
  assert.match(run(undefined, value => {
    const take = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'take');
    take.boundary_tests = take.boundary_tests.filter(item =>
      item.role !== 'mixed_stage_sort_cancel_and_cleanup');
  }), /RelA take: reviewed mixed_stage_sort_cancel_and_cleanup fixture is missing/);
});

test('resource gate rejects a take without exact sort-work evidence', () => {
  assert.match(run(undefined, value => {
    const take = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'take');
    take.boundary_tests = take.boundary_tests.filter(item =>
      item.role !== 'key_completion_work_exact_one_short');
  }), /RelA take: reviewed key_completion_work_exact_one_short fixture is missing/);
});

test('resource gate rejects a fixture connected to a foreign suite', () => {
  assert.match(run(undefined, value => {
    const take = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'take');
    take.boundary_tests.find(item =>
      item.role === 'key_completion_workspace_exact_one_short').suite =
      'moon:query_integration';
  }), /RelA take: boundary evidence must be suite-connected on all targets/);
});

test('resource gate rejects cross join without independent limits', () => {
  assert.match(run(undefined, value => {
    const join = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'cross_join');
    join.boundary_tests = join.boundary_tests.filter(item =>
      item.role !== 'product_work_workspace_exact_one_short');
  }), /RelA cross_join: reviewed product_work_workspace_exact_one_short fixture is missing/);
});

test('resource gate rejects sort without mixed-stage evidence', () => {
  assert.match(run(undefined, value => {
    const sort = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'sort');
    sort.boundary_tests = sort.boundary_tests.filter(item =>
      item.role !== 'mixed_stage_sort_quantum_and_lifetime');
  }), /RelA sort: reviewed mixed_stage_sort_quantum_and_lifetime fixture is missing/);
});

test('resource gate rejects sort without its real Host timer case', () => {
  assert.match(run(undefined, value => {
    const sort = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'sort');
    sort.environment_tests = [];
  }), /RelA sort: selected sort Host timer evidence is missing/);
});

test('resource gate rejects assertion without failure cleanup', () => {
  assert.match(run(undefined, value => {
    const assertion = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'assert_rows');
    assertion.boundary_tests = assertion.boundary_tests.filter(item =>
      item.role !== 'assert_where_failure_cleanup');
  }), /RelA assert_rows: reviewed assert_where_failure_cleanup fixture is missing/);
});

test('resource gate rejects a missing unique assertion product route', () => {
  assert.match(run(undefined, value => {
    const assertion = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'assert_rows');
    delete assertion.additional_dispatch;
  }), /RelA assert_rows: both selected assertion forms must reach production/);
});

test('resource gate rejects unique assertion without its exact boundary', () => {
  assert.match(run(undefined, value => {
    const assertion = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'assert_rows');
    assertion.boundary_tests = assertion.boundary_tests.filter(item =>
      item.role !== 'assert_unique_exact_one_short_workspace');
  }), /RelA assert_rows: reviewed assert_unique_exact_one_short_workspace fixture is missing/);
});

test('resource gate rejects unique assertion without Host cancellation', () => {
  assert.match(run(undefined, value => {
    const assertion = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'assert_rows');
    assertion.environment_tests = [];
  }), /RelA assert_rows: assert_where_in_flight_host_timer fixture is missing/);
});

test('resource gate rejects assertion without exact input admission', () => {
  assert.match(run(undefined, value => {
    const assertion = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'assert_rows');
    assertion.boundary_tests = assertion.boundary_tests.filter(item =>
      item.role !== 'assert_where_input_exact');
  }), /RelA assert_rows: reviewed assert_where_input_exact fixture is missing/);
});

test('resource gate rejects assertion without failed sort cleanup', () => {
  assert.match(run(undefined, value => {
    const assertion = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'assert_rows');
    assertion.boundary_tests = assertion.boundary_tests.filter(item =>
      item.role !== 'assert_unique_sort_failure_cleanup');
  }), /RelA assert_rows: reviewed assert_unique_sort_failure_cleanup fixture is missing/);
});

test('resource gate rejects selection without exact admission evidence', () => {
  assert.match(run(undefined, value => {
    const selection = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'select');
    selection.boundary_tests = selection.boundary_tests.filter(item =>
      item.role !== 'select_input_exact');
  }), /RelA select: reviewed select_input_exact fixture is missing/);
});

test('resource gate rejects filter without its one-short evidence', () => {
  assert.match(run(undefined, value => {
    const filter = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'filter');
    filter.boundary_tests = filter.boundary_tests.filter(item =>
      item.role !== 'filter_input_one_short');
  }), /RelA filter: reviewed filter_input_one_short fixture is missing/);
});

test('resource gate rejects filter without delivered Host cancellation', () => {
  assert.match(run(undefined, value => {
    const filter = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'filter');
    filter.environment_tests = [];
  }), /RelA filter: in-flight Host cancellation fixture is missing/);
});

test('resource gate rejects selection without its bounded product route', () => {
  assert.match(run(undefined, value => {
    const selection = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'select');
    delete selection.selected_entrypoint;
  }), /RelA select: bounded selected entrypoint is missing/);
});

test('resource gate rejects selection without delivered Host cancellation', () => {
  assert.match(run(undefined, value => {
    const selection = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'select');
    selection.environment_tests = [];
  }), /RelA select: in-flight Host cancellation fixture is missing/);
});
