import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {validateResourceAccounting} from './validate-local-resource-accounting.mjs';
import {deepFreeze, loadResourceAccountingSources} from './local-resource-accounting-sources.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const script = join(root, 'scripts/check-local-resource-accounting.mjs');
const source = join(
  root,
  'docs/reviews/2026-09-23-local-resource-accounting-audit.json',
);

const manifestTemplate = deepFreeze(JSON.parse(readFileSync(source, 'utf8')));
const routesTemplate = deepFreeze(JSON.parse(readFileSync(join(
  root, manifestTemplate.production_routes,
), 'utf8')));
const gapsTemplate = readFileSync(join(
  root, 'docs/reviews/2026-09-19-sga-veca-tea-local-gaps.md',
), 'utf8');
const sourceTemplate = loadResourceAccountingSources({
  root, manifest: manifestTemplate, routes: routesTemplate,
});

function evaluate(mutator, routeMutator, args = [], gapsText) {
  const manifest = structuredClone(manifestTemplate);
  const routes = structuredClone(routesTemplate);
  mutator?.(manifest);
  routeMutator?.(routes);
  return validateResourceAccounting({
    root, manifest, routes,
    sources: loadResourceAccountingSources({
      root, manifest, routes, previousSources: sourceTemplate,
    }),
    requireBoundaryComplete: args.includes('--require-boundary-complete'),
    checkSummary: args.includes('--check-summary'),
    writeSummary: args.includes('--write-summary'),
    gapsText: gapsText ?? gapsTemplate,
  });
}

function run(...args) {
  const result = evaluate(...args);
  return (result.errors.length ? result.errors.join('\n') : result.output) + '\n';
}

test('Set requires nested comparison boundary evidence for both operations', () => {
  for (const operation of ['except', 'intersect']) {
    for (const suffix of ['quantum_order', 'work_workspace', 'stop_cleanup']) {
      const role = `${operation}_nested_compare_${suffix}`;
      assert.match(run(undefined, routes => {
        const route = routes.routes.find(entry => entry.family === 'RelA' &&
          entry.operation === operation);
        route.boundary_tests = route.boundary_tests.filter(item => item.role !== role);
      }), new RegExp(`RelA ${operation}: ${role} fixture is missing`, 'u'));
    }
  }
});

test('DISTINCT requires nested comparison limits, stop and public Store evidence', () => {
  for (const suffix of ['quantum_order', 'stop_cleanup', 'workspace', 'work', 'public_barrier']) {
    const role = `distinct_nested_compare_${suffix}`;
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'distinct');
      route.boundary_tests = route.boundary_tests.filter(item => item.role !== role);
    }), new RegExp(`RelA distinct: selected ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'distinct');
    route.environment_tests = route.environment_tests.filter(item =>
      item.role !== 'distinct_nested_compare_public_store');
  }), /RelA distinct: nested DISTINCT public Store fixture is missing/u);
});

test('DISTINCT public evidence cannot lose its actual suite import', () => {
  const file = join(root, 'adapters/host-node/embedded-installation.test.mjs');
  const sources = Object.freeze({...sourceTemplate,
    [file]: Object.freeze({...sourceTemplate[file],
      text: sourceTemplate[file].text.replace(
        "import './public-distinct-value-retention.test.mjs';", '')}),
  });
  const result = validateResourceAccounting({root, manifest: manifestTemplate,
    routes: routesTemplate, sources});
  assert.ok(result.errors.includes(
    'RelA distinct: nested DISTINCT public fixture is not suite-connected'));
});

test('filter requires long expression limits, roots and public Store evidence', () => {
  for (const suffix of ['limits', 'control', 'scan', 'root_stop', 'quantum']) {
    const role = `filter_long_expression_${suffix}`;
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'filter');
      route.boundary_tests = route.boundary_tests.filter(item => item.role !== role);
    }), new RegExp(`RelA filter: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'filter');
    route.environment_tests = route.environment_tests.filter(item =>
      item.role !== 'filter_long_expression_public_store');
  }), /RelA filter: expression comparison public Store fixture is missing/u);
});

test('filter public expression evidence requires an actual suite connection', () => {
  const file = join(root, 'adapters/host-node/embedded-installation.test.mjs');
  const sources = Object.freeze({...sourceTemplate,
    [file]: Object.freeze({...sourceTemplate[file],
      text: sourceTemplate[file].text.replace(
        "import './public-expression-comparison-retention.test.mjs';", '')}),
  });
  const result = validateResourceAccounting({root, manifest: manifestTemplate,
    routes: routesTemplate, sources});
  assert.ok(result.errors.includes(
    'RelA filter: expression comparison public fixture is not suite-connected'));
});

test('Pool requires stepped key limits, stop and public Store evidence', () => {
  for (const suffix of ['quantum', 'limits', 'stop_cleanup', 'public_barrier']) {
    const role = `pool_long_keys_${suffix}`;
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'VecA' &&
        entry.operation === 'pool_vectors');
      route.boundary_tests = route.boundary_tests.filter(item => item.role !== role);
    }), new RegExp(`VecA pool_vectors: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'pool_vectors');
    route.environment_tests = route.environment_tests.filter(item =>
      item.role !== 'pool_long_keys_public_store');
  }), /VecA pool_vectors: Pool key public Store fixture is missing/u);
});

test('Pool public key evidence requires an actual suite connection', () => {
  const file = join(root, 'adapters/host-node/embedded-installation.test.mjs');
  const sources = Object.freeze({...sourceTemplate,
    [file]: Object.freeze({...sourceTemplate[file],
      text: sourceTemplate[file].text.replace(
        "import './public-pool-key-retention.test.mjs';", '')}),
  });
  const result = validateResourceAccounting({root, manifest: manifestTemplate,
    routes: routesTemplate, sources});
  assert.ok(result.errors.includes(
    'VecA pool_vectors: Pool key public fixture is not suite-connected'));
});

test('nearest requires stepped key limits, stop and public Store evidence', () => {
  for (const suffix of ['quantum', 'limits', 'stop_cleanup', 'public_barrier']) {
    const role = `nearest_long_keys_${suffix}`;
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'VecA' &&
        entry.operation === 'nearest');
      route.boundary_tests = route.boundary_tests.filter(item => item.role !== role);
    }), new RegExp(`VecA nearest: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'nearest');
    route.environment_tests = route.environment_tests.filter(item =>
      item.role !== 'nearest_long_keys_public_store');
  }), /VecA nearest: nearest key public Store fixture is missing/u);
});

test('nearest public key evidence requires an actual suite connection', () => {
  const file = join(root, 'adapters/host-node/embedded-installation.test.mjs');
  const sources = Object.freeze({...sourceTemplate,
    [file]: Object.freeze({...sourceTemplate[file],
      text: sourceTemplate[file].text.replace(
        "import './public-nearest-key-retention.test.mjs';", '')}),
  });
  const result = validateResourceAccounting({root, manifest: manifestTemplate,
    routes: routesTemplate, sources});
  assert.ok(result.errors.includes(
    'VecA nearest: nearest key public fixture is not suite-connected'));
});

test('VecA Relation input requires nested limits, shared scans and public custody evidence', () => {
  for (const [operation, prefix, publicName] of [
    ['nearest', 'nearest', 'nearest'], ['pool_vectors', 'pool', 'Pool'],
  ]) {
    for (const suffix of ['limits_stop_cleanup', 'shared_vector']) {
      const role = `${prefix}_relation_input_${suffix}`;
      assert.match(run(undefined, routes => {
        const route = routes.routes.find(entry => entry.family === 'VecA' &&
          entry.operation === operation);
        route.boundary_tests = route.boundary_tests.filter(item => item.role !== role);
      }), new RegExp(`VecA ${operation}: ${role} fixture is missing`, 'u'));
    }
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'VecA' &&
        entry.operation === operation);
      route.environment_tests = route.environment_tests.filter(item =>
        item.role !== `${prefix}_relation_input_public_store`);
    }), new RegExp(`VecA ${operation}: ${publicName} Relation input public Store fixture is missing`, 'u'));
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'VecA' &&
        entry.operation === operation);
      route.boundary_tests.find(item =>
        item.role === `${prefix}_relation_input_shared_vector`).suite = 'moon:local_veca';
    }), new RegExp(`VecA ${operation}: boundary evidence must be suite-connected on all targets`, 'u'));
  }
});

