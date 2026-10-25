// Content groups locate bytes; only a registered handle selects a holder.
// Selection is immutable and carries no new physical or durable authority.
export function createPreparedHolderRegistry(invalid) {
  const originals = new WeakMap();
  const transfers = new Map(), holderTransfers = new WeakMap();
  const finishTransfer = key => {
    for (const original of transfers.get(key) ?? []) holderTransfers.get(original.holder)?.delete(key);
    transfers.delete(key);
  };
  return Object.freeze({
    register(handle, original) {
      if (originals.has(handle)) invalid();
      originals.set(handle, Object.freeze(original));
    },
    original(handle) { return originals.get(handle); },
    retainTransfer(key, selected) {
      const combined = Object.freeze([...new Set([...(transfers.get(key) ?? []), ...selected])]
        .filter(original => original.holder.active));
      if (combined.length === 0) return;
      transfers.set(key, combined);
      for (const original of combined) {
        let keys = holderTransfers.get(original.holder);
        if (keys === undefined) holderTransfers.set(original.holder, keys = new Set());
        keys.add(key);
      }
    },
    pendingTransfer(key) { return transfers.get(key); },
    finishTransfer,
    forgetHolder(holder) {
      for (const key of holderTransfers.get(holder) ?? []) {
        const remaining = transfers.get(key).filter(original => original.holder !== holder);
        if (remaining.length === 0) transfers.delete(key);
        else transfers.set(key, Object.freeze(remaining));
      }
      holderTransfers.delete(holder);
    },
    select(handles, allowed) {
      if (!Array.isArray(handles)) invalid();
      const selected = [], seen = new Set();
      for (const handle of handles) {
        const original = originals.get(handle);
        if (original === undefined || allowed.get(original.cid) !== original.bytes) invalid();
        if (seen.has(handle)) continue;
        seen.add(handle); selected.push(original);
      }
      return Object.freeze(selected);
    },
  });
}
