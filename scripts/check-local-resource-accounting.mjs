import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const defaultManifest = path.join(
  root,
  'docs/reviews/2026-09-23-local-resource-accounting-audit.json',
);
const manifestPath = process.env.ACTQL_LOCAL_RESOURCE_AUDIT
  ? path.resolve(process.env.ACTQL_LOCAL_RESOURCE_AUDIT)
  : defaultManifest;
const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const manifest = readJson(manifestPath);
const errors = [];
const fail = message => errors.push(message);
const requireBoundaryComplete =
  process.argv.includes('--require-boundary-complete');

if (manifest.version !== 'actql-local-resource-accounting-audit/0.1') {
  fail(`unexpected manifest version: ${manifest.version}`);
}

const inventoryPaths = manifest.inventories ?? {};
const relaPath = path.join(root, inventoryPaths.rela ?? '');
const familyPath = path.join(root, inventoryPaths.families ?? '');
const routesPath = path.resolve(root, manifest.production_routes ?? '');
if (!fs.existsSync(relaPath) || !fs.existsSync(familyPath)) {
  fail('both authoritative operation inventories must exist');
}
if (!manifest.production_routes || !fs.existsSync(routesPath)) {
  fail('production route inventory must exist');
}
const rela = fs.existsSync(relaPath) ? readJson(relaPath) : {operations: []};
const families = fs.existsSync(familyPath)
  ? readJson(familyPath)
  : {operations: []};

const requiredFacets = manifest.required_facets ?? [];
const expectedFacets = [
  'admission_before_allocation',
  'charged_bounded_work',
  'finite_stop_observation',
  'temporary_retained_peak_scope',
  'cleanup_owner',
];
if (requiredFacets.length !== expectedFacets.length ||
  expectedFacets.some(facet => !requiredFacets.includes(facet))) {
  fail('required accounting facets do not match the release contract');
}
const requiredPhases = manifest.required_phases ?? [];
const expectedPhases = [
  'prepare',
  'resume',
  'order_or_hash',
  'value_construction',
  'finalize',
  'cancel',
  'cleanup',
];
if (requiredPhases.length !== expectedPhases.length ||
  expectedPhases.some(phase => !requiredPhases.includes(phase))) {
  fail('required execution phases do not match the release contract');
}

const descriptionFields = [
  'work_unit',
  'cumulative_ceiling',
  'temporary_scope',
  'retained_scope',
  'peak_scope',
  'noninterruptible_bound',
  'stop_observation',
  'cleanup_owner',
];
const profiles = manifest.profiles ?? {};
for (const [name, profile] of Object.entries(profiles)) {
  for (const field of descriptionFields) {
    if (typeof profile[field] !== 'string' || profile[field].length < 20) {
      fail(`${name}: missing specific ${field}`);
    }
  }
  const phaseInventory = profile.phase_inventory ?? {};
  for (const phase of requiredPhases) {
    if (typeof phaseInventory[phase] !== 'string' ||
      phaseInventory[phase].length < 30) {
      fail(`${name}: missing specific ${phase} phase accounting`);
    }
  }
  const extraPhases = Object.keys(phaseInventory)
    .filter(phase => !requiredPhases.includes(phase));
  if (extraPhases.length > 0) {
    fail(`${name}: unknown execution phase ${extraPhases[0]}`);
  }
  const sources = profile.sources ?? [];
  if (sources.length === 0 || new Set(sources).size !== sources.length) {
    fail(`${name}: source inventory must be nonempty and unique`);
  }
  for (const source of sources) {
    if (!fs.existsSync(path.join(root, source))) {
      fail(`${name}: missing source ${source}`);
    }
  }
  const covered = new Set();
  const evidence = profile.evidence ?? [];
  if (evidence.length === 0) fail(`${name}: evidence is required`);
  for (const item of evidence) {
    const evidencePath = path.join(root, item.path ?? '');
    if (!item.path || !fs.existsSync(evidencePath)) {
      fail(`${name}: missing evidence file ${item.path}`);
      continue;
    }
    if (typeof item.fixture !== 'string' || item.fixture.length === 0 ||
      !fs.readFileSync(evidencePath, 'utf8').includes(item.fixture)) {
      fail(`${name}: missing fixture ${item.fixture} in ${item.path}`);
    }
    const facets = item.facets ?? [];
    if (facets.length === 0 || new Set(facets).size !== facets.length) {
      fail(`${name}: evidence facets must be nonempty and unique`);
    }
    for (const facet of facets) {
      if (!requiredFacets.includes(facet)) {
        fail(`${name}: unknown accounting facet ${facet}`);
      }
      covered.add(facet);
    }
  }
  for (const facet of requiredFacets) {
    if (!covered.has(facet)) fail(`${name}: missing ${facet} evidence`);
  }
}

