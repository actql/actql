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

function run(mutator, routeMutator, args = [], gapsText) {
  const manifest = JSON.parse(readFileSync(source, 'utf8'));
  mutator?.(manifest);
  const directory = mkdtempSync(join(tmpdir(), 'actql-resource-audit-'));
  let gapsTarget;
  if (gapsText !== undefined) {
    gapsTarget = join(directory, 'gaps.md');
    writeFileSync(gapsTarget, gapsText);
  }
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
      env: {
        ...process.env,
        ACTQL_LOCAL_RESOURCE_AUDIT: target,
        ...(gapsTarget ? {ACTQL_LOCAL_RESOURCE_GAPS: gapsTarget} : {}),
      },
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (error) {
    return String(error.stderr);
  }
}

test('resource gate accepts every normative Local operation', () => {
  assert.match(run(), /68 operations, 5 implementation profiles, 68 production routes mapped, 57 with operation-specific boundary records, 22 with four-role boundary evidence, 22 with full work\/workspace assurance, 47 with path-scoped work\/workspace evidence, 0 with selected-only assurance; full boundary completion is not asserted/);
});

test('generated sequence operators reject missing fixed work evidence', () => {
  for (const operation of ['group', 'pivot', 'unpivot', 'unnest']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === operation);
      route.boundary_tests = [];
    }), new RegExp(`RelA ${operation}: fixed sequence work evidence is missing`, 'u'));
  }
});

test('lag loses its schema workspace boundary when the fixture is removed', () => {
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'lag');
    route.boundary_tests = [];
  }), /RelA lag: lag schema workspace evidence is missing/u);
});

test('rows-to-Graph Bridge loses its boundary when either fixture is removed', () => {
  for (const role of [
    'graph_bridge_work_workspace_exact_one_short_and_kernel_cancel_cleanup',
    'graph_bridge_two_consumer_lifetime',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'Bridge' &&
        entry.operation === 'graph');
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), /Bridge graph: rows-to-Graph Bridge boundary evidence is missing/u);
  }
});

test('vector expressions lose their operation boundary when evidence is removed', () => {
  for (const operation of ['vector_score', 'vector_concat']) {
    for (const role of [
      `${operation}_derive_work_workspace_exact_one_short`,
      `${operation}_derive_cancel_cleanup`,
    ]) {
      assert.match(run(undefined, routes => {
        const route = routes.routes.find(entry =>
          entry.family === 'VecAExpression' && entry.operation === operation);
        route.boundary_tests = route.boundary_tests.filter(item =>
          item.role !== role);
      }), new RegExp(`VecAExpression ${operation}: vector expression boundary evidence is missing`, 'u'));
    }
  }
});

test('ranking loses bounded assembly evidence when its fixture is removed', () => {
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'merge_rankings');
    route.boundary_tests = route.boundary_tests.filter(item =>
      item.role !== 'ranking_bounded_record_output_cancel_cleanup');
  }), /VecA merge_rankings: bounded ranking assembly fixture is missing/u);
});

test('graph matching loses control work evidence when either fixture is removed', () => {
  for (const operation of ['match_nodes', 'match_edges']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === operation);
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== `${operation}_control_work_exact_one_short`);
    }), new RegExp(`SGA ${operation}: match control work evidence is missing`, 'u'));
  }
});

test('edge matching loses bounded type-index evidence without its fixture', () => {
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'SGA' &&
      entry.operation === 'match_edges');
    route.boundary_tests = route.boundary_tests.filter(item =>
      item.role !== 'match_edges_type_index_quantum_workspace_cancel');
  }), /SGA match_edges: bounded type-index evidence is missing/u);
});

test('Graph equality requires its control-work and nested comparison fixtures', () => {
  for (const role of [
    'graphs_equal_control_work_exact_one_short_and_cancel',
    'graphs_equal_nested_value_work_ceiling',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === 'graphs_equal');
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), /SGA graphs_equal: Graph equality control-work evidence is missing/u);
  }
});

test('components requires empty and nonempty boundary fixtures', () => {
  for (const role of [
    'components_empty_exact_work_workspace_cancel_cleanup',
    'components_nonempty_work_ceiling_and_active_cancel',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === 'components');
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), /SGA components: components boundary evidence is missing/u);
  }
});

test('reach and node traversal require shared control-work evidence', () => {
  for (const [operation, role, diagnostic] of [
    ['reach', 'reach_prefix_work_workspace_active_cancel',
      /SGA reach: reach control-work evidence is missing/u],
    ['traverse', 'node_emit_control_work_ceiling',
      /SGA traverse: traversal work evidence is missing/u],
    ['traverse', 'path_emit_control_work_ceiling',
      /SGA traverse: traversal work evidence is missing/u],
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === operation);
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), diagnostic);
  }
});

