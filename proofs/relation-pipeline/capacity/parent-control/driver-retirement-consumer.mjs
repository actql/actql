import assert from 'node:assert/strict';
import {snapshot, hash} from '../../inventory.mjs';
import {parseTestExecution} from '../../../../scripts/test-execution.mjs';
import {retirementOverlay,retirementExecutable} from './driver-retirement-overlay.mjs';
import {inspectDriverRetirement} from './driver-retirement-inspect.mjs';

export function acceptDriverRetirement(receipt, {root, revision, runtime, read}) {
  assert.equal(receipt.version, 'actql-native-driver-retirement/0.1');
  assert.equal(receipt.authority, 'local Native finite correspondence; no Actions identity');
  assert.equal(receipt.reuseAuthorized, false);
  assert.equal(receipt.revision, revision);
  assert.equal(receipt.target, 'native');
  assert.equal(receipt.exit, 0);
  assert.equal(receipt.restored, true);
  const source = snapshot(root);
  assert.deepEqual(receipt.source, source, 'Changed submitted/restored source');
  assert.deepEqual(receipt.runtime, runtime, 'Changed Native runtime');
  const {overlay, boundary, buildIdentity} = retirementOverlay(read, source);
  assert.deepEqual(receipt.boundary, boundary);
  assert.equal(receipt.buildIdentity, buildIdentity);
  const expectedSources = {...source.sources, ...Object.fromEntries(Object.entries(overlay).map(([p,t]) => [p,hash(t)]))};
  const ordered = Object.fromEntries(Object.entries(expectedSources).sort(([a],[b]) => a < b ? -1 : a > b ? 1 : 0));
  assert.deepEqual(receipt.executedSource.sources, ordered, 'Wrong executed overlay inputs');
  assert.equal(receipt.executedSource.digest, hash(JSON.stringify(ordered)));
  const log = read(receipt.log.path);
  assert.equal(hash(log), receipt.log.digest, 'Changed actual execution log');
  const text = log.toString();
  assert.deepEqual(text.split('\n').filter(l => l.startsWith('ACTQL_DRIVER_BUILD:')), ['ACTQL_DRIVER_BUILD:'+buildIdentity]);
  const execution = parseTestExecution('moon', text);
  assert(execution.success && execution.counts.tests === 1 && execution.counts.passed === 1 && execution.counts.failed === 0);
  assert.equal(execution.counts.skipped,null, 'Pinned Moon summary does not report skipped cases');
  const binaries = Object.entries(receipt.binaries);
  assert.equal(binaries.length, 1, 'Expected one actual Native whitebox executable');
  for (const [path, binary] of binaries) {
    assert.equal(path,retirementExecutable,'Not the selected executed Native binary');
    assert.equal(binary.path, '.artifacts/relation-pipeline/driver-retirement-native/binaries/'+binary.digest);
    const bytes = read(binary.path);
    assert.equal(hash(bytes), binary.digest, 'Changed executed binary');
    assert(bytes.includes(Buffer.from('ACTQL_DRIVER_BUILD:'+buildIdentity, 'utf16le')), 'Binary not built from this observation overlay');
  }
  return {version: 'actql-native-driver-retirement-acceptance/0.1', revision, sourceDigest: source.digest,
    receiptValueDigest: hash(JSON.stringify(receipt)), execution: execution.counts,
    observation: inspectDriverRetirement(text), reuseAuthorized: false};
}
