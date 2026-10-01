// Independent finite allocation oracle. IDs represent allocations; values and
// reference counts do not create or collapse identities. No production byte
// measurements are inferred from this model.
export const maximum = (1n << 63n) - 1n;
export function checkedAdd(a, b) {
  if (a < 0n || b < 0n || a > maximum || b > maximum || a > maximum - b) return null;
  return a + b;
}
export function reserve(base, children) {
  if (base.retained < 0n || base.execution < base.retained || children.length < 2) throw new Error('Invalid serial capacity domain');
  let sum = 0n;
  for (const child of children) {
    if (child.retained < 0n || child.execution < child.retained) return null;
    const pair = checkedAdd(child.retained, child.execution);
    if (pair === null || (sum = checkedAdd(sum, pair)) === null) return null;
  }
  const withHandles = checkedAdd(sum, BigInt(children.length) * 256n);
  if (withHandles === null || base.retained > maximum || base.execution > maximum) return null;
  return { retained: base.retained, execution: base.execution > withHandles ? base.execution : withHandles };
}
export function liveBytes(allocations, references) {
  const byId = new Map();
  for (const a of allocations) {
    if (byId.has(a.id) || a.bytes < 0n) throw new Error('Invalid allocation registry');
    byId.set(a.id, a.bytes);
  }
  let total = 0n;
  for (const id of new Set(references)) {
    if (!byId.has(id)) throw new Error('Uninventoried allocation');
    total += byId.get(id);
  }
  return total;
}
