import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';

export const targets = ['js', 'wasm', 'native'];
export const premises = [
  'accepted counters are nonnegative representable and monotone',
  'kernel work per resume is between zero and quantum',
  'cleanup callback true means complete reclamation',
];
export const guarantees = ['delta accounting', 'terminal seals advance', 'cleanup retry without compute'];
// Reviewed coverage of the actual fixture, independent of requested bindings.
// Expanding this table requires reviewing/changing that fixture, not relabeling
// a derived claim. Digests pin that review's code; they do not prove its scope.
export const connectionFixture = 'src/query_integration/local_managed_set_wbtest.mbt';
export const nestConnectionFixture = 'src/query_integration/local_managed_nest_wbtest.mbt';
const scopeKeys = ['operation', 'variant', 'profile', 'provider', 'entrypoint', 'kernel'];
const nestScope = Object.freeze({ operation: 'nest', variant: 'correlated-parent-major',
  profile: 'checked nullable correlation keys; four parents; ordered child projection; two consumers',
  provider: 'src/connectors/local/nest_provider.mbt', entrypoint: 'nest_provider', kernel: 'start_bounded_nest' });
const connectionCoverage = Object.freeze(['except', 'intersect'].flatMap(operation =>
  ['all', 'distinct'].map(variant => Object.freeze({
    operation, variant, profile: 'checked complete rows including nullable fields',
    provider: 'src/connectors/local/set_provider.mbt', entrypoint: 'set_provider',
    kernel: 'start_bounded_set',
  }))));
export const connectionSuites = Object.freeze([
  { id: 'connection', fixture: connectionFixture, minimumTests: 1 },
  { id: 'nest-connection', fixture: nestConnectionFixture, minimumTests: 4 },
]);
export const nestLocalSuites = Object.freeze([
  { id: 'nest-kernel', fixture: 'src/execution_relation/bounded_nest_wbtest.mbt', minimumTests: 8 },
  { id: 'nest-semantics', fixture: 'src/execution_relation/nest_sequence_wbtest.mbt', minimumTests: 7 },
  { id: 'nest-scaling', fixture: 'src/execution_relation/nest_scale_wbtest.mbt', minimumTests: 3 },
  { id: 'nest-workspace', fixture: 'src/execution_relation/bounded_resource_boundary_wbtest.mbt', minimumTests: 1,
    filter: 'bounded nest admits its exact workspace peak' },
]);
export function executedConnectionCoverage(id = 'connection') {
  if (id === 'connection') return { fixture: connectionFixture, scopes: connectionCoverage.map(scope => ({ ...scope })) };
  if (id === 'nest-connection') return { fixture: nestConnectionFixture, scopes: [{ ...nestScope }] };
  throw new Error('Unknown reviewed connection fixture');
}
const scopeMatches = (actual, expected, keys) => keys.every(key => actual?.[key] === expected[key]);
const reviewedScopes = [...connectionCoverage, nestScope];
const connectionId = scope => scope.operation === 'nest' ? 'nest-connection' : 'connection';
function checkExecutedConnection(scope, coverage) {
  const reviewed = executedConnectionCoverage(connectionId(scope));
  if (JSON.stringify(coverage) !== JSON.stringify(reviewed)) throw new Error('Unverified executed connection coverage');
  if (!coverage.scopes.some(verified => scopeMatches(scope, verified, scopeKeys))) {
    throw new Error('Scope mismatch: claim is outside independently executed connection coverage');
  }
}
const hash = value => createHash('sha256').update(value).digest('hex');

function files(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? files(path) : entry.isFile() ? [path] : [];
  });
}

// Include ALL production MoonBit code, package manifests and integration tests,
// not just the selected source symbol. SHA pins evidence, not correctness.
export function snapshot(root) {
  const paths = ['src', 'proofs/bounded-session'].flatMap(dir => files(join(root, dir)))
    .concat(['toolchain.json', 'moon.mod',
      'docs/reviews/2026-09-23-local-resource-production-routes.json',
      'docs/reviews/2026-09-23-local-resource-accounting-audit.json',
    ].map(path => join(root, path))).sort();
  const sources = Object.fromEntries(paths.map(path => [relative(root, path), hash(readFileSync(path))]));
  return { digest: hash(JSON.stringify(sources)), sources };
}

