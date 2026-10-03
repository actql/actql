import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { execute, executions, root, toolchain } from '../execute.mjs';
import { finishCapacityCampaign } from './finish.mjs';
import { hash, snapshot } from '../inventory.mjs';
import { generate, shrink, candidates } from '../engine.mjs';
import { fixedCorpus } from '../corpus.mjs';
import { registrations } from '../obligations.mjs';
import { registry } from '../registry.mjs';
import { compareSemantics } from '../evidence.mjs';
import { applyMutation } from '../sites.mjs';
import { replacements, instrument, mutations, workspaceOverlay, generatedObservers,
  installGeneratedObservers, restoreGeneratedObservers } from './instrument.mjs';
import { inspectEvents, violation, admitClaim, subject, unresolved, inputs, workspaceBound } from './model.mjs';
import { checkCensus } from './census.mjs';
import { runCoreProbe } from './backing/core-probe.mjs';
import { inspectPipelineBacking } from './backing/pipeline.mjs';
const targets = process.argv[2] === 'js' ? ['js'] : ['js', 'wasm', 'native'];
const directory = join(root, '.artifacts/relation-pipeline/capacity');
mkdirSync(directory, { recursive: true });
const source = snapshot(root), revision = spawnSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).stdout.trim();
checkCensus(root);
const originals = Object.fromEntries(Object.keys(replacements).map(path => [path, readFileSync(join(root, path), 'utf8')]));
const overlays = Object.fromEntries(Object.entries(originals).map(([path, code]) => [path, instrument(path, code)]));
function install(variant, boundary) {
  installGeneratedObservers(root);
  for (const [path, code] of Object.entries(originals)) {
    let changed = variant?.path === path ? applyMutation(code, variant) : code;
    if (boundary !== undefined && path.endsWith('bounded_binding_rows.mbt')) changed = workspaceOverlay(changed, boundary);
    writeFileSync(join(root, path), instrument(path, changed));
  }
}
function restore() {
  for (const [path, code] of Object.entries(originals)) writeFileSync(join(root, path), code);
  restoreGeneratedObservers(root);
  assert.equal(snapshot(root).digest, source.digest, 'Capacity observer/mutation was not restored');
}
function eligible(c) { return c.steps.filter(s => s.op === 'distinct').length === 1; }
function fault(c, o, anchor) {
  return eligible(c) && c.steps.some(s => s.id === anchor.step && s.op === 'distinct') &&
    (!anchor.receiver || c.steps[c.steps.findIndex(s => s.id === anchor.step) + 1]?.id === anchor.receiver) &&
    o.faults.some(e => e.event === anchor.event && violation(e) === anchor.fault &&
      (!anchor.receiver || e.rows > 0 && e.consumer === c.steps.findIndex(s => s.id === anchor.receiver)));
}
function probe(cases, target, label, correspondence = false) {
  const observed = execute(cases, registry, target, correspondence, `capacity-${label}`);
  const execution = executions.at(-1);
  execution.capacityArchives = {};
  for (const [path, digest] of Object.entries(execution.receipt.artifacts)) {
    const archive = `.artifacts/relation-pipeline/capacity/binaries/${target}/${digest}`;
    mkdirSync(join(root, `.artifacts/relation-pipeline/capacity/binaries/${target}`), { recursive: true });
    if (!existsSync(join(root, archive))) copyFileSync(join(root, path), join(root, archive));
    assert.equal(hash(readFileSync(join(root, archive))), digest);
    execution.capacityArchives[path] = archive;
  }
  return observed;
}
const corpus = fixedCorpus(registry, registrations).filter(eligible);
const search = generate(registry, 148256, 24).filter(eligible);
const report = { version: 'actql-relation-pipeline-structure/0.1', revision, source, toolchain,
  claim: admitClaim({ subject, kind: 'structural-model-and-finite-correspondence',
    units: 'filled entries and numeric content octets', unresolved: [...unresolved], unconditionalAllocationBytes: false }),
  overlays: Object.fromEntries(Object.entries({ ...overlays, ...generatedObservers }).map(([p, c]) => [p, hash(c)])),
  corpus, normal: {}, boundaries: {}, mutations: [], seed: 148256, search,
  shrinkMeaning: 'local minimum under existing typed reductions, same DISTINCT operation occurrence and accounting resource fault',
  mutationTimingMeaning: 'durationMs is wall span through restored completion, including intervening mutations; activeDurationMs sums this mutation\'s mutated and healthy blocks, excluding the shared restored installation; phase timers include build, execution, hashing and I/O',
  timings: { boundaries: {} } };
