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
  assert.match(run(), /68 operations, 5 implementation profiles, 68 production routes mapped, 17 with operation-specific boundary records, 3 with four-role boundary evidence, 2 with full work\/workspace assurance, 15 with path-scoped work\/workspace evidence, 0 with selected-only assurance; full boundary completion is not asserted/);
});

test('append loses its boundary record when exact resource evidence is removed', () => {
  assert.match(run(undefined, routes => {
    const append = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'append');
    append.boundary_tests = append.boundary_tests.filter(item =>
      item.role !== 'append_work_workspace_exact_one_short');
  }), /RelA append: append_work_workspace_exact_one_short fixture is missing/);
  assert.match(run(undefined, routes => {
    const append = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'append');
    append.boundary_tests.find(item =>
      item.role === 'append_self_occurrence_reclamation').fixture =
      'missing-append-self-occurrence';
  }), /RelA append: missing operation boundary fixture missing-append-self-occurrence/);
  assert.match(run(undefined, routes => {
    const append = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'append');
    delete append.external_input_entrypoint;
  }), /RelA append: bounded external append provider is missing/);
  assert.match(run(undefined, routes => {
    const append = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'append');
    append.boundary_tests = append.boundary_tests.filter(item =>
      item.role !== 'append_external_cancel_cleanup');
  }), /RelA append: append_external_cancel_cleanup fixture is missing/);
  assert.match(run(undefined, routes => {
    const append = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'append');
    append.environment_tests = [];
  }), /RelA append: external_input_entrypoint in_flight_cancel lacks an executable fixture/);
});

test('zero-input values bind their bounded production provider', () => {
  assert.match(run(undefined, routes => {
    const values = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'values');
    delete values.zero_input_entrypoint;
  }), /RelA values: bounded zero-input Values route lacks its production evidence/);
  assert.match(run(undefined, routes => {
    const values = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'values');
    values.boundary_tests = values.boundary_tests.filter(item =>
      item.role !== 'zero_input_cancel_cleanup');
  }), /RelA values: bounded zero-input Values route lacks its production evidence/);
  assert.match(run(undefined, routes => {
    const values = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'values');
    values.environment_tests[0].fixture = 'missing-values-timer';
  }), /RelA values: missing environment fixture missing-values-timer/);
});

test('resource gate requires mixed-stage values execution evidence', () => {
  assert.match(run(undefined, value => {
    const values = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'values');
    values.boundary_tests = values.boundary_tests.filter(item =>
      item.role !== 'zero_input_mixed_stage_two_consumers');
  }), /RelA values: bounded zero-input Values route lacks its production evidence/);
  assert.match(run(undefined, value => {
    const values = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'values');
    values.environment_tests = values.environment_tests.filter(item =>
      item.role !== 'zero_input_mixed_stage_timer_cancel_cleanup');
  }), /RelA values: mixed-stage timer cancellation fixture is missing/);
  assert.match(run(undefined, value => {
    const values = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'values');
    values.boundary_tests = values.boundary_tests.filter(item =>
      item.role !== 'zero_input_sort_take_two_consumers');
  }), /RelA values: bounded zero-input Values route lacks its production evidence/);
  assert.match(run(undefined, value => {
    const values = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'values');
    values.environment_tests = values.environment_tests.filter(item =>
      item.role !== 'zero_input_sort_timer_cancel_cleanup');
  }), /RelA values: mixed-stage timer cancellation fixture is missing/);
  assert.match(run(undefined, value => {
    const values = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'values');
    values.boundary_tests = values.boundary_tests.filter(item =>
      item.role !== 'zero_input_unique_two_consumers');
  }), /RelA values: bounded zero-input Values route lacks its production evidence/);
  assert.match(run(undefined, value => {
    const values = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'values');
    values.environment_tests = values.environment_tests.filter(item =>
      item.role !== 'zero_input_unique_timer_cancel_cleanup');
  }), /RelA values: mixed-stage timer cancellation fixture is missing/);
});

test('selected projection loses its resource proof when the fixture is removed', () => {
  assert.match(run(undefined, routes => {
    const select = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'select');
    select.boundary_tests.find(item =>
      item.role === 'select_workspace_exact_one_short').fixture =
      'missing-selected-projection-resources';
  }), /RelA select: missing operation boundary fixture missing-selected-projection-resources/);
});

