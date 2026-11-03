import {retirementModelExecution, retirementFixture, retirementBindings, isRetirement, retirementPremises, retirementGuarantees, retirementResidual, executedRetirementCoverage, checkRetirementConnection} from './retirement-evidence.mjs';
export {retirementModelExecution, retirementFixture, retirementBindings, executedRetirementCoverage};
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import { snapshot as sessionSnapshot, artifacts, targets, includesObligations } from '../bounded-session/evidence.mjs';
export { artifacts, targets };
// The actual checker inventories 14 Session, 22 chain and 18 stop/pause laws.
export const modelExecution = Object.freeze({target: 'model', count: 14 + 22 + 18,
  command: Object.freeze([process.execPath, 'proofs/relation-chain/check.mjs']),
  summary: 'Checked 54 theorems, expected claim types and axiom dependencies'});
// Parse the complete observed checker result, never a caller-supplied count.
// Capacity and pipeline supply their independently reviewed checker descriptor.
export function modelObservationUnits(output, exit, expected = modelExecution) {
  const summaries = output.split(/\r?\n/u).filter(line => line.startsWith('Checked '));
  if (exit !== 0 || summaries.length !== 1 || summaries[0] !== expected.summary || output.includes('sorryAx')) {
    throw new Error('Missing or incomplete typed model observation');
  }
  return expected.count;
}

export const fixture = 'src/query_integration/relation_chain_evidence_wbtest.mbt';
export const pauseFixture = 'src/query_integration/relation_chain_stop_pause_wbtest.mbt';
export const stopFixture = 'src/query_integration/relation_chain_delayed_work_wbtest.mbt';
export const stopPremises = Object.freeze([
  'accepted stop-only deltas are representable, bounded by quantum; nonterminal Continue work is positive',
  'stop polls do not invoke Compute, start a successor or restore productive permission',
  'stop request and actual stop observation are distinct; no eventual-stop assumption',
  'cleanup completion is observed separately; false or error retains the same child responsibility',
]);
export const stopGuarantees = Object.freeze([
  'productive child and control work remains within the original productive budget',
  'reported work includes accepted stop-only deltas exactly once, including the terminal delta',
  'stop-inclusive diagnostic work may exceed productive max_work without reopening admission',
  'started child responsibility and no-Compute stopping survive finite stop and cleanup traces',
]);
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
const reviewedStop = Object.freeze({
  operation: 'registered-child/stop-accounting', variant: 'budget-exhaustion',
  profile: 'productive limit 1; stop deltas [1,1] or [1,0]; actual chain and standard managed driver',
  length: 2, stopContract: 'accepted-stop-only-polls-without-compute',
  entrypoint: 'bounded_relation_chain_execution',
  provider: 'src/connectors/local/selected_relation_provider.mbt',
  children: [stopFixture],
});
const reviewedPause = Object.freeze({
  operation: 'registered-child/stop-pause', variant: 'request-or-budget-exhaustion',
  profile: 'one productive unit; Waiting(0), Settling(slot=7,work=1), Settling(slot=7,work=0), Stopped(0); same child cleanup false/error/true',
  length: 2, stopContract: 'explicit-pause-kind-and-slot-without-stop-authority',
  entrypoint: 'bounded_relation_chain_execution',
  provider: 'src/connectors/local/selected_relation_provider.mbt', children: [pauseFixture],
});
export const pausePremises = Object.freeze([...stopPremises,
  'Waiting/Settling preserve their explicit kind and slot; no stop authority from zero work',
]);
export const pauseGuarantees = Object.freeze([...stopGuarantees,
  'zero-work pause preserves accounting and child custody; accepted positive pause work is charged once',
]);
const clone = value => JSON.parse(JSON.stringify(value));
export const executedCoverage = () => ({ fixture, scopes: clone(reviewed) });
export const executedStopCoverage = () => ({fixture: stopFixture, scopes: [clone(reviewedStop)]});
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const keys = Object.keys(reviewed[0]);
const matches = (a, b) => keys.every(key => same(a?.[key], b[key]));
const isStop = binding => matches(binding, reviewedStop);
const isPause = binding => matches(binding, reviewedPause);
const isStopping = binding => isStop(binding) || isPause(binding);
const stoppingPremises = binding => isPause(binding) ? pausePremises : stopPremises;
const stoppingGuarantees = binding => isPause(binding) ? pauseGuarantees : stopGuarantees;
const connectionRun = (binding, target) =>
  `${isRetirement(binding) ? 'retirement-connection' : isPause(binding) ? 'pause-connection' : isStop(binding) ? 'stop-connection' : 'connection'}-${target}`;
