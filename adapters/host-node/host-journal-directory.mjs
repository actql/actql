// Selected directory consumption only. The actual Host must capture/adopt the
// native module and its complete lifetime before creating this private view.
// Neither an operation table nor these support bounds issues resource credit.
import {Buffer} from 'node:buffer';
import {TextDecoder, types} from 'node:util';

const apply = Reflect.apply, descriptor = Object.getOwnPropertyDescriptor;
const hasOwn = Object.hasOwn, freeze = Object.freeze, integer = Number.isSafeInteger;
const isProxy = types.isProxy, isBuffer = Buffer.isBuffer;
const decode = TextDecoder.prototype.decode;
const decoder = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true});
const sort = Array.prototype.sort, push = Array.prototype.push;
const NativeSet = Set, setHas = Set.prototype.has, setAdd = Set.prototype.add;
const inspectors = new WeakMap(), weakGet = WeakMap.prototype.get, weakSet = WeakMap.prototype.set;
const fail = code => { throw Object.assign(new Error(code), {code}); };
const own = (value, key) => {
  if (value === null || typeof value !== 'object' || isProxy(value)) {
    fail('HostJournalDirectoryUnavailable');
  }
  const field = descriptor(value, key);
  if (field === undefined || !hasOwn(field, 'value')) fail('HostJournalDirectoryUnavailable');
  return field.value;
};

export function createHostJournalDirectoryInspector(native, limits, assertCurrent) {
  const open = own(native, 'open'), next = own(native, 'next');
  const current = own(native, 'current'), close = own(native, 'close');
  const maxEntries = own(limits, 'maxEntries'), maxNameBytes = own(limits, 'maxNameBytes');
  const maxWork = own(limits, 'maxWork'), maxInspections = own(limits, 'maxInspections');
  if ([open, next, current, close, assertCurrent].some(value => typeof value !== 'function') ||
      !integer(maxEntries) || maxEntries < 1 || !integer(maxNameBytes) || maxNameBytes < 1 ||
      !integer(maxWork) || maxWork < maxEntries ||
      !integer(maxInspections) || maxInspections < 1) fail('HostJournalDirectoryUnavailable');
  let active = false, pendingDuty, inspections = 0;
  const run = function inspect(directory, firstOnly) {
    if (active || pendingDuty !== undefined || typeof directory !== 'string' || directory.length === 0 ||
        directory.length > 4096 ||
        directory.includes('\0') || inspections === maxInspections) fail('HostJournalDirectoryUnavailable');
    // Charge before the first fallible current/open callback. A known refusal,
    // closed FD or collected wrapper does not replenish this original view's
    // finite native-wrapper/name-buffer construction history.
    inspections++;
    active = true;
    let original, closeAttempted = false, closeOutcome, closeFailure;
    let primary, failed = false, entries;
    const closeOriginal = () => {
      if (original === undefined || closeAttempted) return;
      // Latch BEFORE entering the same native original. A consumed descriptor
      // is never retried, including when the callback throws or reenters.
      closeAttempted = true;
      try {
        const observed = apply(close, native, [original]);
        const outcome = own(observed, 'outcome');
        if (outcome !== 'closed' && outcome !== 'unknown') {
          fail('HostJournalDirectoryCloseUnknown');
        }
        closeOutcome = observed;
        if (outcome === 'closed') original = undefined;
      } catch (cause) { closeFailure = cause; }
    };
    try {
      assertCurrent();
      original = apply(open, native, [directory, maxEntries, maxNameBytes, maxWork]);
      if (original === null || typeof original !== 'object') fail('HostJournalDirectoryUnavailable');
      // Retain the acquired original before any post-acquisition fence.
      assertCurrent();
      if (apply(current, native, [original]) !== undefined) fail('HostJournalDirectoryUnavailable');
      entries = [];
      const seen = new NativeSet();
      let work = 0;
      for (;;) {
        assertCurrent();
        const bytes = apply(next, native, [original]);
        if (bytes === null) break;
        if (!isBuffer(bytes) || bytes.length === 0 || bytes.length > maxNameBytes ||
            entries.length === maxEntries || bytes.length >= maxWork - work) {
          fail('HostJournalDirectoryUnavailable');
        }
        work += bytes.length + 1;
        // Emptiness does not require decoding or normalizing an unrelated
        // name. Keep the bounded original bytes so a marker's precedence is
        // not narrowed by a UTF8 condition belonging to the full-name scan.
        if (firstOnly) { apply(push, entries, [bytes]); break; }
        const name = apply(decode, decoder, [bytes]);
        if (name === '.' || name === '..' || name.includes('/') || name.includes('\0') ||
            apply(setHas, seen, [name])) fail('HostJournalDirectoryUnavailable');
        apply(setAdd, seen, [name]);
        apply(push, entries, [name]);
      }
      if (apply(current, native, [original]) !== undefined) fail('HostJournalDirectoryUnavailable');
      assertCurrent();
      if (!firstOnly) apply(sort, entries, []);
    } catch (cause) { failed = true; primary = cause; }
    finally { closeOriginal(); active = false; }
    if (original !== undefined) {
      const status = () => {
        void original; void native;
        return freeze({pending: true, outcome: closeOutcome,
          errors: freeze(closeFailure === undefined ? [] : [closeFailure])});
      };
      const carrier = Object.assign(new Error('HostJournalDirectoryCleanupPending', {
        cause: failed ? primary : closeFailure,
      }), {code: 'HostJournalDirectoryCleanupPending', primaryFailure: failed ? primary : closeFailure,
        cleanupPending: true, cleanupHandle: freeze({status, retry: status})});
      // Keep the actual consumed original and captured operations under this
      // unresolved duty. retry is observation only, never another close.
      pendingDuty = carrier;
      throw carrier;
    }
    if (failed) throw primary;
    return entries;
  };
  const inspect = directory => run(directory, false);
  const first = directory => {
    const entries = run(directory, true);
    return entries.length === 0 ? null : entries[0];
  };
  apply(weakSet, inspectors, [inspect, freeze({maxEntries, first, native, assertCurrent})]);
  return inspect;
}

// Membership is only this private view's provenance, not an operational
// admission. The actual Root must still supply the original native module,
// same installation/currentness and complete co-phase backing before use.
export function assertHostJournalDirectoryInspector(inspector, maxEntries) {
  if (typeof inspector !== 'function' || !integer(maxEntries) || maxEntries < 1 ||
      apply(weakGet, inspectors, [inspector])?.maxEntries !== maxEntries) fail('HostJournalDirectoryUnavailable');
}

export function inspectHostJournalDirectory(inspector, directory, maxEntries) {
  assertHostJournalDirectoryInspector(inspector, maxEntries);
  return apply(inspector, undefined, [directory]);
}

// Same native instance, captured operations, cumulative history and consumed
// close duty as the full scan. A callable/receiver copy cannot select it.
// Only a one-entry view is accepted; this operation issues no new allowance.
// Nonempty returns the original bounded byte Buffer, not a decoded name.
export function inspectHostJournalDirectoryFirstEntry(inspector, directory) {
  assertHostJournalDirectoryInspector(inspector, 1);
  const original = apply(weakGet, inspectors, [inspector]);
  return apply(original.first, undefined, [directory]);
}

// Borrow only the SAME selected native image and currentness fence already
// retained by this original inspector; never select a normal-loader substitute.
export function hostJournalDirectoryNative(inspector) {
  const original = apply(weakGet, inspectors, [inspector]);
  if (original === undefined) fail('HostJournalDirectoryUnavailable');
  original.assertCurrent();
  return Object.freeze({native: original.native, assertCurrent: original.assertCurrent});
}