test('cross join copy evidence must resolve to its managed product fixture', () => {
  assert.match(run(undefined, routes => {
    const crossJoin = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'cross_join');
    crossJoin.boundary_tests.find(item =>
      item.role === 'managed_in_flight_copy_cancel_cleanup').fixture =
      'missing-cross-join-copy-stop';
  }), /RelA cross_join: missing operation boundary fixture missing-cross-join-copy-stop/);
});

test('external cross join binds its provider and bounded fixtures', () => {
  assert.match(run(undefined, routes => {
    const crossJoin = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'cross_join');
    crossJoin.external_input_entrypoint.symbol = 'missing_cross_join_provider';
  }), /RelA cross_join: production entrypoint symbol is missing/);
  assert.match(run(undefined, routes => {
    const crossJoin = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'cross_join');
    crossJoin.boundary_tests.find(item =>
      item.role === 'external_product_host_in_flight_cancel_cleanup').fixture =
      'missing-external-cross-join-cancel';
  }), /RelA cross_join: missing operation boundary fixture missing-external-cross-join-cancel/);
});

test('selected filter retains its shared expression accounting rule', () => {
  assert.match(run(undefined, routes => {
    const filter = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'filter');
    delete filter.shared_resource_rule;
  }), /RelA filter: selected filter lacks its shared expression resource rule/);
  assert.match(run(undefined, routes => {
    const filter = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'filter');
    filter.shared_resource_rule.selected_entrypoint.roles.pop();
  }), /RelA filter: selected_entrypoint shared resource rule lacks reachability or evidence/);
  assert.match(run(undefined, routes => {
    const filter = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'filter');
    filter.shared_resource_rule.selected_entrypoint.caller =
      'src/execution_relation/stable_order.mbt';
  }), /RelA filter: selected_entrypoint shared resource rule lacks reachability or evidence/);
});

test('assured path claims retain the completed selection routes', () => {
  assert.match(run(manifest => {
    manifest.assured_production_paths = manifest.assured_production_paths
      .filter(claim => claim.operation !== 'sort');
  }), /assured production claims differ from resource-assured routes/);
  assert.match(run(undefined, routes => {
    const take = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'take');
    delete take.resource_assurance.selected_entrypoint;
  }), /RelA:take:selected_entrypoint: assured production claim lacks its exact route proofs/);
});

test('assured path claims reject duplicate or invented routes', () => {
  assert.match(run(manifest => {
    manifest.assured_production_paths.push(
      manifest.assured_production_paths[0]);
  }), /assured production claims differ from resource-assured routes/);
  assert.match(run(manifest => {
    manifest.assured_production_paths.push({
      family: 'SGA', operation: 'shortest_path', path: 'entrypoint',
    });
  }), /SGA:shortest_path:entrypoint: assured production claim lacks its exact route proofs/);
});

test('mixed-path gate rejects missing delivered prefix cancellation', () => {
  assert.match(run(undefined, value => {
    value.mixed_paths[0].in_flight_cancel.fixture = 'missing-prefix-case';
  }), /mixed path graph_subgraph_node_rows_filter: missing delivered prefix cancellation fixture/);
});

test('mixed-path gate rejects missing selected Relation cancellation', () => {
  for (const carrier of ['Graph', 'Events', 'Vectors']) {
    assert.match(run(undefined, value => {
      value.mixed_paths.find(path => path.carrier === carrier)
        .selected_in_flight_cancel.fixture = 'missing-selected-case';
    }), new RegExp(`mixed path .*: missing delivered selected Relation cancellation fixture`));
  }
});

test('mixed-path gate preserves Carrier, Bridge, and Relation roles', () => {
  assert.match(run(undefined, value => {
    value.mixed_paths[0].operations = ['subgraph', 'degree', 'filter'];
  }), /mixed path graph_subgraph_node_rows_filter: Carrier, formal Bridge, and Relation roles differ/);
});

