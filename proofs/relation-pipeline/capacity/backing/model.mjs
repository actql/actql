import assert from 'node:assert/strict';
export const maximum = 2147483647n;
const modulus = 4294967296n;
function dimension(value) {
  const n = BigInt(value);
  assert(n >= 0n && n <= maximum, 'Outside admitted Int32 dimension');
  return n;
}
// This describes the pinned non-JS arithmetic. It performs no allocation.
// Correspondence to the compiled core is a separate obligation.
export function growthCapacity(current, length, required) {
  const cap = dimension(current), len = dimension(length), need = dimension(required);
  assert(len <= cap && need >= len, 'Wrapped requirement or invalid array state');
  let space = cap === 0n ? 8n : cap;
  while (space < need) {
    const twice = space * 2n;
    const next = twice <= maximum ? twice : twice - modulus;
    if (next <= space) return need;
    space = next;
  }
  return space;
}
// Initial/reserved capacity must come independently from the admitted contract.
// Clearing/removing does not lower highWater or prove the backing disappeared.
export function currentSlotsCeiling(highWater, initialCapacity = 0) {
  const n = dimension(highWater), initial = dimension(initialCapacity);
  const grown = n === 0n ? 0n : (2n * n > 8n ? 2n * n : 8n);
  return initial > grown ? initial : grown;
}
export function liveSlotsCeiling(highWater, backingCount, initialCapacity = 0) {
  assert(Number.isSafeInteger(backingCount) && backingCount >= 0);
  return currentSlotsCeiling(highWater, initialCapacity) * BigInt(backingCount);
}
export function admitObservation(expectedTarget, executionTarget, contract, fact) {
  assert.equal(executionTarget, expectedTarget, 'Backing fact belongs to another execution target');
  assert(['wasm', 'native'].includes(expectedTarget), 'JS capacity() is not a backing-capacity observation');
  assert.equal(fact.unit, 'MoonBit fixed-buffer slots');
  assert.equal(fact.allocationBytes, false, 'Missing wrapper/header/representation byte evidence');
  assert.equal(fact.highWater, contract.highWater, 'Observation labels differ from independent input contract');
  assert.equal(fact.initialCapacity, contract.initialCapacity, 'Initial allocation differs from reviewed constructor contract');
  const observed = dimension(fact.capacity), highWater = dimension(fact.highWater);
  assert(observed <= currentSlotsCeiling(highWater, contract.initialCapacity), 'Observed backing exceeds input-derived ceiling');
  return { target: expectedTarget, slots: observed.toString(), allocationBytes: false };
}
