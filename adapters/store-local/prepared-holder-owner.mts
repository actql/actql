// Content groups locate bytes; only a registered handle selects a holder.
// Selection is immutable and carries no new physical or durable authority.
type PreparedOriginal = Readonly<{cid: string; bytes: number; holder: {active: boolean}}>;

export function createPreparedHolderRegistry<Original extends PreparedOriginal>(invalid: () => never) {
  const originals = new WeakMap<object, Readonly<Original>>();
  const transfers = new Map<string, readonly Readonly<Original>[]>(),
    holderTransfers = new WeakMap<Original['holder'], Set<string>>();
  const finishTransfer = (key: string) => {
    for (const original of transfers.get(key) ?? []) holderTransfers.get(original.holder)?.delete(key);
    transfers.delete(key);
  };
  return Object.freeze({
    register(handle: object, original: Original) {
      if (originals.has(handle)) invalid();
      originals.set(handle, Object.freeze(original));
    },
    original(handle: object) { return originals.get(handle); },
    retainTransfer(key: string, selected: readonly Readonly<Original>[]) {
      const combined = Object.freeze([...new Set([...(transfers.get(key) ?? []), ...selected])]
        .filter(original => original.holder.active));
      if (combined.length === 0) return;
      transfers.set(key, combined);
      for (const original of combined) {
        let keys = holderTransfers.get(original.holder);
        if (keys === undefined) holderTransfers.set(original.holder, keys = new Set<string>());
        keys.add(key);
      }
    },
    pendingTransfer(key: string) { return transfers.get(key); },
    finishTransfer,
    forgetHolder(holder: Original['holder']) {
      for (const key of holderTransfers.get(holder) ?? []) {
        const remaining = transfers.get(key)!.filter(original => original.holder !== holder);
        if (remaining.length === 0) transfers.delete(key);
        else transfers.set(key, Object.freeze(remaining));
      }
      holderTransfers.delete(holder);
    },
    select(handles: readonly object[], allowed: ReadonlyMap<string, number>) {
      if (!Array.isArray(handles)) invalid();
      const selected: Readonly<Original>[] = [], seen = new Set<object>();
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