export function artifacts(root, target, packagePath) {
  const directory = join(root, '_build', target, 'debug/test', packagePath);
  const paths = files(directory).filter(path => /\.(js|wasm|exe)$/.test(path));
  if (paths.length === 0) throw new Error(`No test artifacts for ${target}/${packagePath}`);
  return Object.fromEntries(paths.sort().map(path => [relative(root, path), hash(readFileSync(path))]));
}

export function graph(bindings, target) {
  const universal = { ...Object.fromEntries(scopeKeys.map(key => [key, '*'])), target };
  const nodes = [
    { id: 'model', kind: 'formal-model', scope: { ...universal, target: 'model' }, dependencies: [], run: 'lean' },
    { id: 'session', kind: 'tested-refinement', scope: { ...universal }, dependencies: ['model'], run: `session-${target}` },
    { id: 'adapter', kind: 'tested-refinement', scope: { ...universal }, dependencies: ['model'], run: `adapter-${target}` },
  ];
  for (const binding of bindings) {
    const scope = { ...Object.fromEntries(scopeKeys.map(key => [key, binding[key]])), target };
    const id = `${binding.operation}/${binding.variant}`;
    nodes.push({ id: `${id}:connection`, kind: 'tested-refinement', scope: { ...scope }, dependencies: [], run: `${connectionId(binding)}-${target}` });
    nodes.push({ id, kind: 'derived', scope: { ...scope }, dependencies: ['session', 'adapter', `${id}:connection`],
      guarantees: [...guarantees], premises: [...binding.premises], residual: [...binding.residual] });
  }
  return nodes;
}