test('Graph diff requires the output-tail work fixture', () => {
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'SGA' &&
      entry.operation === 'graph_diff');
    route.boundary_tests = [];
  }), /SGA graph_diff: Graph diff tail-work evidence is missing/u);
});

test('Graph mean requires its cumulative-work fixture', () => {
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'SGA' &&
      entry.operation === 'mean_graphs');
    route.boundary_tests = [];
  }), /SGA mean_graphs: Graph mean cumulative-work evidence is missing/u);
});

test('structural Graph modes each require a reached work fixture', () => {
  for (const operation of ['graft_graph', 'union_graphs', 'subtract_graphs']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === operation);
      route.boundary_tests = [];
    }), new RegExp(`SGA ${operation}: structural Graph cumulative-work evidence is missing`, 'u'));
  }
});

test('resource summary rejects stale route counts', () => {
  const gaps = readFileSync(join(
    root, 'docs/reviews/2026-09-19-sga-veca-tea-local-gaps.md',
  ), 'utf8');
  const stale = gaps.replace(
    '| Path-scoped work/workspace assurance | 47 |',
    '| Path-scoped work/workspace assurance | 46 |',
  );
  assert.notEqual(stale, gaps);
  assert.match(
    run(undefined, undefined, ['--check-summary'], stale),
    /resource gaps ledger summary is stale/,
  );
});

test('sequence loses assurance without its independent work fixture', () => {
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'sequence');
    route.boundary_tests = route.boundary_tests.filter(test =>
      test.role !== 'sequence_work_exact_one_short');
  }), /TEA sequence: entrypoint operation work lacks an executable fixture/u);
});

test('Events projection loses its boundary evidence when the fixture is removed', () => {
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'Bridge' &&
      entry.operation === 'events');
    route.boundary_tests = [];
  }), /Bridge events: Events projection boundary fixture is missing/u);
});

test('Vectors projection loses its boundary evidence when the fixture is removed', () => {
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'Bridge' &&
      entry.operation === 'vectors');
    route.boundary_tests = [];
  }), /Bridge vectors: Vectors projection boundary fixture is missing/u);
});

test('reverse Bridge routes require delivered Host cancellation evidence', () => {
  for (const [operation, label] of [
    ['events', 'Events'],
    ['vectors', 'Vectors'],
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'Bridge' &&
        entry.operation === operation);
      route.environment_tests = [];
    }), new RegExp(`Bridge ${operation}: ${label} projection Host cancellation fixture is missing`, 'u'));
  }
});