report.backingCore = runCoreProbe(targets);
const backingModel = spawnSync(process.execPath, ['proofs/relation-pipeline/capacity/backing/check.mjs'], { cwd: root, encoding: 'utf8' });
const backingModelLog = `${backingModel.stdout ?? ''}${backingModel.stderr ?? ''}`;
assert.equal(backingModel.status, 0, backingModelLog);
const backingModelPath = '.artifacts/relation-pipeline/capacity/backing-model.log';
writeFileSync(join(root, backingModelPath), backingModelLog);
report.backingModel = { command: ['node', 'proofs/relation-pipeline/capacity/backing/check.mjs'],
  exit: backingModel.status, sourceDigest: source.digest, logPath: backingModelPath, logDigest: hash(backingModelLog) };
function inspectBacking(c, o, target) {
  return inspectPipelineBacking(c, o, registry, target, executions.at(-1).receipt.target);
}
const model = spawnSync(process.execPath, ['proofs/relation-pipeline/capacity/check.mjs'], { cwd: root, encoding: 'utf8' });
const modelLog = `${model.stdout ?? ''}${model.stderr ?? ''}`;
assert.equal(model.status, 0, modelLog);
const modelPath = '.artifacts/relation-pipeline/capacity/model.log';
writeFileSync(join(root, modelPath), modelLog);
report.model = { command: ['node', 'proofs/relation-pipeline/capacity/check.mjs'], exit: model.status,
  sourceDigest: source.digest, logPath: modelPath, logDigest: hash(modelLog) };