export function validate(nodes, report, current, expectedTarget) {
  if (report.source.digest !== current.digest) throw new Error('Stale source/artifact evidence');
  if (report.target !== expectedTarget) throw new Error('Target mismatch');
  const byId = new Map(nodes.map(node => [node.id, node]));
  if (byId.size !== nodes.length) throw new Error('Duplicate claim id');
  const visited = new Set();
  const active = new Set();
  const visit = node => {
    if (active.has(node.id)) throw new Error(`Cyclic evidence: ${node.id}`);
    if (visited.has(node.id)) return;
    if (!['formal-model', 'tested-refinement', 'derived'].includes(node.kind)) throw new Error('Unsupported evidence kind');
    if (node.scope.target !== expectedTarget && !(node.kind === 'formal-model' && node.scope.target === 'model')) {
      throw new Error(`Target mismatch: ${node.id}`);
    }
    active.add(node.id);
    for (const id of node.dependencies) {
      const dep = byId.get(id);
      if (!dep) throw new Error(`Missing premise evidence: ${id}`);
      for (const key of scopeKeys) {
        if (dep.scope[key] !== '*' && dep.scope[key] !== node.scope[key]) throw new Error(`Scope mismatch: ${key}`);
      }
      visit(dep);
    }
    if (node.kind === 'derived') {
      if (!reviewedScopes.some(scope => scopeMatches(node.scope, scope, scopeKeys))) throw new Error('Scope is outside independently executed connection coverage');
      for (const premise of premises) if (!node.premises.includes(premise)) throw new Error(`Missing premise: ${premise}`);
      for (const dependency of ['session', 'adapter', `${node.id}:connection`]) {
        if (!node.dependencies.includes(dependency)) throw new Error(`Missing dependency: ${dependency}`);
      }
      if (JSON.stringify(node.guarantees) !== JSON.stringify(guarantees)) throw new Error('Unsupported guarantee');
      if (!node.residual?.length) throw new Error('Kernel and environment obligations must remain explicit');
      if (node.scope.operation === 'nest' && !nestResidual.every(p => node.residual.includes(p))) throw new Error('Missing Nest-specific residual obligation');
      if (node.scope.operation === 'nest') for (const suite of nestLocalSuites) {
        const result = report.runs[`${suite.id}-${expectedTarget}`];
        const command = ['moon', 'test', suite.fixture, '--target', expectedTarget, '--deny-warn',
          ...(suite.filter ? ['--filter', suite.filter] : [])];
        if (!result?.passed || result.exit !== 0 || result.sourceDigest !== current.digest ||
            result.target !== expectedTarget || result.count < suite.minimumTests ||
            JSON.stringify(result.command) !== JSON.stringify(command) || !Object.keys(result.artifacts ?? {}).length) throw new Error('Missing executed Nest-specific obligation');
        for (const [path, digest] of Object.entries(result.artifacts)) if (current.builtArtifacts?.[path] !== digest) throw new Error('Stale built artifact');
      }
    } else {
      if (node.id.endsWith(':connection') && !reviewedScopes.some(scope => scopeMatches(node.scope, scope, scopeKeys))) throw new Error('Scope mismatch: claim is outside independently executed connection coverage');
      if (node.id === 'model') {
        if (node.kind !== 'formal-model' || node.run !== 'lean' || node.dependencies.length) throw new Error('Invalid common model evidence');
      } else if (node.id === 'session' || node.id === 'adapter') {
        if (node.kind !== 'tested-refinement' || node.run !== `${node.id}-${expectedTarget}` ||
            JSON.stringify(node.dependencies) !== JSON.stringify(['model'])) throw new Error('Invalid common correspondence evidence');
      } else if (node.id.endsWith(':connection')) {
        if (node.id !== `${node.scope.operation}/${node.scope.variant}:connection`) throw new Error('Scope mismatch: connection identity');
        if (node.kind !== 'tested-refinement' || node.run !== `${connectionId(node.scope)}-${expectedTarget}` || node.dependencies.length) throw new Error('Unrelated connection execution');
      } else throw new Error('Unknown evidence role');
      const result = report.runs[node.run];
      if (!result || result.exit !== 0 || !result.passed || result.sourceDigest !== current.digest) {
        throw new Error(`Missing or stale executed evidence: ${node.run}`);
      }
      if (node.kind === 'tested-refinement' && result.target !== expectedTarget) throw new Error('Executed target mismatch');
      if (node.kind === 'tested-refinement' && !Object.keys(result.artifacts ?? {}).length) throw new Error('Missing built artifact');
      const suite = node.run === 'session-' + expectedTarget ? 'src/bounded_execution'
        : node.run === 'adapter-' + expectedTarget ? 'src/connectors/local'
        : node.run === 'connection-' + expectedTarget ? connectionFixture
        : node.run === 'nest-connection-' + expectedTarget ? nestConnectionFixture : null;
      const expected = suite ? ['moon', 'test', suite, '--target', expectedTarget, '--deny-warn'] : null;
      if (expected && (JSON.stringify(result.command) !== JSON.stringify(expected) ||
          !(result.count >= (suite === nestConnectionFixture ? 4 : 1)))) {
        throw new Error(`Unrelated execution used as evidence: ${node.run}`);
      }
      if (node.id.endsWith(':connection')) checkExecutedConnection(node.scope, result.coverage);
      if (node.kind === 'formal-model' && result.command?.[1] !== 'proofs/bounded-session/check.mjs') {
        throw new Error('Wrong proof artifact');
      }
      for (const [path, digest] of Object.entries(result.artifacts ?? {})) {
        if (current.builtArtifacts?.[path] !== digest) throw new Error(`Stale built artifact: ${path}`);
      }
    }
    active.delete(node.id);
    visited.add(node.id);
  };
  for (const node of nodes) visit(node);
  return nodes.filter(node => node.kind === 'derived');
}

