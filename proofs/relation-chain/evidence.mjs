import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import { snapshot as sessionSnapshot, artifacts, targets } from '../bounded-session/evidence.mjs';
export { artifacts, targets };
export const fixture = 'src/query_integration/relation_chain_evidence_wbtest.mbt';
export const premises = Object.freeze([
  'child delta reports are nonnegative representable and bounded by quantum',
  'cancel then next advance confirms stop without invoking Compute or adding work',
  'child cleanup true means completed reclamation; false or error retains responsibility',
  'intermediate producer reads bind the exact checked owner step and input port',
]);
export const guarantees = Object.freeze([
  'reported work is child work plus attempted handoff charges',
  'remaining budget preserves consumed work across children',
  'started child cleanup responsibility survives failure and cancellation',
  'terminal and cleanup retry do not restart Compute',
]);
const reviewed = Object.freeze([2, 3, 4].map(length => Object.freeze({
  operation: ['time_series', ...Array.from({ length: length - 1 }, (_, i) =>
    length > 2 && i === length - 2 ? 'select' : 'filter')].join('/'),
  variant: 'serial',
  profile: 'checked three-row nonnullable UTC Timestamp time; filter true; select time',
  length,
  stopContract: 'cancel-next-advance-no-compute-no-work',
  entrypoint: 'bounded_relation_chain_execution',
  provider: 'src/connectors/local/selected_relation_provider.mbt',
  children: ['src/local_tea_provider/time_series.mbt',
    ...Array(length - 1).fill('src/connectors/local/selected_relation_provider.mbt')],
})));
const clone = value => JSON.parse(JSON.stringify(value));
export const executedCoverage = () => ({ fixture, scopes: clone(reviewed) });
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const keys = Object.keys(reviewed[0]);
const matches = (a, b) => keys.every(key => same(a?.[key], b[key]));
export const bindings = () => reviewed.map(scope => ({ ...clone(scope),
  premises: [...premises], residual: [
    'child semantic and logical work contracts remain operation-specific',
    'capacity sum soundness, machine overflow and physical backend remain separate obligations',
    'finite real traces are tested refinement, not an implementation correspondence proof',
  ],
}));