const expected = [
  ...rela.operations.map(entry => ({
    inventory: 'rela',
    family: 'RelA',
    operation: entry.operation,
  })),
  ...families.operations.map(entry => ({
    inventory: 'families',
    family: entry.family,
    operation: entry.operation,
  })),
];
const expectedKeys = expected.map(
  entry => `${entry.inventory}:${entry.family}:${entry.operation}`,
);
const actual = [];
for (const binding of manifest.bindings ?? []) {
  if (!profiles[binding.profile]) {
    fail(`binding uses unknown profile ${binding.profile}`);
  }
  const family = binding.inventory === 'rela' ? 'RelA' : binding.family;
  for (const operation of binding.operations ?? []) {
    actual.push({
      inventory: binding.inventory,
      family,
      operation,
      profile: binding.profile,
    });
  }
}
const actualKeys = actual.map(
  entry => `${entry.inventory}:${entry.family}:${entry.operation}`,
);
if (new Set(actualKeys).size !== actualKeys.length) {
  fail('operation bindings must be unique');
}
if (actualKeys.length !== expectedKeys.length ||
  expectedKeys.some((key, index) => actualKeys[index] !== key)) {
  fail('bindings must exactly preserve both authoritative inventories');
}

const routes = fs.existsSync(routesPath)
  ? readJson(routesPath)
  : {routes: []};
