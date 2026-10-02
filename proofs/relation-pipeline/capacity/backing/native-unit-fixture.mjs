import { mapRequestedExtent } from './native-extent.mjs';
// Synthetic admission-test data, never implementation correspondence evidence.
export function nativeUnitFixture(bounds) {
  return Object.fromEntries(Object.keys(bounds.capacity).map((name, i) => [name, {
    owner: String(1 + 2 * i), table: String(2 + 2 * i),
    slots: bounds.capacity[name], entries: bounds.entries[name],
    requestedBytes: mapRequestedExtent(bounds.capacity[name], bounds.entries[name]).toString(),
  }]));
}
