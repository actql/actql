// Instrument the real capacity CLI's orchestration, never the hosted product gate.
import assert from 'node:assert/strict';
import { mock } from 'node:test';
import { mkdirSync, readFileSync, writeFileSync, existsSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { mutations as actualMutations } from '../capacity/instrument.mjs';

const [root, options] = [process.argv[2], JSON.parse(process.argv[3])];
const hash = value => createHash('sha256').update(value).digest('hex');
const sourcePath = 'bounded_binding_rows.mbt';
writeFileSync(join(root, sourcePath), 'healthy');
const source = () => readFileSync(join(root, sourcePath), 'utf8');
const calls = [], executions = [], installs = [], checks = [];
let clock = 0, executorClosed = false;
const closes = [], custodyProbes = [], parentProbes = [], restoredCloses = [];
const primaryBoundary = { workspace: 'primary-owner', root, role: 'normal' };
const restoredBoundary = { workspace: 'restored-owner', root, role: 'normal' };
let freshClosed = false, activeBoundary = primaryBoundary;
const reportRelative = options.part ? `parts/${options.part}.json` : `${options.target === 'js' ? 'js' : 'all'}.json`;
const savedRelative = options.part ? `checkpoints/${options.part}.json` : reportRelative;
Object.defineProperty(globalThis, 'performance', { value: { now: () => clock } });
const mutations = actualMutations.map(m => ({ ...m, path: sourcePath }));
const cases = mutations.map((m, slot) => ({ id: `search-${slot}`, slot, rows: [{ value: slot }],
  steps: [{ id: `distinct-${slot}`, op: 'distinct' }, { id: `receiver-${slot}`, op: 'filter' }] }));
const reductions = c => c.minimized ? [{ ...c, id: `terminal-${c.slot}`, noFault: true }]
  : [{ ...c, id: `minimum-${c.slot}`, minimized: true }];
const module = (path, namedExports) => mock.module(new URL(`../${path}`, import.meta.url).href, { namedExports });
const snapshot = () => ({ sources: { [sourcePath]: hash(source()),
  ...(existsSync(join(root, 'observer.mbt')) ? { 'observer.mbt': hash(readFileSync(join(root, 'observer.mbt'))) } : {}) },
  digest: hash(source() + (existsSync(join(root, 'observer.mbt')) ? 'observer' : '')) });
module('inventory.mjs', { hash, snapshot });
module('sites.mjs', { applyMutation: (_code, variant) => variant.name });
module('corpus.mjs', { fixedCorpus: () => cases });
module('registry.mjs', { registry: [] });
module('obligations.mjs', { registrations: [] });
module('capacity/census.mjs', { checkCensus() {} });
module('capacity/audit.mjs', { validateCapacityPart() {} });
module('workspaces.mjs', { workspaceIdentity: () => restoredBoundary });
module('capacity/instrument.mjs', { mutations, replacements: { [sourcePath]: [] },
  generatedObservers: { 'observer.mbt': 'observer' },
  instrument: (_path, code) => `instrumented:${code}`,
  workspaceOverlay: (code, offset) => `${code}:boundary:${offset}`,
  installGeneratedObservers() { clock += 100; installs.push({ clock, afterCalls: calls.length }); writeFileSync(join(root, 'observer.mbt'), 'observer'); },
  restoreGeneratedObservers() { unlinkSync(join(root, 'observer.mbt')); if (options.fail === 'restore') writeFileSync(join(root, sourcePath), 'contaminated'); },
});
const check = (kind, c, o, target) => {
  checks.push({ kind, caseId: c.id, observationId: o.observationId, target });
  assert.equal(o.caseId, c.id, 'Wrong input/observation association');
  assert.equal(o[`${kind}Failure`], undefined, `${kind} failure`);
  if (target) assert.equal(o.target, target, 'Wrong backing target');
};
module('evidence.mjs', { compareSemantics: (c, o) => check('semantics', c, o) });
module('capacity/model.mjs', { inspectEvents: (c, o) => check('events', c, o),
  violation: event => event.fault, admitClaim: value => value, subject: 'fixture', unresolved: [],
  inputs: () => [{ rows: 2, width: 1 }], workspaceBound: () => 10 });
module('capacity/backing/pipeline.mjs', { inspectPipelineBacking: (c, o, _registry, target, receiptTarget) => {
  assert.equal(target, receiptTarget); check('backing', c, o, target);
} });
module('capacity/backing/core-probe.mjs', { runCoreProbe: targets => ({ targets }) });
module('engine.mjs', { generate: () => cases, candidates: reductions,
  shrink: async (original, _registry, execute, preserves) => {
    clock += 7;
    const minimal = reductions(original)[0];
    assert(preserves(minimal, execute([minimal])[0]));
    const finalCandidates = reductions(minimal), finalObservations = execute(finalCandidates);
    assert(!preserves(finalCandidates[0], finalObservations[0]));
    clock += 3;
    return { original, minimal, finalCandidates, finalObservations, localMinimal: true };
  } });
mock.module('node:child_process', { namedExports: { spawnSync: (command, args) => {
  if (command === 'git') return { status: 0, stdout: 'a'.repeat(40) };
  if (args[0].endsWith('/parent-control/custody-check.mjs')) {
    assert(executorClosed, 'Custody verification started before the campaign executor closed');
    assert.equal(source(), 'healthy');
    assert(!existsSync(join(root, 'observer.mbt')));
    const target = options.target === 'js' ? 'js' : 'all';
    assert.equal(args[1], target);
    const campaign = JSON.parse(readFileSync(join(root, `.artifacts/relation-pipeline/capacity/${savedRelative}`)));
    assert.deepEqual(campaign.executions, executions, 'Custody verification started before campaign receipts were saved');
    custodyProbes.push({ afterCalls: calls.length, afterClose: closes.length, target });
    if (options.fail === 'custody-probe') return { status: 24, stdout: '', stderr: 'Injected custody probe failure' };
    const directory = join(root, '.artifacts/relation-pipeline/capacity/custody');
    mkdirSync(directory, { recursive: true });
    writeFileSync(join(directory, `${target}.json`), JSON.stringify({
      kind: 'synthetic custody orchestration', target, separateChild: true,
    }));
    return { status: 0, stdout: 'synthetic custody transport', stderr: '' };
  }
  if (args[0].endsWith('/parent-control/run.mjs')) {
    assert(executorClosed, 'Parent probe started before the campaign executor closed');
    assert.equal(custodyProbes.length, 1, 'Parent probe started before custody verification');
    assert.equal(source(), 'healthy');
    assert(!existsSync(join(root, 'observer.mbt')));
    const campaign = JSON.parse(readFileSync(join(root, `.artifacts/relation-pipeline/capacity/${savedRelative}`)));
    assert.deepEqual(campaign.executions, executions, 'Parent probe started before campaign receipts were saved');
    parentProbes.push({ afterCalls: calls.length, afterClose: closes.length, afterCustody: custodyProbes.length });
    if (options.fail === 'parent-probe') return { status: 23, stdout: '', stderr: 'Injected parent probe failure' };
    const directory = join(root, '.artifacts/relation-pipeline/capacity/parent-control-probe');
    mkdirSync(directory, { recursive: true });
    const report = { kind: 'synthetic native parent orchestration', target: 'native', separateChild: true };
    writeFileSync(join(directory, 'all.json'), JSON.stringify(report));
    return { status: 0, stdout: 'synthetic parent transport', stderr: '' };
  }
  assert(args[0].endsWith('/check.mjs'));
  return { status: 0, stdout: 'instrumented model transport', stderr: '' };
} } });
const mockExecute = (inputs, _registry, target, correspondence, label) => {
    assert(activeBoundary === restoredBoundary ? !freshClosed : !executorClosed, 'Closed campaign executor was reused');
    const call = { inputs: structuredClone(inputs), target, correspondence, label, source: source(), started: clock };
    calls.push(call); clock += 10;
    if (options.fail === `${label}:${target}`) throw new Error('Injected compilation/execution failure');
    const active = mutations.findIndex(m => source() === `instrumented:${m.name}`);
    const boundary = /:boundary:(-?\d+)$/.exec(source());
    const observations = inputs.map((c, i) => ({ caseId: c.id, target, correspondence,
      observationId: `${calls.length}:${i}`, kind: boundary?.[1] === '-1' ? 'failed' : 'success',
      faults: boundary ? [{ event: 'start', limit: 10 + Number(boundary[1]) }]
        : active === c.slot && !c.noFault ? [{ event: mutations[active].event, fault: mutations[active].fault,
          rows: 1, consumer: 1 }] : [],
    }));
    if (label.endsWith('-restored') && target === 'wasm') {
      if (options.fail === 'input-association') observations[0].caseId = 'another-input';
      if (['semantics', 'events', 'backing'].includes(options.fail)) observations[0][`${options.fail}Failure`] = true;
      if (options.fail === 'restored-fault') observations[0].faults = [{ ...mutations[inputs[0].slot], rows: 1, consumer: 1 }];
    }
    const binary = `_build/${target}/capacity.bin`;
    mkdirSync(join(root, '_build', target), { recursive: true });
    writeFileSync(join(root, binary), `compiled:${source()}:${target}`);
    const path = `receipt-${calls.length}.json`;
    const receipt = { target, correspondence, boundary: activeBoundary, cases: inputs.map((testCase, i) => ({ testCase, observation: observations[i] })),
      artifacts: { [binary]: hash(readFileSync(join(root, binary))) } };
    writeFileSync(join(root, path), JSON.stringify(receipt));
    executions.push({ path, receipt });
    call.ended = clock; call.receipt = path;
    return observations;
  };
module('execute.mjs', { root, toolchain: {}, executions, execute: mockExecute, closeExecutor: () => {
    const path = join(root, '.artifacts/relation-pipeline/capacity', savedRelative);
    const report = JSON.parse(readFileSync(path));
    assert.deepEqual(report.executions, executions, 'Executor closed before campaign receipts were saved');
    assert.equal(source(), 'healthy');
    assert(!existsSync(join(root, 'observer.mbt')));
    closes.push({ afterCalls: calls.length, receipts: report.executions.length });
    if (options.fail === 'close') throw new Error('Injected executor close failure');
    executorClosed = true;
  },
  createExecutor: () => {
    assert(executorClosed, 'Fresh owner started before predecessor close');
    assert.equal(source(), 'healthy');
    assert(!existsSync(join(root, 'observer.mbt')));
    return { execute: (...args) => { activeBoundary = restoredBoundary; return mockExecute(...args); },
      close: () => { restoredCloses.push({ afterCalls: calls.length, receipts: executions.length });
        if (options.fail === 'post-restore-close') throw new Error('Injected post-restore close failure');
        freshClosed = true; } };
  } });
process.on('exit', () => {
  const reportPath = join(root, '.artifacts/relation-pipeline/capacity', reportRelative);
  writeFileSync(join(root, 'state.json'), JSON.stringify({ calls, installs, checks, source: source(),
    observerPresent: existsSync(join(root, 'observer.mbt')), executions, clock, closes, restoredCloses, freshClosed, custodyProbes, parentProbes, executorClosed,
    parentReportPresent: existsSync(join(root, '.artifacts/relation-pipeline/capacity/parent-control-probe/all.json')),
    checkpoint: existsSync(join(root, '.artifacts/relation-pipeline/capacity', savedRelative)) ? JSON.parse(readFileSync(join(root, '.artifacts/relation-pipeline/capacity', savedRelative))) : null,
    report: existsSync(reportPath) ? JSON.parse(readFileSync(reportPath)) : null }));
});
if (options.environmentPart) process.env.ACTQL_PIPELINE_PART = options.environmentPart;
process.argv[2] = options.target ?? 'all';
process.argv[3] = options.part ?? (options.normal ? 'normal' : undefined);
const runner = new URL('../capacity/run.mjs', import.meta.url);
if (!options.runnerFault) await import(runner.href);
else {
  let code = readFileSync(runner, 'utf8');
  const replace = (before, after) => { assert.equal(code.split(before).length, 2); code = code.replace(before, after); };
  if (options.runnerFault === 'omit-wasm') replace('const restored = performance.now();', 'const restored = performance.now(); targets.splice(targets.indexOf("wasm"), 1);');
  if (options.runnerFault === 'duplicate-input') replace('probe([result.minimal]', 'probe([pending[0].result.minimal]');
  if (options.runnerFault === 'wrong-result') replace('report.mutations.push(result)', 'report.mutations.push(pending[0].result)');
  if (options.runnerFault === 'omit-semantics') replace('compareSemantics(result.minimal, result.healthy[target], registry);', '');
  if (options.runnerFault === 'span-as-active') replace('mutatedMs + performance.now() - restored', 'performance.now() - started');
  code = code.replace(/from '(\.\.?\/[^']+)'/g, (_match, path) => `from '${new URL(path, runner).href}'`);
  await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
}

