// Necessary capacity only, not a runtime simulator, RSS prediction or a pass.
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {retainedCase, retainedMatrix} from './fixtures.mjs';

export const baselineCapacityEvidence = Object.freeze({
  revision: 'b87584fed46217659589315c1f819994dc0cfe77',
  files: Object.freeze({
    'src/connectors/duckdb/host/native_capacity.mbt':
      '106b78fec0d377f5c1bf57276fc063b1645445f293d9590b57131b15a7a852ee',
    'src/connectors/duckdb/adapter/physical_result.mbt':
      '5b873a945cc72145f8ab329023d897445a5ab2887f479d5dd72d1a258ef16368',
  }),
});

export function verifyBaselineCapacityEvidence() {
  const snapshots = {
    'src/connectors/duckdb/host/native_capacity.mbt': 'baseline-native-capacity.mbt.txt',
    'src/connectors/duckdb/adapter/physical_result.mbt': 'baseline-physical-result.mbt.txt',
  };
  for (const [path, expected] of Object.entries(baselineCapacityEvidence.files)) {
    // Exact archived source fixtures keep shallow CI checkouts independent of
    // history availability; hashes are those of the pinned revision's blobs.
    const source = readFileSync(new URL(snapshots[path], import.meta.url));
    if (createHash('sha256').update(source).digest('hex') !== expected) {
      throw Error(`BaselineCapacityEvidenceMismatch: ${path}`);
    }
  }
  return baselineCapacityEvidence;
}

export function baselineRetentionFeasibility(workload, layout, rows, retentionBytes = 1073741824n) {
  if (typeof retentionBytes !== 'bigint' || retentionBytes < 0n) throw TypeError('InvalidRetentionCeiling');
  const fixture = retainedCase(workload, layout, rows);
  // PhysicalResult accumulates rows/cells/text across the entire validation
  // scan. NativeCapacity reserves each physical bound twice. Ignore nodes,
  // wire, metadata and output storage: omitting positive terms makes this a
  // strict lower bound, so a case below it is NOT thereby executable.
  const rowAndCellBytes = 2n * 256n * BigInt(rows) * BigInt(1 + fixture.fields.length);
  const textBytes = layout === 'text-1024' ? 2n * 8n * BigInt(rows) * 1024n : 0n;
  const lowerBound = rowAndCellBytes + textBytes;
  return Object.freeze({caseId: fixture.id, scope: 'baseline-declared-retention-lower-bound',
    status: lowerBound > retentionBytes ? 'impossible-under-declared-retention' : 'not-ruled-out',
    retentionBytes: String(retentionBytes), lowerBoundBytes: String(lowerBound),
    rowAndCellBytes: String(rowAndCellBytes), textBytes: String(textBytes),
    performanceAcceptance: false});
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const evidence = verifyBaselineCapacityEvidence();
  const cases = retainedMatrix().map(f => baselineRetentionFeasibility(f.workload, f.layout, f.rows));
  console.log(JSON.stringify({evidence, performanceAcceptance: false, cases}, null, 2));
  // This audit detects impossible comparisons; it must not turn them into a
  // successful benchmark or silently omit them from the registered matrix.
  if (cases.some(value => value.status === 'impossible-under-declared-retention')) process.exitCode = 1;
}
