import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import * as chain from '../relation-chain/evidence.mjs';
export const { targets, artifacts } = chain;
export const modelExecution = Object.freeze({target: 'model', count: 14,
  command: Object.freeze([process.execPath, 'proofs/relation-capacity/check.mjs']),
  summary: 'Checked 14 capacity theorems, expected types and axiom dependencies; child/parent bounds are premises'});
export const modelObservationUnits = (output, exit) => chain.modelObservationUnits(output, exit, modelExecution);
export const fixture = 'src/query_integration/relation_chain_capacity_wbtest.mbt';
export const identityFixture = 'src/execution_relation/relation_capacity_identity_wbtest.mbt';
const inventoryPath = 'proofs/relation-capacity/allocations.json';
export const inventoryDigest = '7803891e6bf94d186f30d4ccd2d3547cb9d507978ee63b3638494a20421de9fc';
const clone = x => JSON.parse(JSON.stringify(x));
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const reviewed = Object.freeze(chain.bindings().map(b => Object.freeze({
  operation: b.operation, variant: b.variant, profile: b.profile, length: b.length,
  provider: b.provider, entrypoint: 'bounded_relation_chain_capacity',
  children: clone(b.children),
  inventory: inventoryPath, observation: 'inventoried live allocation bytes with explicit bounds',
})));
export const premises = Object.freeze([
  'complete unique physical allocation registry with stable nonnegative byte sizes',
  'all live allocations are covered by the frozen base/child/parent inventory',
  'base retained allocation bytes fit base.retained_bytes',
  'each child live allocation bytes fit child.retained_bytes + child.execution_bytes',
  'parent-control and uncovered edge allocation bytes fit count * 256 (UNPROVED)',
]);
export const unresolved = Object.freeze([
  'individual child/base allocation upper bounds are assumed, not proved by composition',
  '256-byte parent allowance has no enumerated target-specific sizing derivation',
  'no production allocation census establishes exhaustive byte/identity correspondence',
  'retained descendants after Compute cleanup require the existing Host ownership/independent-copy contract',
  'GC/allocator overhead and process heap/RSS are outside this capacity unit',
]);
export const guarantee = 'conditional live-allocation upper bound under every declared premise';
export const coverage = () => ({ fixture, identityFixture, scopes: clone(reviewed) });
export const bindings = () => reviewed.map(scope => ({ ...clone(scope), premises: [...premises], unresolved: [...unresolved], guarantee }));
export function checkBindings(root, requested, {read = path => readFileSync(join(root, path))} = {}) {
  if (!requested.length) throw new Error('Missing capacity bindings');
  for (const b of requested) {
    if (!reviewed.some(scope => Object.keys(scope).every(k => same(b[k], scope[k]))) ||
        !same(b.premises, premises) || !same(b.unresolved, unresolved) || b.guarantee !== guarantee) throw new Error('Unverified or overstated capacity scope');
  }
  const raw = read(inventoryPath);
  if (hash(raw) !== inventoryDigest) throw new Error('Frozen allocation inventory changed; explicit review required');
  const inventory = JSON.parse(raw);
  if (!inventory.included.some(x => x.id === 'parent-control' && x.status.startsWith('UNPROVED'))) throw new Error('Missing parent allowance obligation');
  for (const entry of inventory.included) {
    const source = read(entry.source).toString('utf8');
    for (const symbol of entry.symbols) if (!source.includes(symbol)) throw new Error(`Missing inventory connection ${symbol}`);
    for (const path of entry.additionalSources ?? []) read(path);
  }
  // Bind the current retained quote inside its actual selected constructor.
  // These are logical input dimensions, not a measured physical byte census.
  const capacity = chain.checkedInputFunction(chain.executableMoonSource(
    read('src/execution_relation/execution_capacity.mbt').toString('utf8')),
  'generated_sequence_capacity');
  const retainedQuote = 'guardexecution_capacity_inventory_bytes([' +
    '{unit:CursorRootSlots,count:rows.retained_entries.to_int64(),copies:1,},' +
    '{unit:CursorRootSlots,count:rows.metadata_entries.to_int64(),copies:1,},' +
    '{unit:ValueNodeSlots,count:rows.output_values.max_nodes.to_int64(),copies:1,},' +
    '{unit:DecodedTextBytes,count:rows.output_values.max_text_bytes.to_int64(),copies:1,},' +
    '])isSome(retained)&&';
  if (!capacity.includes(retainedQuote) ||
      !capacity.includes('Some({retained_bytes:retained,execution_bytes:execution,})')) {
    throw new Error('Missing current retained capacity quote connection');
  }
  // The reviewed scopes all start with TimeSeries, so the existing sum-of-child
  // model must not be silently applied to the built-in-only max-scratch branch.
  chain.checkBindings(root, chain.bindings(), {read: path => read(path).toString('utf8')});
  const source = read('src/connectors/local/selected_relation_provider.mbt').toString('utf8').replace(/\s+/gu, '');
  for (const route of [
    'scratch+=child.execution_bytes',
    'letpreparation=ifcount>1{512L}else{0L}',
    'whilecleanup_index.val>=0{matchcleanup_managed_provider(state.children[cleanup_index.val]){Ok(true)=>cleanup_index.val-=1Ok(false)=>returnOk(false)Err(issue)=>returnErr(issue)}}state.current=Noneifstate.input_preparationisSome(cursor){cancel_relation_chain_inputs(cursor)}state.input_preparation=Nonestate.completed=[]state.children=[]reclaimed.val=true',
  ]) if (!source.includes(route)) throw new Error('Missing current capacity/cleanup custody connection');
}
const hash = b => createHash('sha256').update(b).digest('hex');
const files = path => readdirSync(path, { withFileTypes: true }).flatMap(e => e.isDirectory() ? files(join(path, e.name)) : e.isFile() ? [join(path, e.name)] : []);
export function snapshot(root) {
  const sources = { ...chain.snapshot(root).sources, ...Object.fromEntries(files(join(root, 'proofs/relation-capacity')).sort().map(path => [relative(root, path), hash(readFileSync(path))])) };
  return { digest: hash(JSON.stringify(sources)), sources };
}
export function validate(requested, report, current, target) {
  if (!targets.includes(target) || report.target !== target || report.source.digest !== current.digest) throw new Error('Stale source or target');
  if (!requested.length || report.source.digest !== hash(JSON.stringify(report.source.sources)) ||
      report.source.sources[inventoryPath] !== inventoryDigest || current.sources[inventoryPath] !== inventoryDigest) throw new Error('Invalid source or frozen inventory receipt');
  // The reviewed execution scope is independent of caller bindings and report.
  for (const b of requested) if (!bindings().some(x => same(x, b))) throw new Error('Unverified or unconditional capacity claim');
  if (!same(report.coverage, coverage())) throw new Error('Unverified executed coverage');
  const expected = {
    lean: modelExecution.command,
    [`capacity-${target}`]: ['moon', 'test', fixture, '--target', target, '--deny-warn'],
    [`identity-${target}`]: ['moon', 'test', identityFixture, '--target', target, '--deny-warn'],
    [`ledger-${target}`]: ['moon', 'test', 'src/physical_resources/ledger_wbtest.mbt', '--target', target, '--deny-warn'],
  };
  for (const [id, command] of Object.entries(expected)) {
    const run = report.runs[id];
    if (!run?.passed || run.exit !== 0 || run.sourceDigest !== current.digest || !same(run.command, command)) throw new Error('Missing or unrelated execution');
    if (id === 'lean' && (run.target !== modelExecution.target || run.count !== modelExecution.count))
      throw new Error('Invalid model target or theorem count');
    if (id !== 'lean') {
      if (run.target !== target || run.count < (id.startsWith('capacity') ? 3 : 1) || !Object.keys(run.artifacts ?? {}).length) throw new Error('Unexecuted correspondence fixture');
      for (const [path, digest] of Object.entries(run.artifacts)) if (current.builtArtifacts?.[path] !== digest) throw new Error('Stale artifact');
    }
  }
  return requested.map(b => ({ kind: 'derived', target, ...clone(b) }));
}
