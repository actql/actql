import {retirementModelExecution, retirementFixture, retirementBindings, executedRetirementCoverage} from './retirement-evidence.mjs';
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

for (const name of ['advance_relation_chain_inputs', 'relation_chain_inputs_are_small']) {
  for (const [label, from, to] of [
    ['foreign demand owner', 'bound_producer_read_demand(cursor.owner, bound)', 'bound_producer_read_demand(other, bound)'],
    ['different bound demand', 'bound_producer_read_demand(cursor.owner, bound)', 'bound_producer_read_demand(cursor.owner, other)'],
    ['caller entry allowance', '@execution.producer_read_demand_entries(demand)', 'cursor.max_entries'],
    ['caller name allowance', '@execution.producer_read_demand_name_bytes(demand)', 'cursor.max_value_bytes'],
    ['swapped demand quantity', '@execution.producer_read_demand_entries(demand)', '@execution.producer_read_demand_name_bytes(demand)'],
    ['unproven demand fallback', 'is Some(demand) else {', 'is Some(demand) || true else {'],
  ]) test(`current metadata binding refuses ${name}: ${label}`, () => {
    const path = 'src/connectors/local/relation_chain_input_preparation.mbt';
    const source = readFileSync(root + path, 'utf8');
    const marker = `fn ${name}(`, start = source.indexOf(marker);
    assert(start >= 0); const end = source.indexOf('///|', start);
    const body = source.slice(start, end < 0 ? undefined : end);
    assert.equal(body.split(from).length, 2, 'Mutation reaches exactly one owned path');
    const changed = source.slice(0, start) + body.replace(from, to) + (end < 0 ? '' : source.slice(end));
    assert.throws(() => checkBindings(root, bindings(), {
      read: p => p === path ? changed : readFileSync(root + p, 'utf8'),
    }), /input cursor route/);
  });
}

for (const name of ['advance_relation_chain_inputs', 'relation_chain_inputs_are_small']) {
  for (const disguise of ['line-comment', 'block-comment', 'string', 'unrelated-function'])
    test(`checked demand route cannot be supplied by ${disguise} beside ${name}`, () => {
      const path = 'src/connectors/local/relation_chain_input_preparation.mbt';
      const source = readFileSync(root + path, 'utf8');
      const start = source.indexOf(`fn ${name}(`), end = source.indexOf('///|', start);
      const body = source.slice(start, end < 0 ? undefined : end);
      const wrong = body.replace('bound_producer_read_demand(cursor.owner, bound)', 'bound_producer_read_demand(other, bound)');
      assert.notEqual(wrong, body);
      const retained = disguise === 'line-comment' ? body.split('\n').map(line => '// '+line).join('\n')
        : disguise === 'block-comment' ? `/* ${body} */`
        : disguise === 'string' ? `let unrelated = ${JSON.stringify(body)}`
        : body.replace(`fn ${name}(`, 'fn unrelated_witness(');
      const changed = source.slice(0, start) + wrong + (end < 0 ? '' : source.slice(end)) + '\n' + retained;
      assert.throws(() => checkBindings(root, bindings(), {
        read: p => p === path ? changed : readFileSync(root + p, 'utf8'),
      }), /input cursor route/);
    });
}

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


