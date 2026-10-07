import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { modelExecution, modelObservationUnits, bindings, pauseBindings, pauseFixture, pausePremises, pauseGuarantees, executedPauseCoverage, stopBindings, stopFixture, stopPremises, stopGuarantees, executedStopCoverage, checkBindings, executedCoverage, fixture, graph, premises, snapshot, validate } from './evidence.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const clone = value => structuredClone(value);
function evidence(target = 'js') {
  const source = snapshot(root), artifact = { 'test.js': 'digest' };
  const runs = { lean: { command: [process.execPath, 'proofs/relation-chain/check.mjs'],
    passed: true, exit: 0, target: 'model', count: 54, sourceDigest: source.digest } };
  for (const [id, suite] of [['session', 'src/bounded_execution'], ['connection', fixture]]) {
    runs[`${id}-${target}`] = { command: ['moon', 'test', suite, '--target', target, '--deny-warn'],
      target, passed: true, exit: 0, count: 4, sourceDigest: source.digest,
      artifacts: artifact, ...(id === 'connection' ? { coverage: executedCoverage() } : {}) };
  }
  return { nodes: graph(bindings(), target), report: { source, target, runs },
    current: { ...source, builtArtifacts: clone(artifact) } };
}
test('reviewed actual chain bindings and conditional derived claims', () => {
  checkBindings(root, bindings());
  for (const target of ['js', 'wasm', 'native']) {
    const e = evidence(target);
    assert.equal(validate(e.nodes, e.report, e.current, target).length, 3);
  }
});
for (const [label, from, to] of [
  ['receiver step replaced', 'cursor.step,\n            cursor.port,', '0,\n            cursor.port,'],
  ['receiver port replaced', 'cursor.port,\n            cursor.owner,', '0,\n            cursor.owner,'],
  ['completion selection replaced', 'cursor.completed.get(position)', 'cursor.completed.get(0)'],
  ['producer match bypassed', 'step_index_at(cursor.sequence, position) ==\n        Some(producer) {',
    'step_index_at(cursor.sequence, position) ==\n        Some(0) {'],
]) test(`current metadata binding refuses ${label}`, () => {
  const path = 'src/connectors/local/relation_chain_input_preparation.mbt';
  const source = readFileSync(root + path, 'utf8');
  assert.equal(source.split(from).length, 2, 'Missing unique binding witness');
  assert.throws(() => checkBindings(root, bindings(), {
    read: p => p === path ? source.replace(from, to) : readFileSync(root + p, 'utf8'),
  }), /input cursor route|predecessor completion selection/);
});