try {
  install();
  for (const target of targets) {
    const began = performance.now();
    const observed = probe(corpus, target, 'normal', true);
    observed.forEach((o, i) => { compareSemantics(corpus[i], o, registry); inspectEvents(corpus[i], o, registry); inspectBacking(corpus[i], o, target); });
    report.normal[target] = observed;
    report.timings[target] = performance.now() - began;
    console.log(`${target}: ${corpus.length} real registered pipelines; independent structural bounds and semantics`);
  }
  for (const offset of [-1, 0, 1]) {
    install(undefined, offset);
    report.boundaries[offset] = {};
    report.timings.boundaries[offset] = {};
    for (const target of targets) {
      const began = performance.now();
      const observed = probe(corpus, target, `boundary-${offset}`);
      observed.forEach((o, i) => {
        const b = inputs(corpus[i], registry)[0], expected = workspaceBound(b.rows, b.width);
        const starts = o.faults.filter(e => e.event === 'start');
        assert.equal(starts.length, 1); assert.equal(starts[0].limit, expected + offset);
        if (offset < 0) assert.equal(o.kind, 'failed', 'One-short workspace was accepted');
        else { compareSemantics(corpus[i], o, registry); inspectEvents(corpus[i], o, registry); inspectBacking(corpus[i], o, target); }
      });
      report.boundaries[offset][target] = observed;
      report.timings.boundaries[offset][target] = performance.now() - began;
      console.log(`${target}: independently derived workspace bound ${offset < 0 ? 'one-short rejected' : offset === 0 ? 'exact accepted' : 'one-extra accepted'}`);
    }
  }
  const pending = [];
  if (process.argv[3] !== 'normal') for (const variant of mutations) {
    install(variant);
    const started = performance.now();
    const observations = probe(search, 'js', `${variant.name}-search`);
    const searched = performance.now();
    const index = observations.findIndex((o, i) => {
      const c = search[i], at = c.steps.findIndex(s => s.op === 'distinct');
      return eligible(c) && o.faults.some(e => e.event === variant.event && violation(e) === variant.fault &&
        (!variant.edge || c.steps[at + 1] && e.consumer === at + 1 && e.rows > 0));
    });
    assert(index >= 0, `No actual detection ${variant.name}`);
    const anchor = { step: search[index].steps.find(s => s.op === 'distinct').id,
      resource: variant.resource, event: variant.event, fault: variant.fault };
    if (variant.edge) anchor.receiver = search[index].steps[search[index].steps.findIndex(s => s.op === 'distinct') + 1].id;
    const minimum = await shrink(search[index], registry, cs => probe(cs, 'js', `${variant.name}-shrink`), (c, o) => fault(c, o, anchor));
    const shrunk = performance.now();
    assert(!minimum.finalObservations.some((o, i) => fault(minimum.finalCandidates[i], o, anchor)));
    assert.deepEqual(minimum.finalCandidates, candidates(minimum.minimal, registry));
    const replay = {}, replayMs = {};
    for (const target of targets) {
      const began = performance.now();
      replay[target] = probe([minimum.minimal], target, `${variant.name}-minimal`)[0];
      assert(fault(minimum.minimal, replay[target], anchor));
      replayMs[target] = performance.now() - began;
    }
    pending.push({ started, mutatedMs: performance.now() - started,
      result: { name: variant.name, site: variant.path, anchor, ...minimum, replay, healthy: {},
        timings: { searchMs: searched - started, shrinkMs: shrunk - searched, replayMs, restoredMs: {} } } });
  }
  // Keep the restored sources contiguous. Every minimum still gets its own
  // fresh execution/receipt on every target; only incremental builds persist.
  if (pending.length) install();
  for (const { started, mutatedMs, result } of pending) {
    const restored = performance.now();
    for (const target of targets) {
      const began = performance.now();
      result.healthy[target] = probe([result.minimal], target, `${result.name}-restored`, true)[0];
      compareSemantics(result.minimal, result.healthy[target], registry);
      inspectEvents(result.minimal, result.healthy[target], registry);
      inspectBacking(result.minimal, result.healthy[target], target);
      assert(!fault(result.minimal, result.healthy[target], result.anchor));
      result.timings.restoredMs[target] = performance.now() - began;
    }
    result.activeDurationMs = mutatedMs + performance.now() - restored;
    result.durationMs = performance.now() - started;
    report.mutations.push(result);
    console.log(`${result.name}: fresh JS detection/shrink, same-resource minimum, ${targets.length} mutated/restored targets`);
  }
} finally { restore(); }
// Persist the completed campaign before transferring the checkout's temporary
// fixture slot. Parent and child executors never share a live fixture owner.
finishCapacityCampaign(report, targets);
if (targets.includes('native')) {
  // Keep this receipt separate: the diagnostic observes native parent roots,
  // not the portable child campaign, and must not contaminate its source set.
  const parent = spawnSync(process.execPath, ['proofs/relation-pipeline/capacity/parent-control/run.mjs'],
    { cwd: root, encoding: 'utf8', maxBuffer: 1024 * 1024 });
  process.stdout.write(parent.stdout ?? ''); process.stderr.write(parent.stderr ?? '');
  assert.equal(parent.status, 0, 'Missing actual parent startup correspondence');
  report.parentStartup = JSON.parse(readFileSync(join(directory, 'parent-control-probe/all.json')));
}
report.executions = executions;
writeFileSync(join(directory, `${targets.length === 1 ? 'js' : 'all'}.json`), JSON.stringify(report, null, 2) + '\n');
console.log('Source restored byte-for-byte; structural evidence does not close the runtime/256-byte premise');