test('Pool output requires shared append accounting and public stop custody evidence', () => {
  for (const role of ['pool_output_limits_stop_cleanup',
    'pool_output_record_limits', 'pool_output_record_cleanup',
    'pool_output_owner_exclusion']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'VecA' &&
        entry.operation === 'pool_vectors');
      route.boundary_tests = route.boundary_tests.filter(item => item.role !== role);
    }), new RegExp(`VecA pool_vectors: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'pool_vectors');
    route.environment_tests = route.environment_tests.filter(item =>
      item.role !== 'pool_output_public_store');
  }), /VecA pool_vectors: Pool output public Store fixture is missing/u);
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'pool_vectors');
    route.boundary_tests.find(item => item.role === 'pool_output_record_limits').suite = 'moon:local_veca';
  }), /VecA pool_vectors: boundary evidence must be suite-connected on all targets/u);
});

test('nearest output requires its shared cursor and operator boundary evidence', () => {
  for (const role of ['nearest_output_row_stop_cleanup',
    'nearest_output_public_barrier', 'nearest_output_composite_order',
    'nearest_output_shared_limits', 'nearest_output_shared_cleanup']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'VecA' &&
        entry.operation === 'nearest');
      route.boundary_tests = route.boundary_tests.filter(item => item.role !== role);
    }), new RegExp(`VecA nearest: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'nearest');
    route.environment_tests = route.environment_tests.filter(item =>
      item.role !== 'nearest_output_public_store');
  }), /VecA nearest: nearest output public Store fixture is missing/u);
});

test('ranking requires stepped comparison limits, roots and public Store evidence', () => {
  for (const suffix of ['quantum', 'limits', 'stop_cleanup', 'components']) {
    const role = `ranking_long_keys_${suffix}`;
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'VecA' &&
        entry.operation === 'merge_rankings');
      route.boundary_tests = route.boundary_tests.filter(item => item.role !== role);
    }), new RegExp(`VecA merge_rankings: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'merge_rankings');
    route.environment_tests = route.environment_tests.filter(item =>
      item.role !== 'ranking_long_keys_public_store');
  }), /VecA merge_rankings: ranking key public Store fixture is missing/u);
});

test('ranking output requires its logical limits and shared cursor custody evidence', () => {
  for (const role of ['ranking_output_logical_limits',
    'ranking_output_row_stop_cleanup', 'ranking_output_shared_limits',
    'ranking_output_shared_cleanup']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'VecA' &&
        entry.operation === 'merge_rankings');
      route.boundary_tests = route.boundary_tests.filter(item => item.role !== role);
    }), new RegExp(`VecA merge_rankings: ${role} fixture is missing`, 'u'));
  }
});

test('ranking input requires unused-value limits, shared scans and public custody evidence', () => {
  for (const role of ['ranking_input_value_limits_stop_cleanup',
    'ranking_input_shared_vector', 'ranking_input_shared_json_text']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'VecA' &&
        entry.operation === 'merge_rankings');
      route.boundary_tests = route.boundary_tests.filter(item => item.role !== role);
    }), new RegExp(`VecA merge_rankings: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'merge_rankings');
    route.environment_tests = route.environment_tests.filter(item =>
      item.role !== 'ranking_input_public_store');
  }), /VecA merge_rankings: ranking input public Store fixture is missing/u);
  for (const role of ['ranking_input_shared_vector',
    'ranking_input_shared_json_text']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'VecA' &&
        entry.operation === 'merge_rankings');
      route.boundary_tests.find(item => item.role === role).suite = 'moon:local_veca';
    }), /VecA merge_rankings: boundary evidence must be suite-connected on all targets/u);
  }
});

test('ranking public evidence requires an actual suite connection', () => {
  const file = join(root, 'adapters/host-node/embedded-installation.test.mjs');
  const sources = Object.freeze({...sourceTemplate,
    [file]: Object.freeze({...sourceTemplate[file],
      text: sourceTemplate[file].text.replace(
        "import './public-ranking-key-retention.test.mjs';", '')}),
  });
  const result = validateResourceAccounting({root, manifest: manifestTemplate,
    routes: routesTemplate, sources});
  assert.ok(result.errors.includes(
    'VecA merge_rankings: ranking key public fixture is not suite-connected'));
});

test('interval join requires stepped Text comparison boundary evidence', () => {
  for (const role of [
    'interval_long_text_compare_quantum_order',
    'interval_long_text_compare_stop_cleanup',
    'interval_long_text_compare_work_workspace',
    'interval_long_text_whole_work_workspace',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'TEA' &&
        entry.operation === 'interval_join');
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`TEA interval_join: ${role} fixture is missing`, 'u'));
  }
});

function runCli(mutator, routeMutator, args = [], gapsText, observeDirectory) {
  const manifest = JSON.parse(readFileSync(source, 'utf8'));
  mutator?.(manifest);
  const directory = mkdtempSync(join(tmpdir(), 'actql-resource-audit-'));
  try {
    observeDirectory?.(directory);
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
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
}

test('resource audit fixtures are reclaimed on success, rejection, and setup failure', () => {
  const directories = [];
  const observe = directory => directories.push(directory);
  assert.match(runCli(undefined, undefined, [], undefined, observe),
    /69 operations, 5 implementation profiles/u);
  assert.match(runCli(manifest => { manifest.bindings = []; },
    undefined, [], undefined, observe), /bindings must exactly preserve/u);
  assert.throws(() => runCli(undefined,
    () => { throw new Error('route fixture failure'); },
    [], 'partial fixture', observe), /route fixture failure/u);
  assert.throws(() => runCli(undefined, undefined, [], Symbol('invalid'), observe),
    {code: 'ERR_INVALID_ARG_TYPE'});
  assert.equal(directories.length, 4);
  for (const directory of directories) assert.equal(existsSync(directory), false);
});

test('resource gate accepts every normative Local operation', () => {
  assert.match(run(), /69 operations, 5 implementation profiles, 63 production routes mapped, 6 typed pre-execution refusals \(not execution success\), 63 with operation-specific boundary records, 62 with four-role boundary evidence, 62 with full work\/workspace assurance, 114 with path-scoped work\/workspace evidence, 0 with selected-only assurance; full boundary completion is not asserted/);
});

test('union resource route retains independent work and actual Host cleanup custody evidence', () => {
  const roleNames = ['union_empty_work_exact_one_short_active_cancel_cleanup',
    'union_positive_work_cancel_cleanup', 'union_host_cleanup_failure_retry_custody'];
  for (const removed of roleNames) {
    const result = run(undefined, routes => {
      const route = routes.routes.find(value => value.family === 'SGA' && value.operation === 'union_graphs');
      route.boundary_tests = route.boundary_tests.filter(value => value.role !== removed);
    });
    assert.match(result, removed === roleNames[0]
      ? /SGA union_graphs: structural Graph cumulative-work evidence is missing/
      : /SGA union_graphs: union positive-work cancellation and cleanup evidence is missing/);
  }
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(value => value.family === 'SGA' && value.operation === 'union_graphs');
    route.dispatch.marker = '@sga.uninstalled_union(';
  }), /SGA union_graphs: dispatch marker does not reach production source/);
});

test('unsupported Graph routes require one shared public refusal boundary and cannot claim execution', () => {
  const coverage = JSON.parse(readFileSync(join(root,
    'docs/reviews/2026-09-19-sga-veca-tea-local-coverage.json'), 'utf8'));
  const refused = Object.entries(coverage.current_graph_profile.classification)
    .filter(([, status]) => status === 'blocked').map(([operation]) => operation);
  assert.ok(refused.length > 0);
  for (const operation of refused) {
    for (const field of ['entrypoint', 'resource_assurance', 'path_assurance']) {
      assert.match(run(undefined, routes => {
        routes.routes.find(route => route.operation === operation)[field] = {};
      }, ['--require-boundary-complete']),
      /refused consumer must not claim an executable or resource-assured route/u);
    }
  }
  for (const field of ['suite', 'path', 'fixture', 'targets']) {
    assert.match(run(undefined, routes => { delete routes.refusal_boundary[field]; },
      ['--require-boundary-complete']),
    /current Graph refusals lack the shared required public pre-execution boundary/u);
  }
});

test('current Graph diagnostics require their own bounded and Host stop fixtures', () => {
  for (const [operation, boundaryRole, hostRole] of [
    ['graph_bounds', 'graph_bounds_work_exact_one_short',
      'graph_bounds_selected_host_in_flight_cancel'],
    ['degree', 'degree_control_work_exact_one_short',
      'degree_selected_host_in_flight_cancel'],
  ]) {
    for (const [field, role] of [
      ['boundary_tests', boundaryRole],
      ['environment_tests', hostRole],
    ]) {
      assert.match(run(undefined, routes => {
        const route = routes.routes.find(entry => entry.family === 'SGA' &&
          entry.operation === operation);
        route[field] = route[field].filter(item => item.role !== role);
      }, ['--require-boundary-complete']),
      new RegExp(`SGA ${operation}:`));
    }
  }
});