function retirementEvidence(target = 'js') {
  const e = evidence(target);
  e.nodes = graph([...bindings(), ...retirementBindings()], target);
  e.report.runs['retirement-lean'] = {command: [...retirementModelExecution.command],
    target: 'model', count: retirementModelExecution.count, passed: true, exit: 0, sourceDigest: e.current.digest};
  e.report.runs[`retirement-connection-${target}`] = {...clone(e.report.runs[`connection-${target}`]),
    command: ['moon', 'test', retirementFixture, '--target', target, '--deny-warn'], count: 8,
    coverage: executedRetirementCoverage()};
  return e;
}
test('existing lifetime scope composes the additional model without widening prompt or stop claims', () => {
  checkBindings(root, [...bindings(), ...retirementBindings()]);
  for (const target of ['js', 'wasm', 'native']) {
    const e = retirementEvidence(target);
    assert.equal(validate(e.nodes, e.report, e.current, target).length, 4);
    assert.deepEqual(e.nodes.at(-1).dependencies,
      ['session', 'retirement-model', 'builtin-chain/early-retirement:connection']);
  }
});
for (const [label, change] of [
  ['original model substituted', e => { e.report.runs['retirement-lean'] = clone(e.report.runs.lean); }],
  ['missing additional model', e => { delete e.report.runs['retirement-lean']; }],
  ['required case absent', e => { e.report.runs['retirement-connection-js'].count = 7; }],
  ['string count', e => { e.report.runs['retirement-connection-js'].count = '8'; }],
  ['ordinary fixture substituted', e => { e.report.runs['retirement-connection-js'].command[2] = fixture; }],
  ['missing execution coverage', e => { delete e.report.runs['retirement-connection-js'].coverage; }],
  ['missing cleanup premise', e => { e.nodes.at(-1).premises.splice(1, 1); }],
  ['missing capacity residual', e => { e.nodes.at(-1).residual.splice(1, 1); }],
  ['physical memory claim added', e => { e.nodes.at(-1).guarantees.push('peak physical memory bounded by maximum child'); }],
  ['missing model dependency', e => { e.nodes.at(-1).dependencies.splice(1, 1); }],
  ['scope widened on both sides', e => {
    e.nodes.at(-1).scope.profile = '*';
    e.report.runs['retirement-connection-js'].coverage.scopes[0].profile = '*';
  }],
]) test(`controlled retirement admission rejects ${label}`, () => {
  const e = retirementEvidence(); change(e);
  assert.throws(() => validate(e.nodes, e.report, e.current, 'js'));
});
for (const [label, from, to] of [
  ['physical stop guard omitted', 'state.current is Some(active) && managed_provider_stopped(active)', 'state.current is Some(active)'],
  ['execution retained after successful cleanup', 'state.children = []\n      state.reclaiming = false', 'state.reclaiming = false'],
  ['parent cleanup pending custody lost', 'Ok(false) => return Ok(false)', 'Ok(false) => ()'],
  ['prefix replaced by unconditional full eligibility', 'let cleanup_index = Ref(-1)\n  let reclaimed_prefix = relation_chain_reclaimed_prefix(sequence)', 'let cleanup_index = Ref(-1)\n  let reclaimed_prefix = count'],
  ['last eligible intermediate child excluded', 'let reclaims_scratch = state.position <= reclaimed_prefix', 'let reclaims_scratch = state.position < reclaimed_prefix'],
  ['family suffix admitted to retirement', 'let reclaims_scratch = state.position <= reclaimed_prefix', 'let reclaims_scratch = true'],
  ['accepted output saved at the next position', 'state.completed[state.position] = Some(output)\n            state.position += 1', 'state.position += 1\n            state.completed[state.position] = Some(output)'],
  ['completed child not marked pending', 'state.pending = true\n            let reclaims_scratch', 'state.pending = false\n            let reclaims_scratch'],
  ['cleanup false permits successor admission', 'Ok(false) => return Ok(managed_provider_waiting(0L, 0L))', 'Ok(false) => ()'],
  ['cleanup error permits successor admission', 'Err(issue) => {\n              terminal.val = true\n              return Ok(managed_provider_failed(issue, 0L, 0L))\n            }\n          }\n          if used.val', 'Err(_) => ()\n          }\n          if used.val'],
  ['unconfirmed cleanup reports a successful ACK', 'result => result\n  }', 'result => Ok(true)\n  }'],
  ['family suffix discards retained child executions', '} else {\n              state.current = None\n            }\n            if work >', '} else {\n              state.current = None\n              state.children = []\n            }\n            if work >'],
  ['successor is not retained for parent cleanup', 'state.children.push(next)\n    state.current = Some(next)', 'state.current = Some(next)'],
]) test(`reviewed retirement source rejects ${label}`, () => {
  const requested = retirementBindings(), path = requested[0].provider;
  const source = readFileSync(root + path, 'utf8');
  assert.equal(source.split(from).length, 2, 'Missing uniquely reviewed route');
  assert.throws(() => checkBindings(root, requested, {
    read: p => p === path ? source.replace(from, to) : readFileSync(root + p, 'utf8'),
  }), /guard|retirement|custody/);
});