if (routes.version !== 'actql-local-resource-production-routes/0.1') {
  fail(`unexpected production route version: ${routes.version}`);
}
const routeEntries = routes.routes ?? [];
const routeKeys = routeEntries.map(
  entry => `${entry.inventory}:${entry.family}:${entry.operation}`,
);
if (routeKeys.length !== actualKeys.length ||
  actualKeys.some((key, index) => routeKeys[index] !== key) ||
  new Set(routeKeys).size !== routeKeys.length) {
  fail('production routes must exactly preserve both authoritative inventories');
}
for (const [index, route] of routeEntries.entries()) {
  const binding = actual[index];
  const label = `${route.family} ${route.operation}`;
  if (binding?.profile !== route.profile || !profiles[route.profile]) {
    fail(`${label}: production route profile differs from binding`);
  }
  const dispatch = route.dispatch ?? {};
  const entrypoint = route.entrypoint ?? {};
  const productionSources = [['dispatch', dispatch], ['entrypoint', entrypoint]];
  if (route.selected_entrypoint !== undefined) {
    productionSources.push(['selected_entrypoint', route.selected_entrypoint]);
  }
  for (const [role, value] of productionSources) {
    if (typeof value.path !== 'string' ||
      !value.path.startsWith('src/') ||
      value.path.split('/').includes('..') ||
      /(?:_test|_wbtest|\.generated)\./u.test(value.path)) {
      fail(`${label}: ${role} must bind a production source`);
      continue;
    }
    const file = path.join(root, value.path);
    if (!fs.existsSync(file)) {
      fail(`${label}: missing ${role} production source ${value.path}`);
      continue;
    }
    const sourceText = fs.readFileSync(file, 'utf8');
    if (role === 'dispatch' &&
      (typeof value.marker !== 'string' || !sourceText.includes(value.marker))) {
      fail(`${label}: dispatch marker does not reach production source`);
    }
    if (role !== 'dispatch' &&
      (typeof value.symbol !== 'string' ||
        !/^[a-z][a-z0-9_]*$/u.test(value.symbol) ||
        !new RegExp(`(?:^|\\n)(?:pub )?fn(?:\\[[^\\]]+\\])?\\s+${value.symbol}\\s*\\(`, 'u')
          .test(sourceText))) {
      fail(`${label}: production entrypoint symbol is missing`);
    }
  }
  const boundaryTests = route.boundary_tests ?? [];
  const boundaryRoles = new Set();
  for (const item of boundaryTests) {
    if (typeof item.role !== 'string' || boundaryRoles.has(item.role)) {
      fail(`${label}: boundary roles must be named and unique`);
    }
    boundaryRoles.add(item.role);
    const suiteDirectory = {
      'moon:query_integration': 'query_integration',
      'moon:execution_relation': 'execution_relation',
    }[item.suite];
    if (!suiteDirectory ||
      JSON.stringify(item.targets) !== JSON.stringify(['js', 'wasm', 'native']) ||
      typeof item.path !== 'string' ||
      !item.path.startsWith(`src/${suiteDirectory}/`) ||
      !item.path.endsWith('_wbtest.mbt') ||
      typeof item.fixture !== 'string') {
      fail(`${label}: boundary evidence must be suite-connected on all targets`);
      continue;
    }
    const file = path.join(root, item.path);
    if (!fs.existsSync(file) ||
      !fs.readFileSync(file, 'utf8').includes(`test "${item.fixture}"`)) {
      fail(`${label}: missing operation boundary fixture ${item.fixture}`);
    }
  }
  const environmentRoles = new Set();
  for (const item of route.environment_tests ?? []) {
    if (typeof item.role !== 'string' || environmentRoles.has(item.role)) {
      fail(`${label}: environment roles must be named and unique`);
    }
    environmentRoles.add(item.role);
    const suitePath = {
      'node:duckdb_standard_host':
        'adapters/connectors/duckdb/node/test/standard-host.test.mjs',
    }[item.suite];
    if (!suitePath || item.path !== suitePath ||
      JSON.stringify(item.targets) !== JSON.stringify(['node']) ||
      typeof item.fixture !== 'string') {
      fail(`${label}: environment evidence must name an executable suite`);
      continue;
    }
    const sourceText = fs.readFileSync(path.join(root, suitePath), 'utf8');
    if (!sourceText.includes(`name: '${item.fixture}'`)) {
      fail(`${label}: missing environment fixture ${item.fixture}`);
    }
  }
  const boundaryAssurance = route.boundary_assurance;
  if (boundaryAssurance !== undefined) {
    const requiredProofs = [
      'exact_limit',
      'one_short_limit',
      'in_flight_cancel',
      'cleanup',
    ];
    if (!boundaryAssurance || typeof boundaryAssurance !== 'object' ||
      Array.isArray(boundaryAssurance) ||
      Object.keys(boundaryAssurance).length !== requiredProofs.length ||
      requiredProofs.some(proof =>
        typeof boundaryAssurance[proof] !== 'string')) {
      fail(`${label}: boundary assurance must name all four proof roles`);
    } else {
      for (const proof of requiredProofs) {
        const role = boundaryAssurance[proof];
        const roles = proof === 'in_flight_cancel'
          ? environmentRoles
          : boundaryRoles;
        if (!roles.has(role)) {
          fail(`${label}: ${proof} does not bind an executable fixture`);
        }
      }
    }
  } else if (requireBoundaryComplete) {
    fail(`${label}: boundary assurance is missing`);
  }
  if (['traverse', 'apply_graph_delta'].includes(route.operation) &&
    route.family === 'SGA' &&
    !boundaryRoles.has('exact_one_short_and_cancel_cleanup')) {
    fail(`${label}: reviewed exact/cancel boundary fixture is missing`);
  }
  if (route.family === 'RelA' && route.operation === 'filter') {
    if (route.selected_entrypoint?.symbol !==
      'selected_binding_rows_execution') {
      fail(`${label}: bounded selected entrypoint is missing`);
    }
    for (const role of [
      'filter_mixed_stage_lifetime',
      'filter_input_exact',
      'filter_input_one_short',
      'filter_cancel_cleanup',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: reviewed ${role} fixture is missing`);
      }
    }
    if (!environmentRoles.has('filter_in_flight_host_timer')) {
      fail(`${label}: in-flight Host cancellation fixture is missing`);
    }
  }
  if (route.family === 'RelA' && route.operation === 'select') {
    if (route.selected_entrypoint?.symbol !==
      'selected_binding_rows_execution') {
      fail(`${label}: bounded selected entrypoint is missing`);
    }
    for (const role of [
      'select_mixed_stage_lifetime',
      'select_input_exact',
      'select_input_one_short',
      'select_cancel_cleanup',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: reviewed ${role} fixture is missing`);
      }
    }
  }
  if (route.family === 'RelA' && route.operation === 'take') {
    for (const role of [
      'mixed_stage_sort_quantum_and_lifetime',
      'mixed_stage_sort_cancel_and_cleanup',
      'key_completion_work_exact_one_short',
      'key_completion_workspace_exact_one_short',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: reviewed ${role} fixture is missing`);
      }
    }
  }
  if (route.family === 'RelA' && route.operation === 'sort') {
    for (const role of [
      'mixed_stage_sort_quantum_and_lifetime',
      'selected_sort_cancel_cleanup',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: reviewed ${role} fixture is missing`);
      }
    }
    if (!environmentRoles.has('selected_sort_wide_comparison_host_timer')) {
      fail(`${label}: selected sort Host timer evidence is missing`);
    }
  }
  if (route.family === 'RelA' && route.operation === 'assert_rows') {
    for (const role of [
      'assert_where_mixed_stage_lifetime',
      'assert_where_failure_cleanup',
      'assert_where_cancel_cleanup',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: reviewed ${role} fixture is missing`);
      }
    }
  }
  if (route.family === 'RelA' && route.operation === 'cross_join') {
    for (const role of [
      'product_work_workspace_exact_one_short',
      'managed_cancel_cleanup',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: reviewed ${role} fixture is missing`);
      }
    }
  }
}

for (const entry of rela.operations) {
  if (entry.layers?.performance !== 'complete' ||
    (entry.evidence?.performance ?? []).length === 0) {
    fail(`RelA ${entry.operation}: performance evidence is incomplete`);
  }
}
for (const entry of families.operations) {
  const layers = new Set(entry.completed_layers ?? []);
  if (entry.status !== 'complete' || !layers.has('resources') ||
    !layers.has('cancellation')) {
    fail(`${entry.family} ${entry.operation}: resource layers are incomplete`);
  }
}

if (errors.length > 0) {
  for (const error of errors) console.error(error);
  process.exitCode = 1;
} else {
  const boundaryRoutes = routeEntries.filter(route =>
    (route.boundary_tests ?? []).length > 0).length;
  const assuredRoutes = routeEntries.filter(route =>
    route.boundary_assurance !== undefined).length;
  console.log(
    `Local resource accounting: ${actual.length} operations, ` +
    `${Object.keys(profiles).length} implementation profiles, ` +
    `${routeEntries.length} production routes mapped, ` +
    `${boundaryRoutes} with operation-specific boundary records, ` +
    `${assuredRoutes} with complete boundary assurance; ` +
    `full boundary completion is not asserted.`,
  );
}
