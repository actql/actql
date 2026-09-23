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
      const selectedVariants = route.family === 'RelA' &&
        pathName === 'selected_entrypoint'
        ? {take: ['unkeyed', 'keyed'], sort: ['ordered', 'empty']}[
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
      if (selectedVariants &&
        (Object.keys(dimensions ?? {}).length !== 1 ||
          Object.keys(dimensions?.variants ?? {}).length !== 2 ||
          selectedVariants.some(variant => !dimensions.variants[variant]))) {
        fail(`${label}: ${pathName} needs ${selectedVariants.join(' and ')} resource variants`);
        continue;
      }
      const proofSets = assertion || selectedVariants
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
              (assertion && !role.startsWith(`assert_${variant}_`)) ||
              (selectedVariants &&
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
  }
  for (const [operation, role] of [
    ['rename', 'ordinary_rename_quantum_and_lifetime'],
    ['drop', 'ordinary_drop_quantum_and_lifetime'],
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
  if (route.family === 'RelA' && route.operation === 'take') {
    if (route.selected_entrypoint?.symbol !==
      'selected_binding_rows_execution' ||
      route.ordinary_entrypoint?.symbol !==
        'selected_binding_rows_execution') {
      fail(`${label}: bounded selected and ordinary entrypoints are required`);
    }
    for (const role of [
      'ordinary_take_quantum_and_lifetime',
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
        'selected_binding_rows_execution') {
      fail(`${label}: both selected assertion forms must reach production`);
    }
    for (const role of [
      'assert_where_mixed_stage_lifetime',
      'assert_where_input_exact',
      'assert_where_input_one_short',
      'assert_where_failure_cleanup',
      'assert_where_cancel_cleanup',
      'assert_unique_mixed_stage_lifetime',
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
      'assert_where_in_flight_host_timer',
      'assert_unique_in_flight_host_timer',
    ]) {
      if (!environmentRoles.has(role)) {
        fail(`${label}: ${role} fixture is missing`);
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
  const assuredRoutes = routeEntries.filter(route => [
    'entrypoint',
    ...(route.ordinary_entrypoint ? ['ordinary_entrypoint'] : []),
    ...(route.selected_entrypoint ? ['selected_entrypoint'] : []),
  ].every(pathName => route.path_assurance?.[pathName] !== undefined)).length;
  const fullyAssuredRoutes = routeEntries.filter(route => [
    'entrypoint',
    ...(route.ordinary_entrypoint ? ['ordinary_entrypoint'] : []),
    ...(route.selected_entrypoint ? ['selected_entrypoint'] : []),
  ].every(pathName => route.path_assurance?.[pathName] !== undefined &&
    route.resource_assurance?.[pathName] !== undefined)).length;
  const resourceAssuredPaths = routeEntries.reduce((count, route) =>
    count + Object.keys(route.resource_assurance ?? {}).length, 0);
  const selectedAssuredRoutes = routeEntries.filter(route =>
    route.path_assurance?.selected_entrypoint !== undefined &&
    Object.keys(route.path_assurance).length === 1).length;
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