for (const [label, from, to] of [
  ['mixed chain relabeled as all eligible', 'assert_false(relation_chain_reclaims_completed_scratch(sequence))', 'assert_true(relation_chain_reclaims_completed_scratch(sequence))'],
  ['audited prefix boundary ignored', 'assert_eq(relation_chain_reclaimed_prefix(sequence), 1)', 'assert_eq(relation_chain_reclaimed_prefix(sequence), 0)'],
  ['conservative suffix execution dropped', 'assert_eq(state.children.length(), count - 1)', 'assert_eq(state.children.length(), 0)'],
  ['parent cleanup success ACK omitted', 'assert_true(cleanup_managed_provider(active).unwrap())', 'assert_false(cleanup_managed_provider(active).unwrap())'],
  ['original completed output lost after cleanup', 'assert_true(@execution.completed_output_available(source))', 'assert_false(@execution.completed_output_available(source))'],
]) test(`retirement counterexample refuses ${label}`, () => {
  const requested = retirementBindings(), path = retirementFixture;
  const source = readFileSync(root + path, 'utf8');
  const start = source.indexOf('test "audited prefix releases scratch before conservative child custody"');
  const next = source.indexOf('\ntest "', start + 1);
  const end = next < 0 ? source.length : next;
  const original = source.slice(start, end);
  assert(start >= 0 && original.split(from).length === 2, 'Missing uniquely reviewed counterexample');
  const changed = source.slice(0, start) + original.replace(from, to) + source.slice(end);
  assert.throws(() => checkBindings(root, requested, {
    read: p => p === path ? changed : readFileSync(root + p, 'utf8'),
  }), /conservative retirement scope/);
});

for (const [label, from, to] of [
  ['foreign demand owner', 'bound_producer_read_demand(cursor.owner, bound)', 'bound_producer_read_demand(other_owner, bound)'],
  ['foreign checked binding', 'bound_producer_read_demand(cursor.owner, bound)', 'bound_producer_read_demand(cursor.owner, other_bound)'],
  ['different admitted demand', 'is Some(demand)', 'is Some(other_demand)'],
  ['entries from another demand', 'producer_read_demand_entries(demand)', 'producer_read_demand_entries(other_demand)'],
  ['name bytes from another demand', 'producer_read_demand_name_bytes(demand)', 'producer_read_demand_name_bytes(other_demand)'],
  ['unrelated cursor entry ceiling', '@execution.producer_read_demand_entries(demand)', 'cursor.max_entries'],
  ['unrelated cursor value ceiling', '@execution.producer_read_demand_name_bytes(demand)', 'cursor.max_value_bytes'],
]) test(`checked producer-read demand refuses ${label}`, () => {
  const path = 'src/connectors/local/relation_chain_input_preparation.mbt';
  const source = readFileSync(root + path, 'utf8');
  const start = source.indexOf('@execution.bind_completed_operation_input(');
  const end = source.indexOf('cursor.read = Some(read)', start);
  assert(start >= 0 && end > start, 'Missing selected receiver preparation');
  const selected = source.slice(start, end);
  assert.equal(selected.split(from).length, 2, 'Missing unique selected demand witness');
  // A healthy baseline is required: an earlier route failure cannot stand in
  // for detecting this substitution. The other small-read probe stays exact.
  assert.doesNotThrow(() => checkBindings(root, bindings()));
  const changed = source.slice(0, start) + selected.replace(from, to) + source.slice(end);
  assert.throws(() => checkBindings(root, bindings(), {
    read: p => p === path ? changed : readFileSync(root + p, 'utf8'),
  }), /current checked input cursor route: advance_relation_chain_inputs admitted demand/);
});