test('current Graph equality requires its selected value, resource, and Host evidence', () => {
  for (const role of [
    'property_equality_work_exact_one_short',
    'property_equality_workspace_exact_one_short',
    'property_equality_cancel_cleanup',
    'property_equality_nested_value_work_ceiling',
    'property_equality_long_text_quantum_cancel_cleanup',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === 'graphs_equal');
      route.boundary_tests = route.boundary_tests.filter(item => item.role !== role);
    }, ['--require-boundary-complete']),
    /SGA graphs_equal: Graph equality control-work evidence is missing/u);
  }
  for (const role of [
    'property_equality_retained_named_results',
    'property_equality_host_in_flight_cancel',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === 'graphs_equal');
      route.environment_tests = route.environment_tests.filter(item =>
        item.role !== role);
    }, ['--require-boundary-complete']),
    /SGA graphs_equal: Graph equality control-work evidence is missing/u);
  }
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'SGA' &&
      entry.operation === 'graphs_equal');
    route.selected_entrypoint.symbol = 'start_graphs_equal_view';
  }, ['--require-boundary-complete']),
  /SGA graphs_equal: selected Graph operation does not reach its view kernel/u);
});

test('current Delta Host stop records name executable conversion and application fixtures', () => {
  for (const role of ['timer_delivered_input_conversion_cancel_and_cleanup',
    'timer_delivered_bounded_application_cancel_and_cleanup']) {
    const delta = routes => routes.routes.find(route=>route.operation==='apply_graph_delta');
    assert.match(run(undefined, routes => {
      delta(routes).environment_tests.find(item=>item.role===role).fixture = 'missing-Delta-stop-fixture';
    }), /SGA apply_graph_delta: missing environment fixture missing-Delta-stop-fixture/u);
    assert.match(run(undefined, routes => {
      delta(routes).environment_tests.find(item=>item.role===role).targets = ['js','wasm','native'];
    }), /SGA apply_graph_delta: environment evidence must name an executable suite/u);
  }
});

test('keyed property constructor cannot borrow legacy boundary or cancellation evidence', () => {
  for (const field of ['path_assurance','resource_assurance']) {
    assert.match(run(undefined, value => {
      delete value.routes.find(route=>route.operation==='property_graph')[field].entrypoint;
    }), /Bridge property_graph: keyed production work\/workspace and Host cancellation evidence are required/u);
  }
  for (const role of ['property_graph_control_work_workspace_exact_one_short',
    'property_graph_private_capacity_cancel_cleanup']) {
    assert.match(run(undefined, value => {
      const route = value.routes.find(route=>route.operation==='property_graph');
      route.boundary_tests = route.boundary_tests.filter(item=>item.role!==role);
    }), /Bridge property_graph: keyed production work\/workspace and Host cancellation evidence are required/u);
  }
  assert.match(run(undefined, value => {
    value.routes.find(route=>route.operation==='property_graph').environment_tests=[];
  }), /Bridge property_graph: keyed production work\/workspace and Host cancellation evidence are required/u);
  assert.match(run(undefined, value => {
    value.routes.find(route=>route.operation==='property_graph').dispatch.marker='@bridge.start_rows_to_graph(';
  }), /Bridge property_graph: keyed production work\/workspace and Host cancellation evidence are required/u);
});