export const pauseResidual = Object.freeze([
  'finite diagnostic child only; no arbitrary Model/Store provider refinement or eventual stop',
  'slot/schema authority, machine overflow, invalid reports and physical capacity remain separate obligations',
  'holding marker checks callback custody; it is not a physical allocation measurement',
]);
export const pauseBindings = () => [{...clone(reviewedPause), premises: [...pausePremises], residual: [...pauseResidual]}];
export const executedPauseCoverage = () => ({fixture: pauseFixture, scopes: [clone(reviewedPause)]});
export const stopResidual = Object.freeze([
  'finite registered diagnostic child only; no arbitrary delayed-stop provider refinement or liveness',
  'machine overflow, invalid-report handling and capacity/physical retirement remain runtime obligations',
  'Waiting/Settling zero-work pause transitions are outside this six-case execution scope; use the separate pause claim',
  'early scratch retirement and semantic values are outside the stop-accounting model',
]);
export const stopBindings = () => [{...clone(reviewedStop), premises: [...stopPremises], residual: [...stopResidual]}];
export const promptResidual = Object.freeze([
    'child semantic and logical work contracts remain operation-specific',
    'capacity sum soundness, machine overflow and physical backend remain separate obligations',
    'finite real traces are tested refinement, not an implementation correspondence proof',
]);
const residualFor = scope => isRetirement(scope) ? retirementResidual : isPause(scope) ? pauseResidual : isStop(scope) ? stopResidual : promptResidual;
export const bindings = () => reviewed.map(scope => ({ ...clone(scope),
  premises: [...premises], residual: [...promptResidual],
}));

// Lexical masking preserves offsets while refusing unterminated source. This
// scanner does not interpret predicates: the finite witness below still names
// each exact checked operation and guarded handoff.
export function executableMoonSource(source) {
  let out = '', index = 0;
  const blank = text => text.replace(/[^\n]/gu, ' ');
  while (index < source.length) {
    const start = index;
    if (source.startsWith('//', index) || source.startsWith('#|', index) || source.startsWith('$|', index)) {
      const end = source.indexOf('\n', index); index = end < 0 ? source.length : end;
      out += blank(source.slice(start, index));
    } else if (source.startsWith('/*', index)) {
      let depth = 1; index += 2;
      while (index < source.length && depth) {
        if (source.startsWith('/*', index)) { depth++; index += 2; }
        else if (source.startsWith('*/', index)) { depth--; index += 2; }
        else index++;
      }
      if (depth) throw new Error('Unterminated current checked input cursor route comment');
      out += blank(source.slice(start, index));
    } else if (source[index] === '"' || source[index] === "'") {
      const quote = source[index++]; let closed = false;
      while (index < source.length) {
        if (source[index] === '\\') { index += 2; continue; }
        if (source[index++] === quote) { closed = true; break; }
      }
      if (!closed) throw new Error('Unterminated current checked input cursor route literal');
      out += blank(source.slice(start, index));
    } else out += source[index++];
  }
  return out;
}