test('resource completion requires each unselected Carrier prefix', () => {
  for (const carrier of ['Graph', 'Events', 'Vectors']) {
    assert.match(run(undefined, value => {
      value.mixed_paths = value.mixed_paths.filter(path =>
        path.carrier !== carrier);
    }, ['--require-boundary-complete']),
    new RegExp(`${carrier}: unselected prefix mixed-stage assurance is missing`));
  }
});

test('resource completion requires work and workspace proof independently', () => {
  assert.match(run(undefined, undefined, ['--require-boundary-complete']),
    /SGA normalize_graph: entrypoint work\/workspace assurance is missing/);
});

test('graph bounds retains both exact resource dimensions', () => {
  assert.match(run(undefined, routes => {
    const bounds = routes.routes.find(entry => entry.family === 'SGA' &&
      entry.operation === 'graph_bounds');
    delete bounds.resource_assurance.entrypoint.workspace;
  }), /SGA graph_bounds: entrypoint operation needs work and workspace assurance/);
});

test('graph bounds work evidence cannot disappear from its route', () => {
  assert.match(run(undefined, routes => {
    const bounds = routes.routes.find(entry => entry.family === 'SGA' &&
      entry.operation === 'graph_bounds');
    bounds.boundary_tests = bounds.boundary_tests.filter(item =>
      item.role !== 'graph_bounds_work_exact_one_short');
  }), /SGA graph_bounds: exact work boundary fixture is missing/);
});

test('degree control-work evidence cannot disappear from its route', () => {
  assert.match(run(undefined, routes => {
    const degree = routes.routes.find(entry => entry.family === 'SGA' &&
      entry.operation === 'degree');
    degree.boundary_tests = degree.boundary_tests.filter(item =>
      item.role !== 'degree_control_work_exact_one_short');
  }), /SGA degree: exact control-work boundary fixture is missing/);
});

test('degree value-work evidence cannot disappear from its route', () => {
  assert.match(run(undefined, routes => {
    const degree = routes.routes.find(entry => entry.family === 'SGA' &&
      entry.operation === 'degree');
    degree.boundary_tests = degree.boundary_tests.filter(item =>
      item.role !== 'degree_work_exact_one_short');
  }), /SGA degree: entrypoint operation work lacks an executable fixture/);
});

test('shortest path cannot lose its kernel cancellation evidence', () => {
  assert.match(run(undefined, routes => {
    const shortest = routes.routes.find(entry => entry.family === 'SGA' &&
      entry.operation === 'shortest_path');
    shortest.boundary_tests = shortest.boundary_tests.filter(item =>
      item.role !== 'shortest_kernel_cancel_cleanup');
  }), /SGA shortest_path: reviewed shortest_kernel_cancel_cleanup fixture is missing/);
});

test('resource completion cannot accept the synchronous providerless lane', () => {
  assert.match(run(undefined, undefined, ['--require-boundary-complete']),
    /providerless managed execution still computes and copies synchronously/);
});

test('cross join pre-execution close is not in-flight evidence', () => {
  assert.match(run(undefined, undefined, ['--require-boundary-complete']),
    /RelA cross_join: in-flight Host cancellation evidence is missing/);
});

test('selected take needs both keyed and unkeyed resource branches', () => {
  assert.match(run(undefined, value => {
    const take = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'take');
    delete take.resource_assurance.selected_entrypoint.variants.keyed;
  }), /RelA take: selected_entrypoint needs unkeyed and keyed resource variants/);
});

test('selected sort needs ordered and empty resource branches', () => {
  assert.match(run(undefined, value => {
    const sort = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'sort');
    delete sort.resource_assurance.selected_entrypoint.variants.empty;
  }), /RelA sort: selected_entrypoint needs ordered and empty resource variants/);
});

test('selected sort loses proof when its ordered work fixture is removed', () => {
  assert.match(run(undefined, value => {
    const sort = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'sort');
    sort.boundary_tests.find(item =>
      item.role === 'sort_ordered_work_exact_one_short').fixture =
      'missing-ordered-work-case';
  }), /RelA sort: missing operation boundary fixture missing-ordered-work-case/);
});

