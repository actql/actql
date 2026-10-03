import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { validate } from './audit.mjs';
import { snapshot } from '../inventory.mjs';
import { unionCapacityParts } from './parts.mjs';
import { prepareCapacityRegressionInputs } from './regression-inputs.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
const path = join(root, '.artifacts/relation-pipeline/capacity/all.json');
const original = JSON.parse(readFileSync(path));
const directory = join(root, '.artifacts/relation-pipeline/capacity/target-substitution');
mkdirSync(directory, { recursive: true });
// Only immutable same-source preparation is shared. The healthy CLI and every
// negative's full union/semantic validation remain independent below.
const timings = { preparation: {}, cases: [] };
let prepared;
if (original.kind === 'capacity-union') {
  let started = performance.now();
  const current = snapshot(root);
  timings.preparation.snapshotMs = performance.now() - started;
  started = performance.now();
  prepared = prepareCapacityRegressionInputs(original, current, path => readFileSync(join(root, path)));
  timings.preparation.loadPartsMs = performance.now() - started;
}
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
for (const slot of ['healthy', 'js', 'wasm', 'bytes', 'edge', 'history', 'compiler', 'core-js', 'core-wasm', 'custody-js', 'custody-wasm']) {
  const started = performance.now();
  const timing = { slot };
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
  writeFileSync(fixture, JSON.stringify(report) + '\n');
  timing.writeFixtureMs = performance.now() - phase;
  let result;
  if (original.kind === 'capacity-union' && slot !== 'healthy') {
    // Corrupt cloned producer views as well as their derived union, so these
    // controls still reach semantic audits rather than merely failing the
    // immutable-original digest check. Real producer bytes stay untouched.
    const overrides = new Map();
    phase = performance.now();
    const parts = prepared.parts().map(({ path, report: part }) => {
      for (const key of Object.keys(part)) if (Object.hasOwn(report, key) &&
        !['part', 'kind', 'executions', 'executionOwners', 'timings', 'complete', 'targets'].includes(key)) part[key] = structuredClone(report[key]);
      overrides.set(path, JSON.stringify(part, null, 2) + '\n');
      return { path, report: part };
    });
    timing.cloneAndOverridePartsMs = performance.now() - phase;
    const read = path => overrides.get(path) ?? readFileSync(join(root, path));
    try {
      phase = performance.now();
      const union = unionCapacityParts(parts, read);
      timing.unionMs = performance.now() - phase;
      phase = performance.now();
      try { validate(union, prepared.current, ['js', 'wasm', 'native'], read); }
      finally { timing.validateMs = performance.now() - phase; }
      result = { status: 0, stdout: '', stderr: '' };
    } catch (error) { result = { status: 1, stdout: '', stderr: error.stack }; }
  } else {
    phase = performance.now();
    result = spawnSync(process.execPath, ['proofs/relation-pipeline/capacity/audit.mjs', fixture],
      { cwd: root, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
    timing.cliMs = performance.now() - phase;
  }
  writeFileSync(join(directory, `${slot}.log`), `${result.stdout ?? ''}${result.stderr ?? ''}`);
  assert.ifError(result.error);
  assert(Number.isInteger(result.status), 'Audit did not finish normally');
  assert.equal(result.status === 0, slot === 'healthy', `Actual capacity audit admitted ${slot} substitution`);
  if (slot !== 'healthy') assert(result.stderr.includes(reasons[slot]), 'Substitution failed for an unrelated reason');
  timing.totalMs = performance.now() - started;
  timings.cases.push(timing);
  console.log(`Capacity regression timing: ${JSON.stringify(timing)}`);
}
writeFileSync(join(directory, 'timings.json'), JSON.stringify(timings, null, 2) + '\n');
console.log(`Capacity regression preparation: ${JSON.stringify(timings.preparation)}`);
console.log('Actual audit accepts healthy 3-target records and refuses target/byte/edge/shrink/compiler substitutions');
