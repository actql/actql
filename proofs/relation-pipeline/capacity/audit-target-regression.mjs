import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { basename, join } from 'node:path';
import { snapshot } from '../inventory.mjs';
import { prepareCapacityRegressionInputs } from './regression-inputs.mjs';
import { retainCapacityRegressionFixture, retainCapacityRegressionText, capacityRegressionDescriptor } from './regression-fixtures.mjs';
import { runCapacityRegressionWorkers } from './regression-workers.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
const parent = join(root, '.artifacts/relation-pipeline/capacity/target-substitution');
mkdirSync(parent, { recursive: true });
const directory = mkdtempSync(join(parent, 'run-'));
const reasons = {
  js: 'Requested target/case differs from independent execution',
  wasm: 'Requested target/case differs from independent execution',
  bytes: 'Missing runtime evidence for unconditional byte claims',
  edge: 'Missing checked handoff edge',
  history: 'Shrink choice differs from real resource observations',
  compiler: 'Unpinned compiler declaration',
  'core-js': 'Requested core probe target differs from execution',
  'core-wasm': 'Requested core probe target differs from execution',
  'custody-js': 'Requested custody target differs from execution',
  'custody-wasm': 'Requested custody target differs from execution',
};
const slots = ['healthy', 'js', 'wasm', 'bytes', 'edge', 'history', 'compiler', 'core-js', 'core-wasm', 'custody-js', 'custody-wasm'];
const timings = { preparation: {}, cases: [], census: slots.map(slot => ({ slot, state: 'unexecuted' })) };
function retainEvidence() {
  writeFileSync(join(directory, 'timings.json'), JSON.stringify(timings, null, 2) + '\n');
}
function inspectResult(slot, result) {
  writeFileSync(join(directory, `${slot}.log`), `${result.stdout ?? ''}${result.stderr ?? ''}${result.error ?? ''}`);
  assert.ifError(result.error);
  assert(Number.isInteger(result.status), 'Audit did not finish normally');
  assert.equal(result.status === 0, slot === 'healthy', `Actual capacity audit admitted ${slot} substitution`);
  if (slot !== 'healthy') assert(result.stderr.includes(reasons[slot]), 'Substitution failed for an unrelated reason');
}