test('selected sort rejects an empty-branch proof from ordered sort', () => {
  assert.match(run(undefined, value => {
    const sort = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'sort');
    sort.resource_assurance.selected_entrypoint.variants.empty
      .workspace.one_short_limit = 'sort_ordered_workspace_one_short';
  }), /RelA sort: selected_entrypoint empty workspace lacks an executable fixture/);
});

test('selected take loses resource proof when a fixture is removed', () => {
  assert.match(run(undefined, value => {
    const take = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'take');
    take.boundary_tests.find(item =>
      item.role === 'take_unkeyed_workspace_exact_one_short').fixture =
      'missing-unkeyed-workspace-case';
  }), /RelA take: missing operation boundary fixture missing-unkeyed-workspace-case/);
});

test('selected take rejects a borrowed resource role', () => {
  assert.match(run(undefined, value => {
    const take = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'take');
    take.resource_assurance.selected_entrypoint.variants.unkeyed
      .workspace.one_short_limit = 'take_keyed_workspace_exact_one_short';
  }), /RelA take: selected_entrypoint unkeyed workspace lacks an executable fixture/);
});

test('resource gate rejects a borrowed work fixture', () => {
  assert.match(run(undefined, value => {
    const bounds = value.routes.find(entry => entry.family === 'SGA' &&
      entry.operation === 'graph_bounds');
    bounds.resource_assurance = {
      entrypoint: {
        work: {
          exact_limit: 'product_work_workspace_exact_one_short',
          one_short_limit: 'product_work_workspace_exact_one_short',
        },
        workspace: {
          exact_limit: 'graph_bounds_workspace_exact_one_short',
          one_short_limit: 'graph_bounds_workspace_exact_one_short',
        },
      },
    };
  }), /SGA graph_bounds: entrypoint operation work lacks an executable fixture/);
});

test('resource gate keeps assertion work proofs variant-specific', () => {
  assert.match(run(undefined, value => {
    const assertion = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'assert_rows');
    assertion.resource_assurance = {
      selected_entrypoint: {
        variants: {
          where: {
            work: {
              exact_limit: 'assert_where_input_exact',
              one_short_limit: 'assert_where_input_one_short',
            },
            workspace: {
              exact_limit: 'assert_where_input_exact',
              one_short_limit: 'assert_where_input_one_short',
            },
          },
        },
      },
    };
  }), /RelA assert_rows: selected_entrypoint needs both assertion resource variants/);
});

test('resource completion rejects every unassured operation', () => {
  assert.match(run(undefined, undefined, ['--require-boundary-complete']),
    /RelA filter: entrypoint boundary assurance is missing/);
});

test('resource completion also rejects an unassured SGA route', () => {
  assert.match(run(undefined, undefined, ['--require-boundary-complete']),
    /SGA shortest_path: entrypoint boundary assurance is missing/);
});

test('resource completion requires the selected sort proof set', () => {
  assert.match(run(undefined, value => {
    const sort = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'sort');
    delete sort.path_assurance.selected_entrypoint;
  }, ['--require-boundary-complete']),
  /RelA sort: selected_entrypoint boundary assurance is missing/);
});

test('resource completion requires the selected take proof set', () => {
  assert.match(run(undefined, value => {
    const take = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'take');
    delete take.path_assurance.selected_entrypoint;
  }, ['--require-boundary-complete']),
  /RelA take: selected_entrypoint boundary assurance is missing/);
});

test('resource completion rejects borrowed proof roles on another route', () => {
  assert.match(run(undefined, value => {
    const path = value.routes.find(entry => entry.family === 'SGA' &&
      entry.operation === 'shortest_path');
    path.path_assurance = {
      entrypoint: {
        exact_limit: 'select_input_exact',
        one_short_limit: 'select_input_one_short',
        in_flight_cancel: 'select_in_flight_host_timer',
        cleanup: 'select_cancel_cleanup',
      },
    };
  }, ['--require-boundary-complete']),
  /SGA shortest_path: entrypoint exact_limit lacks an executable fixture/);
});

test('resource completion requires every registered selection path', () => {
  assert.match(run(undefined, value => {
    const selection = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'select');
    selection.path_assurance.entrypoint =
      selection.path_assurance.selected_entrypoint;
  }, ['--require-boundary-complete']),
  /RelA select: shared proof reuse lacks an exact common entrypoint/);
});

