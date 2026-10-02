import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
const root = fileURLToPath(new URL('../../../', import.meta.url));
const path = join(root, '.artifacts/relation-pipeline/capacity/all.json');
const original = JSON.parse(readFileSync(path));
const directory = join(root, '.artifacts/relation-pipeline/capacity/target-substitution');
mkdirSync(directory, { recursive: true });
for (const slot of ['healthy', 'js', 'wasm', 'bytes', 'edge', 'history', 'compiler']) {
  const report = structuredClone(original);
  if (slot === 'bytes') report.claim.unconditionalAllocationBytes = true;
  else if (slot === 'edge') delete report.mutations.find(m => m.name === 'handoff-copy-without-accounting').anchor.receiver;
  else if (slot === 'history') report.mutations[0].history[0].accepted = -2;
  else if (slot === 'compiler') report.toolchain.version += '-unreviewed';
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
  writeFileSync(fixture, JSON.stringify(report) + '\n');
  const result = spawnSync(process.execPath, ['proofs/relation-pipeline/capacity/audit.mjs', fixture], { cwd: root, encoding: 'utf8' });
  writeFileSync(join(directory, `${slot}.log`), `${result.stdout ?? ''}${result.stderr ?? ''}`);
  assert.equal(result.status === 0, slot === 'healthy', `Actual capacity audit admitted ${slot} substitution`);
}
console.log('Actual audit accepts healthy 3-target records and refuses target/byte/edge/shrink/compiler substitutions');
