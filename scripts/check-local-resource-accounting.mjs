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
const assertionVariants = new Set(
  rela.operations.find(entry => entry.operation === 'assert_rows')
    ?.variant_scope ?? [],
);
if (!assertionVariants.has('where') ||
  !assertionVariants.has('unique_by')) {
  fail('RelA assert_rows: formal where and unique_by variants are required');
}

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
if (routes.version !== 'actql-local-resource-production-routes/0.2') {
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
const assuredPaths = manifest.assured_production_paths;
if (!Array.isArray(assuredPaths)) {
  fail('assured production paths must be an array');
} else {
  const claimKeys = [];
  for (const claim of assuredPaths) {
    const key = `${claim?.family}:${claim?.operation}:${claim?.path}`;
    claimKeys.push(key);
    const route = routeEntries.find(entry =>
      entry.family === claim?.family &&
      entry.operation === claim?.operation);
    if (!route ||
      ![
        'entrypoint',
        'ordinary_entrypoint',
        'selected_entrypoint',
        'external_input_entrypoint',
        'same_stage_entrypoint',
        'zero_input_entrypoint',
        'relation_entrypoint',
        'view_entrypoint',
      ]
        .includes(claim?.path) ||
      route[claim.path] === undefined ||
      route.path_assurance?.[claim.path] === undefined ||
      route.resource_assurance?.[claim.path] === undefined ||
      Object.keys(claim).length !== 3) {
      fail(`${key}: assured production claim lacks its exact route proofs`);
    }
  }
  const recordedKeys = routeEntries.flatMap(route =>
    Object.keys(route.resource_assurance ?? {}).map(pathName =>
      `${route.family}:${route.operation}:${pathName}`));
  if (new Set(claimKeys).size !== claimKeys.length ||
    claimKeys.length !== recordedKeys.length ||
    claimKeys.some(key => !recordedKeys.includes(key))) {
    fail('assured production claims differ from resource-assured routes');
  }
}
const mixedPaths = routes.mixed_paths ?? [];
if (!Array.isArray(mixedPaths)) {
  fail('mixed production paths must be an array');
} else {
  const names = new Set();
  for (const mixed of mixedPaths) {
    const label = `mixed path ${mixed?.id}`;
    if (!mixed || typeof mixed !== 'object' || Array.isArray(mixed)) {
      fail(`${label}: entry must be an object`);
      continue;
    }
    if (typeof mixed?.id !== 'string' || names.has(mixed.id)) {
      fail(`${label}: id must be unique`);
    }
    names.add(mixed.id);
    if (!['Graph', 'Events', 'Vectors'].includes(mixed.carrier) ||
      mixed.standalone_prefix_provider !== false ||
      !Array.isArray(mixed.operations) || mixed.operations.length < 3 ||
      new Set(mixed.operations).size !== mixed.operations.length ||
      mixed.operations.some(operation =>
        actual.filter(entry => entry.operation === operation).length !== 1)) {
      fail(`${label}: must bind an unselected typed Carrier prefix and Relation operation`);
    } else {
      const family = {Graph: 'SGA', Events: 'TEA', Vectors: 'VecA'}[
        mixed.carrier
      ];
      const bridge = {
        Graph: ['node_rows', 'edge_rows'],
        Events: ['events'],
        Vectors: ['vectors'],
      }[mixed.carrier];
      const entryFor = operation => actual.find(entry =>
        entry.operation === operation);
      if (entryFor(mixed.operations[0])?.family !== family ||
        !mixed.operations.slice(1, -1).some(operation =>
          bridge.includes(operation) &&
          entryFor(operation)?.family === 'Bridge') ||
        entryFor(mixed.operations.at(-1))?.family !== 'RelA') {
        fail(`${label}: Carrier, formal Bridge, and Relation roles differ`);
      }
    }
    const host = mixed.standard_host ?? {};
    if (host.suite !== 'moon:query_integration' ||
      JSON.stringify(host.targets) !== JSON.stringify(['js', 'wasm', 'native']) ||
      typeof host.path !== 'string' ||
      !host.path.startsWith('src/query_integration/') ||
      host.path.split('/').includes('..') ||
      !host.path.endsWith('_wbtest.mbt') ||
      typeof host.fixture !== 'string' ||
      !fs.existsSync(path.join(root, host.path)) ||
      !fs.readFileSync(path.join(root, host.path), 'utf8')
        .includes(`test "${host.fixture}"`)) {
      fail(`${label}: missing three-target standard Host consumer fixture`);
    }
    const nodeHost = 'adapters/connectors/duckdb/node/test/standard-host.test.mjs';
    for (const [scope, field] of [
      ['prefix', 'in_flight_cancel'],
      ['selected Relation', 'selected_in_flight_cancel'],
    ]) {
      const cancellation = mixed[field] ?? {};
      if (cancellation.suite !== 'node:duckdb_standard_host' ||
        JSON.stringify(cancellation.targets) !== JSON.stringify(['node']) ||
        cancellation.path !== nodeHost ||
        typeof cancellation.fixture !== 'string' ||
        !fs.readFileSync(path.join(root, nodeHost), 'utf8')
          .includes(`name: '${cancellation.fixture}'`)) {
        fail(`${label}: missing delivered ${scope} cancellation fixture`);
      }
    }
  }
  if (requireBoundaryComplete) {
    for (const carrier of ['Graph', 'Events', 'Vectors']) {
      if (!mixedPaths.some(path => path.carrier === carrier &&
        path.standalone_prefix_provider === false)) {
        fail(`${carrier}: unselected prefix mixed-stage assurance is missing`);
      }
    }
  }
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
  if (route.additional_dispatch !== undefined) {
    productionSources.push(['dispatch', route.additional_dispatch]);
  }
  if (route.selected_entrypoint !== undefined) {
    productionSources.push(['selected_entrypoint', route.selected_entrypoint]);
  }
  if (route.ordinary_entrypoint !== undefined) {
    productionSources.push(['ordinary_entrypoint', route.ordinary_entrypoint]);
  }
  if (route.external_input_entrypoint !== undefined) {
    productionSources.push([
      'external_input_entrypoint', route.external_input_entrypoint,
    ]);
  }
  if (route.same_stage_entrypoint !== undefined) {
    productionSources.push([
      'same_stage_entrypoint', route.same_stage_entrypoint,
    ]);
  }
  if (route.zero_input_entrypoint !== undefined) {
    productionSources.push([
      'zero_input_entrypoint', route.zero_input_entrypoint,
    ]);
  }
  if (route.relation_entrypoint !== undefined) {
    productionSources.push([
      'relation_entrypoint', route.relation_entrypoint,
    ]);
  }
  if (route.view_entrypoint !== undefined) {
    productionSources.push(['view_entrypoint', route.view_entrypoint]);
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
      'moon:local_sga': 'local_sga',
      'moon:local_tea': 'local_tea',
      'moon:local_veca': 'local_veca',
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
  if (route.family === 'RelA' && route.operation === 'values') {
    const requiredValuesRoles = [
      'zero_input_quantum_and_output',
      'zero_input_work_and_workspace',
      'zero_input_cancel_cleanup',
      'zero_input_two_consumers',
      'zero_input_mixed_stage_two_consumers',
      'zero_input_derive_two_consumers',
      'zero_input_sort_take_two_consumers',
      'zero_input_unique_two_consumers',
    ];
    if (route.zero_input_entrypoint?.symbol !== 'values_provider' ||
      requiredValuesRoles.some(role => !boundaryRoles.has(role))) {
      fail(`${label}: bounded zero-input Values route lacks its production evidence`);
    }
  }
  if (route.family === 'RelA' && route.operation === 'append') {
    if (route.external_input_entrypoint?.symbol !== 'append_provider') {
      fail(`${label}: bounded external append provider is missing`);
    }
    if (route.same_stage_entrypoint?.symbol !== 'append_provider') {
      fail(`${label}: bounded same-stage append provider is missing`);
    }
    for (const role of [
      'append_work_workspace_exact_one_short',
      'append_two_consumer_reclamation',
      'append_self_occurrence_reclamation',
      'append_external_work_workspace_exact_one_short',
      'append_external_input_value_exact_one_short',
      'append_external_host_receiving_input_limit',
      'append_external_nested_input_cancel_cleanup',
      'append_external_quantum_and_output',
      'append_external_nullable_alignment',
      'append_external_cancel_cleanup',
      'append_same_stage_two_consumer_reclamation',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: ${role} fixture is missing`);
      }
    }
  }
  if (route.family === 'RelA' && route.operation === 'cross_join' &&
    (route.same_stage_entrypoint?.symbol !== 'cross_join_provider' ||
      !boundaryRoles.has('direct_product_host_two_consumers'))) {
    fail(`${label}: bounded same-stage cross join evidence is missing`);
  }
  if (route.family === 'RelA' && route.operation === 'distinct') {
    for (const role of [
      'distinct_unkeyed_workspace_exact_one_short',
      'distinct_unkeyed_work_exact_one_short',
      'distinct_keyed_workspace_exact_one_short',
      'distinct_keyed_work_exact_one_short',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: ${role} fixture is missing`);
      }
    }
  }
  if (route.family === 'VecA' && route.operation === 'merge_rankings' &&
    !boundaryRoles.has('ranking_bounded_record_output_cancel_cleanup')) {
    fail(`${label}: bounded ranking assembly fixture is missing`);
  }
  if (route.family === 'TEA' && route.operation === 'window_events') {
    for (const role of [
      'window_control_work_exact_one_short',
      'window_workspace_exact_one_short',
      'window_empty_finish_work_exact_one_short',
      'window_kernel_cancel_cleanup',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: ${role} fixture is missing`);
      }
    }
  }
  if (route.family === 'TEA' && route.operation === 'watermark_events') {
    for (const role of [
      'watermark_control_work_exact_one_short',
      'watermark_workspace_exact_one_short',
      'watermark_empty_finish_work_exact_one_short',
      'watermark_kernel_cancel_cleanup',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: ${role} fixture is missing`);
      }
    }
  }
  if (route.family === 'TEA' && route.operation === 'dedupe_events') {
    for (const role of [
      'dedupe_incremental_initialization_cancel_cleanup',
      'dedupe_scratch_workspace_admission',
      'dedupe_control_work_exact_one_short',
      'dedupe_output_workspace_exact_one_short',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: ${role} fixture is missing`);
      }
    }
  }
  if (route.family === 'TEA' && route.operation === 'session') {
    if (route.relation_entrypoint?.symbol !== 'start_session_relation' ||
      route.view_entrypoint?.symbol !== 'start_session_view') {
      fail(`${label}: all three session source entrypoints must be registered`);
    }
    for (const role of [
      'session_incremental_initialization_cancel_cleanup',
      'session_control_work_exact_one_short',
      'session_output_workspace_exact_one_short',
      'session_relation_work_workspace_exact_one_short',
      'session_view_work_workspace_exact_one_short',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: ${role} fixture is missing`);
      }
    }
  }
  if (route.family === 'TEA' && route.operation === 'time_series') {
    for (const role of [
      'time_series_output_exact_one_short_and_finish_work',
      'time_series_output_value_work_exact_one_short',
      'time_series_control_work_exact_one_short',
      'time_series_schema_workspace_exact_one_short',
      'time_series_cancel_cleanup',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: ${role} fixture is missing`);
      }
    }
  }
  for (const [operation, prefix] of [
    ['interval_join', 'interval'],
    ['asof_join', 'asof'],
  ]) {
    if (route.family === 'TEA' && route.operation === operation) {
      for (const role of [
        `${prefix}_metadata_workspace_preflight`,
        `${prefix}_output_workspace_exact_one_short`,
        `${prefix}_work_exact_one_short`,
        `${prefix}_kernel_cancel_cleanup`,
      ]) {
        if (!boundaryRoles.has(role)) {
          fail(`${label}: ${role} fixture is missing`);
        }
      }
    }
  }
  if (route.family === 'TEA' && route.operation === 'sequence') {
    for (const role of [
      'sequence_quantum_one_output_and_cleanup',
      'sequence_in_flight_cancel_cleanup',
      'sequence_output_limit_cleanup',
      'sequence_column_resolution_work_independent_exact_one_short',
      'sequence_wide_init_cancel_cleanup',
      'sequence_workspace_exact_one_short',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: ${role} fixture is missing`);
      }
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
  if (route.family === 'TEA' && route.operation === 'window_events') {
    for (const role of [
      'window_fixed_host_timer',
      'window_sliding_host_timer',
    ]) {
      if (!environmentRoles.has(role)) {
        fail(`${label}: ${role} fixture is missing`);
      }
    }
  }
  if (route.family === 'TEA' && route.operation === 'watermark_events' &&
    !environmentRoles.has('watermark_host_timer')) {
    fail(`${label}: watermark_host_timer fixture is missing`);
  }
  if (route.family === 'TEA' && route.operation === 'dedupe_events' &&
    !environmentRoles.has('dedupe_host_timer')) {
    fail(`${label}: dedupe_host_timer fixture is missing`);
  }
  if (route.family === 'TEA' && route.operation === 'session' &&
    !environmentRoles.has('session_host_timer')) {
    fail(`${label}: session_host_timer fixture is missing`);
  }
  if (route.family === 'TEA' && route.operation === 'time_series' &&
    !environmentRoles.has('time_series_host_timer')) {
    fail(`${label}: time_series_host_timer fixture is missing`);
  }
  for (const operation of ['interval_join', 'asof_join']) {
    if (route.family === 'TEA' && route.operation === operation &&
      !environmentRoles.has(`${operation}_host_in_flight_cancel`)) {
      fail(`${label}: ${operation}_host_in_flight_cancel fixture is missing`);
    }
  }
  if (route.family === 'TEA' && route.operation === 'sequence' &&
    !environmentRoles.has('sequence_host_in_flight_cancel')) {
    fail(`${label}: sequence_host_in_flight_cancel fixture is missing`);
  }
  if (route.family === 'RelA' && route.operation === 'append' &&
    !environmentRoles.has('append_same_stage_node_timer_cancel_cleanup')) {
    fail(`${label}: same-stage append timer evidence is missing`);
  }
  if (route.family === 'RelA' && route.operation === 'values' &&
    !environmentRoles.has('zero_input_derive_timer_cancel_cleanup')) {
    fail(`${label}: same-stage derive timer evidence is missing`);
  }
  if (route.family === 'RelA' && route.operation === 'cross_join' &&
    !environmentRoles.has('direct_product_node_timer_cancel_cleanup')) {
    fail(`${label}: same-stage cross join timer evidence is missing`);
  }
  if (route.family === 'RelA' && route.operation === 'distinct' &&
    (!environmentRoles.has('same_stage_distinct_timer_cancel_cleanup') ||
      !environmentRoles.has('ordinary_distinct_in_flight_host_timer'))) {
    fail(`${label}: both distinct timer paths need executable evidence`);
  }
  const validateAssurance = (scope, boundaryAssurance, rolePrefix) => {
    if (boundaryAssurance === undefined) return;
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
      fail(`${label}: ${scope} assurance must name all four proof roles`);
    } else {
      for (const proof of requiredProofs) {
        const role = boundaryAssurance[proof];
        const roles = proof === 'in_flight_cancel'
          ? environmentRoles
          : boundaryRoles;
        if (rolePrefix && !role.startsWith(rolePrefix)) {
          fail(`${label}: ${scope} ${proof} uses another variant's proof`);
        }
        if (!roles.has(role)) {
          fail(`${label}: ${scope} ${proof} lacks an executable fixture`);
        }
      }
    }
  };
  const requiredPaths = [
    'entrypoint',
    ...(route.ordinary_entrypoint ? ['ordinary_entrypoint'] : []),
    ...(route.selected_entrypoint ? ['selected_entrypoint'] : []),
    ...(route.external_input_entrypoint ? ['external_input_entrypoint'] : []),
    ...(route.same_stage_entrypoint ? ['same_stage_entrypoint'] : []),
    ...(route.zero_input_entrypoint ? ['zero_input_entrypoint'] : []),
    ...(route.relation_entrypoint ? ['relation_entrypoint'] : []),
    ...(route.view_entrypoint ? ['view_entrypoint'] : []),
  ];
  const pathAssurance = route.path_assurance ?? {};
  const proofPaths = new Map();
  const recordProofPaths = (pathName, assurance) => {
    const proofSets = route.family === 'RelA' &&
      route.operation === 'assert_rows'
      ? Object.values(assurance?.variants ?? {})
      : [assurance];
    for (const proofSet of proofSets) {
      for (const role of Object.values(proofSet ?? {})) {
        if (typeof role !== 'string') continue;
        if (!proofPaths.has(role)) proofPaths.set(role, new Set());
        proofPaths.get(role).add(pathName);
      }
    }
  };
  if (route.boundary_assurance !== undefined ||
    route.selected_boundary_assurance !== undefined ||
    route.selected_variant_assurance !== undefined) {
    fail(`${label}: flat or legacy assurance bypasses production paths`);
  }
  if (!pathAssurance || typeof pathAssurance !== 'object' ||
    Array.isArray(pathAssurance)) {
    fail(`${label}: path assurance must be an object`);
  } else {
    for (const pathName of Object.keys(pathAssurance)) {
      if (!requiredPaths.includes(pathName)) {
        fail(`${label}: assurance names an unregistered production path`);
        continue;
      }
      const assurance = pathAssurance[pathName];
      if (route.family === 'RelA' && route.operation === 'assert_rows') {
        const variants = assurance?.variants ?? {};
        if (Object.keys(assurance ?? {}).length !== 1 ||
          Object.keys(variants).length !== 2 ||
          !variants.where || !variants.unique_by) {
          fail(`${label}: ${pathName} assertion variants need separate proof sets`);
        }
        for (const [variant, prefix] of [
          ['where', 'assert_where_'],
          ['unique_by', 'assert_unique_'],
        ]) {
          validateAssurance(
            `${pathName} ${variant}`,
            variants[variant],
            prefix,
          );
        }
      } else {
        validateAssurance(pathName, assurance);
      }
      recordProofPaths(pathName, assurance);
    }
  }
  const resourceAssurance = route.resource_assurance ?? {};
  if (!resourceAssurance || typeof resourceAssurance !== 'object' ||
    Array.isArray(resourceAssurance)) {
    fail(`${label}: resource assurance must be an object`);
  } else {
    for (const [pathName, dimensions] of Object.entries(resourceAssurance)) {
      if (!requiredPaths.includes(pathName) ||
        pathAssurance[pathName] === undefined) {
        fail(`${label}: resource assurance lacks its production path`);
        continue;
      }
      const assertion = route.family === 'RelA' &&
        route.operation === 'assert_rows';
      const rowVariants = route.family === 'RelA' &&
        ['selected_entrypoint', 'ordinary_entrypoint'].includes(pathName)
          ? {take: ['unkeyed', 'keyed'], sort: ['ordered', 'empty'],
            distinct: ['unkeyed', 'keyed']}[
            route.operation
          ]
        : undefined;
      if (assertion &&
        (Object.keys(dimensions ?? {}).length !== 1 ||
          Object.keys(dimensions?.variants ?? {}).length !== 2 ||
          !dimensions.variants.where || !dimensions.variants.unique_by)) {
        fail(`${label}: ${pathName} needs both assertion resource variants`);
        continue;
      }
      if (rowVariants &&
        (Object.keys(dimensions ?? {}).length !== 1 ||
          Object.keys(dimensions?.variants ?? {}).length !== 2 ||
          rowVariants.some(variant => !dimensions.variants[variant]))) {
        fail(`${label}: ${pathName} needs ${rowVariants.join(' and ')} resource variants`);
        continue;
      }
      const proofSets = assertion || rowVariants
        ? Object.entries(dimensions.variants)
        : [['operation', dimensions]];
      for (const [variant, proofSet] of proofSets) {
        if (!proofSet || typeof proofSet !== 'object' ||
          Array.isArray(proofSet) ||
          Object.keys(proofSet).length !== 2 ||
          !proofSet.work || !proofSet.workspace) {
          fail(`${label}: ${pathName} ${variant} needs work and workspace assurance`);
          continue;
        }
        for (const dimension of ['work', 'workspace']) {
          const proofs = proofSet[dimension];
          if (!proofs || typeof proofs !== 'object' ||
            Array.isArray(proofs) ||
            Object.keys(proofs).length !== 2 ||
            typeof proofs.exact_limit !== 'string' ||
            typeof proofs.one_short_limit !== 'string') {
            fail(`${label}: ${pathName} ${variant} ${dimension} needs exact and one-short proofs`);
            continue;
          }
          for (const role of Object.values(proofs)) {
            if (!boundaryRoles.has(role) ||
              (assertion && !role.startsWith(
                variant === 'unique_by' ? 'assert_unique_' : 'assert_where_')) ||
              (rowVariants &&
                !role.startsWith(`${route.operation}_${variant}_`))) {
              fail(`${label}: ${pathName} ${variant} ${dimension} lacks an executable fixture`);
            }
            if (!proofPaths.has(role)) proofPaths.set(role, new Set());
            proofPaths.get(role).add(pathName);
          }
        }
      }
    }
  }
  const sharedRules = route.shared_resource_rule ?? {};
  if (route.family === 'RelA' && route.operation === 'filter' &&
    resourceAssurance.selected_entrypoint !== undefined &&
    sharedRules.selected_entrypoint === undefined) {
    fail(`${label}: selected filter lacks its shared expression resource rule`);
  }
  if (!sharedRules || typeof sharedRules !== 'object' ||
    Array.isArray(sharedRules)) {
    fail(`${label}: shared resource rules must be an object`);
  } else {
    for (const [pathName, rule] of Object.entries(sharedRules)) {
      const caller = rule?.caller;
      const shared = rule?.shared_entrypoint;
      const roles = rule?.roles;
      const requiredFilterRoles = [
        'filter_shared_nested_workspace',
        'filter_shared_text_work',
        'filter_shared_branch_demand',
      ];
      if (!requiredPaths.includes(pathName) ||
        resourceAssurance[pathName] === undefined ||
        typeof caller !== 'string' ||
        typeof shared !== 'string' ||
        !caller.startsWith('src/') ||
        !shared.startsWith('src/') ||
        !fs.existsSync(path.join(root, caller)) ||
        !fs.existsSync(path.join(root, shared)) ||
        typeof rule.shared_symbol !== 'string' ||
        !/^[a-z][a-z0-9_]*$/u.test(rule.shared_symbol) ||
        !fs.readFileSync(path.join(root, caller), 'utf8')
          .includes(`${rule.shared_symbol}(`) ||
        !new RegExp(`(?:^|\\n)fn\\s+${rule.shared_symbol}\\s*\\(`, 'u')
          .test(fs.readFileSync(path.join(root, shared), 'utf8')) ||
        !Array.isArray(roles) ||
        roles.length !== 3 ||
        new Set(roles).size !== roles.length ||
        roles.some(role => !boundaryRoles.has(role)) ||
        (route.family === 'RelA' && route.operation === 'filter' &&
          requiredFilterRoles.some(role => !roles.includes(role))) ||
        typeof rule.reason !== 'string' || rule.reason.length < 100) {
        fail(`${label}: ${pathName} shared resource rule lacks reachability or evidence`);
      }
    }
  }
  const allowedReuse = Array.isArray(route.shared_proof_reuse)
    ? route.shared_proof_reuse
    : [];
  if (route.shared_proof_reuse !== undefined &&
    !Array.isArray(route.shared_proof_reuse)) {
    fail(`${label}: shared proof reuse must be an array`);
  }
  for (const grant of allowedReuse) {
    const paths = grant?.paths ?? [];
    if (typeof grant?.role !== 'string' ||
      !Array.isArray(paths) || paths.length < 2 ||
      new Set(paths).size !== paths.length ||
      typeof grant.reason !== 'string' || grant.reason.length < 40 ||
      !paths.every(pathName => requiredPaths.includes(pathName)) ||
      !paths.every(pathName =>
        route[pathName]?.path === route[paths[0]]?.path &&
        route[pathName]?.symbol === route[paths[0]]?.symbol) ||
      !proofPaths.has(grant.role) ||
      [...proofPaths.get(grant.role)].some(pathName =>
        !paths.includes(pathName)) ||
      paths.some(pathName => !proofPaths.get(grant.role).has(pathName))) {
      fail(`${label}: shared proof reuse lacks an exact common entrypoint`);
    }
  }
  for (const [role, paths] of proofPaths) {
    if (paths.size > 1 &&
      !allowedReuse.some(grant => grant?.role === role)) {
      fail(`${label}: ${role} is reused across production paths`);
    }
  }
  if (route.family === 'TEA' && route.operation === 'window_events' &&
    (pathAssurance.entrypoint === undefined ||
      resourceAssurance.entrypoint === undefined)) {
    fail(`${label}: fixed and sliding work, workspace, and lifecycle assurance is missing`);
  }
  if (route.family === 'TEA' && route.operation === 'watermark_events' &&
    (pathAssurance.entrypoint === undefined ||
      resourceAssurance.entrypoint === undefined)) {
    fail(`${label}: work, workspace, and lifecycle assurance is missing`);
  }
  if (route.family === 'TEA' && route.operation === 'dedupe_events' &&
    (pathAssurance.entrypoint === undefined ||
      resourceAssurance.entrypoint === undefined)) {
    fail(`${label}: work, workspace, and lifecycle assurance is missing`);
  }
  if (requireBoundaryComplete) {
    for (const pathName of requiredPaths) {
      if (pathAssurance[pathName] === undefined) {
        fail(`${label}: ${pathName} boundary assurance is missing`);
      }
      if (resourceAssurance[pathName] === undefined) {
        fail(`${label}: ${pathName} work/workspace assurance is missing`);
      }
    }
  }
  if (['traverse', 'apply_graph_delta'].includes(route.operation) &&
    route.family === 'SGA' &&
    !boundaryRoles.has('exact_one_short_and_cancel_cleanup')) {
    fail(`${label}: reviewed exact/cancel boundary fixture is missing`);
  }
  if (route.family === 'SGA' && route.operation === 'normalize_graph') {
    if (route.selected_entrypoint?.symbol !== 'start_normalize_view' ||
      !fs.readFileSync(path.join(root, route.dispatch.path), 'utf8')
        .includes('@sga.start_normalize_view(')) {
      fail(`${label}: managed-view production route is missing`);
    }
    for (const role of [
      'normalize_exact_node_capacity',
      'normalize_one_short_node_capacity',
      'normalize_one_short_edge_capacity',
      'normalize_cancel_cleanup',
      'normalize_view_exact_node_capacity',
      'normalize_view_one_short_node_capacity',
      'normalize_view_one_short_edge_capacity',
      'normalize_view_cancel_cleanup',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: reviewed ${role} fixture is missing`);
      }
    }
  }
  if (route.family === 'RelA' && route.operation === 'filter') {
    if (route.selected_entrypoint?.symbol !==
      'selected_binding_rows_execution') {
      fail(`${label}: bounded selected entrypoint is missing`);
    }
    if (route.ordinary_entrypoint?.symbol !==
      'selected_binding_rows_execution') {
      fail(`${label}: bounded ordinary entrypoint is missing`);
    }
    for (const role of [
      'ordinary_filter_quantum_and_lifetime',
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
    if (route.ordinary_entrypoint?.symbol !==
      'selected_binding_rows_execution') {
      fail(`${label}: bounded ordinary entrypoint is missing`);
    }
    for (const role of [
      'ordinary_select_quantum_and_lifetime',
      'select_mixed_stage_lifetime',
      'values_split_select_lifetime',
      'select_input_exact',
      'select_input_one_short',
      'select_cancel_cleanup',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: reviewed ${role} fixture is missing`);
      }
    }
    if (!environmentRoles.has('select_in_flight_host_timer')) {
      fail(`${label}: in-flight Host cancellation fixture is missing`);
    }
    if (!environmentRoles.has('values_split_select_in_flight_host_timer')) {
      fail(`${label}: split values/select Host timer fixture is missing`);
    }
  }
  for (const [operation, role] of [
    ['rename', 'ordinary_rename_quantum_and_lifetime'],
    ['drop', 'ordinary_drop_quantum_and_lifetime'],
    ['derive', 'ordinary_derive_quantum_and_lifetime'],
  ]) {
    if (route.family !== 'RelA' || route.operation !== operation) continue;
    if (route.ordinary_entrypoint?.symbol !==
      'selected_binding_rows_execution') {
      fail(`${label}: bounded ordinary entrypoint is missing`);
    }
    if (!boundaryRoles.has(role)) {
      fail(`${label}: reviewed ${role} fixture is missing`);
    }
  }
  if (route.family === 'RelA' && route.operation === 'derive' &&
    !environmentRoles.has('ordinary_derive_in_flight_host_timer')) {
    fail(`${label}: ordinary derive Host timer evidence is missing`);
  }
  if (route.family === 'RelA' && route.operation === 'derive' &&
    (!environmentRoles.has('same_stage_values_derive_timer_cancel_cleanup') ||
      !boundaryRoles.has('same_stage_values_derive_two_consumers'))) {
    fail(`${label}: same-stage values derive evidence is missing`);
  }
  if (route.family === 'RelA' && route.operation === 'take') {
    if (route.selected_entrypoint?.symbol !==
      'selected_binding_rows_execution' ||
      route.ordinary_entrypoint?.symbol !==
        'selected_binding_rows_execution') {
      fail(`${label}: bounded selected and ordinary entrypoints are required`);
    }
    for (const role of [
      'ordinary_take_quantum_and_lifetime',
      'values_split_take_lifetime',
      'mixed_stage_sort_quantum_and_lifetime',
      'mixed_stage_sort_cancel_and_cleanup',
      'key_completion_work_exact_one_short',
      'key_completion_workspace_exact_one_short',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: reviewed ${role} fixture is missing`);
      }
    }
    if (!environmentRoles.has('selected_take_host_timer')) {
      fail(`${label}: selected take Host timer evidence is missing`);
    }
    if (!environmentRoles.has('values_split_take_in_flight_host_timer')) {
      fail(`${label}: split values/take Host timer fixture is missing`);
    }
  }
  if (route.family === 'RelA' && route.operation === 'sort') {
    if (route.selected_entrypoint?.symbol !==
      'selected_binding_rows_execution') {
      fail(`${label}: bounded selected sort entrypoint is missing`);
    }
    if (route.ordinary_entrypoint?.symbol !==
      'selected_binding_rows_execution') {
      fail(`${label}: bounded ordinary sort entrypoint is missing`);
    }
    for (const role of [
      'ordinary_sort_quantum_and_lifetime',
      'mixed_stage_sort_quantum_and_lifetime',
      'selected_sort_cancel_cleanup',
      'selected_sort_workspace_exact',
      'selected_sort_workspace_one_short',
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
    if (route.additional_dispatch?.marker !== 'AssertUnique(' ||
      route.selected_entrypoint?.symbol !==
        'selected_binding_rows_execution' ||
      route.ordinary_entrypoint?.symbol !==
        'selected_binding_rows_execution') {
      fail(`${label}: selected and ordinary assertion forms must reach production`);
    }
    for (const role of [
      'ordinary_assert_where_quantum_and_lifetime',
      'ordinary_assert_unique_quantum_and_lifetime',
      'assert_where_mixed_stage_lifetime',
      'assert_where_input_exact',
      'assert_where_input_one_short',
      'assert_where_failure_cleanup',
      'assert_where_cancel_cleanup',
      'assert_unique_mixed_stage_lifetime',
      'assert_unique_values_split_lifetime',
      'assert_unique_exact_one_short_workspace',
      'assert_unique_failure_cleanup',
      'assert_unique_cancel_cleanup',
      'assert_unique_sort_cancel_cleanup',
      'assert_unique_sort_failure_cleanup',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: reviewed ${role} fixture is missing`);
      }
    }
    for (const role of [
      'assert_where_ordinary_in_flight_host_timer',
      'assert_unique_ordinary_in_flight_host_timer',
      'assert_unique_values_split_host_timer',
    ]) {
      if (!environmentRoles.has(role)) {
        fail(`${label}: ${role} fixture is missing`);
      }
    }
    for (const role of [
      'assert_where_in_flight_host_timer',
      'assert_unique_in_flight_host_timer',
    ]) {
      if (!environmentRoles.has(role)) {
        fail(`${label}: ${role} fixture is missing`);
      }
    }
  }
  if (route.family === 'RelA' && route.operation === 'values' &&
    (!environmentRoles.has('zero_input_mixed_stage_timer_cancel_cleanup') ||
      !environmentRoles.has('zero_input_sort_timer_cancel_cleanup') ||
      !environmentRoles.has('zero_input_unique_timer_cancel_cleanup'))) {
    fail(`${label}: mixed-stage timer cancellation fixture is missing`);
  }
  if (route.family === 'RelA' && route.operation === 'cross_join') {
    for (const role of [
      'product_work_workspace_exact_one_short',
      'managed_pre_execution_cancel_cleanup',
      'external_product_mixed_stage_two_consumers',
      'external_product_input_value_exact_one_short',
      'external_product_host_receiving_input_limit',
      'external_product_self_input_occurrences',
      'external_product_empty_output_input_admission',
      'external_product_empty_singleton_quantum',
      'external_product_long_text_quantum',
      'external_product_utf8_input_exact_one_short',
      'external_product_input_cancel_cleanup',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: reviewed ${role} fixture is missing`);
      }
    }
    if (!environmentRoles.has(
      'external_product_mixed_stage_timer_cancel_cleanup')) {
      fail(`${label}: mixed-stage timer cancellation fixture is missing`);
    }
    if (!environmentRoles.has(
      'external_product_empty_right_admission_timer_cancel_cleanup')) {
      fail(`${label}: empty-right admission timer fixture is missing`);
    }
    // Closing before execute cannot prove a delivered in-flight stop.
    // A future unrelated environment fixture must not close this route.
    if (requireBoundaryComplete &&
      !environmentRoles.has('cross_join_in_flight_host_timer')) {
      fail(`${label}: in-flight Host cancellation evidence is missing`);
    }
  }
  if (route.family === 'RelA' && route.operation === 'distinct') {
    for (const role of [
      'selected_distinct_first_occurrence_and_null',
      'selected_distinct_keyed_projection',
      'distinct_unkeyed_workspace_exact_one_short',
      'selected_distinct_kernel_cancel_cleanup',
      'same_stage_distinct_two_consumers',
      'same_stage_values_distinct_two_consumers',
      'same_stage_values_distinct_dag_selection',
      'same_stage_keyed_distinct_join',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: selected ${role} fixture is missing`);
      }
    }
    if (!environmentRoles.has('same_stage_distinct_timer_cancel_cleanup')) {
      fail(`${label}: same-stage distinct timer fixture is missing`);
    }
  }
  if (route.family === 'SGA' && route.operation === 'graph_bounds' &&
    !boundaryRoles.has('graph_bounds_work_exact_one_short')) {
    fail(`${label}: exact work boundary fixture is missing`);
  }
  if (route.family === 'SGA' && route.operation === 'degree' &&
    !boundaryRoles.has('degree_control_work_exact_one_short')) {
    fail(`${label}: exact control-work boundary fixture is missing`);
  }
  if (route.family === 'SGA' && route.operation === 'subgraph' &&
    !boundaryRoles.has('subgraph_false_edge_work_workspace_exact_one_short')) {
    fail(`${label}: false-edge work/workspace fixture is missing`);
  }
  if (route.family === 'VecA' && route.operation === 'normalize_vectors') {
    for (const role of [
      'normalize_control_work_exact_one_short',
      'normalize_workspace_exact',
      'normalize_workspace_one_short',
      'normalize_kernel_cancel_cleanup',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: ${role} fixture is missing`);
      }
    }
    if (!environmentRoles.has('normalize_host_in_flight_cancel') ||
      pathAssurance.entrypoint === undefined) {
      fail(`${label}: bounded Host cancellation assurance is missing`);
    }
  }
  if (route.family === 'VecA' && route.operation === 'score_vectors') {
    for (const role of [
      'score_empty_work_exact_one_short',
      'score_record_work_exact_one_short',
      'score_workspace_exact',
      'score_workspace_one_short',
      'score_kernel_cancel_cleanup',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: ${role} fixture is missing`);
      }
    }
    if (!environmentRoles.has('score_host_in_flight_cancel') ||
      pathAssurance.entrypoint === undefined) {
      fail(`${label}: bounded Host cancellation assurance is missing`);
    }
  }
  if (route.family === 'VecA' && route.operation === 'pool_vectors') {
    if (route.relation_entrypoint?.symbol !== 'start_relation_pool' ||
      route.additional_dispatch?.marker !== '@veca.start_relation_pool(') {
      fail(`${label}: Relation input entrypoint is missing`);
    }
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
      if (!boundaryRoles.has(role)) {
        fail(`${label}: ${role} fixture is missing`);
      }
    }
    if (!environmentRoles.has('pool_host_in_flight_cancel') ||
      !environmentRoles.has('pool_relation_host_in_flight_cancel') ||
      pathAssurance.entrypoint === undefined ||
      pathAssurance.relation_entrypoint === undefined) {
      fail(`${label}: direct and Relation Host cancellation assurances are required`);
    }
    if (resourceAssurance.entrypoint === undefined ||
      resourceAssurance.relation_entrypoint === undefined) {
      fail(`${label}: direct and Relation work/workspace assurances are required`);
    }
  }
  if (route.family === 'TEA' &&
      ['interval_join', 'asof_join'].includes(route.operation)) {
    if (pathAssurance.entrypoint === undefined ||
      resourceAssurance.entrypoint === undefined) {
      fail(`${label}: bounded join production assurance is missing`);
    }
  }
  if (route.family === 'VecA' && route.operation === 'nearest') {
    if (route.relation_entrypoint?.symbol !==
        'start_nearest_inputs_with_relations' ||
      route.additional_dispatch?.marker !==
        '@veca.start_nearest_inputs_with_relations(') {
      fail(`${label}: fused Relation input entrypoint is missing`);
    }
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
      if (!boundaryRoles.has(role)) {
        fail(`${label}: ${role} fixture is missing`);
      }
    }
    if (!environmentRoles.has('nearest_relation_host_in_flight_cancel') ||
      !environmentRoles.has('nearest_fused_relation_host_in_flight_cancel')) {
      fail(`${label}: direct and fused Relation Host cancellation fixtures are required`);
    }
    if (route.path_assurance?.entrypoint === undefined ||
      route.resource_assurance?.entrypoint === undefined) {
      fail(`${label}: direct Relation resource assurance is missing`);
    }
    if (route.path_assurance?.relation_entrypoint === undefined ||
      route.resource_assurance?.relation_entrypoint === undefined) {
      fail(`${label}: fused Relation resource assurance is missing`);
    }
  }
  if (route.family === 'SGA' && route.operation === 'shortest_path') {
    for (const role of [
      'shortest_workspace_exact_one_short',
      'shortest_value_preallocation_rejection',
      'shortest_kernel_cancel_cleanup',
      'shortest_standard_host_consumers',
    ]) {
      if (!boundaryRoles.has(role)) {
        fail(`${label}: reviewed ${role} fixture is missing`);
      }
    }
  }
  if (route.family === 'SGA' &&
    ['match_nodes', 'match_edges'].includes(route.operation) &&
    !boundaryRoles.has(`${route.operation}_control_work_exact_one_short`)) {
    fail(`${label}: match control work evidence is missing`);
  }
  if (route.family === 'SGA' && route.operation === 'match_edges' &&
    !boundaryRoles.has('match_edges_type_index_quantum_workspace_cancel')) {
    fail(`${label}: bounded type-index evidence is missing`);
  }
  if (route.family === 'SGA' && route.operation === 'graphs_equal' &&
    (!boundaryRoles.has('graphs_equal_control_work_exact_one_short_and_cancel') ||
      !boundaryRoles.has('graphs_equal_nested_value_work_ceiling'))) {
    fail(`${label}: Graph equality control-work evidence is missing`);
  }
  if (route.family === 'SGA' && route.operation === 'components' &&
    (!boundaryRoles.has('components_empty_exact_work_workspace_cancel_cleanup') ||
      !boundaryRoles.has('components_nonempty_work_ceiling_and_active_cancel'))) {
    fail(`${label}: components boundary evidence is missing`);
  }
  if (route.family === 'SGA' && route.operation === 'reach' &&
    !boundaryRoles.has('reach_prefix_work_workspace_active_cancel')) {
    fail(`${label}: reach control-work evidence is missing`);
  }
  if (route.family === 'SGA' && route.operation === 'traverse' &&
    (!boundaryRoles.has('node_emit_control_work_ceiling') ||
      !boundaryRoles.has('path_emit_control_work_ceiling'))) {
    fail(`${label}: traversal work evidence is missing`);
  }
  if (route.family === 'SGA' && route.operation === 'graph_diff' &&
    !boundaryRoles.has('graph_diff_tail_work_ceiling_and_kernel_cancel_cleanup')) {
    fail(`${label}: Graph diff tail-work evidence is missing`);
  }
  if (route.family === 'SGA' && route.operation === 'mean_graphs' &&
    !boundaryRoles.has('mean_empty_work_exact_one_short_and_cleanup')) {
    fail(`${label}: Graph mean cumulative-work evidence is missing`);
  }
  if (route.family === 'SGA') {
    const structuralRole = {
      graft_graph: 'graft_empty_work_exact_one_short_and_cleanup',
      union_graphs: 'union_empty_work_exact_one_short_active_cancel_cleanup',
      subtract_graphs: 'subtract_empty_work_exact_one_short_and_cleanup',
    }[route.operation];
    if (structuralRole && !boundaryRoles.has(structuralRole)) {
      fail(`${label}: structural Graph cumulative-work evidence is missing`);
    }
  }
  if (route.family === 'VecAExpression') {
    const required = [
      `${route.operation}_derive_work_workspace_exact_one_short`,
      `${route.operation}_derive_cancel_cleanup`,
    ];
    if (required.some(role => !boundaryRoles.has(role))) {
      fail(`${label}: vector expression boundary evidence is missing`);
    }
  }
  if (route.family === 'Bridge' &&
    ['node_rows', 'edge_rows', 'to_events', 'to_vectors'].includes(
      route.operation,
    )) {
    const role = `${route.operation}_work_workspace_exact_one_short_and_kernel_cancel_cleanup`;
    if (!boundaryRoles.has(role)) {
      fail(`${label}: ${role} fixture is missing`);
    }
    if (!environmentRoles.has(`${route.operation}_host_in_flight_cancel`) ||
      route.path_assurance?.entrypoint === undefined) {
      fail(`${label}: delivered Bridge cancellation assurance is missing`);
    }
  }
  if (route.family === 'Bridge' && route.operation === 'events' &&
    !boundaryRoles.has('events_projection_value_width_and_kernel_cancel_cleanup')) {
    fail(`${label}: Events projection boundary fixture is missing`);
  }
  if (route.family === 'Bridge' && route.operation === 'events' &&
    !environmentRoles.has('events_projection_host_in_flight_cancel')) {
    fail(`${label}: Events projection Host cancellation fixture is missing`);
  }
  if (route.family === 'Bridge' && route.operation === 'vectors' &&
    !boundaryRoles.has('vectors_projection_value_width_and_kernel_cancel_cleanup')) {
    fail(`${label}: Vectors projection boundary fixture is missing`);
  }
  if (route.family === 'Bridge' && route.operation === 'vectors' &&
    !environmentRoles.has('vectors_projection_host_in_flight_cancel')) {
    fail(`${label}: Vectors projection Host cancellation fixture is missing`);
  }
}

