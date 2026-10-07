import assert from 'node:assert/strict';
import { checkDeclaredLayouts } from './native-extent.mjs';
import { nativeProfile } from './source.mjs';
// Source/ABI extent, not an observed maximum. The caller supplies the already
// checked input-derived slot bound; this module never derives one from output.
export function arrayStorageExtent(element, slots) {
  checkDeclaredLayouts();
  assert(['int', 'reference'].includes(element), 'Unreviewed native element representation');
  assert.deepEqual(nativeProfile.arrayElements, {
    int: { kind: 1, bytes: 4 }, reference: { kind: 2, bytes: 8 },
  });
  assert(Number.isSafeInteger(slots) && slots >= 0 && slots <= 2147483647);
  return 24n + 8n + BigInt(slots) * BigInt(nativeProfile.arrayElements[element].bytes);
}
// Identity is valid only within one borrowed observation. Do not union these
// tokens across polls: allocator address reuse would require generation evidence.
export function inspectNativeArrays(descriptors, capacities, ceilings) {
  assert.deepEqual(Object.keys(descriptors ?? {}).sort(), ['inputNames', 'outputNames', 'rowSources', 'snapshot', 'sortedIndices']);
  const allocations = new Map();
  let upper = 0n;
  function add(token, bytes, immortal, role, backing = null) {
    assert(typeof token === 'string' && /^[1-9][0-9]*$/.test(token));
    assert(BigInt(token) <= 18446744073709551615n);
    assert.equal(typeof immortal, 'boolean');
    const entry = { bytes, immortal, role, backing };
    if (allocations.has(token)) assert.deepEqual(allocations.get(token), entry, 'Aliased backing has inconsistent extent or ownership');
    else allocations.set(token, entry);
  }
  for (const name of ['inputNames', 'outputNames', 'rowSources', 'snapshot', 'sortedIndices']) {
    const d = descriptors[name];
    if (d === null) {
      assert.equal(name, 'sortedIndices', 'Missing required Array');
      assert.equal(capacities[name], 0, 'Absent index Array reports live slots');
      continue;
    }
    assert(d && typeof d === 'object');
    assert.deepEqual(Object.keys(d).sort(), ['owner', 'backing', 'slots', 'length', 'elementBytes',
      'ownerBytes', 'backingBytes', 'ownerStatic', 'backingStatic'].sort());
    const element = name === 'sortedIndices' ? 'int' : 'reference';
    assert.equal(d.elementBytes, nativeProfile.arrayElements[element].bytes, 'Native element representation differs from typed route');
    assert.equal(d.slots, capacities[name], 'Backing length differs from actual Array capacity');
    assert(Number.isSafeInteger(d.length) && d.length >= 0 && d.length <= d.slots);
    if (name !== 'sortedIndices') assert.equal(BigInt(d.length), ceilings[name], 'Name Array differs from input schema width');
    assert(BigInt(d.slots) <= ceilings[name], 'Native Array exceeds independent input bound');
    const extent = arrayStorageExtent(element, d.slots);
    assert.equal(d.ownerBytes, '24');
    assert.equal(d.backingBytes, (extent - 24n).toString(), 'Native backing extent differs from independent ABI');
    assert.equal(d.backingStatic, d.slots === 0, 'Empty singleton identity differs from pinned runtime');
    add(d.owner, 24n, d.ownerStatic, `${element} Array owner`, d.backing);
    add(d.backing, extent - 24n, d.backingStatic, `${element} backing`);
    upper += arrayStorageExtent(element, Number(ceilings[name]));
  }
  let storage = 0n, dynamic = 0n, staticBytes = 0n;
  for (const a of allocations.values()) {
    storage += a.bytes;
    if (a.immortal) staticBytes += a.bytes; else dynamic += a.bytes;
  }
  assert(storage <= upper, 'Unique selected Array storage exceeds input-derived bound');
  return { uniqueStorageBytes: storage.toString(), dynamicRequestedBytes: dynamic.toString(),
    staticStorageBytes: staticBytes.toString(), inputDerivedBound: upper.toString(),
    selectedAllocations: allocations.size, completeLifetimeUnion: false, unconditionalAllocationBytes: false };
}
