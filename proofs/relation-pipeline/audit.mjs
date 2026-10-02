import { variants } from './mutation-registry.mjs';
import { fixedCorpus, coverage } from './corpus.mjs';
import { registrations } from './obligations.mjs';
import { checkTakeHistory, checkFoundation } from './history.mjs';
import { decision } from './exploration-impact.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { candidates, program } from './engine.mjs';
import { registry, baseRegistry } from './registry.mjs';
import { hash, snapshot, checkBaseline } from './inventory.mjs';
import { validate, compareSemantics } from './evidence.mjs';
import { body, boundFixture, payload, inputVariable } from './fixture.mjs';
import { applyMutation } from './sites.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const directory = resolve(process.argv[2] ?? join(root, '.artifacts/relation-pipeline'));
const artifact = path => {
  assert(path.startsWith('.artifacts/relation-pipeline/'));
  const relative = path.slice('.artifacts/relation-pipeline/'.length);
  assert(!relative.split('/').includes('..'));
  return join(directory, relative);
};
const read = path => JSON.parse(readFileSync(path, 'utf8'));
checkBaseline(root);
checkFoundation(root);
const current = snapshot(root);
const expectedImpact = decision(root);
const receiptPaths = new Set(), observedIds = new Set();
function auditExecution(execution, selected, expectedTarget = execution.receipt.target, workspace = null) {
  assert(!receiptPaths.has(execution.path), 'Execution receipt reused across obligations');
  receiptPaths.add(execution.path);
  const run = execution.receipt;
  assert(['js', 'wasm', 'native'].includes(expectedTarget));
  assert.equal(run.target, expectedTarget, 'Receipt target differs from requested audit target');
  assert.equal(run.exit, 0, 'Failed execution cannot be mutation evidence');
  assert.equal(hash(JSON.stringify(read(artifact(execution.path)))), execution.digest);
  assert.equal(hash(JSON.stringify(run)), execution.digest);
  const source = read(artifact(run.sourcePath));
  assert.equal(hash(JSON.stringify(source.sources)), source.digest);
  assert.equal(source.digest, run.sourceDigest);
  assert.equal(run.boundary.version, 'actql-pipeline-execution-boundary/0.1');
  assert.equal(run.boundary.sourceDigest, run.sourceDigest);
  assert.equal(run.boundary.target, expectedTarget, 'Compiled target boundary differs');
  assert.deepEqual(run.boundary.command, run.command, 'Compiled command boundary differs');
  assert.equal(run.boundary.fixtureDigest, hash(body));
  assert.equal(run.buildIdentity, hash(JSON.stringify(run.boundary)));
  assert(['normal', 'pristine', 'mutable'].includes(run.boundary.role));
  if (workspace) {
    assert.equal(run.boundary.workspace, workspace.id, 'Execution workspace identity mismatch');
    assert.equal(run.boundary.root, workspace.root, 'Execution workspace root mismatch');
  } else assert.equal(run.boundary.role, 'normal');
  run.cases.forEach(entry => {
    assert(!observedIds.has(entry.id), 'Observation identity reused across executions');
    observedIds.add(entry.id);
    assert.deepEqual(entry.program, program(entry.testCase, selected));
    assert.equal(entry.caseDigest, hash(JSON.stringify(entry.testCase)));
    assert.equal(entry.observation.id, entry.id);
    assert.equal(entry.observation.source, entry.program.source);
    assert.equal(entry.observation.steps, entry.program.steps);
    assert(entry.observation.checked && entry.observation.registered);
    assert.equal(entry.observation.correspondence, run.correspondence);
  });
  assert.equal(run.compiler, read(join(root, 'toolchain.json')).moonc);
  assert.deepEqual(run.command, ['moon', 'test', 'src/query_integration/relation_pipeline_batch_wbtest.mbt', '--target', expectedTarget, '--deny-warn']);
  assert(Object.keys(run.artifacts).length > 0);
  for (const path of Object.keys(run.artifacts)) {
    assert(path.startsWith(`_build/${expectedTarget}/debug/test/query_integration/`), 'Artifact target differs from requested audit target');
  }
  assert.equal(run.inputVariable, inputVariable);
  const inputs = payload(run.cases, run.correspondence);
  assert.equal(readFileSync(artifact(run.inputPath), 'utf8'), inputs);
  assert.equal(hash(inputs), run.inputDigest);
  const expectedFixture = boundFixture(run.boundary);
  assert.equal(readFileSync(artifact(run.fixturePath), 'utf8'), expectedFixture);
  assert.equal(hash(expectedFixture), run.fixtureDigest);
  const log = readFileSync(artifact(run.logPath), 'utf8');
  assert.equal(hash(log), run.logDigest);
  assert.deepEqual(log.split('\n').filter(line => line.startsWith('ACTQL_PIPELINE_BUILD:')),
    [`ACTQL_PIPELINE_BUILD:${run.buildIdentity}`], 'Executed binary boundary differs');
  assert.match(log, /Total tests: 1, passed: 1, failed: 0/);
  let id; let faults = []; const observations = [];
  for (const line of log.split('\n')) {
    if (line.startsWith('ACTQL_PIPELINE_CASE:')) { id = JSON.parse(line.slice(20)); faults = []; }
    if (line.startsWith('ACTQL_PIPELINE_FAULT:')) faults.push(JSON.parse(line.slice(21)));
    if (line.startsWith('ACTQL_PIPELINE:')) {
      const actual = JSON.parse(line.slice(15)); assert.equal(actual.id, id);
      observations.push({ ...actual, tableRows: actual.rows,
        rows: actual.wireRows.map(row => actual.columns.map(field => row[field])), faults });
    }
  }
  assert.deepEqual(run.cases.map(c => c.observation), observations, 'Archived execution observations differ from log');
  return source;
}
function auditModels(report) {
  for (const [id, count] of [['session', 14], ['chain', 36]]) {
    const model = report.models[id];
    const log = readFileSync(artifact(model.logPath), 'utf8');
    assert.equal(hash(log), model.logDigest);
    assert(log.includes(`Checked ${count} theorems, expected claim types and axiom dependencies`));
    assert(!log.includes('sorryAx'));
  }
}
const baseReport = read(join(directory, 'base-js.json'));
assert.equal(baseReport.target, 'js', 'Baseline report target differs from requested audit target js');
assert.equal(baseReport.revision, expectedImpact.revision);
validate(baseReport, current, baseRegistry);
assert.deepEqual(baseReport.executions.flatMap(e => e.receipt.cases.map(c => c.testCase)), fixedCorpus(baseRegistry, registrations));
baseReport.executions.forEach(e => auditExecution(e, baseRegistry, 'js'));
auditModels(baseReport);
for (const target of ['js', 'wasm', 'native']) {
  const report = read(join(directory, `${target}.json`));
  assert.equal(report.target, target, `Report target differs from requested audit target ${target}`);
  assert.equal(report.revision, expectedImpact.revision);
  validate(report, current, registry);
  assert.deepEqual(report.obligations, coverage(fixedCorpus(registry, registrations), registry, registrations));
  assert.equal(report.caseCount, fixedCorpus(registry, registrations).length);
  assert.deepEqual(report.executions.flatMap(e => e.receipt.cases.map(c => c.testCase)), fixedCorpus(registry, registrations));
  report.executions.forEach(e => auditExecution(e, registry, target));
  auditModels(report);
  for (const execution of report.executions) {
    assert.deepEqual(Object.keys(execution.receipt.archives), Object.keys(execution.receipt.artifacts));
    for (const [path, expected] of Object.entries(execution.receipt.artifacts)) {
      assert.equal(hash(readFileSync(artifact(execution.receipt.archives[path]))), expected, 'Final normal artifact changed');
    }
  }
  console.log(`${target}: exact normal corpus, source, fixtures and successful logs audited`);
}
const impact = read(join(directory, 'exploration-decision.json'));
assert.deepEqual(impact, decision(root));
for (const mode of impact.required ? ['fixed', 'explore'] : ['fixed']) {
const mutations = read(join(directory, mode === 'fixed' ? 'fixed-mutations.json' : 'mutations.json'));
assert.equal(mutations.mode, mode);
assert.deepEqual(mutations.decision, impact);
assert.equal(mutations.revision, impact.revision);
assert.deepEqual(mutations.source, current);
assert.notEqual(mutations.workspaces.pristine.id, mutations.workspaces.mutable.id);
assert.notEqual(mutations.workspaces.pristine.root, mutations.workspaces.mutable.root);
assert.equal(mutations.explorationTarget, mode === 'explore' ? 'js' : null);
assert.equal(mutations.seed, mode === 'explore' ? 105106 : null);
assert.deepEqual(mutations.results.map(r => r.name), variants.map(v => v.name));
for (const result of mutations.results) {
  const variant = variants.find(v => v.name === result.name);
  const preserves = (c, o, a) => variant.eligible(c) && variant.preserves(c, o, a, registry);
  const changed = Object.keys(current.sources).filter(path => current.sources[path] !== result.source.sources[path]);
  assert.deepEqual(changed, [result.site], 'Mutation changed unrelated source');
  assert.equal(result.originalDigest, current.sources[result.site]);
  assert.equal(result.mutatedDigest, result.source.sources[result.site]);
  const site = variant;
  assert.equal(site.path, result.site);
  assert.equal(hash(applyMutation(readFileSync(join(root, site.path), 'utf8'), site)), result.mutatedDigest);
  assert.equal(result.source.digest, hash(JSON.stringify(result.source.sources)));
  assert(result.killed);
  if (mode === 'explore') {
  assert(result.localMinimal && result.history.at(-1).accepted === -1);
  assert.deepEqual(result.finalCandidates, candidates(result.minimal, registry));
  assert.equal(result.finalCandidates.length, result.finalObservations.length);
  assert(result.finalCandidates.every((c, i) => !preserves(c, result.finalObservations[i], result.anchor)), 'False local minimality');
  assert.deepEqual(result.executions[0].receipt.cases.map(c => c.testCase), fixedCorpus(registry, registrations).filter(variant.eligible));
  const original = result.executions[0].receipt.cases.find(c => JSON.stringify(c.testCase) === JSON.stringify(result.original));
  assert(original && preserves(result.original, original.observation, result.anchor));
  let intermediate = result.original;
  let cursor = 1;
  for (const history of result.history) {
    const reductions = candidates(intermediate, registry);
    const observations = reductions.length ? result.executions[cursor++].receipt.cases.map(c => c.observation) : [];
    if (reductions.length) assert.deepEqual(result.executions[cursor - 1].receipt.cases.map(c => c.testCase), reductions);
    assert.equal(history.attempted, reductions.length);
    assert.equal(history.accepted, reductions.findIndex((c, i) => preserves(c, observations[i], result.anchor)));
    if (history.accepted >= 0) intermediate = reductions[history.accepted];
    else assert.deepEqual(observations, result.finalObservations);
  }
  assert.deepEqual(intermediate, result.minimal);
  assert.equal(result.executions.length, cursor + 3);
  } else {
    const fixed = read(join(root, 'proofs/relation-pipeline/regressions.json')).find(r => r.name === result.name);
    assert.deepEqual(result.minimal, fixed.testCase);
    assert.deepEqual(result.anchor, fixed.anchor);
    assert.equal(result.localMinimal, false);
    assert.equal(result.executions.length, 3);
  }
  const recorded = new Map();
  for (const execution of result.executions) {
    assert.equal(execution.receipt.boundary.role, 'mutable');
    assert.deepEqual(auditExecution(execution, registry, execution.receipt.target, mutations.workspaces.mutable), result.source);
    for (const entry of execution.receipt.cases) recorded.set(JSON.stringify(entry.observation), entry.testCase);
  }
  for (const [i, actual] of (result.finalObservations ?? []).entries()) {
    assert.deepEqual(recorded.get(JSON.stringify(actual)), result.finalCandidates[i]);
  }
  for (const target of ['js', 'wasm', 'native']) {
    const actual = result.replay[target];
    assert(preserves(result.minimal, actual, result.anchor));
    const execution = result.executions.find(e => e.receipt.target === target && e.receipt.cases.some(c => JSON.stringify(c.observation) === JSON.stringify(actual)));
    assert(execution); assert.deepEqual(recorded.get(JSON.stringify(actual)), result.minimal);
  }
  const healthy = new Map();
  assert.equal(result.healthyExecutions.length, 3);
  assert.deepEqual(result.healthyExecutions.map(e => e.receipt.target), ['js', 'wasm', 'native']);
  for (const execution of result.healthyExecutions) {
    assert.equal(execution.receipt.boundary.role, 'pristine');
    assert.deepEqual(auditExecution(execution, registry, execution.receipt.target, mutations.workspaces.pristine), current);
    assert(execution.receipt.correspondence);
    execution.receipt.cases.forEach(c => healthy.set(JSON.stringify(c.observation), { target: execution.receipt.target, testCase: c.testCase }));
  }
  for (const target of ['js', 'wasm', 'native']) {
    compareSemantics(result.minimal, result.healthy[target], registry);
    assert(!preserves(result.minimal, result.healthy[target], result.anchor));
    assert.deepEqual(healthy.get(JSON.stringify(result.healthy[target])), { target, testCase: result.minimal });
  }
  console.log(`${result.name}: ${mode} evidence and mutated/restored finite replay audited`);
}
}
const extension = checkTakeHistory(root);
assert.equal(extension.handwrittenCombinationAdditions, 0);
console.log('Historical take measurement preserved; current foundation changes are counted separately');