test('resource gate rejects reuse justified by a different entrypoint', () => {
  assert.match(run(undefined, value => {
    const selection = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'select');
    selection.path_assurance.entrypoint =
      selection.path_assurance.selected_entrypoint;
    selection.shared_proof_reuse = [
      'select_input_exact',
      'select_input_one_short',
      'select_in_flight_host_timer',
      'select_cancel_cleanup',
    ].map(role => ({
      role,
      paths: ['entrypoint', 'selected_entrypoint'],
      reason: 'Both paths are claimed to share all resource behavior.',
    }));
  }), /RelA select: shared proof reuse lacks an exact common entrypoint/);
});

test('resource completion rejects incomplete path assurance', () => {
  assert.match(run(undefined, value => {
    const selection = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'select');
    delete selection.path_assurance.ordinary_entrypoint;
  }, ['--require-boundary-complete']),
  /RelA select: ordinary_entrypoint boundary assurance is missing/);
});

test('ordinary select requires its delivered Host cancellation fixture', () => {
  assert.match(run(undefined, value => {
    const selection = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'select');
    selection.environment_tests = selection.environment_tests.filter(item =>
      item.role !== 'ordinary_select_in_flight_host_timer');
  }), /RelA select: ordinary_entrypoint in_flight_cancel lacks an executable fixture/);
});

test('ordinary filter requires its delivered Host cancellation fixture', () => {
  assert.match(run(undefined, value => {
    const filter = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'filter');
    filter.environment_tests = filter.environment_tests.filter(item =>
      item.role !== 'ordinary_filter_in_flight_host_timer');
  }), /RelA filter: ordinary_entrypoint in_flight_cancel lacks an executable fixture/);
});

test('ordinary sort and take require delivered Host cancellation', () => {
  for (const [operation, role] of [
    ['sort', 'ordinary_sort_in_flight_host_timer'],
    ['take', 'ordinary_take_in_flight_host_timer'],
  ]) {
    assert.match(run(undefined, value => {
      const route = value.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === operation);
      route.environment_tests = route.environment_tests.filter(item =>
        item.role !== role);
    }), new RegExp(
      `RelA ${operation}: ordinary_entrypoint in_flight_cancel lacks an executable fixture`,
    ));
  }
});

test('ordinary sort and take retain their exact resource variants', () => {
  for (const [operation, variant] of [
    ['sort', 'empty'], ['take', 'keyed'],
  ]) {
    assert.match(run(undefined, value => {
      const route = value.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === operation);
      delete route.resource_assurance.ordinary_entrypoint.variants[variant];
    }), new RegExp(`RelA ${operation}: ordinary_entrypoint needs`));
  }
});

test('resource gate rejects a false in-flight assurance', () => {
  assert.match(run(undefined, value => {
    const filter = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'filter');
    filter.path_assurance.selected_entrypoint.in_flight_cancel =
      'filter_cancel_cleanup';
  }), /RelA filter: selected_entrypoint in_flight_cancel lacks an executable fixture/);
});