test('sequence retains product cancellation and cleanup evidence', () => {
  for (const role of [
    'sequence_quantum_one_output_and_cleanup',
    'sequence_in_flight_cancel_cleanup',
    'sequence_output_limit_cleanup',
    'sequence_column_resolution_work_independent_exact_one_short',
    'sequence_wide_init_cancel_cleanup',
    'sequence_workspace_exact_one_short',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'TEA' &&
        entry.operation === 'sequence');
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`TEA sequence: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'sequence');
    route.environment_tests = [];
  }), /TEA sequence: sequence_host_in_flight_cancel fixture is missing/);
});

test('session Events view retains exact limits and delivered cancellation', () => {
  const role = 'session_view_work_workspace_exact_one_short';
  assert.match(run(undefined, routes => {
    const session = routes.routes.find(entry =>
      entry.family === 'TEA' && entry.operation === 'session');
    session.boundary_tests = session.boundary_tests.filter(item =>
      item.role !== role);
  }), /TEA session: view_entrypoint exact_limit lacks an executable fixture/);
  assert.match(run(undefined, routes => {
    const session = routes.routes.find(entry =>
      entry.family === 'TEA' && entry.operation === 'session');
    session.environment_tests = [];
  }), /TEA session: view_entrypoint in_flight_cancel lacks an executable fixture/);
  for (const dimension of ['work', 'workspace']) {
    for (const limit of ['exact_limit', 'one_short_limit']) {
      assert.match(run(undefined, routes => {
        const session = routes.routes.find(entry =>
          entry.family === 'TEA' && entry.operation === 'session');
        delete session.resource_assurance.view_entrypoint[dimension][limit];
      }), new RegExp(
        `TEA session: view_entrypoint operation ${dimension} needs exact and one-short proofs`,
      ));
    }
  }
});

test('fused session retains distinct limits and delivered cancellation', () => {
  for (const role of [
    'session_control_work_exact_one_short',
    'session_output_workspace_exact_one_short',
  ]) {
    assert.match(run(undefined, routes => {
      const session = routes.routes.find(entry =>
        entry.family === 'TEA' && entry.operation === 'session');
      session.boundary_tests = session.boundary_tests.filter(item =>
        item.role !== role);
    }), /TEA session: entrypoint .* lacks an executable fixture/u);
  }
  assert.match(run(undefined, routes => {
    const session = routes.routes.find(entry =>
      entry.family === 'TEA' && entry.operation === 'session');
    session.environment_tests = session.environment_tests.filter(item =>
      item.role !== 'session_host_timer');
  }), /TEA session: entrypoint in_flight_cancel lacks an executable fixture/u);
});

test('session Relation path retains separate Host and resource evidence', () => {
  const role = 'session_relation_work_workspace_exact_one_short';
  assert.match(run(undefined, routes => {
    const session = routes.routes.find(entry =>
      entry.family === 'TEA' && entry.operation === 'session');
    session.boundary_tests = session.boundary_tests.filter(item =>
      item.role !== role);
  }), /TEA session: relation_entrypoint exact_limit lacks an executable fixture/);
  assert.match(run(undefined, routes => {
    const session = routes.routes.find(entry =>
      entry.family === 'TEA' && entry.operation === 'session');
    session.environment_tests = session.environment_tests.filter(item =>
      item.role !== 'session_relation_host_timer');
  }), /TEA session: relation_entrypoint in_flight_cancel lacks an executable fixture/);
  for (const dimension of ['work', 'workspace']) {
    for (const limit of ['exact_limit', 'one_short_limit']) {
      assert.match(run(undefined, routes => {
        const session = routes.routes.find(entry =>
          entry.family === 'TEA' && entry.operation === 'session');
        delete session.resource_assurance.relation_entrypoint[dimension][limit];
      }), new RegExp(
        `TEA session: relation_entrypoint operation ${dimension} needs exact and one-short proofs`,
      ));
    }
  }
});

test('temporal joins retain delivered Host cancellation evidence', () => {
  for (const operation of ['interval_join', 'asof_join']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'TEA' &&
        entry.operation === operation);
      route.environment_tests = [];
    }), new RegExp(`TEA ${operation}: ${operation}_host_in_flight_cancel fixture is missing`, 'u'));
  }
});

test('temporal joins retain exact output workspace evidence', () => {
  for (const [operation, prefix] of [
    ['interval_join', 'interval'],
    ['asof_join', 'asof'],
  ]) {
    const role = `${prefix}_output_workspace_exact_one_short`;
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'TEA' &&
        entry.operation === operation);
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`TEA ${operation}: ${role} fixture is missing`, 'u'));
  }
});

test('temporal joins retain work and kernel cleanup evidence', () => {
  for (const [operation, prefix] of [
    ['interval_join', 'interval'],
    ['asof_join', 'asof'],
  ]) {
    for (const role of [
      `${prefix}_work_exact_one_short`,
      `${prefix}_kernel_cancel_cleanup`,
    ]) {
      assert.match(run(undefined, routes => {
        const route = routes.routes.find(entry => entry.family === 'TEA' &&
          entry.operation === operation);
        route.boundary_tests = route.boundary_tests.filter(item =>
          item.role !== role);
      }), new RegExp(`TEA ${operation}: ${role} fixture is missing`, 'u'));
    }
  }
});

test('time-series output and Host cancellation evidence must remain bound', () => {
  assert.match(run(undefined, routes => {
    const series = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'time_series');
    series.boundary_tests = series.boundary_tests.filter(item =>
      item.role !== 'time_series_output_exact_one_short_and_finish_work');
  }), /TEA time_series: time_series_output_exact_one_short_and_finish_work fixture is missing/);
  assert.match(run(undefined, routes => {
    const series = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'time_series');
    series.boundary_tests = series.boundary_tests.filter(item =>
      item.role !== 'time_series_output_value_work_exact_one_short');
  }), /TEA time_series: time_series_output_value_work_exact_one_short fixture is missing/);
  for (const role of [
    'time_series_control_work_exact_one_short',
    'time_series_schema_workspace_exact_one_short',
  ]) {
    assert.match(run(undefined, routes => {
      const series = routes.routes.find(entry => entry.family === 'TEA' &&
        entry.operation === 'time_series');
      series.boundary_tests = series.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`TEA time_series: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const series = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'time_series');
    series.environment_tests = [];
  }), /TEA time_series: time_series_host_timer fixture is missing/);
});

test('session initialization and Host timer evidence must remain executable', () => {
  assert.match(run(undefined, routes => {
    const session = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'session');
    session.boundary_tests = [];
  }), /TEA session: session_incremental_initialization_cancel_cleanup fixture is missing/);
  assert.match(run(undefined, routes => {
    const session = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'session');
    session.environment_tests = [];
  }), /TEA session: session_host_timer fixture is missing/);
  assert.match(run(undefined, routes => {
    const session = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'session');
    session.boundary_tests = session.boundary_tests.filter(item =>
      item.role !== 'session_control_work_exact_one_short');
  }), /TEA session: session_control_work_exact_one_short fixture is missing/);
  assert.match(run(undefined, routes => {
    const session = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'session');
    session.boundary_tests = session.boundary_tests.filter(item =>
      item.role !== 'session_output_workspace_exact_one_short');
  }), /TEA session: session_output_workspace_exact_one_short fixture is missing/);
  for (const role of [
    'session_relation_work_workspace_exact_one_short',
    'session_view_work_workspace_exact_one_short',
  ]) {
    assert.match(run(undefined, routes => {
      const session = routes.routes.find(entry => entry.family === 'TEA' &&
        entry.operation === 'session');
      session.boundary_tests = session.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`TEA session: ${role} fixture is missing`, 'u'));
  }
  for (const source of ['relation_entrypoint', 'view_entrypoint']) {
    assert.match(run(undefined, routes => {
      const session = routes.routes.find(entry => entry.family === 'TEA' &&
        entry.operation === 'session');
      delete session[source];
    }), /TEA session: all three session source entrypoints must be registered/);
  }
});

