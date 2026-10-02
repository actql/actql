import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { checkCensus } from './capacity/census.mjs';
import { bound, workspaceBound, admitClaim, subject, unresolved, violation } from './capacity/model.mjs';
import { instrument, replacements, mutations } from './capacity/instrument.mjs';
test('structural quantities are derived from input dimensions independently of output duplicates', () => {
  const b = bound(6, 3);
  assert.equal(b.index, 12n); assert.equal(b.keep, 6n);
  assert.equal(b.outputCells, 18n); assert.equal(b.ownedFilledEntries, 86n);
  assert.equal(b.numericContentOctets, 144n);
  assert.equal(workspaceBound(0, 3), 15); assert.equal(workspaceBound(6, 3), 27);
  assert.throws(() => bound(-1, 3)); assert.throws(() => bound(1, 0));
  const largest = 2147483647;
  assert.equal(bound(largest, largest).outputCells, BigInt(largest) ** 2n);
});
test('the claim boundary refuses unconditional byte claims and omitted runtime premises', () => {
  const claim = { subject, kind: 'structural-model-and-finite-correspondence', units: 'filled entries and numeric content octets',
    unresolved: [...unresolved], unconditionalAllocationBytes: false };
  admitClaim(claim);
  assert.throws(() => admitClaim({ ...claim, unconditionalAllocationBytes: true }));
  assert.throws(() => admitClaim({ ...claim, unresolved: unresolved.slice(0, -1) }));
  assert.throws(() => admitClaim({ ...claim, units: 'physical heap bytes' }));
  assert.throws(() => admitClaim({ ...claim, physicalHeapGuaranteed: true }));
});
test('the source census rejects a new unreviewed holding container', () => {
  const root = fileURLToPath(new URL('../../', import.meta.url));
  checkCensus(root);
  assert.throws(() => checkCensus(root, path => {
    const source = readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
    return path.endsWith('bounded_binding_rows.mbt')
      ? source.replace('struct BoundedBindingRowsState {\n', 'struct BoundedBindingRowsState {\n  unreviewed_backing : Array[Int]\n')
      : source;
  }), /Unreviewed state\/container field/);
});
test('observation overlays bind uniquely to real production sites without storing observed objects', () => {
  for (const path of Object.keys(replacements)) {
    const original = readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
    const changed = instrument(path, original);
    assert(changed.includes('ACTQL_PIPELINE_FAULT:'));
    assert.throws(() => instrument(path, original + original));
  }
  const observer = readFileSync(new URL('./capacity/observer.mbt.txt', import.meta.url), 'utf8');
  assert(!/Ref\(|\.push\(|= state\./.test(observer.replace(/let[^\n]+/g, '')));
});
test('same resource fault requires observed reserve/release deltas, not a mutation label', () => {
  assert.equal(violation({ kind: 'capacity observation', event: 'index-admission', n: 3, delta: 6 }), null);
  assert.equal(violation({ kind: 'capacity observation', event: 'index-admission', n: 3, delta: 0 }), mutations[0].fault);
  assert.equal(violation({ kind: 'capacity observation', event: 'index-transfer', n: 3, delta: -6, length: 3 }), mutations[2].fault);
  assert.equal(violation({ kind: 'capacity observation', event: 'premature-release', keep: 0, delta: 0 }), null);
  assert.equal(violation({ kind: 'capacity observation', event: 'output-transfer', sharedOutput: false }), 'output custody lost');
});