test('resource gate rejects selected assurance without its product route', () => {
  assert.match(run(undefined, value => {
    const filter = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'filter');
    delete filter.selected_entrypoint;
  }), /RelA filter: assurance names an unregistered production path/);
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

test('resource gate rejects missing SGA normalization boundary evidence', () => {
  assert.match(run(undefined, value => {
    const normalization = value.routes.find(entry =>
      entry.family === 'SGA' && entry.operation === 'normalize_graph');
    normalization.boundary_tests[0].fixture = 'missing exact node capacity';
  }), /SGA normalize_graph: missing operation boundary fixture/);
});

test('resource gate rejects a removed SGA normalization proof role', () => {
  assert.match(run(undefined, value => {
    const normalization = value.routes.find(entry =>
      entry.family === 'SGA' && entry.operation === 'normalize_graph');
    normalization.boundary_tests = normalization.boundary_tests.filter(item =>
      item.role !== 'normalize_one_short_node_capacity');
  }), /SGA normalize_graph: reviewed normalize_one_short_node_capacity fixture is missing/);
});

test('resource gate rejects a missing normalization edge limit', () => {
  assert.match(run(undefined, value => {
    const normalization = value.routes.find(entry =>
      entry.family === 'SGA' && entry.operation === 'normalize_graph');
    normalization.boundary_tests = normalization.boundary_tests.filter(item =>
      item.role !== 'normalize_view_one_short_edge_capacity');
  }), /SGA normalize_graph: reviewed normalize_view_one_short_edge_capacity fixture is missing/);
});

test('resource gate requires the normalization managed-view route', () => {
  assert.match(run(undefined, value => {
    const normalization = value.routes.find(entry =>
      entry.family === 'SGA' && entry.operation === 'normalize_graph');
    delete normalization.selected_entrypoint;
  }), /SGA normalize_graph: managed-view production route is missing/);
});

test('resource gate rejects normalization without its Host timer', () => {
  assert.match(run(undefined, value => {
    const normalization = value.routes.find(entry =>
      entry.family === 'SGA' && entry.operation === 'normalize_graph');
    normalization.environment_tests = [];
  }), /SGA normalize_graph: selected_entrypoint in_flight_cancel lacks an executable fixture/);
});

test('resource gate rejects normalization without fused Host cancellation', () => {
  assert.match(run(undefined, value => {
    const normalization = value.routes.find(entry =>
      entry.family === 'SGA' && entry.operation === 'normalize_graph');
    normalization.environment_tests = normalization.environment_tests.filter(
      item => item.role !== 'normalize_fused_in_flight_host_timer');
  }), /SGA normalize_graph: entrypoint in_flight_cancel lacks an executable fixture/);
});

test('resource gate rejects graph diagnostics without Host cancellation', () => {
  assert.match(run(undefined, value => {
    const bounds = value.routes.find(entry => entry.family === 'SGA' &&
      entry.operation === 'graph_bounds');
    bounds.environment_tests = [];
  }), /SGA graph_bounds: entrypoint in_flight_cancel lacks an executable fixture/);
});

test('resource gate rejects an ordered take without its cancellation fixture', () => {
  assert.match(run(undefined, value => {
    const take = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'take');
    take.boundary_tests = take.boundary_tests.filter(item =>
      item.role !== 'mixed_stage_sort_cancel_and_cleanup');
  }), /RelA take: reviewed mixed_stage_sort_cancel_and_cleanup fixture is missing/);
});

test('resource gate rejects take without ordinary quantum evidence', () => {
  assert.match(run(undefined, value => {
    const take = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'take');
    take.boundary_tests = take.boundary_tests.filter(item =>
      item.role !== 'ordinary_take_quantum_and_lifetime');
  }), /RelA take: reviewed ordinary_take_quantum_and_lifetime fixture is missing/);
});

test('resource gate rejects take without its ordinary product route', () => {
  assert.match(run(undefined, value => {
    const take = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'take');
    delete take.ordinary_entrypoint;
  }), /RelA take: bounded selected and ordinary entrypoints are required/);
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

test('resource gate rejects cross join without delivered Host cancellation', () => {
  assert.match(run(undefined, value => {
    const join = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'cross_join');
    join.environment_tests.find(item =>
      item.role === 'external_product_node_timer_cancel_cleanup').fixture =
      'missing-external-cross-join-timer';
  }), /RelA cross_join: missing environment fixture/);
});

test('resource gate retains the providerless row-copy timer fixture', () => {
  assert.match(run(undefined, value => {
    const join = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'cross_join');
    join.environment_tests = join.environment_tests.filter(item =>
      item.role !== 'providerless_cross_join_copy_host_timer');
  }), /RelA cross_join: providerless row-copy timer fixture is missing/);
});

test('resource gate requires mixed-stage cross join execution evidence', () => {
  assert.match(run(undefined, value => {
    const join = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'cross_join');
    join.boundary_tests = join.boundary_tests.filter(item =>
      item.role !== 'external_product_mixed_stage_two_consumers');
  }), /RelA cross_join: reviewed external_product_mixed_stage_two_consumers fixture is missing/);
  assert.match(run(undefined, value => {
    const join = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'cross_join');
    join.environment_tests = join.environment_tests.filter(item =>
      item.role !== 'external_product_mixed_stage_timer_cancel_cleanup');
  }), /RelA cross_join: mixed-stage timer cancellation fixture is missing/);
});