test('dedupe initialization and Host timer evidence must remain executable', () => {
  assert.match(run(undefined, routes => {
    const dedupe = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'dedupe_events');
    dedupe.boundary_tests = dedupe.boundary_tests.filter(item =>
      item.role !== 'dedupe_incremental_initialization_cancel_cleanup');
  }), /TEA dedupe_events: dedupe_incremental_initialization_cancel_cleanup fixture is missing/);
  assert.match(run(undefined, routes => {
    const dedupe = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'dedupe_events');
    dedupe.environment_tests = [];
  }), /TEA dedupe_events: dedupe_host_timer fixture is missing/);
  for (const role of [
    'dedupe_control_work_exact_one_short',
    'dedupe_output_workspace_exact_one_short',
  ]) {
    assert.match(run(undefined, routes => {
      const dedupe = routes.routes.find(entry => entry.family === 'TEA' &&
        entry.operation === 'dedupe_events');
      dedupe.boundary_tests = dedupe.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`TEA dedupe_events: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const dedupe = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'dedupe_events');
    delete dedupe.resource_assurance.entrypoint.work.one_short_limit;
  }), /TEA dedupe_events: entrypoint operation work needs exact and one-short proofs/);
  assert.match(run(undefined, routes => {
    const dedupe = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'dedupe_events');
    delete dedupe.path_assurance.entrypoint;
  }), /TEA dedupe_events: work, workspace, and lifecycle assurance is missing/);
});

test('watermark resource and Host evidence must remain executable', () => {
  assert.match(run(undefined, routes => {
    const watermark = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'watermark_events');
    watermark.boundary_tests = watermark.boundary_tests.filter(item =>
      item.role !== 'watermark_control_work_exact_one_short');
  }), /TEA watermark_events: watermark_control_work_exact_one_short fixture is missing/);
  assert.match(run(undefined, routes => {
    const watermark = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'watermark_events');
    watermark.boundary_tests = watermark.boundary_tests.filter(item =>
      item.role !== 'watermark_empty_finish_work_exact_one_short');
  }), /TEA watermark_events: watermark_empty_finish_work_exact_one_short fixture is missing/);
  assert.match(run(undefined, routes => {
    const watermark = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'watermark_events');
    watermark.environment_tests = [];
  }), /TEA watermark_events: watermark_host_timer fixture is missing/);
  assert.match(run(undefined, routes => {
    const watermark = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'watermark_events');
    delete watermark.resource_assurance.entrypoint.workspace.one_short_limit;
  }), /TEA watermark_events: entrypoint operation workspace needs exact and one-short proofs/);
  assert.match(run(undefined, routes => {
    const watermark = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'watermark_events');
    delete watermark.path_assurance.entrypoint;
  }), /TEA watermark_events: work, workspace, and lifecycle assurance is missing/);
});

test('event window work, workspace, and Host evidence must remain executable', () => {
  assert.match(run(undefined, routes => {
    const window = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'window_events');
    window.boundary_tests.find(item =>
      item.role === 'window_control_work_exact_one_short').fixture =
      'missing-window-control-work';
  }), /TEA window_events: missing operation boundary fixture missing-window-control-work/);
  assert.match(run(undefined, routes => {
    const window = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'window_events');
    window.boundary_tests = window.boundary_tests.filter(item =>
      item.role !== 'window_workspace_exact_one_short');
  }), /TEA window_events: window_workspace_exact_one_short fixture is missing/);
  assert.match(run(undefined, routes => {
    const window = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'window_events');
    window.boundary_tests = window.boundary_tests.filter(item =>
      item.role !== 'window_empty_finish_work_exact_one_short');
  }), /TEA window_events: window_empty_finish_work_exact_one_short fixture is missing/);
  assert.match(run(undefined, routes => {
    const window = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'window_events');
    window.environment_tests = window.environment_tests.filter(item =>
      item.role !== 'window_sliding_host_timer');
  }), /TEA window_events: window_sliding_host_timer fixture is missing/);
  assert.match(run(undefined, routes => {
    const window = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'window_events');
    delete window.resource_assurance.entrypoint.workspace.one_short_limit;
  }), /TEA window_events: entrypoint operation workspace needs exact and one-short proofs/);
  assert.match(run(undefined, routes => {
    const window = routes.routes.find(entry => entry.family === 'TEA' &&
      entry.operation === 'window_events');
    delete window.path_assurance.entrypoint;
  }), /TEA window_events: fixed and sliding work, workspace, and lifecycle assurance is missing/);
});

test('global top-k loses its bounded ordinary evidence when removed', () => {
  assert.match(run(undefined, routes => {
    const topK = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'top_k');
    topK.boundary_tests.find(item =>
      item.role === 'top_k_work_workspace_exact_one_short').fixture =
      'missing-top-k-boundary';
  }), /RelA top_k: missing operation boundary fixture missing-top-k-boundary/);
  assert.match(run(undefined, routes => {
    const topK = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'top_k');
    topK.environment_tests = [];
  }), /RelA top_k: ordinary_entrypoint in_flight_cancel lacks an executable fixture/);
});

test('subgraph literal control-work evidence must remain executable', () => {
  assert.match(run(undefined, routes => {
    const subgraph = routes.routes.find(entry => entry.family === 'SGA' &&
      entry.operation === 'subgraph');
    subgraph.boundary_tests.find(item =>
      item.role === 'subgraph_literal_control_work_exact_one_short').fixture =
      'missing-subgraph-control-work';
  }), /SGA subgraph: missing operation boundary fixture missing-subgraph-control-work/);
});

test('subgraph false-edge bounds must remain bound to its route', () => {
  assert.match(run(undefined, routes => {
    const subgraph = routes.routes.find(entry => entry.family === 'SGA' &&
      entry.operation === 'subgraph');
    subgraph.boundary_tests = subgraph.boundary_tests.filter(item =>
      item.role !== 'subgraph_false_edge_work_workspace_exact_one_short');
  }), /SGA subgraph: false-edge work\/workspace fixture is missing/);
});

test('subgraph product resource proof cannot be silently unbound', () => {
  for (const dimension of ['work', 'workspace']) {
    for (const limit of ['exact_limit', 'one_short_limit']) {
      assert.match(run(undefined, routes => {
        const subgraph = routes.routes.find(entry =>
          entry.family === 'SGA' && entry.operation === 'subgraph');
        delete subgraph.resource_assurance.entrypoint[dimension][limit];
      }), new RegExp(
        `SGA subgraph: entrypoint operation ${dimension} needs exact and one-short proofs`,
      ));
    }
  }
  assert.match(run(manifest => {
    manifest.assured_production_paths = manifest.assured_production_paths
      .filter(claim => claim.family !== 'SGA' ||
        claim.operation !== 'subgraph');
  }), /assured production claims differ from resource-assured routes/);
});

test('vector normalization retains its bounded production evidence', () => {
  for (const role of [
    'normalize_control_work_exact_one_short',
    'normalize_workspace_exact',
    'normalize_workspace_one_short',
    'normalize_kernel_cancel_cleanup',
  ]) {
    assert.match(run(undefined, routes => {
      const normalize = routes.routes.find(entry => entry.family === 'VecA' &&
        entry.operation === 'normalize_vectors');
      normalize.boundary_tests = normalize.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`VecA normalize_vectors: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const normalize = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'normalize_vectors');
    normalize.environment_tests = [];
  }), /VecA normalize_vectors: bounded Host cancellation assurance is missing/);
  assert.match(run(undefined, routes => {
    const normalize = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'normalize_vectors');
    delete normalize.resource_assurance.entrypoint.work.one_short_limit;
  }), /VecA normalize_vectors: entrypoint operation work needs exact and one-short proofs/);
});