function stoppingEvidence(target = 'js') {
  const e = evidence(target);
  e.nodes = graph([...bindings(), ...stopBindings()], target);
  const original = e.report.runs[`connection-${target}`];
  e.report.runs[`stop-connection-${target}`] = {...clone(original), count: 6,
    command: ['moon', 'test', stopFixture, '--target', target, '--deny-warn'],
    coverage: executedStopCoverage()};
  return e;
}
test('scoped delayed-stop evidence composes with the existing graph without weakening prompt-stop claims', () => {
  checkBindings(root, [...bindings(), ...stopBindings()]);
  for (const target of ['js', 'wasm', 'native']) {
    const e = stoppingEvidence(target);
    assert.equal(validate(e.nodes, e.report, e.current, target).length, 4);
    const derived = e.nodes.at(-1);
    assert.deepEqual(derived.dependencies, ['model', `${derived.id}:connection`]);
    assert.deepEqual(derived.guarantees, stopGuarantees);
  }
});
for (const [label, change] of [
  ['ordinary prompt-stop fixture substituted', e => { e.report.runs['stop-connection-js'].command[2] = fixture; }],
  ['unexecuted stop case', e => { e.report.runs['stop-connection-js'].count = 5; }],
  ['invented stopping profile', e => { e.nodes.at(-1).scope.stopContract = 'eventual-stop'; }],
  ['missing stop prerequisite', e => { e.nodes.at(-1).premises = stopPremises.slice(1); }],
  ['productive and reported budgets conflated', e => { e.nodes.at(-1).guarantees.push('all reported work below max_work'); }],
  ['missing stop model', e => { e.nodes.at(-1).dependencies.shift(); }],
  ['missing actual stop coverage', e => { delete e.report.runs['stop-connection-js'].coverage; }],
  ['stop scope widened on both sides', e => {
    e.nodes.at(-1).scope.profile = '*';
    e.report.runs['stop-connection-js'].coverage.scopes[0].profile = '*';
  }],
]) test(`refuse delayed-stop evidence: ${label}`, () => {
  const e = stoppingEvidence(); change(e);
  assert.throws(() => validate(e.nodes, e.report, e.current, 'js'));
});
for (const [label, change] of [
  ['profile', b => { b.profile = 'UNCHECKED rows with arbitrary field types'; }],
  ['provider', b => { b.children[0] = 'unverified/provider.mbt'; }],
  ['stop premise', b => { b.stopContract = 'eventual-stop'; }],
  ['length', b => { b.length = 100; }],
  ['operation', b => { b.operation = 'time_series/distinct'; }],
]) test(`same-source both-sided ${label} relabeling cannot reuse execution`, () => {
  const e = evidence(), requested = bindings();
  change(requested[0]);
  assert.throws(() => checkBindings(root, requested));
  // Neither the independent execution record nor source/artifact changes.
  assert.throws(() => validate(graph(requested, 'js'), e.report, e.current, 'js'));
});
for (const [label, corrupt] of [
  ['missing child premise', e => { e.nodes.at(-1).premises = premises.slice(1); }],
  ['missing connection', e => { e.nodes.at(-1).dependencies.pop(); }],
  ['stale source', e => { e.current.digest = 'changed'; }],
  ['stale artifact', e => { e.current.builtArtifacts['test.js'] = 'changed'; }],
  ['unexecuted fixture', e => { e.report.runs['connection-js'].count = 0; }],
  ['target substitution', e => { e.report.runs['connection-js'].target = 'native'; }],
  ['fixture substitution', e => { e.report.runs['connection-js'].command[2] = 'src/other'; }],
  ['coverage widened in record', e => { e.report.runs['connection-js'].coverage.scopes[0].profile = '*'; }],
  ['forged formal connection', e => { const n = e.nodes.find(n => n.id.endsWith(':connection')); n.kind = 'formal-model'; n.scope.target = 'model'; n.run = 'lean'; }],
  ['cycle', e => { e.nodes[0].dependencies = [e.nodes.at(-1).id]; }],
  ['capacity guarantee', e => { e.nodes.at(-1).guarantees.push('all memory bounded'); }],
]) test(`reject ${label}`, () => {
  const e = evidence(); corrupt(e);
  assert.throws(() => validate(e.nodes, e.report, e.current, 'js'));
});

function pauseEvidence(target = 'js') {
  const e = stoppingEvidence(target);
  e.nodes = graph([...bindings(), ...stopBindings(), ...pauseBindings()], target);
  e.report.runs[`pause-connection-${target}`] = {...clone(e.report.runs[`connection-${target}`]), count: 2,
    command: ['moon', 'test', pauseFixture, '--target', target, '--deny-warn'],
    coverage: executedPauseCoverage()};
  return e;
}
test('pause claim inherits common stop laws with its own independently executed connection', () => {
  checkBindings(root, [...bindings(), ...stopBindings(), ...pauseBindings()]);
  for (const target of ['js', 'wasm', 'native']) {
    const e = pauseEvidence(target);
    assert.equal(validate(e.nodes, e.report, e.current, target).length, 5);
    assert.deepEqual(e.nodes.at(-1).guarantees, pauseGuarantees);
    assert.deepEqual(e.nodes.at(-1).dependencies, ['model', 'registered-child/stop-pause:connection']);
  }
});
for (const [label, change] of [
  ['old six-case connection substituted', e => {e.report.runs['pause-connection-js'].command[2] = stopFixture;}],
  ['only one stop trigger executed', e => {e.report.runs['pause-connection-js'].count = 1;}],
  ['pause custody premise absent', e => {e.nodes.at(-1).premises = pausePremises.slice(0, -1);} ],
  ['missing independent pause coverage', e => {delete e.report.runs['pause-connection-js'].coverage;}],
  ['slot broadened on both sides', e => {
    e.nodes.at(-1).scope.profile = 'arbitrary Model slots';
    e.report.runs['pause-connection-js'].coverage.scopes[0].profile = 'arbitrary Model slots';
  }],
  ['pause classified as formal implementation proof', e => {e.nodes.at(-2).kind = 'formal-model';}],
  ['pause treated as stop confirmation', e => {e.nodes.at(-1).guarantees.push('Waiting confirms physical stop');}],
]) test(`refuse pause evidence: ${label}`, () => {
  const e = pauseEvidence(); change(e);
  assert.throws(() => validate(e.nodes, e.report, e.current, 'js'));
});
test('actual pause forwarding and distinct zero-work acceptance remain mandatory', () => {
  const path = 'src/connectors/local/selected_relation_provider.mbt';
  const source = readFileSync(root + path, 'utf8');
  const from = 'Waiting(..) | Settling(_, ..) => Ok(poll)';
  assert.equal(source.split(from).length, 3);
  assert.throws(() => checkBindings(root, pauseBindings(), {
    read: p => p === path ? source.replace(from, '_ => Ok(poll)') : readFileSync(root + p, 'utf8'),
  }), /exact stop pause forwarding/);
});