test('retained source-free Values requires exact admission and Host evidence', () => {
  const values = routes => routes.routes.find(route =>
    route.family === 'RelA' && route.operation === 'values');
  for (const role of ['retained_source_free_chain_admission',
    'retained_source_free_chain_rejection',
    'retained_source_free_product_configuration',
    'retained_source_free_product_rejection', 'retained_source_free_chain_budgets']) {
    assert.match(run(undefined, routes => {
      const route = values(routes);
      route.boundary_tests = route.boundary_tests.filter(test => test.role !== role);
    }), /bounded zero-input Values route lacks its production evidence/u);
  }
  for (const role of ['retained_source_free_named_results',
    'retained_source_free_empty_input', 'retained_source_free_empty_output',
    'retained_source_free_filter_timer_cleanup', 'retained_source_free_filter_arithmetic',
    'retained_source_free_append_cleanup', 'retained_source_free_finalize_cleanup_retry',
    'retained_source_free_host_exact_budgets', 'retained_source_free_host_work_short',
    'retained_source_free_host_workspace_short']) {
    assert.match(run(undefined, routes => {
      const route = values(routes);
      route.environment_tests = route.environment_tests.filter(test => test.role !== role);
    }), new RegExp(`${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    values(routes).environment_tests.find(test =>
      test.role === 'retained_source_free_named_results').fixture = 'absent-values-fixture';
  }), /missing environment fixture absent-values-fixture/u);
});

test('installed retained families require actual product Host fault evidence', () => {
  for (const [family, operation, roles] of [
    ['TEA', 'watermark_events', [
      'installed_retained_events_named_results',
      'installed_retained_events_kernel_cancel',
      'installed_retained_events_filter_arithmetic',
      'installed_retained_events_publication_finalize_cleanup',
    ]],
    ['VecA', 'normalize_vectors', [
      'installed_retained_vectors_named_results',
      'installed_retained_vectors_filter_cancel',
      'installed_retained_vectors_publication_append_cleanup',
    ]],
  ]) {
    const find = routes => routes.routes.find(route =>
      route.family === family && route.operation === operation);
    for (const role of roles) {
      assert.match(run(undefined, routes => {
        const route = find(routes);
        route.environment_tests = route.environment_tests.filter(item => item.role !== role);
      }), new RegExp(`${role} fixture is missing`, 'u'));
    }
    assert.match(run(undefined, routes => {
      find(routes).environment_tests.find(item => item.role === roles[0])
        .fixture = 'absent-installed-family-case';
    }), /missing environment fixture absent-installed-family-case/u);
  }
});

test('captured retained Host requires acquisition binding and executable fault evidence', () => {
  const filter = routes => routes.routes.find(route =>
    route.family === 'RelA' && route.operation === 'filter');
  assert.match(run(undefined, routes => {
    const route = filter(routes);
    route.boundary_tests = route.boundary_tests.filter(item =>
      item.role !== 'retained_captured_factory_binding');
  }), /reviewed retained_captured_factory_binding fixture is missing/u);
  for (const role of ['retained_file_identity_exact_content',
    'retained_file_capture_identity_lifetime']) {
    assert.match(run(undefined, routes => {
      const route = filter(routes);
      route.boundary_tests = route.boundary_tests.filter(item => item.role !== role);
    }), new RegExp(`reviewed ${role} fixture is missing`, 'u'));
  }
  for (const role of [
    'retained_captured_named_results', 'retained_captured_empty_input',
    'retained_captured_empty_output', 'retained_captured_host_exact_budgets',
    'retained_captured_host_work_short', 'retained_captured_host_workspace_short',
    'retained_captured_progress_timer_cleanup', 'retained_captured_filter_arithmetic',
    'retained_captured_append_cleanup', 'retained_captured_finalize_cleanup_retry',
    'retained_file_identity_delivered_stop', 'retained_file_compute_delivered_stop',
  ]) {
    assert.match(run(undefined, routes => {
      const route = filter(routes);
      route.environment_tests = route.environment_tests.filter(item => item.role !== role);
    }), new RegExp(`${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    filter(routes).environment_tests.find(item =>
      item.role === 'retained_captured_named_results').fixture = 'missing-captured-case';
  }), /missing environment fixture missing-captured-case/u);
});

test('Events as-of view requires its own limits, delivered stop and cleanup proof', () => {
  const asof = routes => routes.routes.find(entry =>
    entry.family === 'TEA' && entry.operation === 'asof_join');
  assert.match(run(undefined, routes => {
    const route = asof(routes);
    route.boundary_tests = route.boundary_tests.filter(item =>
      item.role !== 'asof_events_exact_one_short_cancel_cleanup');
  }), /TEA asof_join: view_entrypoint exact_limit lacks an executable fixture/u);
  assert.match(run(undefined, routes => {
    const route = asof(routes);
    route.environment_tests = route.environment_tests.filter(item =>
      item.role !== 'asof_events_host_cancel_cleanup');
  }), /TEA asof_join: view_entrypoint in_flight_cancel lacks an executable fixture/u);
  assert.match(run(undefined, routes => {
    asof(routes).path_assurance.view_entrypoint.cleanup = 'missing_cleanup';
  }), /TEA asof_join: view_entrypoint cleanup lacks an executable fixture/u);
});

test('Relation session chain requires its retained offer, limits and fault evidence', () => {
  const session = routes => routes.routes.find(entry =>
    entry.family === 'TEA' && entry.operation === 'session');
  for (const role of [
    'session_relation_retained_offer', 'session_relation_bounded_chain',
    'session_relation_child_cancel_cleanup', 'session_relation_cumulative_work',
    'session_relation_output_envelope', 'session_empty_finish_limits',
  ]) {
    assert.match(run(undefined, routes => {
      session(routes).boundary_tests = session(routes).boundary_tests
        .filter(item => item.role !== role);
    }), new RegExp(`TEA session: ${role} fixture is missing`, 'u'));
  }
  for (const role of [
    'session_relation_retained_publication', 'session_relation_retained_empty',
    'session_relation_retained_chain_stop', 'session_relation_retained_arithmetic',
    'session_relation_retained_append_failure',
    'session_relation_retained_finalize_failure',
    'session_relation_retained_cleanup_retry',
  ]) {
    assert.match(run(undefined, routes => {
      session(routes).environment_tests = session(routes).environment_tests
        .filter(item => item.role !== role);
    }), new RegExp(`TEA session: ${role} fixture is missing`, 'u'));
  }
});

test('standalone Relation pooling requires registered limits and retained stop evidence', () => {
  const pool = routes => routes.routes.find(entry =>
    entry.family === 'VecA' && entry.operation === 'pool_vectors');
  assert.match(run(undefined, routes => {
    const route = pool(routes);
    route.boundary_tests = route.boundary_tests.filter(item =>
      item.role !== 'pool_relation_registered_generation');
  }), /VecA pool_vectors: relation_entrypoint operation work lacks an executable fixture/u);
  assert.match(run(undefined, routes => {
    const route = pool(routes);
    route.boundary_tests = route.boundary_tests.filter(item =>
      item.role !== 'pool_relation_registered_limits_stop_cleanup');
  }), /VecA pool_vectors: relation_entrypoint cleanup lacks an executable fixture/u);
  assert.match(run(undefined, routes => {
    const route = pool(routes);
    route.environment_tests = route.environment_tests.filter(item =>
      item.role !== 'pool_relation_host_in_flight_cancel');
  }), /VecA pool_vectors: relation_entrypoint in_flight_cancel lacks an executable fixture/u);
});



test('same-stage equality join requires its bounded route and evidence', () => {
  const joinRoute = routes => routes.routes.find(entry =>
    entry.family === 'RelA' && entry.operation === 'join');
  assert.match(run(undefined, routes => {
    delete joinRoute(routes).selected_entrypoint;
  }), /RelA join: bounded selected join provider is missing/u);
  for (const role of [
    'bounded_join_empty_work_workspace_exact_one_short',
    'bounded_join_output_workspace_exact_one_short',
    'bounded_join_split_dag_edges',
    'bounded_join_split_two_consumers',
    'bounded_join_split_cancel_cleanup',
  ]) {
    assert.match(run(undefined, routes => {
      const route = joinRoute(routes);
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`RelA join: ${role} fixture is missing`, 'u'));
  }
  for (const role of [
    'bounded_join_split_host_timer',
    'bounded_join_split_named_result',
  ]) {
    assert.match(run(undefined, routes => {
      const route = joinRoute(routes);
      route.environment_tests = route.environment_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`RelA join: ${role} fixture is missing`, 'u'));
  }
});


test('global count assurance requires its bounded product path and proofs', () => {
  for (const role of [
    'count_if_work_workspace_exact_one_short',
    'count_if_cancel_cleanup',
    'count_if_two_consumers',
    'count_if_same_stage_two_consumers',
    'count_if_same_stage_cancel_cleanup',
    'direct_group_work_exact_one_short',
    'direct_group_stop_nonpublication',
    'direct_group_two_consumers',
    'direct_group_cancel_cleanup',
    'keyed_count_long_output_exact_one_short',
    'keyed_count_long_output_cancel_cleanup',
    'keyed_count_long_output_two_consumers',
    'keyed_count_long_output_host_cancel_cleanup',
    'keyed_count_raw_rowtable_recheck',
    'keyed_count_same_stage_work_exact_one_short',
    'keyed_count_same_stage_overlap_capacity',
    'count_nested_input_cancel_cleanup',
    'count_nested_value_exact_one_short',
    'count_long_text_input_exact_one_short',
    'count_long_text_input_cancel_cleanup',
  ]) {
    assert.match(run(undefined, routes => {
      const group = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'group');
      group.boundary_tests = group.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`RelA group: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const group = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'group');
    group.boundary_tests = group.boundary_tests.filter(item =>
      item.role !== 'count_nested_input_host_cancel_cleanup');
  }), /RelA group: count_nested_input_host_cancel_cleanup fixture is missing/u);
  assert.match(run(undefined, routes => {
    const group = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'group');
    group.boundary_tests = group.boundary_tests.filter(item =>
      item.role !== 'count_nested_input_host_two_consumers');
  }), /RelA group: count_nested_input_host_two_consumers fixture is missing/u);
  assert.match(run(undefined, routes => {
    const group = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'group');
    group.boundary_tests = group.boundary_tests.filter(item =>
      item.role !== 'keyed_count_same_stage_workspace_exact_one_short');
  }), /RelA group: keyed_count_same_stage_workspace_exact_one_short fixture is missing/u);
  assert.match(run(undefined, routes => {
    const group = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'group');
    delete group.global_count_entrypoint;
  }), /RelA group: assurance names an unregistered production path/u);
  assert.match(run(undefined, routes => {
    const group = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'group');
    group.boundary_tests = group.boundary_tests.filter(item =>
      item.role !== 'global_count_work_workspace_exact_one_short');
  }), /RelA group: global_count_entrypoint exact_limit lacks an executable fixture/u);
  assert.match(run(undefined, routes => {
    const group = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'group');
    group.environment_tests = group.environment_tests.filter(item =>
      item.role !== 'global_count_host_timer');
  }), /RelA group: global_count_entrypoint in_flight_cancel lacks an executable fixture/u);
  assert.match(run(undefined, routes => {
    const group = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'group');
    group.environment_tests = group.environment_tests.filter(item =>
      item.role !== 'count_if_same_stage_timer');
  }), /RelA group: count_if_same_stage_timer fixture is missing/u);
  assert.match(run(undefined, routes => {
    const group = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'group');
    group.boundary_tests = group.boundary_tests.filter(item =>
      item.role !== 'global_count_two_consumers');
  }), /RelA group: global_count_two_consumers fixture is missing/u);
  assert.match(run(undefined, routes => {
    const group = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'group');
    group.environment_tests = group.environment_tests.filter(item =>
      item.role !== 'global_count_host_two_consumers');
  }), /RelA group: global_count_host_two_consumers fixture is missing/u);
  for (const role of [
    'global_count_same_stage_two_consumers',
    'global_count_same_stage_timer',
    'keyed_count_values_split_two_consumers',
    'keyed_count_values_split_timer',
    'keyed_count_values_split_publication',
  ]) {
    assert.match(run(undefined, routes => {
      const group = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'group');
      group.environment_tests = group.environment_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`RelA group: ${role} fixture is missing`, 'u'));
  }
  for (const role of [
    'keyed_count_values_split_two_consumers',
    'keyed_count_values_split_cancel_cleanup',
  ]) {
    assert.match(run(undefined, routes => {
      const group = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'group');
      group.boundary_tests = group.boundary_tests.filter(item => item.role !== role);
    }), new RegExp(`RelA group: ${role} fixture is missing`, 'u'));
  }
});

test('empty RelA resource boundaries are required by their routes', () => {
  for (const operation of ['window_group', 'join', 'analytic']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === operation);
      route.boundary_tests = [];
    }), new RegExp(`RelA ${operation}: .* fixture is missing`, 'u'));
  }
});

test('supplied Relation selection loses assurance without its fixtures', () => {
  for (const role of [
    'supplied_select_work_workspace_exact_one_short',
    'supplied_relation_chain_two_consumers',
    'supplied_relation_chain_cancel_cleanup',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'select');
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`RelA select: reviewed ${role} fixture is missing`, 'u'));
  }
});

test('nest loses its independent empty boundary if the fixture is removed', () => {
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'nest');
    route.boundary_tests = [];
  }), /RelA nest: independent empty nest resource evidence is missing/u);
});

test('partitioned top-k loses bounded assurance if either fixture is absent', () => {
  for (const role of [
    'top_k_by_bounded_quantum_and_lifetime',
    'top_k_by_bounded_cancel_cleanup',
    'top_k_by_work_workspace_exact_one_short',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'top_k_by');
      route.boundary_tests = route.boundary_tests.filter(test =>
        test.role !== role);
    }), new RegExp(`RelA top_k_by: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'top_k_by');
    route.environment_tests = [];
  }), /RelA top_k_by: delivered Host cancellation evidence is missing/u);
});

test('selected top-k proof reuse requires the exact product entrypoint', () => {
  for (const operation of ['top_k', 'top_k_by']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === operation);
      route.selected_entrypoint.symbol = 'unrelated_execution';
    }), new RegExp(`RelA ${operation}: shared proof reuse lacks an exact common entrypoint`, 'u'));
  }
});