test('vector scoring retains its bounded production evidence', () => {
  for (const role of [
    'score_empty_work_exact_one_short',
    'score_record_work_exact_one_short',
    'score_workspace_exact',
    'score_workspace_one_short',
    'score_kernel_cancel_cleanup',
  ]) {
    assert.match(run(undefined, routes => {
      const score = routes.routes.find(entry => entry.family === 'VecA' &&
        entry.operation === 'score_vectors');
      score.boundary_tests = score.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`VecA score_vectors: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const score = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'score_vectors');
    score.environment_tests = [];
  }), /VecA score_vectors: bounded Host cancellation assurance is missing/);
  assert.match(run(undefined, routes => {
    const score = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'score_vectors');
    delete score.resource_assurance.entrypoint.workspace.exact_limit;
  }), /VecA score_vectors: entrypoint operation workspace needs exact and one-short proofs/);
});

test('vector pooling retains its bounded production evidence', () => {
  assert.match(run(undefined, routes => {
    const pool = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'pool_vectors');
    delete pool.relation_entrypoint;
  }), /VecA pool_vectors: Relation input entrypoint is missing/);
  assert.match(run(undefined, routes => {
    const pool = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'pool_vectors');
    delete pool.additional_dispatch;
  }), /VecA pool_vectors: Relation input entrypoint is missing/);
  for (const role of [
    'pool_relation_work_exact_one_short',
    'pool_relation_workspace_exact_one_short',
    'pool_relation_kernel_cancel_cleanup',
    'pool_empty_work_exact_one_short',
    'pool_record_work_exact_one_short',
    'pool_workspace_exact',
    'pool_workspace_one_short',
    'pool_kernel_cancel_cleanup',
    'pool_relation_host_two_consumers',
    'pool_relation_composite_identity',
  ]) {
    assert.match(run(undefined, routes => {
      const pool = routes.routes.find(entry => entry.family === 'VecA' &&
        entry.operation === 'pool_vectors');
      pool.boundary_tests = pool.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`VecA pool_vectors: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const pool = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'pool_vectors');
    pool.environment_tests = [];
  }), /VecA pool_vectors: direct and Relation Host cancellation assurances are required/);
  assert.match(run(undefined, routes => {
    const pool = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'pool_vectors');
    pool.environment_tests = pool.environment_tests.filter(item =>
      item.role !== 'pool_relation_host_in_flight_cancel');
  }), /VecA pool_vectors: direct and Relation Host cancellation assurances are required/);
  assert.match(run(undefined, routes => {
    const pool = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'pool_vectors');
    delete pool.resource_assurance.relation_entrypoint;
  }), /VecA pool_vectors: direct and Relation work\/workspace assurances are required/);
  assert.match(run(undefined, routes => {
    const pool = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'pool_vectors');
    delete pool.resource_assurance.entrypoint.workspace.one_short_limit;
  }), /VecA pool_vectors: entrypoint operation workspace needs exact and one-short proofs/);
});