// This scope owns the large original, mutable clones and serialized strings.
// It returns only compressed descriptors and the detached Source snapshot,
// before any workers are started. Do not retain fixture closures here.
async function prepare() {
  const path = join(root, '.artifacts/relation-pipeline/capacity/all.json');
  const original = JSON.parse(readFileSync(path));
  let prepared;
  if (original.kind === 'capacity-union') {
    let started = performance.now();
    const current = snapshot(root);
    timings.preparation.snapshotMs = performance.now() - started;
    started = performance.now();
    prepared = prepareCapacityRegressionInputs(original, current, path => readFileSync(join(root, path)));
    timings.preparation.loadPartsMs = performance.now() - started;
  }
  const cases = [];
  for (const slot of slots) {
    const started = performance.now();
    const timing = { slot };
    timings.cases.push(timing);
    let phase = performance.now();
    const report = structuredClone(original);
    timing.cloneReportMs = performance.now() - phase;
    if (slot === 'bytes') report.claim.unconditionalAllocationBytes = true;
    else if (slot === 'edge') delete report.mutations.find(m => m.name === 'handoff-copy-without-accounting').anchor.receiver;
    else if (slot === 'history') report.mutations[0].history[0].accepted = -2;
    else if (slot === 'compiler') report.toolchain.version += '-unreviewed';
    else if (slot.startsWith('core-')) report.backingCore.runs[slot.slice(5)] = structuredClone(report.backingCore.runs.native);
    else if (slot.startsWith('custody-')) {
      for (const entry of report.custody.records.filter(entry => entry.target === slot.slice(8))) {
        const native = report.custody.records.find(other => other.target === 'native' && other.mode === entry.mode);
        // Preserve the independently requested slot; point to the untouched,
        // internally consistent native receipt/artifact/command/log instead.
        entry.path = native.path; entry.digest = native.digest;
      }
    }
    else if (slot !== 'healthy') {
      // Keep every native receipt, source, artifact and log internally valid.
      report.normal[slot] = report.normal.native;
      for (const offset of [-1, 0, 1]) report.boundaries[offset][slot] = report.boundaries[offset].native;
      for (const mutation of report.mutations) {
        mutation.replay[slot] = mutation.replay.native;
        mutation.healthy[slot] = mutation.healthy.native;
      }
    }
    const fixture = join(directory, `${slot}.json`);
    phase = performance.now();
    const retained = await retainCapacityRegressionFixture(fixture, report);
    timing.writeFixtureMs = performance.now() - phase;
    timing.fixtureBytes = retained.bytes;
    timing.retainedFixtureBytes = retained.compressedBytes;
    timing.fixtureArchive = basename(retained.archivePath);
    timing.fixtureSha256 = retained.sha256;
    if (original.kind === 'capacity-union' && slot !== 'healthy') {
      // Corrupt cloned producer views as well as their derived union, so these
      // controls still reach semantic audits rather than a stale digest check.
      // Stage them serially, preserving each original pretty JSON wire.
      phase = performance.now();
      const parts = prepared.parts();
      for (const { report: part } of parts) {
        for (const key of Object.keys(part)) if (Object.hasOwn(report, key) &&
          !['part', 'kind', 'executions', 'executionOwners', 'timings', 'complete', 'targets'].includes(key)) part[key] = structuredClone(report[key]);
      }
      timing.cloneAndOverridePartsMs = performance.now() - phase;
      phase = performance.now();
      const archives = [];
      for (const { path, report: part } of parts) {
        const archive = await retainCapacityRegressionText(join(directory, `${slot}-${part.part}.json`),
          JSON.stringify(part, null, 2) + '\n');
        archives.push({ path, archive: capacityRegressionDescriptor(archive) });
      }
      timing.writePartsMs = performance.now() - phase;
      cases.push({ slot, parts: archives });
      timings.census[slots.indexOf(slot)].state = 'prepared';
    } else {
      phase = performance.now();
      const result = retained.withUncompressed(path => spawnSync(process.execPath,
        ['proofs/relation-pipeline/capacity/audit.mjs', path],
        { cwd: root, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 }));
      timing.cliMs = performance.now() - phase;
      const record = timings.census[slots.indexOf(slot)];
      record.state = 'closed'; record.result = { status: result.status, error: result.error?.stack };
      inspectResult(slot, result);
    }
    timing.prepareMs = performance.now() - started;
    retainEvidence();
  }
  return { cases, current: prepared?.current };
}

try {
  retainEvidence();
  const { cases, current } = await prepare();
  const records = await runCapacityRegressionWorkers(cases.map(entry => ({ ...entry, root, current })), {
    onUpdate(records) {
      for (const record of records) {
        timings.census[slots.indexOf(record.slot)] = record;
        if (record.state === 'closed') writeFileSync(join(directory, `${record.slot}.log`),
          `${record.result?.stdout ?? ''}${record.result?.stderr ?? ''}${record.error ?? ''}`);
      }
      retainEvidence();
    },
  });
  const failures = [];
  for (const record of records) {
    const timing = timings.cases.find(entry => entry.slot === record.slot);
    Object.assign(timing, record.result?.timings, { workerMs: record.workerMs });
    try { inspectResult(record.slot, { ...record.result, error: record.error }); }
    catch (error) { failures.push(error); }
  }
  assert.deepEqual(timings.census.map(({ state }) => state), slots.map(() => 'closed'),
    'Missing capacity regression execution');
  for (const timing of timings.cases) console.log(`Capacity regression timing: ${JSON.stringify(timing)}`);
  if (failures.length) throw new AggregateError(failures, 'Capacity substitutions did not produce their exact independent refusals');
  console.log(`Capacity regression preparation: ${JSON.stringify(timings.preparation)}`);
  console.log('Actual audit accepts healthy 3-target records and refuses target/byte/edge/shrink/compiler substitutions');
} catch (error) {
  timings.error = error.stack;
  throw error;
} finally { retainEvidence(); }