export function checkBindings(root, requested) {
  if (!requested.length) throw new Error('Missing chain bindings');
  for (const binding of requested) {
    if (!reviewed.some(scope => matches(binding, scope))) throw new Error('Unverified chain execution scope');
    if (!premises.every(p => binding.premises?.includes(p))) throw new Error('Missing child premise');
  }
  // Reviewed real route, not a provider name or a reported capability flag.
  const chain = readFileSync(join(root, reviewed[0].provider), 'utf8');
  const tea = readFileSync(join(root, reviewed[0].children[0]), 'utf8');
  const connection = readFileSync(join(root, fixture), 'utf8');
  for (const symbol of ['bounded_relation_chain_execution(', 'start_bounded_relation_step(',
    'remaining.to_int()', 'bind_completed_operation_input(', 'selected_binding_rows_execution(',
    '@execution.start_bounded_binding_rows(', '@bounded.request_cancel(control)']) {
    if (!chain.includes(symbol)) throw new Error(`Missing reviewed chain route: ${symbol}`);
  }
  if (!tea.includes('@tea.start_time_series(') || !tea.includes('@bounded.request_cancel(control)') ||
      !connection.includes('local_module_managed_provider(') ||
      !connection.includes('chain_evidence_reference(')) throw new Error('Missing actual child/provider connection');
}
const hash = data => createHash('sha256').update(data).digest('hex');
const files = path => readdirSync(path, { withFileTypes: true }).flatMap(entry => {
  const child = join(path, entry.name);
  return entry.isDirectory() ? files(child) : entry.isFile() ? [child] : [];
});
export function snapshot(root) {
  const sources = { ...sessionSnapshot(root).sources,
    ...Object.fromEntries(files(join(root, 'proofs/relation-chain')).sort()
      .map(path => [relative(root, path), hash(readFileSync(path))])),
  };
  return { digest: hash(JSON.stringify(sources)), sources };
}
export function graph(requested, target) {
  const universal = { operation: '*', variant: '*', profile: '*', target };
  const nodes = [
    { id: 'model', kind: 'formal-model', scope: { ...universal, target: 'model' }, dependencies: [], run: 'lean' },
    { id: 'session', kind: 'tested-refinement', scope: universal, dependencies: ['model'], run: `session-${target}` },
  ];
  for (const binding of requested) {
    const scope = Object.fromEntries(keys.map(key => [key, clone(binding[key])]));
    scope.target = target;
    const id = binding.operation;
    nodes.push({ id: `${id}:connection`, kind: 'tested-refinement', scope: clone(scope),
      dependencies: ['model'], run: `connection-${target}` });
    nodes.push({ id, kind: 'derived', scope: clone(scope), dependencies: ['session', `${id}:connection`],
      premises: clone(binding.premises), guarantees: [...guarantees], residual: clone(binding.residual) });
  }
  return nodes;
}
export function validate(nodes, report, current, target) {
  if (!targets.includes(target) || report.target !== target) throw new Error('Target mismatch');
  if (report.source.digest !== current.digest) throw new Error('Stale source evidence');
  const byId = new Map(nodes.map(n => [n.id, n]));
  if (byId.size !== nodes.length) throw new Error('Duplicate claim');
  const visiting = new Set(), visited = new Set();
  const visit = node => {
    if (visiting.has(node.id)) throw new Error('Cyclic dependency');
    if (visited.has(node.id)) return;
    visiting.add(node.id);
    const model = node.kind === 'formal-model';
    if (node.id === 'model') {
      if (!model || node.run !== 'lean' || node.dependencies.length) throw new Error('Invalid model root');
    } else if (node.id === 'session') {
      if (node.kind !== 'tested-refinement' || node.run !== `session-${target}` ||
          !same(node.dependencies, ['model'])) throw new Error('Invalid Session correspondence');
    } else if (node.id.endsWith(':connection')) {
      if (node.kind !== 'tested-refinement' || node.run !== `connection-${target}` ||
          !same(node.dependencies, ['model'])) throw new Error('Invalid connection evidence');
    } else if (node.kind !== 'derived') throw new Error('Unknown evidence role');
    if (node.scope.target !== (model ? 'model' : target)) throw new Error('Claim target mismatch');
    if (!['formal-model', 'tested-refinement', 'derived'].includes(node.kind)) throw new Error('Unsupported evidence kind');
    for (const id of node.dependencies) {
      const dep = byId.get(id);
      if (!dep) throw new Error('Missing dependency evidence');
      if (dep.scope.operation !== '*' && !matches(node.scope, dep.scope)) throw new Error('Dependency scope mismatch');
      visit(dep);
    }
    if (node.kind === 'derived') {
      if (!reviewed.some(scope => matches(node.scope, scope))) throw new Error('Unverified derived execution scope');
      if (!same(node.guarantees, guarantees) || !premises.every(p => node.premises?.includes(p)) ||
          !node.residual?.length) throw new Error('Missing or unsupported obligations');
      for (const id of ['session', `${node.id}:connection`]) {
        if (!node.dependencies.includes(id)) throw new Error('Missing derivation premise');
      }
    } else {
      const result = report.runs[node.run];
      const suite = node.run === `session-${target}` ? 'src/bounded_execution'
        : node.run === `connection-${target}` ? fixture : null;
      const command = model ? [process.execPath, 'proofs/relation-chain/check.mjs']
        : ['moon', 'test', suite, '--target', target, '--deny-warn'];
      if (!result?.passed || result.exit !== 0 || result.sourceDigest !== current.digest ||
          !same(result.command, command)) throw new Error('Missing or unrelated executed evidence');
      if (!model) {
        if (!suite || result.target !== target || !(result.count >= (suite === fixture ? 4 : 1)) ||
            !Object.keys(result.artifacts ?? {}).length) throw new Error('Invalid executed target/artifact');
        for (const [path, digest] of Object.entries(result.artifacts)) {
          if (current.builtArtifacts?.[path] !== digest) throw new Error('Stale built artifact');
        }
      }
      if (suite === fixture && (!same(result.coverage, executedCoverage()) ||
          !result.coverage.scopes.some(scope => matches(node.scope, scope)))) {
        throw new Error('Scope not independently verified by execution fixture');
      }
    }
    visiting.delete(node.id); visited.add(node.id);
  };
  nodes.forEach(visit);
  return nodes.filter(n => n.kind === 'derived');
}