test('resource gate rejects an unbound external cross join work proof', () => {
  assert.match(run(undefined, value => {
    const join = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'cross_join');
    join.resource_assurance.external_input_entrypoint.work.exact_limit =
      'missing-external-work-proof';
  }), /RelA cross_join: external_input_entrypoint operation work lacks an executable fixture/);
});

test('resource gate rejects sort without mixed-stage evidence', () => {
  assert.match(run(undefined, value => {
    const sort = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'sort');
    sort.boundary_tests = sort.boundary_tests.filter(item =>
      item.role !== 'mixed_stage_sort_quantum_and_lifetime');
  }), /RelA sort: reviewed mixed_stage_sort_quantum_and_lifetime fixture is missing/);
});

test('resource gate rejects sort without ordinary quantum evidence', () => {
  assert.match(run(undefined, value => {
    const sort = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'sort');
    sort.boundary_tests = sort.boundary_tests.filter(item =>
      item.role !== 'ordinary_sort_quantum_and_lifetime');
  }), /RelA sort: reviewed ordinary_sort_quantum_and_lifetime fixture is missing/);
});

test('resource gate rejects sort without its real Host timer case', () => {
  assert.match(run(undefined, value => {
    const sort = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'sort');
    sort.environment_tests = [];
  }), /RelA sort: selected sort Host timer evidence is missing/);
});

test('resource gate rejects sort without its one-short workspace proof', () => {
  assert.match(run(undefined, value => {
    const sort = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'sort');
    sort.boundary_tests = sort.boundary_tests.filter(item =>
      item.role !== 'selected_sort_workspace_one_short');
  }), /RelA sort: reviewed selected_sort_workspace_one_short fixture is missing/);
});

test('resource gate rejects sort without its selected product entrypoint', () => {
  assert.match(run(undefined, value => {
    const sort = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'sort');
    delete sort.selected_entrypoint;
  }), /RelA sort: bounded selected sort entrypoint is missing/);
});

test('resource gate rejects sort without its ordinary product entrypoint', () => {
  assert.match(run(undefined, value => {
    const sort = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'sort');
    delete sort.ordinary_entrypoint;
  }), /RelA sort: bounded ordinary sort entrypoint is missing/);
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
  }), /RelA assert_rows: selected and ordinary assertion forms must reach production/);
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

test('resource gate rejects mixed assertion-variant proof roles', () => {
  assert.match(run(undefined, value => {
    const assertion = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'assert_rows');
    assertion.path_assurance.selected_entrypoint.variants.where.in_flight_cancel =
      'assert_unique_in_flight_host_timer';
  }), /RelA assert_rows: selected_entrypoint where in_flight_cancel uses another variant's proof/);
});

test('resource gate rejects an omitted assertion variant', () => {
  assert.match(run(undefined, value => {
    const assertion = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'assert_rows');
    delete assertion.path_assurance.selected_entrypoint.variants.unique_by;
  }), /RelA assert_rows: selected_entrypoint assertion variants need separate proof sets/);
});

test('resource gate rejects flat assertion assurance', () => {
  assert.match(run(undefined, value => {
    const assertion = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'assert_rows');
    assertion.path_assurance.selected_entrypoint =
      assertion.path_assurance.selected_entrypoint.variants.where;
  }), /RelA assert_rows: selected_entrypoint assertion variants need separate proof sets/);
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

test('resource gate rejects filter without ordinary quantum evidence', () => {
  assert.match(run(undefined, value => {
    const filter = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'filter');
    filter.boundary_tests = filter.boundary_tests.filter(item =>
      item.role !== 'ordinary_filter_quantum_and_lifetime');
  }), /RelA filter: reviewed ordinary_filter_quantum_and_lifetime fixture is missing/);
});

