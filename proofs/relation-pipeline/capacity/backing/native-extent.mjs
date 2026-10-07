import assert from 'node:assert/strict';
import { nativeProfile } from './source.mjs';
// Declared-field layout for the admitted 64-bit native ABI. This is an input
// model; the compiled core reader checks static layout descriptors separately.
const align = (offset, alignment) => (offset + alignment - 1n) / alignment * alignment;
export function fieldLayout(kinds) {
  let offset = 0n;
  const offsets = kinds.map(kind => {
    assert(['ref', 'i32'].includes(kind));
    const width = kind === 'ref' ? 8n : 4n;
    offset = align(offset, width);
    const current = offset; offset += width; return Number(current);
  });
  return { offsets, payloadBytes: Number(align(offset, 8n)) };
}
export function checkDeclaredLayouts() {
  for (const [name, kinds] of Object.entries({
    map: ['ref', 'i32', 'i32', 'i32', 'i32', 'ref', 'i32'],
    entry: ['i32', 'ref', 'i32', 'i32', 'ref', 'i32'],
    array: ['ref', 'i32'],
  })) assert.deepEqual(nativeProfile.declaredFieldLayouts[name], { kinds, ...fieldLayout(kinds) });
  assert.deepEqual(nativeProfile.derived, { headerBytes: 8, pointerBytes: 8,
    mapBytes: 48, tableSlotBytes: 8, entryBytes: 48 });
}
export function mapRequestedExtent(slots, entries) {
  checkDeclaredLayouts();
  assert(Number.isSafeInteger(slots) && slots >= 0 && slots <= 2147483647);
  assert(Number.isSafeInteger(entries) && entries >= 0 && entries <= slots);
  return 48n + 8n + 8n * BigInt(slots) + 48n * BigInt(entries);
}
export function admittedMapExtent(maximumKeys) {
  assert(Number.isSafeInteger(maximumKeys) && maximumKeys >= 0 && maximumKeys <= 6);
  return mapRequestedExtent(8, maximumKeys);
}
// Three current ordinal Maps: two with at most width entries and one empty.
// The snapshot now has Array storage and is checked by the Array observer.
// Product-level backing identity and reservation custody remain prerequisites.
export function distinctMapExtent(width) {
  assert(Number.isSafeInteger(width) && width >= 1 && width <= 3);
  return 2n * admittedMapExtent(width) + admittedMapExtent(0);
}