test('temporal joins require their production resource assurance', () => {
  for (const operation of ['interval_join', 'asof_join']) {
    assert.match(run(undefined, routes => {
      const join = routes.routes.find(entry => entry.family === 'TEA' &&
        entry.operation === operation);
      delete join.path_assurance.entrypoint;
    }), new RegExp(`TEA ${operation}: bounded join production assurance is missing`, 'u'));
    assert.match(run(undefined, routes => {
      const join = routes.routes.find(entry => entry.family === 'TEA' &&
        entry.operation === operation);
      delete join.resource_assurance.entrypoint;
    }), new RegExp(`TEA ${operation}: bounded join production assurance is missing`, 'u'));
    assert.match(run(undefined, routes => {
      const join = routes.routes.find(entry => entry.family === 'TEA' &&
        entry.operation === operation);
      delete join.resource_assurance.entrypoint.work.one_short_limit;
    }), new RegExp(`TEA ${operation}: entrypoint operation work needs exact and one-short proofs`, 'u'));
  }
});

test('nearest retains its fused Relation production entrypoint', () => {
  assert.match(run(undefined, routes => {
    const nearest = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'nearest');
    delete nearest.relation_entrypoint;
  }), /VecA nearest: fused Relation input entrypoint is missing/);
  assert.match(run(undefined, routes => {
    const nearest = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'nearest');
    delete nearest.additional_dispatch;
  }), /VecA nearest: fused Relation input entrypoint is missing/);
  for (const role of [
    'nearest_direct_relation_work_exact_one_short',
    'nearest_direct_relation_workspace_exact_one_short',
    'nearest_direct_relation_cleanup',
    'nearest_work_exact',
    'nearest_work_one_short',
    'nearest_workspace_exact_one_short',
    'nearest_kernel_initialization_cancel_cleanup',
    'nearest_relation_work_exact',
    'nearest_relation_work_one_short',
    'nearest_relation_workspace_exact_one_short',
    'nearest_relation_kernel_cancel_cleanup',
    'nearest_mixed_carrier_relation_host',
    'nearest_relation_roles_host',
  ]) {
    assert.match(run(undefined, routes => {
      const nearest = routes.routes.find(entry => entry.family === 'VecA' &&
        entry.operation === 'nearest');
      nearest.boundary_tests = nearest.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`VecA nearest: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const nearest = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'nearest');
    nearest.environment_tests = [];
  }), /VecA nearest: direct and fused Relation Host cancellation fixtures are required/);
  assert.match(run(undefined, routes => {
    const nearest = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'nearest');
    nearest.environment_tests = nearest.environment_tests.filter(item =>
      item.role !== 'nearest_fused_relation_host_in_flight_cancel');
  }), /VecA nearest: direct and fused Relation Host cancellation fixtures are required/);
  assert.match(run(undefined, routes => {
    const nearest = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'nearest');
    delete nearest.resource_assurance.entrypoint;
  }), /VecA nearest: direct Relation resource assurance is missing/);
  assert.match(run(undefined, routes => {
    const nearest = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'nearest');
    delete nearest.resource_assurance.relation_entrypoint;
  }), /VecA nearest: fused Relation resource assurance is missing/);
});

for (const operation of ['node_rows', 'edge_rows', 'to_events', 'to_vectors']) {
  test(`${operation} loses its Bridge boundary record when removed`, () => {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'Bridge' &&
        entry.operation === operation);
      route.boundary_tests = [];
    }), new RegExp(`Bridge ${operation}: ${operation}_work_workspace_exact_one_short_and_kernel_cancel_cleanup fixture is missing`));
  });
  test(`${operation} loses delivered cancellation assurance when removed`, () => {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'Bridge' &&
        entry.operation === operation);
      route.environment_tests = [];
    }), new RegExp(`Bridge ${operation}: delivered Bridge cancellation assurance is missing`));
  });
  test(`${operation} needs exact work and workspace on its Bridge path`, () => {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'Bridge' &&
        entry.operation === operation);
      delete route.resource_assurance.entrypoint.work.one_short_limit;
    }), new RegExp(`Bridge ${operation}: entrypoint operation work needs exact and one-short proofs`));
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'Bridge' &&
        entry.operation === operation);
      delete route.resource_assurance.entrypoint.workspace;
    }), new RegExp(`Bridge ${operation}: entrypoint operation needs work and workspace assurance`));
  });
}

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

test('same-stage append needs its bounded provider and delivered timer', () => {
  assert.match(run(undefined, routes => {
    const append = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'append');
    delete append.same_stage_entrypoint;
  }), /RelA append: bounded same-stage append provider is missing/);
  assert.match(run(undefined, routes => {
    const append = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'append');
    append.environment_tests = append.environment_tests.filter(item =>
      item.role !== 'append_same_stage_node_timer_cancel_cleanup');
  }), /RelA append: same-stage append timer evidence is missing/);
});

test('same-stage cross join needs its provider and two consumers', () => {
  assert.match(run(undefined, routes => {
    const cross = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'cross_join');
    delete cross.same_stage_entrypoint;
  }), /RelA cross_join: bounded same-stage cross join evidence is missing/);
  assert.match(run(undefined, routes => {
    const cross = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'cross_join');
    cross.boundary_tests = cross.boundary_tests.filter(item =>
      item.role !== 'direct_product_host_two_consumers');
  }), /RelA cross_join: bounded same-stage cross join evidence is missing/);
});

test('binary receivers need their input admission fixtures', () => {
  for (const [operation, role] of [
    ['append', 'append_external_input_value_exact_one_short'],
    ['append', 'append_external_host_receiving_input_limit'],
    ['append', 'append_external_nested_input_cancel_cleanup'],
    ['cross_join', 'external_product_input_value_exact_one_short'],
    ['cross_join', 'external_product_host_receiving_input_limit'],
    ['cross_join', 'external_product_self_input_occurrences'],
    ['cross_join', 'external_product_empty_output_input_admission'],
    ['cross_join', 'external_product_empty_singleton_quantum'],
    ['cross_join', 'external_product_long_text_quantum'],
    ['cross_join', 'external_product_utf8_input_exact_one_short'],
    ['cross_join', 'external_product_input_cancel_cleanup'],
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === operation);
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`RelA ${operation}: (?:reviewed )?${role} fixture is missing`));
  }
  assert.match(run(undefined, routes => {
    const cross = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'cross_join');
    cross.environment_tests = cross.environment_tests.filter(item =>
      item.role !== 'external_product_empty_right_admission_timer_cancel_cleanup');
  }), /RelA cross_join: empty-right admission timer fixture is missing/);
});

test('distinct resource evidence covers full-row and keyed forms', () => {
  for (const role of [
    'distinct_unkeyed_workspace_exact_one_short',
    'distinct_unkeyed_work_exact_one_short',
    'distinct_keyed_workspace_exact_one_short',
    'distinct_keyed_work_exact_one_short',
  ]) {
    assert.match(run(undefined, routes => {
      const distinct = routes.routes.find(entry =>
        entry.family === 'RelA' && entry.operation === 'distinct');
      distinct.boundary_tests = distinct.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`RelA distinct: ${role} fixture is missing`));
  }
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

test('same-stage values derive needs its connected cancellation fixture', () => {
  assert.match(run(undefined, routes => {
    const values = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'values');
    values.environment_tests = values.environment_tests.filter(item =>
      item.role !== 'zero_input_derive_timer_cancel_cleanup');
  }), /RelA values: same-stage derive timer evidence is missing/);
  assert.match(run(undefined, routes => {
    const derive = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'derive');
    derive.boundary_tests = derive.boundary_tests.filter(item =>
      item.role !== 'same_stage_values_derive_two_consumers');
  }), /RelA derive: same-stage values derive evidence is missing/);
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

test('same-stage values cancellation resolves to its managed fixture', () => {
  assert.match(run(undefined, routes => {
    const crossJoin = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'cross_join');
    crossJoin.boundary_tests.find(item =>
      item.role === 'same_stage_values_kernel_cancel_cleanup').fixture =
      'missing-values-kernel-stop';
  }), /RelA cross_join: missing operation boundary fixture missing-values-kernel-stop/);
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
  assert.match(run(undefined, routes => {
    const normalize = routes.routes.find(entry => entry.family === 'SGA' &&
      entry.operation === 'normalize_graph');
    delete normalize.resource_assurance.entrypoint;
  }, ['--require-boundary-complete']),
    /SGA normalize_graph: entrypoint work\/workspace assurance is missing/);
});

test('normalize requires work and workspace evidence for both paths', () => {
  for (const path of ['entrypoint', 'selected_entrypoint']) {
    assert.match(run(undefined, routes => {
      const normalize = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === 'normalize_graph');
      delete normalize.resource_assurance[path].work.one_short_limit;
    }), new RegExp(`SGA normalize_graph: ${path} operation work needs exact and one-short proofs`));
    assert.match(run(undefined, routes => {
      const normalize = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === 'normalize_graph');
      delete normalize.resource_assurance[path].workspace;
    }), new RegExp(`SGA normalize_graph: ${path} operation needs work and workspace assurance`));
  }
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
    /providerless managed execution still computes synchronously/);
});

test('selected Relation provider has no synchronous row fallback', () => {
  const provider = readFileSync(join(
    root, 'src/connectors/local/selected_relation_provider.mbt',
  ), 'utf8');
  assert.match(provider, /fn selected_binding_rows_supported\(/);
  assert.doesNotMatch(provider, /@execution\.execute_selected_relation_step\(/);
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

test('resource gate retains bounded values/select and values/take evidence', () => {
  for (const [operation, role, timer] of [
    ['select', 'values_split_select_lifetime',
      'values_split_select_in_flight_host_timer'],
    ['take', 'values_split_take_lifetime',
      'values_split_take_in_flight_host_timer'],
  ]) {
    assert.match(run(undefined, value => {
      const route = value.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === operation);
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`RelA ${operation}: reviewed ${role} fixture is missing`));
    assert.match(run(undefined, value => {
      const route = value.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === operation);
      route.environment_tests = route.environment_tests.filter(item =>
        item.role !== timer);
    }), new RegExp(`RelA ${operation}: .*Host timer fixture is missing`));
  }
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

test('resource gate retains both distinct timer paths', () => {
  for (const role of [
    'same_stage_distinct_timer_cancel_cleanup',
    'ordinary_distinct_in_flight_host_timer',
  ]) {
    assert.match(run(undefined, value => {
      const distinct = value.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'distinct');
      distinct.environment_tests = distinct.environment_tests.filter(item =>
        item.role !== role);
    }), /RelA distinct: both distinct timer paths need executable evidence/);
  }
});

test('distinct resource assurance cannot lose its keyed variant', () => {
  assert.match(run(undefined, value => {
    const distinct = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'distinct');
    delete distinct.resource_assurance.ordinary_entrypoint.variants.keyed;
  }), /RelA distinct: ordinary_entrypoint needs unkeyed and keyed resource variants/);
});

test('resource gate requires the direct values-distinct split', () => {
  for (const role of [
    'same_stage_values_distinct_two_consumers',
    'same_stage_values_distinct_dag_selection',
    'same_stage_keyed_distinct_join',
  ]) {
    assert.match(run(undefined, value => {
      const distinct = value.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'distinct');
      distinct.boundary_tests = distinct.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`RelA distinct: selected ${role} fixture is missing`));
  }
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

test('rename and drop lose bounded assurance when a resource proof is removed', () => {
  for (const operation of ['rename', 'drop']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === operation);
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== `${operation}_work_exact_one_short`);
    }), new RegExp(`RelA ${operation}: ordinary_entrypoint operation work lacks an executable fixture`));
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === operation);
      route.environment_tests = [];
    }), new RegExp(`RelA ${operation}: ordinary_entrypoint in_flight_cancel lacks an executable fixture`));
  }
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

test('derive loses bounded assurance when a resource proof is removed', () => {
  for (const role of [
    'derive_scalar_work_exact_one_short',
    'derive_scalar_workspace_exact_one_short',
    'derive_input_exact_one_short',
    'derive_cancel_cleanup',
  ]) {
    assert.match(run(undefined, routes => {
      const derive = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'derive');
      derive.boundary_tests = derive.boundary_tests.filter(item =>
        item.role !== role);
    }), /RelA derive: .*lacks an executable fixture/);
  }
  assert.match(run(undefined, routes => {
    const derive = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'derive');
    derive.environment_tests = derive.environment_tests.filter(item =>
      item.role !== 'same_stage_values_derive_timer_cancel_cleanup');
  }), /RelA derive: selected_entrypoint in_flight_cancel lacks an executable fixture/);
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
