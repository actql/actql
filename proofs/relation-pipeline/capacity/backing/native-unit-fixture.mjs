import { mapRequestedExtent } from './native-extent.mjs';
// Synthetic admission-test data, never implementation correspondence evidence.
export function nativeUnitFixture(bounds) {
  return Object.fromEntries(Object.keys(bounds.capacity).map((name, i) => [name, {
    owner: String(1 + 2 * i), table: String(2 + 2 * i),
    slots: bounds.capacity[name], entries: bounds.entries[name],
    requestedBytes: mapRequestedExtent(bounds.capacity[name], bounds.entries[name]).toString(),
  }]));
}

// Synthetic one-point Array descriptors for validator negatives, not FFI evidence.
export function nativeArrayUnitFixture(bounds) {
  return Object.fromEntries(['inputNames', 'outputNames', 'rowSources', 'snapshot', 'sortedIndices'].map((name, i) => {
    const slots = Number(bounds[name]), bytes = name === 'sortedIndices' ? 4 : 8;
    return [name, { owner: String(100 + 2 * i), backing: slots === 0 && bytes === 8 ? '999' : String(101 + 2 * i), slots,
      length: slots, elementBytes: bytes, ownerBytes: '24', backingBytes: String(8 + slots * bytes),
      ownerStatic: false, backingStatic: slots === 0 }];
  }));
}
