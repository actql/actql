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
  const universal = { operation: '*', variant: '*', profile: '*', target };
  const nodes = [
    { id: 'model', kind: 'formal-model', scope: { ...universal, target: 'model' }, dependencies: [], run: 'lean' },
    { id: 'session', kind: 'tested-refinement', scope: { ...universal }, dependencies: ['model'], run: `session-${target}` },
    { id: 'adapter', kind: 'tested-refinement', scope: { ...universal }, dependencies: ['model'], run: `adapter-${target}` },
  ];
  for (const binding of bindings) {
    const scope = { operation: binding.operation, variant: binding.variant, profile: binding.profile, target };
    const id = `${binding.operation}/${binding.variant}`;
    nodes.push({ id: `${id}:connection`, kind: 'tested-refinement', scope: { ...scope }, dependencies: [], run: `connection-${target}` });
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
      for (const key of ['operation', 'variant', 'profile']) {
        if (dep.scope[key] !== '*' && dep.scope[key] !== node.scope[key]) throw new Error(`Scope mismatch: ${key}`);
      }
      visit(dep);
    }
    if (node.kind === 'derived') {
      for (const premise of premises) if (!node.premises.includes(premise)) throw new Error(`Missing premise: ${premise}`);
      for (const dependency of ['session', 'adapter', `${node.id}:connection`]) {
        if (!node.dependencies.includes(dependency)) throw new Error(`Missing dependency: ${dependency}`);
      }
      if (JSON.stringify(node.guarantees) !== JSON.stringify(guarantees)) throw new Error('Unsupported guarantee');
      if (!node.residual?.length) throw new Error('Kernel and environment obligations must remain explicit');
    } else {
      const result = report.runs[node.run];
      if (!result || result.exit !== 0 || !result.passed || result.sourceDigest !== current.digest) {
        throw new Error(`Missing or stale executed evidence: ${node.run}`);
      }
      if (node.kind === 'tested-refinement' && result.target !== expectedTarget) throw new Error('Executed target mismatch');
      if (node.kind === 'tested-refinement' && !Object.keys(result.artifacts ?? {}).length) throw new Error('Missing built artifact');
      const suite = node.run === 'session-' + expectedTarget ? 'src/bounded_execution'
        : node.run === 'adapter-' + expectedTarget ? 'src/connectors/local'
        : node.run === 'connection-' + expectedTarget ? 'src/query_integration/local_managed_set_wbtest.mbt' : null;
      const expected = suite ? ['moon', 'test', suite, '--target', expectedTarget, '--deny-warn'] : null;
      if (expected && (JSON.stringify(result.command) !== JSON.stringify(expected) || !(result.count > 0))) {
        throw new Error(`Unrelated execution used as evidence: ${node.run}`);
      }
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

export function checkBindings(root, bindings) {
  const inventory = JSON.parse(readFileSync(join(root, 'docs/reviews/2026-09-23-local-resource-production-routes.json')));
  for (const binding of bindings) {
    const route = inventory.routes.find(row => row.operation === binding.operation);
    if (!route || route.entrypoint?.path !== binding.provider || route.entrypoint.symbol !== binding.entrypoint) {
      throw new Error(`Provider differs from authoritative route: ${binding.operation}`);
    }
    const provider = readFileSync(join(root, binding.provider), 'utf8');
    if (!provider.includes('bounded_session_execution(') || !provider.includes(`@execution.${binding.kernel}(`)) {
      throw new Error(`Missing reviewed adapter/kernel connection: ${binding.operation}`);
    }
    if (!['all', 'distinct'].includes(binding.variant) || !premises.every(p => binding.premises.includes(p))) {
      throw new Error('Invalid variant or missing premise');
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