for (const [label, transform] of [
  ['unrelated nonempty text', _ => ['no remaining obligations']],
  ['all obligations embedded in one string', values => [values.join('; ')]],
  ['string instead of list', values => values.join('; ')],
  ['duplicate obligation', values => [...values, values[0]]],
]) test(`all chain scopes preserve independent residual obligations: ${label}`, () => {
  for (const [b, make] of [[bindings()[0], evidence], [stopBindings()[0], stoppingEvidence], [pauseBindings()[0], pauseEvidence]]) {
    const changed = transform(b.residual);
    assert.throws(() => checkBindings(root, [{...b, residual: changed}]), /Missing chain residual/);
    const e = make();
    const claim = e.nodes.find(node => node.kind === 'derived' && node.scope.operation === b.operation);
    claim.residual = changed;
    assert.throws(() => validate(e.nodes, e.report, e.current, 'js'), /Missing or unsupported obligations/);
  }
});
test('each prompt, stop and pause residual is individually required while additional local obligations remain allowed', () => {
  for (const [b, make] of [[bindings()[0], evidence], [stopBindings()[0], stoppingEvidence], [pauseBindings()[0], pauseEvidence]]) {
    for (const omitted of b.residual) {
      const remaining = b.residual.filter(value => value !== omitted);
      assert.throws(() => checkBindings(root, [{...b, residual: remaining}]), /Missing chain residual/);
      const e = make();
      e.nodes.find(node => node.kind === 'derived' && node.scope.operation === b.operation).residual = remaining;
      assert.throws(() => validate(e.nodes, e.report, e.current, 'js'), /Missing or unsupported obligations/);
    }
    const expanded = {...b, residual: [...b.residual].reverse().concat('additional explicitly retained local obligation')};
    checkBindings(root, [expanded]);
    const e = make();
    e.nodes.find(node => node.kind === 'derived' && node.scope.operation === b.operation).residual = expanded.residual;
    assert(validate(e.nodes, e.report, e.current, 'js').some(node => node.scope.operation === b.operation));
  }
});
test('chain common premises cannot be satisfied by a concatenated string', () => {
  const b = bindings()[0];
  assert.throws(() => checkBindings(root, [{...b, premises: b.premises.join('; ')}]), /Missing child premise/);
  const e = evidence(); e.nodes.find(node => node.kind === 'derived').premises = b.premises.join('; ');
  assert.throws(() => validate(e.nodes, e.report, e.current, 'js'), /Missing or unsupported obligations/);
});

for (const [label, change] of [
  ['zero laws', r => { r.count = 0; }],
  ['missing count', r => { delete r.count; }],
  ['null count', r => { r.count = null; }],
  ['partial legacy inventory', r => { r.count = 36; }],
  ['extra laws', r => { r.count = 55; }],
  ['string count', r => { r.count = '54'; }],
  ['runtime target', r => { r.target = 'js'; }],
  ['missing target', r => { delete r.target; }],
]) test(`chain refuses ${label} across prompt, delayed-stop and pause scopes`, () => {
  for (const make of [evidence, stoppingEvidence, pauseEvidence]) {
    const e = make(); change(e.report.runs.lean);
    assert.throws(() => validate(e.nodes, e.report, e.current, 'js'), /model target or theorem count/);
  }
});
test('chain model count comes from one complete observed typed/axiom summary', () => {
  const summary = 'Checked 54 theorems, expected claim types and axiom dependencies';
  assert.equal(modelObservationUnits(`audit lines\n${summary}\n`, 0), 54);
  assert.equal(modelObservationUnits(`${summary}\r\n`, 0), 54);
  for (const [output, exit] of [
    ['', 0], [summary.replace('54', '36'), 0], [summary.replace('54', '55'), 0],
    [summary, 1], [summary, null], [`quoted: ${summary}`, 0],
    [`${summary}\n${summary}`, 0], [`sorryAx\n${summary}`, 0],
  ]) assert.throws(() => modelObservationUnits(output, exit), /typed model observation/);
  assert.equal(modelExecution.count, 54);
});