test('row window loses its bounded route when production evidence is removed', () => {
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'row_window');
    delete route.selected_entrypoint;
  }), /RelA row_window: bounded selected row-window entrypoint is missing/u);
  for (const role of [
    'row_window_bounded_quantum_output',
    'row_window_exact_output_boundary',
    'row_window_bounded_cancel_cleanup',
    'row_window_bounded_workspace_exact_one_short',
    'row_window_bounded_control_work_exact_one_short',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'row_window');
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`RelA row_window: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'row_window');
    route.environment_tests = route.environment_tests.filter(item =>
      item.role !== 'row_window_in_flight_host_timer');
  }), /RelA row_window: selected_entrypoint in_flight_cancel lacks an executable fixture/u);
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'row_window');
    delete route.resource_assurance.selected_entrypoint.workspace;
  }), /RelA row_window: selected_entrypoint operation needs work and workspace assurance/u);
});

test('unpivot loses its bounded route when production evidence is removed', () => {
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'unpivot');
    delete route.selected_entrypoint;
  }), /RelA unpivot: bounded selected unpivot entrypoint is missing/u);
  for (const role of [
    'unpivot_bounded_quantum_output',
    'unpivot_bounded_cancel_cleanup',
    'unpivot_bounded_workspace_exact_one_short',
    'unpivot_bounded_control_work_exact_one_short',
    'unpivot_nonempty_work_workspace_exact_one_short',
    'unpivot_bounded_output_limit',
    'unpivot_captured_chain_two_consumers',
    'unpivot_captured_chain_cancel_cleanup',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'unpivot');
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), role === 'unpivot_nonempty_work_workspace_exact_one_short'
      ? /RelA unpivot: selected_entrypoint exact_limit lacks an executable fixture/u
      : new RegExp(`RelA unpivot: ${role} fixture is missing`, 'u'));
  }
  for (const role of [
    'unpivot_standard_host_two_consumers',
    'unpivot_same_stage_host_two_consumers',
    'unpivot_in_flight_host_timer',
    'unpivot_captured_chain_host_two_consumers',
    'unpivot_retained_chain_host_two_consumers',
    'unpivot_captured_chain_in_flight_host_timer',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'unpivot');
      route.environment_tests = route.environment_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`RelA unpivot: ${role} fixture is missing`, 'u'));
  }
});

test('unnest loses its bounded route when production evidence is removed', () => {
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'unnest');
    delete route.selected_entrypoint;
  }), /RelA unnest: bounded selected unnest entrypoint is missing/u);
  for (const role of [
    'unnest_bounded_quantum_output',
    'unnest_bounded_cancel_cleanup',
    'unnest_bounded_workspace_exact_one_short',
    'unnest_bounded_control_work_exact_one_short',
    'unnest_nonempty_work_workspace_exact_one_short',
    'unnest_bounded_output_limit',
    'unnest_nested_chain_two_consumers',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'unnest');
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), role === 'unnest_nonempty_work_workspace_exact_one_short'
      ? /RelA unnest: selected_entrypoint exact_limit lacks an executable fixture/u
      : new RegExp(`RelA unnest: ${role} fixture is missing`, 'u'));
  }
  for (const role of [
    'unnest_standard_host_two_consumers',
    'unnest_same_stage_host_two_consumers',
    'unnest_in_flight_host_timer',
    'unnest_nested_chain_host_two_consumers',
    'unnest_nested_chain_in_flight_host_timer',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'unnest');
      route.environment_tests = route.environment_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`RelA unnest: ${role} fixture is missing`, 'u'));
  }
});

test('watermark loses its independent resource boundary with its fixture', () => {
  for (const role of [
    'watermark_fixed_work_workspace_exact_one_short',
    'watermark_selected_work_workspace_exact_one_short',
    'watermark_selected_cancel_cleanup',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'watermark_rows');
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`RelA watermark_rows: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'watermark_rows');
    delete route.selected_entrypoint;
  }), /RelA watermark_rows: bounded selected watermark entrypoint is missing/u);
  for (const role of [
    'watermark_fixed_host_two_consumers',
    'watermark_prefix_host_two_consumers',
    'watermark_fixed_in_flight_host_timer',
    'watermark_prefix_in_flight_host_timer',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'watermark_rows');
      route.environment_tests = route.environment_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`RelA watermark_rows: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'watermark_rows');
    delete route.resource_assurance.selected_entrypoint;
  }), /RelA:watermark_rows:selected_entrypoint: assured production claim lacks its exact route proofs/u);
});

test('json pick loses its independent resource boundary with its fixture', () => {
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'json_pick');
    route.boundary_tests = [];
  }), /RelA json_pick: independent json pick resource evidence is missing/u);
});

test('json pick selected route loses evidence when a fixture is removed', () => {
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'json_pick');
    delete route.selected_entrypoint;
  }), /RelA json_pick: bounded selected json pick entrypoint is missing/u);
  for (const role of [
    'json_pick_selected_work_workspace_exact_one_short',
    'json_pick_completed_work_workspace_exact_one_short',
    'json_pick_selected_cancel_cleanup',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'json_pick');
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`RelA json_pick: ${role} fixture is missing`, 'u'));
  }
  for (const role of [
    'json_pick_host_two_consumers',
    'json_pick_same_stage_host_two_consumers',
    'json_pick_in_flight_host_timer',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'json_pick');
      route.environment_tests = route.environment_tests.filter(item =>
        item.role !== role);
    }), new RegExp(`RelA json_pick: ${role} fixture is missing`, 'u'));
  }
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'json_pick');
    delete route.resource_assurance.selected_entrypoint;
  }), /RelA:json_pick:selected_entrypoint: assured production claim lacks its exact route proofs/u);
});

test('dedupe loses its independent resource boundary with its fixture', () => {
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'dedupe_rows');
    route.boundary_tests = [];
  }), /RelA dedupe_rows: independent dedupe resource evidence is missing/u);
});

test('bounded dedupe assurance requires reached limits and Host cancellation', () => {
  const dedupe = routes => routes.routes.find(entry =>
    entry.family === 'RelA' && entry.operation === 'dedupe_rows');
  assert.match(run(undefined, routes => {
    dedupe(routes).boundary_tests = dedupe(routes).boundary_tests.filter(
      item => item.role !== 'dedupe_bounded_work_workspace_exact_one_short',
    );
  }), /RelA dedupe_rows: selected_entrypoint exact_limit lacks an executable fixture/u);
  assert.match(run(undefined, routes => {
    dedupe(routes).environment_tests = [];
  }), /RelA dedupe_rows: selected_entrypoint in_flight_cancel lacks an executable fixture/u);
  assert.match(run(undefined, routes => {
    delete dedupe(routes).resource_assurance.ordinary_entrypoint;
  }), /RelA:dedupe_rows:ordinary_entrypoint: assured production claim lacks its exact route proofs/u);
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

test('selected lag assurance requires its route-specific evidence', () => {
  for (const role of [
    'lag_selected_work_exact_one_short',
    'lag_selected_workspace_exact_one_short',
    'lag_selected_cancel_cleanup',
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'lag');
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), /RelA lag: selected_entrypoint .* lacks an executable fixture/u,
    role);
  }
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'lag');
    route.environment_tests = route.environment_tests.filter(item =>
      item.role !== 'lag_selected_in_flight_host_timer');
  }), /RelA lag: selected_entrypoint in_flight_cancel lacks an executable fixture/u);
});

test('window and set routes lose schema workspace evidence without fixtures', () => {
  for (const operation of ['row_window', 'except', 'intersect']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === operation);
      route.boundary_tests = [];
    }), new RegExp(`RelA ${operation}: empty schema workspace evidence is missing`, 'u'));
  }
});

test('reshape and window routes reject missing pre-admission evidence', () => {
  for (const operation of ['row_window', 'unpivot', 'unnest']) {
    const roles = [`${operation}_input_index_pre_admission`];
    if (operation !== 'row_window') {
      roles.push(`${operation}_empty_schema_workspace_exact_one_short`);
    }
    for (const role of roles) {
      assert.match(run(undefined, routes => {
        const route = routes.routes.find(entry => entry.family === 'RelA' &&
          entry.operation === operation);
        route.boundary_tests = route.boundary_tests.filter(item =>
          item.role !== role);
      }), new RegExp(`RelA ${operation}: ${role} fixture is missing`, 'u'));
    }
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

test('ranking assurance requires provider limits and Host cancellation', () => {
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'merge_rankings');
    route.boundary_tests = route.boundary_tests.filter(item =>
      item.role !== 'ranking_provider_work_workspace_exact_one_short');
  }), /VecA merge_rankings: entrypoint exact_limit lacks an executable fixture/u);
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'merge_rankings');
    route.environment_tests = [];
  }), /VecA merge_rankings: entrypoint in_flight_cancel lacks an executable fixture/u);
  assert.match(run(undefined, routes => {
    const route = routes.routes.find(entry => entry.family === 'VecA' &&
      entry.operation === 'merge_rankings');
    delete route.resource_assurance.entrypoint;
  }), /VecA:merge_rankings:entrypoint: assured production claim lacks its exact route proofs/u);
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





test('graph matcher assurance requires its exact bounded provider call', () => {
  for (const operation of ['match_nodes', 'match_edges']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === operation);
      route.dispatch.marker = '@sga.start_graph_bounds(';
    }), new RegExp(`SGA ${operation}: assured matcher provider loses execution limits`, 'u'));
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === operation);
      delete route.resource_assurance.entrypoint;
    }), new RegExp(`SGA:${operation}:entrypoint: assured production claim lacks its exact route proofs`, 'u'));
  }
});

test('selected graph match loses assurance without its view proof or Host stop', () => {
  for (const operation of ['match_nodes', 'match_edges']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === operation);
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== `${operation}_view_exact_one_short_cancel_cleanup`);
    }), new RegExp(`SGA ${operation}: selected_entrypoint exact_limit lacks an executable fixture`, 'u'));
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === operation);
      route.environment_tests = route.environment_tests.filter(item =>
        item.role !== `${operation}_view_host_in_flight_cancel`);
    }), new RegExp(`SGA ${operation}: selected_entrypoint in_flight_cancel lacks an executable fixture`, 'u'));
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === operation);
      delete route.resource_assurance.selected_entrypoint;
    }), new RegExp(`SGA:${operation}:selected_entrypoint: assured production claim lacks its exact route proofs`, 'u'));
  }
});

test('graph matching loses identity workspace evidence when either fixture is removed', () => {
  for (const operation of ['match_nodes', 'match_edges']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === operation);
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== `${operation}_identity_workspace_exact_one_short`);
    }), new RegExp(`SGA ${operation}: match identity workspace evidence is missing`, 'u'));
  }
});

test('graph matching requires bounded long-key comparison evidence', () => {
  for (const operation of ['match_nodes', 'match_edges']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === operation);
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== `${operation}_long_text_compare_cancel_cleanup`);
    }), new RegExp(`SGA ${operation}: bounded long-key comparison evidence is missing`, 'u'));
  }
});

test('graph matcher variants require product and predicate boundary evidence', () => {
  for (const operation of ['match_nodes', 'match_edges']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === operation);
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== `${operation}_predicate_workspace_exact_one_short`);
    }), new RegExp(`SGA ${operation}: predicate workspace evidence is missing`, 'u'));
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === operation);
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== `${operation}_predicate_work_exact_one_short`);
    }), new RegExp(`SGA ${operation}: predicate work evidence is missing`, 'u'));
    for (const role of [
      `${operation}_literal_host_two_consumers`,
      `${operation}_predicate_host_two_consumers`,
      `${operation}_predicate_host_in_flight_cancel`,
      ...(operation === 'match_edges'
        ? ['match_edges_literal_host_in_flight_cancel'] : []),
    ]) {
      assert.match(run(undefined, routes => {
        const route = routes.routes.find(entry => entry.family === 'SGA' &&
          entry.operation === operation);
        route.environment_tests = route.environment_tests.filter(item =>
          item.role !== role);
      }), new RegExp(`SGA ${operation}: ${role} Host fixture is missing`, 'u'));
    }
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



test('current TRAIL variants require work workspace and stop custody evidence', () => {
  for (const [operation, role, diagnostic] of [
    ['traverse', 'traverse_variant_work_exact_one_short',
      /SGA traverse: traversal work evidence is missing/u],
    ['traverse', 'traverse_variant_workspace_exact_one_short',
      /SGA traverse: traversal work evidence is missing/u],
    ['traverse', 'traverse_variant_cancel_cleanup',
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




test('resource summary rejects stale route counts', () => {
  const gaps = readFileSync(join(
    root, 'docs/reviews/2026-09-19-sga-veca-tea-local-gaps.md',
  ), 'utf8');
  const stale = gaps.replace(
    '| Path-scoped work/workspace assurance | 114 |',
    '| Path-scoped work/workspace assurance | 54 |',
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
      item.role !== 'session_relation_retained_chain_stop');
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

test('as-of join requires each long text comparison proof', () => {
  for (const role of [
    'asof_long_text_key_cancel_cleanup',
    'asof_long_text_identity_cancel_cleanup',
    'asof_long_text_tie_cancel_cleanup',
    'asof_long_text_result_order',
  ]) {
    assert.match(run(undefined, routes => {
      const join = routes.routes.find(entry => entry.family === 'TEA' &&
        entry.operation === 'asof_join');
      join.boundary_tests = join.boundary_tests.filter(fixture =>
        fixture.role !== role);
    }), new RegExp(`TEA asof_join: ${role} fixture is missing`, 'u'));
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
  for (const [field, roles] of [
    ['boundary_tests', ['append_chain_two_consumers', 'append_chain_cancel_cleanup',
      'append_chain_work_workspace_exact_one_short']],
    ['environment_tests', ['append_chain_timer', 'append_chain_publication']],
  ]) {
    for (const role of roles) {
      assert.match(run(undefined, routes => {
        const append = routes.routes.find(entry => entry.family === 'RelA' &&
          entry.operation === 'append');
        append[field] = append[field].filter(item => item.role !== role);
      }), new RegExp(`RelA append: ${role} fixture is missing`, 'u'));
    }
  }
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
  assert.match(run(undefined, routes => {
    const append = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'append');
    delete append.resource_assurance.same_stage_entrypoint;
  }), /RelA:append:same_stage_entrypoint: assured production claim lacks its exact route proofs/u);
  assert.match(run(undefined, routes => {
    const append = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'append');
    append.shared_proof_reuse = [];
  }), /RelA append: append_external_work_workspace_exact_one_short is reused across production paths/u);
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
  assert.match(run(undefined, routes => {
    const cross = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'cross_join');
    delete cross.resource_assurance.same_stage_entrypoint;
  }), /RelA:cross_join:same_stage_entrypoint: assured production claim lacks its exact route proofs/u);
  assert.match(run(undefined, routes => {
    const cross = routes.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'cross_join');
    cross.shared_proof_reuse = [];
  }), /RelA cross_join: external_product_work_exact_one_short is reused across production paths/u);
});

test('VecA row expressions retain bounded and delivered-cancel proofs', () => {
  for (const operation of ['vector_score', 'vector_concat']) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry =>
        entry.family === 'VecAExpression' &&
        entry.operation === operation);
      route.environment_tests = [];
    }), new RegExp(`VecAExpression ${operation}: entrypoint in_flight_cancel lacks an executable fixture`, 'u'));
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry =>
        entry.family === 'VecAExpression' &&
        entry.operation === operation);
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== `${operation}_derive_work_workspace_exact_one_short`);
    }), new RegExp(`VecAExpression ${operation}: entrypoint exact_limit lacks an executable fixture`, 'u'));
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry =>
        entry.family === 'VecAExpression' &&
        entry.operation === operation);
      delete route.resource_assurance.entrypoint;
    }), new RegExp(`VecAExpression:${operation}:entrypoint: assured production claim lacks its exact route proofs`, 'u'));
  }
});

test('binary receivers need their input admission fixtures', () => {
  for (const [operation, role] of [
    ['append', 'append_external_input_value_exact_one_short'],
    ['append', 'append_external_host_receiving_input_limit'],
    ['append', 'append_external_host_input_cancel_cleanup'],
    ['append', 'append_external_nested_input_cancel_cleanup'],
    ['cross_join', 'external_product_input_value_exact_one_short'],
    ['cross_join', 'external_product_host_receiving_input_limit'],
    ['cross_join', 'external_product_host_input_cancel_cleanup'],
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

test('adjacent row comparisons retain bounded cancellation evidence', () => {
  for (const [operation, role] of [
    ['distinct', 'distinct_adjacent_long_key_cancel_cleanup'],
    ['assert_rows', 'assert_unique_adjacent_long_key_cancel_cleanup'],
  ]) {
    assert.match(run(undefined, routes => {
      const route = routes.routes.find(entry =>
        entry.family === 'RelA' && entry.operation === operation);
      route.boundary_tests = route.boundary_tests.filter(item =>
        item.role !== role);
    }), new RegExp(
      `RelA ${operation}: (?:selected |reviewed )?${role} fixture is missing`,
    ));
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
      family: 'SGA', operation: 'graph_diff', path: 'selected_entrypoint',
    });
  }), /SGA:graph_diff:selected_entrypoint: assured production claim lacks its exact route proofs/);
});

test('mixed-path gate rejects missing delivered prefix cancellation', () => {
  assert.match(run(undefined, value => {
    value.mixed_paths[0].in_flight_cancel.fixture = 'missing-prefix-case';
  }), /mixed path graph_constructor_match_nodes_filter: missing delivered prefix cancellation fixture/);
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
  }), /mixed path graph_constructor_match_nodes_filter: Carrier, formal Bridge, and Relation roles differ/);
});

test('resource completion requires each typed Carrier prefix', () => {
  for (const carrier of ['Graph', 'Events', 'Vectors']) {
    assert.match(run(undefined, value => {
      value.mixed_paths = value.mixed_paths.filter(path =>
        path.carrier !== carrier);
    }, ['--require-boundary-complete']),
    new RegExp(`${carrier}: typed prefix mixed-stage assurance is missing`));
  }
});

test('resource completion requires work and workspace proof independently', () => {
  assert.match(run(undefined, routes => {
    const normalize = routes.routes.find(entry => entry.family === 'SGA' &&
      entry.operation === 'match_nodes');
    delete normalize.resource_assurance.entrypoint;
  }, ['--require-boundary-complete']),
    /SGA match_nodes: entrypoint work\/workspace assurance is missing/);
});

test('MATCH requires work and workspace evidence for both paths', () => {
  for (const path of ['entrypoint', 'selected_entrypoint']) {
    assert.match(run(undefined, routes => {
      const normalize = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === 'match_nodes');
      delete normalize.resource_assurance[path].work.one_short_limit;
    }), new RegExp(`SGA match_nodes: ${path} operation work needs exact and one-short proofs`));
    assert.match(run(undefined, routes => {
      const normalize = routes.routes.find(entry => entry.family === 'SGA' &&
        entry.operation === 'match_nodes');
      delete normalize.resource_assurance[path].workspace;
    }), new RegExp(`SGA match_nodes: ${path} operation needs work and workspace assurance`));
  }
});









test('managed dispatch has no synchronous providerless lane', () => {
  const result = run(undefined, undefined, ['--require-boundary-complete']);
  assert.doesNotMatch(result,
    /providerless managed execution still computes synchronously/);
  assert.doesNotMatch(result, /providerless managed execution must be rejected/);
  assert.doesNotMatch(result, /managed execution lane inventory must be reviewed/);
  const driver = readFileSync(join(
    root, 'src/connectors/local/driver/managed_dispatch.mbt',
  ), 'utf8');
  assert.doesNotMatch(driver, /execute_local_managed_fixed_compute\(/);
});

test('ordinary and retained Store Local have no synchronous lane', () => {
  const result = run(undefined, undefined, ['--require-boundary-complete']);
  assert.doesNotMatch(result,
    /ordinary Local dispatch keeps a synchronous computation lane/);
  assert.doesNotMatch(result,
    /Node Local driver keeps a synchronous execute fallback/);
  assert.doesNotMatch(result,
    /retained Store Local lacks standard Host in-flight evidence/);
});

test('selected Relation provider has no synchronous row fallback', () => {
  const provider = readFileSync(join(
    root, 'src/connectors/local/selected_relation_provider.mbt',
  ), 'utf8');
  assert.match(provider, /fn selected_binding_rows_supported\(/);
  assert.doesNotMatch(provider, /@execution\.execute_selected_relation_step\(/);
});

test('strict gate recognizes cross join after positive pair work', () => {
  const result = run(undefined, undefined, ['--require-boundary-complete']);
  assert.doesNotMatch(result,
    /RelA cross_join: in-flight Host cancellation evidence is missing/);
  assert.doesNotMatch(result,
    /RelA cross_join: entrypoint boundary assurance is missing/);
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
      entry.operation === 'match_nodes');
    bounds.resource_assurance = {
      entrypoint: {
        work: {
          exact_limit: 'product_work_workspace_exact_one_short',
          one_short_limit: 'product_work_workspace_exact_one_short',
        },
        workspace: {
          exact_limit: 'match_nodes_identity_workspace_exact_one_short',
          one_short_limit: 'match_nodes_identity_workspace_exact_one_short',
        },
      },
    };
  }), /SGA match_nodes: entrypoint operation work lacks an executable fixture/);
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
  }), /RelA assert_rows: selected_entrypoint needs both resource variants/);
});

test('resource completion rejects every unassured operation', () => {
  assert.match(run(undefined, value => {
    const route = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'analytic');
    delete route.path_assurance.entrypoint;
  }, ['--require-boundary-complete']),
  /RelA analytic: entrypoint boundary assurance is missing/);
});

const pendingBoundaryErrors = [];

test('Delta combined workspace and delivered stop cannot lose their registered proof roles', () => {
  const delta = routes => routes.routes.find(route=>route.operation==='apply_graph_delta');
  for (const [collection,role,expected] of [
    ['boundary_tests','delta_combined_workspace_exact_one_short',
      'SGA apply_graph_delta: entrypoint operation workspace lacks an executable fixture'],
    ['environment_tests','timer_delivered_bounded_application_cancel_and_cleanup',
      'SGA apply_graph_delta: entrypoint in_flight_cancel lacks an executable fixture'],
  ]) {
    const result = evaluate(undefined, routes => {
      delta(routes)[collection] = delta(routes)[collection].filter(item=>item.role!==role);
    });
    assert(result.errors.includes(expected), result.errors.join('\n'));
  }
  const result = evaluate(undefined, routes => {
    delete delta(routes).resource_assurance.entrypoint;
  }, ['--require-boundary-complete']);
  assert(result.errors.includes('SGA apply_graph_delta: entrypoint work/workspace assurance is missing'));
});

test('strict resource completion accepts the registered Graph boundary evidence', () => {
  assert.deepEqual(evaluate(undefined, undefined,
    ['--require-boundary-complete']).errors, pendingBoundaryErrors);
});

test('current Graph diff requires exact limits and delivered Host cancellation evidence', () => {
  for (const role of ['graph_diff_work_workspace_exact_one_short',
    'graph_diff_host_delivered_cancel_cleanup']) {
    assert.match(run(undefined, routes => {
      const diff = routes.routes.find(route=>route.operation === 'graph_diff');
      const records = role.includes('host') ? diff.environment_tests : diff.boundary_tests;
      records.find(record=>record.role === role).fixture = 'missing-current-diff-case';
    }), /SGA graph_diff: missing (?:operation boundary|environment) fixture missing-current-diff-case/);
  }
});

test('Subgraph assurance cannot borrow selected cancellation for the fused entrypoint', () => {
  const subgraph = routes => routes.routes.find(route=>route.operation==='subgraph');
  const borrowed = evaluate(undefined, routes => {
    const route = subgraph(routes);
    route.path_assurance.entrypoint.in_flight_cancel =
      route.path_assurance.selected_entrypoint.in_flight_cancel;
  }, ['--require-boundary-complete']);
  assert(borrowed.errors.includes(
    'SGA subgraph: subgraph_selected_host_in_flight_cancel is reused across production paths'));
  const missingTimer = evaluate(undefined, routes => {
    const route = subgraph(routes);
    route.environment_tests = route.environment_tests.filter(
      item=>item.role !== 'subgraph_fused_host_in_flight_cancel');
  }, ['--require-boundary-complete']);
  assert(missingTimer.errors.includes('SGA subgraph: entrypoint in_flight_cancel lacks an executable fixture'));
  for (const [field, expected] of [
    ['path_assurance','SGA subgraph: entrypoint boundary assurance is missing'],
    ['resource_assurance','SGA subgraph: entrypoint work/workspace assurance is missing'],
  ]) {
    const result = evaluate(undefined, routes => {
      delete subgraph(routes)[field].entrypoint;
    }, ['--require-boundary-complete']);
    assert(result.errors.includes(expected), result.errors.join('\n'));
  }
});

test('whole-sequence take owes both keyed and unkeyed resource branches', () => {
  assert.match(run(undefined, value => {
    const take = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'take');
    delete take.resource_assurance.entrypoint.variants.keyed;
  }), /RelA take: entrypoint needs unkeyed and keyed resource variants/);
});

test('whole-sequence filter proof reuse needs its shared entrypoint grant', () => {
  assert.match(run(undefined, value => {
    const filter = value.routes.find(entry => entry.family === 'RelA' &&
      entry.operation === 'filter');
    for (const grant of filter.shared_proof_reuse) {
      grant.paths = grant.paths.filter(path => path !== 'entrypoint');
    }
  }), /RelA filter: shared proof reuse lacks an exact common entrypoint/);
});

test('resource completion also rejects an unassured SGA route', () => {
  assert.match(run(undefined, value => {
    const route = value.routes.find(entry => entry.family === 'SGA' &&
      entry.operation === 'match_nodes');
    delete route.path_assurance.entrypoint;
  }, ['--require-boundary-complete']),
  /SGA match_nodes: entrypoint boundary assurance is missing/);
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
      entry.operation === 'match_nodes');
    path.path_assurance = {
      entrypoint: {
        exact_limit: 'select_input_exact',
        one_short_limit: 'select_input_one_short',
        in_flight_cancel: 'select_in_flight_host_timer',
        cleanup: 'select_cancel_cleanup',
      },
    };
  }, ['--require-boundary-complete']),
  /SGA match_nodes: entrypoint exact_limit lacks an executable fixture/);
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
    value.routes.find(entry => entry.operation === 'match_nodes')
      .entrypoint.symbol = 'missing_shortest_entrypoint';
  }), /SGA match_nodes: production entrypoint symbol is missing/);
});

test('resource gate rejects a bypassed provider call', () => {
  assert.match(run(undefined, value => {
    value.routes.find(entry => entry.operation === 'match_nodes')
      .dispatch.marker = '@sga.start_shortest_bypass(';
  }), /SGA match_nodes: dispatch marker does not reach production source/);
});

test('resource gate refuses a test fixture as the production entrypoint', () => {
  assert.match(run(undefined, value => {
    value.routes.find(entry => entry.operation === 'match_nodes')
      .entrypoint.path = 'src/query_integration/property_graph_construction_wbtest.mbt';
  }), /SGA match_nodes: entrypoint must bind a production source/);
});

test('resource gate rejects a reviewed operation without its exact boundary fixture', () => {
  assert.match(run(undefined, value => {
    value.routes.find(entry => entry.operation === 'match_nodes')
      .boundary_tests[0].fixture = 'missing exact boundary';
  }), /SGA match_nodes: missing operation boundary fixture/);
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

test('strict cross join gate retains both in-flight product paths', () => {
  for (const role of [
    'external_product_node_timer_cancel_cleanup',
    'direct_product_node_timer_cancel_cleanup',
  ]) {
    assert.match(run(undefined, value => {
      const join = value.routes.find(entry => entry.family === 'RelA' &&
        entry.operation === 'cross_join');
      join.environment_tests = join.environment_tests.filter(item =>
        item.role !== role);
    }, ['--require-boundary-complete']),
    /RelA cross_join: in-flight Host cancellation evidence is missing/);
  }
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
  }), /RelA assert_rows: ordinary_entrypoint needs both resource variants/);
});


test('resource validator inputs are immutable and errors are fresh in either order', () => {
  const options = {root, manifest: manifestTemplate, routes: routesTemplate,
    sources: sourceTemplate, requireBoundaryComplete: true};
  const before = JSON.stringify(options);
  const good = validateResourceAccounting(options);
  assert.deepEqual(good.errors, pendingBoundaryErrors);
  const badManifest = structuredClone(manifestTemplate);
  badManifest.bindings = [];
  const bad = validateResourceAccounting({...options, manifest: badManifest});
  assert.ok(bad.errors.length > 0);
  assert.deepEqual(validateResourceAccounting(options), good);
  assert.deepEqual(validateResourceAccounting({...options, manifest: badManifest}), bad);
  assert.notEqual(validateResourceAccounting(options).errors, good.errors);
  assert.equal(JSON.stringify(options), before);
  good.errors.push('caller-owned error collection');
  assert.deepEqual(validateResourceAccounting(options).errors, pendingBoundaryErrors);
});

test('resource validator matches the CLI for scoped success and strict independent rejections', () => {
  const omitMixed = routes => { routes.mixed_paths = []; };
  assert.equal(evaluate(undefined, omitMixed).errors.length, 0);
  assert.match(run(undefined, omitMixed, ['--require-boundary-complete']),
    /typed prefix mixed-stage assurance is missing/u);
  for (const [mutator, routeMutator, args, gapsText] of [
    [undefined, undefined],
    [undefined, undefined, ['--require-boundary-complete']],
    [undefined, omitMixed, ['--require-boundary-complete']],
    [manifest => { manifest.bindings = []; }],
    [undefined, routes => { routes.routes[0].entrypoint = {path: 'missing.mbt'}; }],
    [undefined, undefined, ['--check-summary'], 'no summary markers'],
  ]) {
    assert.equal(run(mutator, routeMutator, args, gapsText),
      runCli(mutator, routeMutator, args, gapsText));
  }
});

test('resource source snapshots preserve missing files and cannot leak fixture edits', () => {
  assert.ok(Object.isFrozen(sourceTemplate));
  const inventory = sourceTemplate[join(root, manifestTemplate.inventories.rela)];
  assert.ok(Object.isFrozen(inventory.json.operations));
  assert.throws(() => { inventory.json.operations.length = 0; }, TypeError);
  const input = structuredClone(manifestTemplate);
  input.profiles[Object.keys(input.profiles)[0]].sources.push('src/absent-resource-fixture.mbt');
  const changed = loadResourceAccountingSources({root, manifest: input,
    routes: routesTemplate, previousSources: sourceTemplate});
  assert.equal(changed[join(root, 'src/absent-resource-fixture.mbt')].exists, false);
  assert.equal(Object.hasOwn(sourceTemplate, join(root, 'src/absent-resource-fixture.mbt')), false);
  assert.match(validateResourceAccounting({root, manifest: input,
    routes: routesTemplate, sources: changed}).errors.join('\n'), /missing source/u);
  assert.deepEqual(evaluate().errors, []);
});


test('resource CLI honors environment, strict checks, and summary write custody', () => {
  const directory = mkdtempSync(join(tmpdir(), 'actql-resource-cli-'));
  const target = join(directory, 'manifest.json');
  const gapsTarget = join(directory, 'gaps.md');
  const invoke = (args = [], extraEnv = {}) => execFileSync(process.execPath,
    [script, ...args], {cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
      env: {...process.env, ACTQL_LOCAL_RESOURCE_AUDIT: target,
        ACTQL_LOCAL_RESOURCE_GAPS: gapsTarget, ...extraEnv}});
  try {
    writeFileSync(target, JSON.stringify(manifestTemplate));
    const stale = gapsTemplate.replace('| Registered operations | 69 |',
      '| Registered operations | 0 |');
    assert.notEqual(stale, gapsTemplate);
    writeFileSync(gapsTarget, stale);
    assert.throws(() => invoke(['--check-summary']), error =>
      error.status === 1 && /summary is stale/u.test(String(error.stderr)));
    const incompleteRoutes = structuredClone(routesTemplate);
    delete incompleteRoutes.routes.find(route=>route.operation==='subgraph')
      .path_assurance.entrypoint;
    const incompletePath = join(directory, 'incomplete-routes.json');
    writeFileSync(incompletePath, JSON.stringify(incompleteRoutes));
    writeFileSync(target, JSON.stringify({...manifestTemplate,
      production_routes:incompletePath}));
    assert.throws(() => invoke(['--check-summary', '--write-summary',
      '--require-boundary-complete']), error => error.status === 1 &&
      String(error.stderr).includes('SGA subgraph: entrypoint boundary assurance is missing'));
    assert.equal(readFileSync(gapsTarget, 'utf8'), stale);
    writeFileSync(target, JSON.stringify(manifestTemplate));
    assert.match(invoke(['--check-summary', '--write-summary']), /69 operations/u);
    assert.equal(readFileSync(gapsTarget, 'utf8'), gapsTemplate);
    const rejected = structuredClone(manifestTemplate);
    rejected.bindings = [];
    writeFileSync(target, JSON.stringify(rejected));
    writeFileSync(gapsTarget, stale);
    assert.throws(() => invoke(['--check-summary', '--write-summary']), error =>
      error.status === 1 && /bindings must exactly preserve/u.test(String(error.stderr)));
    assert.equal(readFileSync(gapsTarget, 'utf8'), stale);
    assert.throws(() => invoke([], {ACTQL_LOCAL_RESOURCE_AUDIT:
      join(directory, 'missing.json')}), error => error.status === 1);
    writeFileSync(target, JSON.stringify(manifestTemplate));
    assert.throws(() => invoke(['--check-summary'], {ACTQL_LOCAL_RESOURCE_GAPS:
      join(directory, 'missing.md')}), error =>
      error.status === 1 && /ledger is missing/u.test(String(error.stderr)));
    assert.match(invoke([], {ACTQL_LOCAL_RESOURCE_AUDIT: '',
      ACTQL_LOCAL_RESOURCE_GAPS: ''}), /69 operations/u);
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
  assert.equal(existsSync(directory), false);
});

test('resource snapshots are explicit per-run source bytes rather than validation caches', () => {
  const directory = mkdtempSync(join(tmpdir(), 'actql-resource-snapshot-'));
  const file = join(directory, 'source.mbt');
  try {
    const manifest = structuredClone(manifestTemplate);
    manifest.profiles[Object.keys(manifest.profiles)[0]].sources.push(file);
    writeFileSync(file, 'first source');
    const first = loadResourceAccountingSources({root, manifest,
      routes: routesTemplate, previousSources: sourceTemplate});
    writeFileSync(file, 'second source');
    const reused = loadResourceAccountingSources({root, manifest,
      routes: routesTemplate, previousSources: first});
    const fresh = loadResourceAccountingSources({root, manifest, routes: routesTemplate});
    assert.equal(first[file].text, 'first source');
    assert.equal(reused[file].text, 'first source');
    assert.equal(fresh[file].text, 'second source');
    assert.equal(Object.hasOwn(sourceTemplate, file), false);
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
  assert.equal(existsSync(directory), false);
});