const nestObligations = JSON.parse(readFileSync(new URL('nest-obligations.json', import.meta.url)));
const nestResidual = nestObligations.residual;
export function checkNestObligations(root) {
  const obligations = JSON.parse(readFileSync(join(root, 'proofs/bounded-session/nest-obligations.json')));
  if (JSON.stringify(obligations.scope) !== JSON.stringify(nestScope) || obligations.testRetirements.length) throw new Error('Unreviewed Nest obligation scope');
  for (const [path, digest] of Object.entries(obligations.unchangedCommon)) {
    if (hash(readFileSync(join(root, path))) !== digest) throw new Error(`Common proof/protocol artifact changed: ${path}`);
  }
  for (const path of obligations.retainedSuites) readFileSync(join(root, path));
  const provider = readFileSync(join(root, nestScope.provider), 'utf8');
  const kernel = readFileSync(join(root, obligations.connection.kernelSource), 'utf8');
  const fixture = readFileSync(join(root, nestConnectionFixture), 'utf8');
  const registration = readFileSync(join(root, obligations.route.registration), 'utf8');
  for (const marker of ['guard inputs is [parent, child]', 'bounded_session_execution(', '@execution.start_bounded_nest(', '@execution.advance_bounded_nest(', '@execution.cleanup_bounded_nest(active)', '@bounded.request_cancel(control)']) {
    if (!provider.includes(marker)) throw new Error(`Missing Nest provider connection: ${marker}`);
  }
  for (const marker of ['producer_read_matches_operation_input(parent, owner, step, 0)', 'producer_read_matches_operation_input(child, owner, step, 1)', '@bounded.start(', '@bounded.advance(value.session, token, quantum)', 'cleanup_bounded_nest_state', 'release_slots(state.workspace, state.workspace.live)']) {
    if (!kernel.includes(marker)) throw new Error(`Missing Nest kernel/ownership connection: ${marker}`);
  }
  if (!registration.includes('nest_provider(installed.execution, installed.measurement)') ||
      !fixture.includes('prepare_local_dispatch_module(') || !fixture.includes('require_provider=true') ||
      !fixture.includes('[parents, children]') || !fixture.includes('assert_eq(nested_rows, expected)')) throw new Error('Missing registered two-input Nest witness');
  return obligations;
}
export function checkBindings(root, bindings) {
  const inventory = JSON.parse(readFileSync(join(root, 'docs/reviews/2026-09-23-local-resource-production-routes.json')));
  for (const binding of bindings) {
    // Each provider needs its OWN reviewed executed fixture; sharing the
    // adapter is not that connection witness.
    const verified = reviewedScopes.find(scope => scopeMatches(binding, scope,
      ['operation', 'variant', 'provider', 'entrypoint', 'kernel']));
    if (!verified) {
      throw new Error('Unsupported connection scope: supply an executed provider-specific witness');
    }
    if (binding.profile !== verified.profile) {
      throw new Error('Unverified connection profile');
    }
    const route = inventory.routes.find(row => row.operation === binding.operation);
    if (!route || route.entrypoint?.path !== binding.provider || route.entrypoint.symbol !== binding.entrypoint) {
      throw new Error(`Provider differs from authoritative route: ${binding.operation}`);
    }
    const provider = readFileSync(join(root, binding.provider), 'utf8');
    if (!provider.includes('bounded_session_execution(') || !provider.includes(`@execution.${binding.kernel}(`)) {
      throw new Error(`Missing reviewed adapter/kernel connection: ${binding.operation}`);
    }
    if (!premises.every(p => binding.premises.includes(p))) {
      throw new Error('Invalid variant or missing premise');
    }
    if (binding.operation === 'nest') {
      checkNestObligations(root);
      if (!nestResidual.every(p => binding.residual.includes(p))) throw new Error('Missing Nest-specific residual obligation');
    }
  }
}

export function checkRetirements(root) {
  const path = join(root, 'proofs/bounded-session/retirements.json');
  if (!existsSync(path)) return [];
  const manifest = JSON.parse(readFileSync(path));
  if (manifest.version !== 'actql-session-test-retirements/0.1') throw new Error('Unknown retirement manifest');
  const expected = ['bounded session advances with fresh tokens and finite work',
    'stop confirmation precedes retryable cleanup'];
  if (manifest.retirements?.length !== expected.length ||
      expected.some(name => !manifest.retirements.some(entry => entry.old_test === name))) {
    throw new Error('Every retired example requires its own replacement mapping');
  }
  const model = readFileSync(join(root, 'proofs/bounded-session/Session.lean'), 'utf8');
  for (const entry of manifest.retirements) {
    const old = readFileSync(join(root, entry.path), 'utf8');
    const replacement = readFileSync(join(root, entry.replacement), 'utf8');
    if (old.includes(`test "${entry.old_test}"`)) throw new Error('Retired example is still present');
    if (!replacement.includes(`test "${entry.replacement_test}"`) ||
      !entry.observations?.length || !entry.premises?.length || !entry.mutations?.length ||
      !/^[0-9a-f]{64}$/.test(entry.prior_body_sha256)) throw new Error('Incomplete replacement mapping');
    for (const name of entry.formal_model_theorems) {
      if (!model.includes(`theorem ${name} `)) throw new Error(`Missing replacement theorem: ${name}`);
    }
    for (const name of entry.retained_regressions) {
      if (!old.includes(`test "${name}"`)) throw new Error(`Unique regression removed: ${name}`);
    }
  }
  // Names here only check the mapping's references. check.mjs still proves
  // propositions and their expected types; source text alone is not evidence.
  return manifest.retirements;
}