export function checkedInputFunction(source, name) {
  const matches = [...source.matchAll(new RegExp(`\\bfn\\s+${name}\\s*\\(`, 'gu'))];
  if (matches.length !== 1) throw new Error(`Missing current checked input cursor route: ${name}`);
  const start = source.indexOf('{', matches[0].index); let depth = 0;
  if (start < 0) throw new Error(`Missing current checked input cursor route: ${name} body`);
  for (let index = start; index < source.length; index++) {
    if (source[index] === '{') depth++;
    if (source[index] === '}' && --depth === 0) return source.slice(start, index + 1).replace(/\s+/gu, '');
  }
  throw new Error(`Unterminated current checked input cursor route: ${name}`);
}

export function checkBindings(root, requested, {read = path => readFileSync(join(root, path), 'utf8')} = {}) {
  if (!requested.length) throw new Error('Missing chain bindings');
  for (const binding of requested) {
    if (!isRetirement(binding) && !isStopping(binding) && !reviewed.some(scope => matches(binding, scope))) throw new Error('Unverified chain execution scope');
    if (!includesObligations(binding.premises, isRetirement(binding) ? retirementPremises : isStopping(binding) ? stoppingPremises(binding) : premises)) throw new Error('Missing child premise');
    if (!includesObligations(binding.residual, residualFor(binding))) throw new Error('Missing chain residual obligation');
  }
  if (requested.some(isRetirement)) checkRetirementConnection(read);
  // Reviewed real route, not a provider name or a reported capability flag.
  const chain = read(reviewed[0].provider);
  const tea = read(reviewed[0].children[0]);
  const connection = read(fixture);
  for (const symbol of ['bounded_relation_chain_execution(', 'start_bounded_relation_step(',
    'remaining.to_int()', 'start_relation_chain_inputs(', 'advance_relation_chain_inputs(',
    'cancel_relation_chain_inputs(', 'selected_binding_rows_execution(',
    '@execution.start_bounded_binding_rows(', '@bounded.request_cancel(control)']) {
    if (!chain.includes(symbol)) throw new Error(`Missing reviewed chain route: ${symbol}`);
  }
  if (!tea.includes('@tea.start_time_series(') || !tea.includes('@bounded.request_cancel(control)') ||
      !connection.includes('local_module_managed_provider(') ||
      !connection.includes('chain_evidence_reference(')) throw new Error('Missing actual child/provider connection');
  // The existing metadata owner now carries this binding; do not accept a
  // symbol elsewhere as evidence that the actual receiver/port/output match.
  const input = read('src/connectors/local/relation_chain_input_preparation.mbt');
  const executable = executableMoonSource(input);
  const compact = executable.replace(/\s+/gu, '');
  for (const route of [
    '@execution.bind_completed_operation_input(cursor.owner,cursor.step,cursor.port,cursor.owner,output,)',
    '@execution.start_prepare_producer_read(cursor.owner,bound,@execution.producer_read_demand_entries(demand),@execution.producer_read_demand_name_bytes(demand),)',
    '@execution.advance_prepare_producer_read(read)',
    'cursor.selected.push(RelationInput(read))',
    '@execution.cancel_prepare_producer_read(read)',
  ]) if (!compact.includes(route)) throw new Error(`Missing current checked input cursor route: ${route}`);
  // Each actual checked receiver/port binding must issue its own demand before
  // the same bound input is prepared. A matching call in the other path does
  // not justify a stale or caller-sized read in this one.
  for (const [name, port, bindingFailure, demandFailure] of [
    ['advance_relation_chain_inputs', 'cursor.port', 'returnErr(@connector.Execution(@execution.InputSet))',
      'returnErr(@connector.Execution(@execution.InputLimit))'],
    ['relation_chain_inputs_are_small', 'port', 'returntrue', 'returntrue'],
  ]) {
    const body = checkedInputFunction(executable, name);
    const route = `letbound=match@execution.bind_completed_operation_input(cursor.owner,cursor.step,${port},cursor.owner,output,){Ok(bound)=>boundErr(_)=>${bindingFailure}}` +
      `guard@execution.bound_producer_read_demand(cursor.owner,bound)isSome(demand)else{${demandFailure}}` +
      'letread=match@execution.start_prepare_producer_read(cursor.owner,bound,@execution.producer_read_demand_entries(demand),@execution.producer_read_demand_name_bytes(demand),)';
    if (!body.includes(route)) throw new Error(`Missing current checked input cursor route: ${name} admitted demand`);
  }
  if (!compact.includes('cursor.completed.get(position)isSome(Some(output))') ||
      !compact.includes('@execution.generated_sequence_step_index_at(cursor.sequence,position)==Some(producer)')) {
    throw new Error('Missing exact predecessor completion selection');
  }
  if (requested.some(isStopping)) {
    const stop = read(stopFixture);
    if (requested.some(isStop)) for (const name of [
      'delayed-stop work audit preserves final physical stop work',
      'delayed-stop work audit confirms a zero-work terminal stop control',
      'budget stop retains cleanup when a stopped child rejects further polling',
      'chain retains child accounting failure through stop and cleanup',
      'work audit records the existing completed-only observation boundary',
      'standard driver retains exhausted chain work through failure and cleanup',
    ]) if (!stop.includes(`test "${name}"`)) throw new Error('Missing reviewed stop correspondence fixture');
    for (const symbol of ['cancel_managed_provider(active)', 'advance_managed_provider(active, 1)',
      'Stopped(progress~, work~) => (progress, work)', 'managed_provider_stopped_poll(progress, work)',
      'managed_provider_stopped(active)']) {
      if (!chain.includes(symbol)) throw new Error(`Missing actual stop work route: ${symbol}`);
    }
  }
  if (requested.some(isPause)) {
    const pause = read(pauseFixture);
    for (const name of [
      'explicit stop preserves Waiting and Settling custody through cleanup retry',
      'budget stop preserves Waiting and Settling custody through cleanup retry',
    ]) if (!pause.includes(`test "${name}"`)) throw new Error('Missing reviewed pause correspondence fixture');
    const begin = chain.indexOf('if cancelled.val || used.val >= execution.max_work.to_int64() {');
    const end = chain.indexOf('let remaining = execution.max_work.to_int64() - used.val', begin);
    const stopRoute = chain.slice(begin, end).replace(/\s+/gu, '');
    if (begin < 0 || end <= begin || !stopRoute.includes('Waiting(..)|Settling(_,..)=>Ok(poll)')) {
      throw new Error('Missing exact stop pause forwarding route');
    }
    const driver = read('src/connectors/local/managed_provider.mbt').replace(/\s+/gu, '');
    if (!driver.includes('(pollisContinue(..)&&work==0L)')) {
      throw new Error('Missing distinct pause/Continue work acceptance');
    }
  }
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
  if (requested.some(isRetirement)) nodes.push({id: 'retirement-model', kind: 'formal-model',
    scope: {...universal, target: 'model'}, dependencies: ['model'], run: 'retirement-lean'});
  for (const binding of requested) {
    const scope = Object.fromEntries(keys.map(key => [key, clone(binding[key])]));
    scope.target = target;
    const id = binding.operation;
    const stopping = isStopping(binding);
    nodes.push({ id: `${id}:connection`, kind: 'tested-refinement', scope: clone(scope),
      dependencies: [isRetirement(binding) ? 'retirement-model' : 'model'], run: connectionRun(binding, target) });
    nodes.push({ id, kind: 'derived', scope: clone(scope),
      dependencies: [...(isRetirement(binding) ? ['session', 'retirement-model'] : [stopping ? 'model' : 'session']), `${id}:connection`],
      premises: clone(binding.premises), guarantees: [...(isRetirement(binding) ? retirementGuarantees : stopping ? stoppingGuarantees(binding) : guarantees)], residual: clone(binding.residual) });
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
    } else if (node.id === 'retirement-model') {
      if (!model || node.run !== 'retirement-lean' || !same(node.dependencies, ['model'])) throw new Error('Invalid retirement model root');
    } else if (node.id === 'session') {
      if (node.kind !== 'tested-refinement' || node.run !== `session-${target}` ||
          !same(node.dependencies, ['model'])) throw new Error('Invalid Session correspondence');
    } else if (node.id.endsWith(':connection')) {
      if (node.kind !== 'tested-refinement' || node.run !== connectionRun(node.scope, target) ||
          !same(node.dependencies, [isRetirement(node.scope) ? 'retirement-model' : 'model'])) throw new Error('Invalid connection evidence');
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
      const stopping = isStopping(node.scope);
      if (!isRetirement(node.scope) && !stopping && !reviewed.some(scope => matches(node.scope, scope))) throw new Error('Unverified derived execution scope');
      if (!same(node.guarantees, isRetirement(node.scope) ? retirementGuarantees : stopping ? stoppingGuarantees(node.scope) : guarantees) || !includesObligations(node.premises, isRetirement(node.scope) ? retirementPremises : stopping ? stoppingPremises(node.scope) : premises) ||
          !includesObligations(node.residual, residualFor(node.scope))) throw new Error('Missing or unsupported obligations');
      for (const id of [...(isRetirement(node.scope) ? ['session', 'retirement-model'] : [stopping ? 'model' : 'session']), `${node.id}:connection`]) {
        if (!node.dependencies.includes(id)) throw new Error('Missing derivation premise');
      }
    } else {
      const result = report.runs[node.run];
      const suite = node.run === `session-${target}` ? 'src/bounded_execution'
        : node.run === `connection-${target}` ? fixture
        : node.run === `stop-connection-${target}` ? stopFixture
        : node.run === `pause-connection-${target}` ? pauseFixture
        : node.run === `retirement-connection-${target}` ? retirementFixture : null;
      const expectedModel = node.id === 'retirement-model' ? retirementModelExecution : modelExecution;
      const command = model ? expectedModel.command
        : ['moon', 'test', suite, '--target', target, '--deny-warn'];
      if (!result?.passed || result.exit !== 0 || result.sourceDigest !== current.digest ||
          !same(result.command, command)) throw new Error('Missing or unrelated executed evidence');
      if (model && (result.target !== expectedModel.target || result.count !== expectedModel.count))
        throw new Error('Invalid model target or theorem count');
      if (!model) {
        if (!suite || result.target !== target || !(result.count >= (suite === retirementFixture ? 8 : suite === pauseFixture ? 2 : suite === stopFixture ? 6 : suite === fixture ? 4 : 1)) ||
            !Object.keys(result.artifacts ?? {}).length) throw new Error('Invalid executed target/artifact');
        for (const [path, digest] of Object.entries(result.artifacts)) {
          if (current.builtArtifacts?.[path] !== digest) throw new Error('Stale built artifact');
        }
      }
      if (suite === retirementFixture && (!Number.isSafeInteger(result.count) ||
          !same(result.coverage, executedRetirementCoverage()) ||
          !result.coverage.scopes.some(scope => isRetirement(scope) && isRetirement(node.scope)))) {
        throw new Error('Retirement scope not independently executed');
      }
      if (suite === fixture && (!same(result.coverage, executedCoverage()) ||
          !result.coverage.scopes.some(scope => matches(node.scope, scope)))) {
        throw new Error('Scope not independently verified by execution fixture');
      }
      if (suite === stopFixture && (!same(result.coverage, executedStopCoverage()) ||
          !result.coverage.scopes.some(scope => matches(node.scope, scope)))) {
        throw new Error('Stop scope not independently verified by execution fixture');
      }
      if (suite === pauseFixture && (!same(result.coverage, executedPauseCoverage()) ||
          !result.coverage.scopes.some(scope => matches(node.scope, scope)))) {
        throw new Error('Pause scope not independently verified by execution fixture');
      }
    }
    visiting.delete(node.id); visited.add(node.id);
  };
  nodes.forEach(visit);
  return nodes.filter(n => n.kind === 'derived');
}