test('resource gate rejects filter without its ordinary product route', () => {
  assert.match(run(undefined, value => {
    const filter = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'filter');
    delete filter.ordinary_entrypoint;
  }), /RelA filter: bounded ordinary entrypoint is missing/);
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

test('resource gate rejects selection without ordinary quantum evidence', () => {
  assert.match(run(undefined, value => {
    const selection = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'select');
    selection.boundary_tests = selection.boundary_tests.filter(item =>
      item.role !== 'ordinary_select_quantum_and_lifetime');
  }), /RelA select: reviewed ordinary_select_quantum_and_lifetime fixture is missing/);
});

test('resource gate rejects selection without ordinary product route', () => {
  assert.match(run(undefined, value => {
    const selection = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'select');
    delete selection.ordinary_entrypoint;
  }), /RelA select: bounded ordinary entrypoint is missing/);
});

test('resource gate rejects selection without delivered Host cancellation', () => {
  assert.match(run(undefined, value => {
    const selection = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'select');
    selection.environment_tests = [];
  }), /RelA select: in-flight Host cancellation fixture is missing/);
});

test('resource gate rejects rename without its ordinary evidence', () => {
  assert.match(run(undefined, value => {
    const rename = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'rename');
    rename.boundary_tests = [];
  }), /RelA rename: reviewed ordinary_rename_quantum_and_lifetime fixture is missing/);
});

test('resource gate rejects drop without its bounded entrypoint', () => {
  assert.match(run(undefined, value => {
    const drop = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'drop');
    delete drop.ordinary_entrypoint;
  }), /RelA drop: bounded ordinary entrypoint is missing/);
});

test('resource gate rejects derive without its ordinary bounded route', () => {
  assert.match(run(undefined, value => {
    const derive = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'derive');
    delete derive.ordinary_entrypoint;
  }), /RelA derive: bounded ordinary entrypoint is missing/);
  assert.match(run(undefined, value => {
    const derive = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'derive');
    derive.boundary_tests = [];
  }), /RelA derive: reviewed ordinary_derive_quantum_and_lifetime fixture is missing/);
  assert.match(run(undefined, value => {
    const derive = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'derive');
    derive.environment_tests = [];
  }), /RelA derive: ordinary derive Host timer evidence is missing/);
});

test('resource gate rejects assertions without ordinary bounded evidence', () => {
  assert.match(run(undefined, value => {
    const assertion = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'assert_rows');
    delete assertion.ordinary_entrypoint;
  }), /RelA assert_rows: selected and ordinary assertion forms must reach production/);
  assert.match(run(undefined, value => {
    const assertion = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'assert_rows');
    assertion.boundary_tests = assertion.boundary_tests.filter(item =>
      item.role !== 'ordinary_assert_unique_quantum_and_lifetime');
  }), /RelA assert_rows: reviewed ordinary_assert_unique_quantum_and_lifetime fixture is missing/);
  assert.match(run(undefined, value => {
    const assertion = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'assert_rows');
    assertion.environment_tests = assertion.environment_tests.filter(item =>
      item.role !== 'assert_where_ordinary_in_flight_host_timer');
  }), /RelA assert_rows: assert_where_ordinary_in_flight_host_timer fixture is missing/);
  assert.match(run(undefined, value => {
    const assertion = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'assert_rows');
    assertion.boundary_tests = assertion.boundary_tests.filter(item =>
      item.role !== 'assert_unique_work_workspace_exact_one_short');
  }), /RelA assert_rows: ordinary_entrypoint unique_by work lacks an executable fixture/);
  assert.match(run(undefined, value => {
    const assertion = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'assert_rows');
    assertion.boundary_tests = assertion.boundary_tests.filter(item =>
      item.role !== 'assert_unique_values_split_lifetime');
  }), /RelA assert_rows: reviewed assert_unique_values_split_lifetime fixture is missing/);
  assert.match(run(undefined, value => {
    const assertion = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'assert_rows');
    assertion.environment_tests = assertion.environment_tests.filter(item =>
      item.role !== 'assert_unique_values_split_host_timer');
  }), /RelA assert_rows: assert_unique_values_split_host_timer fixture is missing/);
  assert.match(run(undefined, value => {
    const assertion = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'assert_rows');
    delete assertion.resource_assurance.ordinary_entrypoint.variants.where;
  }), /RelA assert_rows: ordinary_entrypoint needs both assertion resource variants/);
});