// Route fixtures cannot make a synchronous providerless resume interruptible.
// Its independent copy is bounded, but the preceding compute remains a known
// counterexample until it is replaced by bounded or stoppable work.
if (requireBoundaryComplete) {
  const driver = fs.readFileSync(path.join(
    root, 'src/connectors/local/driver/managed_dispatch.mbt',
  ), 'utf8');
  const switchAt = driver.indexOf('match setup.provider {');
  const fallbackAt = driver.indexOf('None => {', switchAt);
  const computeAt = driver.indexOf(
    '@local.execute_local_managed_fixed_compute(', fallbackAt,
  );
  const boundedCopyAt = driver.indexOf(
    '@execution.start_bounded_independent_row_copy(', fallbackAt,
  );
  if (switchAt < 0 || fallbackAt < 0 || boundedCopyAt < fallbackAt) {
    fail('managed execution lane inventory must be reviewed');
  } else if (fallbackAt < computeAt && computeAt < boundedCopyAt) {
    fail('providerless managed execution still computes synchronously');
  }
}

// Selected Relation tasks may only enter the bounded row evaluator. Keep an
// unreachable synchronous fallback from becoming reachable after future
// lowering capability changes.
const relationProvider = fs.readFileSync(path.join(
  root, 'src/connectors/local/selected_relation_provider.mbt',
), 'utf8');
if (relationProvider.includes('@execution.execute_selected_relation_step(')) {
  fail('selected Relation provider computes rows synchronously');
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

const boundaryRoutes = routeEntries.filter(route =>
  (route.boundary_tests ?? []).length > 0).length;
const assuredRoutes = routeEntries.filter(route => [
  'entrypoint',
  ...(route.ordinary_entrypoint ? ['ordinary_entrypoint'] : []),
  ...(route.selected_entrypoint ? ['selected_entrypoint'] : []),
  ...(route.relation_entrypoint ? ['relation_entrypoint'] : []),
  ...(route.view_entrypoint ? ['view_entrypoint'] : []),
].every(pathName => route.path_assurance?.[pathName] !== undefined)).length;
const fullyAssuredRoutes = routeEntries.filter(route => [
  'entrypoint',
  ...(route.ordinary_entrypoint ? ['ordinary_entrypoint'] : []),
  ...(route.selected_entrypoint ? ['selected_entrypoint'] : []),
  ...(route.relation_entrypoint ? ['relation_entrypoint'] : []),
  ...(route.view_entrypoint ? ['view_entrypoint'] : []),
].every(pathName => route.path_assurance?.[pathName] !== undefined &&
  route.resource_assurance?.[pathName] !== undefined)).length;
const resourceAssuredPaths = routeEntries.reduce((count, route) =>
  count + Object.keys(route.resource_assurance ?? {}).length, 0);
const selectedAssuredRoutes = routeEntries.filter(route =>
  route.path_assurance?.selected_entrypoint !== undefined &&
  Object.keys(route.path_assurance).length === 1).length;
const summaryStart = '<!-- local-resource-accounting-summary:start -->';
const summaryEnd = '<!-- local-resource-accounting-summary:end -->';
const summary = [
  summaryStart,
  '| Resource boundary evidence | Count |',
  '|---|---:|',
  `| Production routes | ${routeEntries.length} |`,
  `| Operation-specific boundary records | ${boundaryRoutes} |`,
  `| Four-role lifecycle assurance | ${assuredRoutes} |`,
  `| Full route work/workspace assurance | ${fullyAssuredRoutes} |`,
  `| Path-scoped work/workspace assurance | ${resourceAssuredPaths} |`,
  `| Selected-only assurance | ${selectedAssuredRoutes} |`,
  summaryEnd,
].join('\n');
const defaultGaps = path.join(
  root, 'docs/reviews/2026-09-19-sga-veca-tea-local-gaps.md',
);
const gapsPath = process.env.ACTQL_LOCAL_RESOURCE_GAPS
  ? path.resolve(process.env.ACTQL_LOCAL_RESOURCE_GAPS)
  : defaultGaps;
if (manifestPath === defaultManifest ||
  process.argv.includes('--check-summary')) {
  if (!fs.existsSync(gapsPath)) {
    fail('resource gaps ledger is missing');
  } else {
    const gaps = fs.readFileSync(gapsPath, 'utf8');
    const start = gaps.indexOf(summaryStart);
    const end = gaps.indexOf(summaryEnd);
    if (start < 0 || end < start) {
      fail('resource gaps ledger lacks generated summary markers');
    } else if (process.argv.includes('--write-summary') &&
      errors.length === 0) {
      fs.writeFileSync(
        gapsPath,
        gaps.slice(0, start) + summary + gaps.slice(end + summaryEnd.length),
      );
    } else if (gaps.slice(start, end + summaryEnd.length) !== summary) {
      fail('resource gaps ledger summary is stale');
    }
  }
}
if (errors.length > 0) {
  for (const error of errors) console.error(error);
  process.exitCode = 1;
} else {
  console.log(
    `Local resource accounting: ${actual.length} operations, ` +
    `${Object.keys(profiles).length} implementation profiles, ` +
    `${routeEntries.length} production routes mapped, ` +
    `${boundaryRoutes} with operation-specific boundary records, ` +
    `${assuredRoutes} with four-role boundary evidence, ` +
    `${fullyAssuredRoutes} with full work/workspace assurance, ` +
    `${resourceAssuredPaths} with path-scoped work/workspace evidence, ` +
    `${selectedAssuredRoutes} with selected-only assurance; ` +
    `full boundary completion is not asserted.`,
  );
}
