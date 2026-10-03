import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { hash, snapshot } from '../inventory.mjs';
import { fixedCorpus } from '../corpus.mjs';
import { registry } from '../registry.mjs';
import { registrations } from '../obligations.mjs';
import { program, candidates, oracle, generate } from '../engine.mjs';
import { auditFixture, payload, inputVariable } from '../fixture.mjs';
import { compareSemantics } from '../evidence.mjs';
import { mutations, replacements, instrument, workspaceOverlay, generatedObservers } from './instrument.mjs';
import { admitClaim, inspectEvents, violation, workspaceBound, inputs } from './model.mjs';
import { checkCensus } from './census.mjs';
import { auditCoreProbe } from './backing/core-probe.mjs';
import { inspectPipelineBacking } from './backing/pipeline.mjs';
import { auditParentStartup } from './parent-control/audit.mjs';
import { rejectParentSubstitutions } from './parent-control/regression.mjs';
import { capacityObligationsByPart } from '../proof-parts.mjs';
import { resolveCapacityUnion, validateCapacityOwners } from './parts.mjs';
import { auditCustody, auditCustodyMutations } from './parent-control/custody.mjs';
export function validateCapacityPart(report, current, targets, read) {
  validateCapacityOwners(report);
  return validate(report, current, targets, read);
}
export function validate(report, current, targets, read) {
  assert(report.kind === undefined || ['capacity-part', 'capacity-union'].includes(report.kind), 'Unknown capacity report kind');
  if (report.part !== undefined) assert.equal(report.kind, 'capacity-part', 'Unbound capacity fragment scope');
  if (report.kind === 'capacity-union') resolveCapacityUnion(report, read);
  if (report.kind === 'capacity-part') {
    validateCapacityOwners(report);
    assert.deepEqual(targets, report.targets, 'Requested capacity targets differ from fragment');
  }
  const normalPart = report.part !== 'L-C1', mutationPart = report.part !== 'L-C0';
  assert.equal(report.version, 'actql-relation-pipeline-structure/0.1');
  assert.deepEqual(report.source, current, 'Stale capacity source');
  assert.deepEqual(report.toolchain, JSON.parse(read('toolchain.json')), 'Unpinned compiler declaration');
  if (normalPart) {
    assert.deepEqual(report.custody.source, current, 'Stale custody campaign');
    auditCustodyMutations(report.custody.mutations, current, read);
    assert.deepEqual(report.custody.records.map(({ target, mode }) => ({ target, mode })),
      targets.flatMap(target => ['normal', 'pending', 'success'].map(mode => ({ target, mode }))), 'Incomplete custody targets/modes');
    for (const entry of report.custody.records) {
      const bytes = read(entry.path);
      assert.equal(hash(bytes), entry.digest);
      auditCustody(JSON.parse(bytes), entry.target, entry.mode, current, read);
    }
    auditCoreProbe(report.backingCore, targets, read);
    assert.deepEqual(report.backingModel.command, ['node', 'proofs/relation-pipeline/capacity/backing/check.mjs']);
    assert.equal(report.backingModel.exit, 0); assert.equal(report.backingModel.sourceDigest, current.digest);
    assert.equal(hash(read(report.backingModel.logPath)), report.backingModel.logDigest);
    assert(read(report.backingModel.logPath).toString().includes('6 array backing model propositions checked'));
    assert(read(report.backingModel.logPath).toString().includes('4 restricted Map model propositions checked'));
    assert(read(report.backingModel.logPath).toString().includes('4 conditional native Map extent propositions checked'));
    assert(read(report.backingModel.logPath).toString().includes('3 selected native Array extent propositions checked'));
  }
  admitClaim(report.claim);
  if (normalPart && targets.includes('native')) {
    auditParentStartup(report.parentStartup, current, read);
    rejectParentSubstitutions(report.parentStartup, current, read);
  } else assert.equal(report.parentStartup, undefined, 'Native parent evidence cannot apply to a portable-only campaign');
  const corpus = fixedCorpus(registry, registrations).filter(c => c.steps.filter(s => s.op === 'distinct').length === 1);
  if (report.kind) assert.equal(corpus.length, capacityObligationsByPart['L-C0'].normal.caseCount, 'Capacity corpus differs from canonical part plan');
  assert.deepEqual(report.corpus, corpus, 'Scope must come from the reviewed corpus, not caller labels');
  assert.equal(report.seed, 148256);
  assert.deepEqual(report.search, generate(registry, 148256, 24).filter(c => c.steps.filter(s => s.op === 'distinct').length === 1));
  if (normalPart) {
    assert.deepEqual(report.model.command, ['node', 'proofs/relation-pipeline/capacity/check.mjs']);
    assert.equal(report.model.exit, 0); assert.equal(report.model.sourceDigest, current.digest);
    assert.equal(hash(read(report.model.logPath)), report.model.logDigest);
    assert(read(report.model.logPath).toString().includes('8 structural model propositions checked'));
  }
  const byObservation = new Map(), receiptPaths = new Set(), observationIds = new Set();
  function runs(label, target) {
    return report.executions.filter(e => e.receipt.target === target && e.receipt.logPath.includes(`capacity-${label}-${target}`));
  }
  if (report.kind === 'capacity-part' || report.kind === 'capacity-union') {
    const expectedExecutions = [];
    if (normalPart) for (const target of targets) for (const label of ['normal', 'boundary--1', 'boundary-0', 'boundary-1']) {
      const found = runs(label, target);
      assert.equal(found.length, 1, 'Missing or duplicate capacity normal/boundary execution');
      expectedExecutions.push(...found);
    }
    if (mutationPart) for (const mutation of report.mutations) {
      for (const [label, target] of [['search', 'js'], ...targets.flatMap(target => ['minimal', 'restored', 'post-restore'].map(label => [label, target]))]) {
        const found = runs(`${mutation.name}-${label}`, target);
        assert.equal(found.length, 1, 'Missing or duplicate capacity mutation execution');
        expectedExecutions.push(...found);
      }
      expectedExecutions.push(...runs(`${mutation.name}-shrink`, 'js'));
    }
    assert.equal(new Set(expectedExecutions.map(e => e.path)).size, report.executions.length, 'Unbound capacity execution');
  }
  const generatedHashes = Object.fromEntries(Object.entries(generatedObservers).map(([p, code]) => [p, hash(code)]));
  assert.deepEqual(report.overlays, {
    ...Object.fromEntries(Object.keys(replacements).map(p => [p, hash(instrument(p, read(p).toString()))])),
    ...generatedHashes,
  }, 'Unknown capacity observer source');
  for (const execution of report.executions) {
    assert(!receiptPaths.has(execution.path), 'Duplicate capacity receipt'); receiptPaths.add(execution.path);
    const run = execution.receipt;
    assert.deepEqual(JSON.parse(read(execution.path)), run, 'Report differs from independent receipt');
    assert.equal(execution.digest, hash(JSON.stringify(run)));
    assert.equal(run.inputVariable, inputVariable);
    assert.equal(run.inputDigest, hash(payload(run.cases, run.correspondence)));
    assert.equal(read(run.inputPath).toString(), payload(run.cases, run.correspondence));
    assert.equal(run.compiler, report.toolchain.moonc); assert.equal(run.exit, 0);
    assert.deepEqual(run.command, ['moon', 'test', 'src/query_integration/relation_pipeline_batch_wbtest.mbt', '--target', run.target, '--deny-warn']);
    assert(targets.includes(run.target));
    const source = JSON.parse(read(run.sourcePath));
    assert.equal(source.digest, run.sourceDigest); assert.equal(source.digest, hash(JSON.stringify(source.sources)));
    const postRestore = execution.receipt.logPath.includes('-post-restore-');
    const expected = postRestore ? { ...current.sources } : { ...current.sources, ...generatedHashes };
    const variant = mutations.find(m => run.logPath.includes(`capacity-${m.name}-`) && !run.logPath.includes('-restored-'));
    const boundary = [-1, 0, 1].find(n => run.logPath.includes(`capacity-boundary-${n}-`));
    if (!postRestore) for (const path of Object.keys(replacements)) {
      let original = read(path).toString();
      if (variant?.path === path) {
        assert.equal(original.split(variant.before).length, 2);
        original = original.replace(variant.before, variant.after);
      }
      if (boundary !== undefined && path.endsWith('bounded_binding_rows.mbt')) original = workspaceOverlay(original, boundary);
      expected[path] = hash(instrument(path, original));
    }
    assert.deepEqual(source.sources, expected, 'Unknown observation or mutation source');
    if (postRestore) {
      assert.equal(run.boundary.workspace, report.postRestore.owner, 'Wrong post-restore execution owner');
      assert.equal(run.sourceDigest, current.digest, 'Post-restore execution is not pristine');
    }
    const log = read(run.logPath).toString(); assert.equal(hash(log), run.logDigest);
    auditFixture(run, read(run.fixturePath), log, run.target);
    assert.equal(run.boundary.role, 'normal', 'Capacity evidence requires a same-checkout normal-role owner');
    const recorded = []; let id; let faults;
    for (const line of log.split('\n')) {
      if (line.startsWith('ACTQL_PIPELINE_CASE:')) { id = JSON.parse(line.slice(20)); faults = []; }
      if (line.startsWith('ACTQL_PIPELINE_FAULT:')) faults.push(JSON.parse(line.slice(21)));
      if (line.startsWith('ACTQL_PIPELINE:')) {
        const o = JSON.parse(line.slice(15)); assert.equal(o.id, id);
        recorded.push({ ...o, tableRows: o.rows, rows: o.wireRows.map(row => o.columns.map(f => row[f])), faults });
      }
    }
    assert.deepEqual(run.cases.map(c => c.observation), recorded, 'Execution differs from archived log');
    assert(Object.keys(run.artifacts).length > 0);
    for (const [path, digest] of Object.entries(run.artifacts)) {
      assert(path.startsWith(`_build/${run.target}/debug/test/query_integration/`));
      const archive = execution.capacityArchives[path];
      assert(archive.startsWith(`.artifacts/relation-pipeline/capacity/binaries/${run.target}/`));
      assert.equal(hash(read(archive)), digest, 'Executed capacity artifact changed');
    }
    for (const c of run.cases) {
      assert(!observationIds.has(c.id), 'Duplicate capacity observation identity'); observationIds.add(c.id);
      assert.equal(c.caseDigest, hash(JSON.stringify(c.testCase)));
      assert.deepEqual(c.program, program(c.testCase, registry));
      assert.equal(c.observation.source, c.program.source); assert.equal(c.observation.steps, c.program.steps);
      assert(c.observation.checked && c.observation.registered);
      byObservation.set(JSON.stringify(c.observation), { target: run.target, testCase: c.testCase });
    }
  }
  function observed(o, target, testCase) {
    const execution = byObservation.get(JSON.stringify(o));
    assert.deepEqual(execution, { target, testCase }, 'Requested target/case differs from independent execution');
    return execution.target;
  }
  function backing(o, target, testCase) {
    inspectPipelineBacking(testCase, o, registry, target, observed(o, target, testCase));
  }
  if (normalPart) for (const target of targets) {
    assert.equal(report.normal[target].length, corpus.length);
    report.normal[target].forEach((o, i) => {
      observed(o, target, corpus[i]); assert.equal(o.correspondence, true);
      compareSemantics(corpus[i], o, registry); inspectEvents(corpus[i], o, registry);
      backing(o, target, corpus[i]);
    });
    assert.deepEqual(report.normal[target], runs('normal', target)[0].receipt.cases.map(c => c.observation), 'Normal result differs from its execution');
    for (const offset of [-1, 0, 1]) {
      assert.equal(report.boundaries[offset][target].length, corpus.length);
      report.boundaries[offset][target].forEach((o, i) => {
        observed(o, target, corpus[i]);
        const b = inputs(corpus[i], registry)[0], start = o.faults.find(e => e.event === 'start');
        assert.equal(start.limit, workspaceBound(b.rows, b.width) + offset);
        if (offset < 0) assert.equal(o.kind, 'failed');
        else { compareSemantics(corpus[i], o, registry); inspectEvents(corpus[i], o, registry); backing(o, target, corpus[i]); }
      });
      assert.deepEqual(report.boundaries[offset][target], runs(`boundary-${offset}`, target)[0].receipt.cases.map(c => c.observation), 'Boundary result differs from its execution');
    }
  }
  if (mutationPart) {
    if (report.kind) assert.deepEqual(mutations.map(m => m.name), capacityObligationsByPart['L-C1'].mutations, 'Capacity mutations differ from canonical part plan');
    assert.deepEqual(report.mutations.map(m => m.name), mutations.map(m => m.name), 'Missing actual resource mutation');
    for (const m of report.mutations) {
      const variant = mutations.find(v => v.name === m.name);
      assert.equal(m.anchor.event, variant.event); assert.equal(m.anchor.resource, variant.resource); assert.equal(m.anchor.fault, variant.fault);
      assert.equal(Boolean(m.anchor.receiver), Boolean(variant.edge), 'Missing checked handoff edge');
      const originalStep = m.original.steps.findIndex(s => s.op === 'distinct');
      assert.equal(m.anchor.step, m.original.steps[originalStep].id);
      if (variant.edge) assert.equal(m.anchor.receiver, m.original.steps[originalStep + 1]?.id);
      const preserves = (c, o) => c.steps.some(s => s.id === m.anchor.step && s.op === 'distinct') &&
        (!m.anchor.receiver || c.steps[c.steps.findIndex(s => s.id === m.anchor.step) + 1]?.id === m.anchor.receiver) &&
        o.faults.some(e => e.event === m.anchor.event && violation(e) === m.anchor.fault &&
          (!m.anchor.receiver || e.rows > 0 && e.consumer === c.steps.findIndex(s => s.id === m.anchor.receiver)));
      assert(m.localMinimal); assert.deepEqual(m.finalCandidates, candidates(m.minimal, registry));
      assert.equal(m.finalCandidates.length, m.finalObservations.length);
      m.finalObservations.forEach((o, i) => { observed(o, 'js', m.finalCandidates[i]); assert(!preserves(m.finalCandidates[i], o)); });
      assert(report.search.some(c => JSON.stringify(c) === JSON.stringify(m.original)));
      const searches = report.executions.filter(e => e.receipt.logPath.includes(`capacity-${m.name}-search-js`));
      assert.equal(searches.length, 1);
      assert.deepEqual(searches[0].receipt.cases.map(c => c.testCase), report.search);
      assert(searches[0].receipt.cases.some(c => JSON.stringify(c.testCase) === JSON.stringify(m.original) && preserves(c.testCase, c.observation)));
      const shrinkRuns = report.executions.filter(e => e.receipt.logPath.includes(`capacity-${m.name}-shrink-js`));
      let state = m.original, cursor = 0;
      assert(m.history.length > 0);
      m.history.forEach((h, index) => {
        const reductions = candidates(state, registry);
        assert.equal(h.attempted, reductions.length);
        const entries = reductions.length ? shrinkRuns[cursor++]?.receipt.cases : [];
        assert(entries, 'Missing shrink execution receipt');
        assert.deepEqual(entries.map(c => c.testCase), reductions);
        const chosen = reductions.findIndex((c, i) => preserves(c, entries[i].observation));
        assert.equal(h.accepted, chosen, 'Shrink choice differs from real resource observations');
        if (chosen >= 0) {
          assert(index < m.history.length - 1, 'Shrink has no terminal local-minimum check');
          state = reductions[chosen];
        } else {
          assert.equal(index, m.history.length - 1);
          assert.deepEqual(entries.map(c => c.observation), m.finalObservations);
        }
      });
      assert.equal(cursor, shrinkRuns.length, 'Unbound shrink executions');
      assert.deepEqual(state, m.minimal, 'Minimum is not the recorded typed shrink result');
      for (const target of targets) {
        observed(m.replay[target], target, m.minimal); assert(preserves(m.minimal, m.replay[target]));
        observed(m.healthy[target], target, m.minimal); assert(!preserves(m.minimal, m.healthy[target]));
        assert(m.healthy[target].correspondence);
        compareSemantics(m.minimal, m.healthy[target], registry); inspectEvents(m.minimal, m.healthy[target], registry);
        backing(m.healthy[target], target, m.minimal);
        for (const [label, observation] of [['minimal', m.replay[target]], ['restored', m.healthy[target]]]) {
          const receipts = runs(`${m.name}-${label}`, target);
          assert.equal(receipts.length, 1, 'Missing independent minimum execution');
          assert.deepEqual(receipts[0].receipt.cases.map(c => c.testCase), [m.minimal]);
          assert.deepEqual(receipts[0].receipt.cases.map(c => c.observation), [observation], 'Minimum result differs from its execution');
        }
      }
    }
  }
  if (report.postRestore) {
    assert.deepEqual(report.postRestore.records.map(record => record.name), mutations.map(m => m.name), 'Missing post-restore minimum');
    for (const [index, record] of report.postRestore.records.entries()) {
      assert.deepEqual(record.minimal, report.mutations[index].minimal, 'Post-restore replay changed minimum');
      assert.deepEqual(Object.keys(record.observations), targets, 'Incomplete post-restore targets');
      for (const target of targets) {
        const observation = record.observations[target];
        observed(observation, target, record.minimal);
        assert.equal(observation.correspondence, true);
        assert.deepEqual(observation.faults, [], 'Post-restore execution remains instrumented');
        compareSemantics(record.minimal, observation, registry);
        const matching = report.executions.filter(e => e.receipt.boundary.workspace === report.postRestore.owner &&
          e.receipt.target === target && e.receipt.logPath.includes(`capacity-${record.name}-post-restore-`));
        assert.equal(matching.length, 1, 'Missing independent post-restore execution');
        assert.deepEqual(matching[0].receipt.cases.map(c => c.testCase), [record.minimal]);
        assert.deepEqual(matching[0].receipt.cases.map(c => c.observation), [observation]);
      }
    }
  }
  const distinctInputs = corpus.flatMap(c => oracle(c, registry).stages.filter(s => s.operation === 'distinct').map(s => s.input));
  assert(distinctInputs.some(rows => rows.length === 0));
  assert(distinctInputs.some(rows => rows.some(r => Object.values(r.values).includes(null))));
  assert(distinctInputs.some(rows => new Set(rows.map(r => JSON.stringify(r.values))).size < rows.length));
  assert(distinctInputs.some(rows => rows.length > 1 && new Set(rows.map(r => JSON.stringify(r.values))).size === rows.length));
  return { ...(report.kind === 'capacity-part' ? { part: report.part, scope: 'fragment', cases: normalPart ? corpus.length : 0 } : { cases: corpus.length }),
    targets, unconditionalAllocationBytes: false };
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = fileURLToPath(new URL('../../../', import.meta.url));
  checkCensus(root);
  const report = JSON.parse(readFileSync(process.argv[2] ?? join(root, '.artifacts/relation-pipeline/capacity/all.json')));
  assert.notEqual(report.kind, 'capacity-part', 'Whole capacity audit requires a complete union');
  const result = validate(report, snapshot(root), ['js', 'wasm', 'native'], path => {
    assert(!path.includes('..') && !path.startsWith('/'), 'Non-local evidence path');
    return readFileSync(join(root, path));
  });
  console.log(JSON.stringify(result));
}
