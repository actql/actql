'use strict';

// The existing Node Host/Resource bridge retains original, instance-local Run
// controls. Normal platform allocation is the supplier; these counters are
// managed limits, not pre-reserved RAM, authority or a whole-runtime lease.
const runs = new WeakMap();
const freeze = Object.freeze;
const unavailable = () => {throw Object.assign(new Error('NodeManagedRunAdmissionUnavailable'),
  {code: 'NodeManagedRunAdmissionUnavailable'});};

function retainOrdinaryManagedRun(prepared, requirements, assertCurrent,
  childrenPending, purpose = 'source-compute') {
  if (prepared === null || typeof prepared !== 'object' ||
      typeof assertCurrent !== 'function' || typeof childrenPending !== 'function' ||
      !['source-compute', 'local-mock-model', 'local-content', 'local-preparation'].includes(purpose)) unavailable();
  const quotas = ['planningWork', 'attempts', 'holdings', 'transferBytes', 'retainedBytes', 'executionBytes']
    .map((name, index) => {
      const amount = requirements[name];
      if (index < 3 ? !Number.isSafeInteger(amount) || amount < 0 || amount > 2147483647 :
          typeof amount !== 'bigint' || amount < 0n || amount > 9223372036854775807n) unavailable();
      return BigInt(amount);
    });
  assertCurrent();
  const original = freeze(Object.create(null));
  // Exact identity membership is provenance, not ownership of the heavy body.
  // The active preparation/Run owns that body; this fixed Root retains only a
  // weak original receipt and cannot accept an equal-shaped replacement.
  const preparedOriginals = new WeakSet();
  preparedOriginals.add(prepared);
  runs.set(original, {preparedOriginals, quotas: freeze(quotas), assertCurrent, childrenPending, purpose,
    portsTaken: false, admitted: false, stopped: false, retiring: false, usage: undefined});
  return original;
}
function originalRun(original, prepared) {
  const state = runs.get(original);
  if (state === undefined || state.stopped || state.retiring || !state.preparedOriginals.has(prepared)) unavailable();
  try {state.assertCurrent();} catch (cause) {state.retiring = true; throw cause;}
  if (runs.get(original) !== state || state.stopped || state.retiring ||
      state.preparedOriginals === undefined || !state.preparedOriginals.has(prepared)) unavailable();
  return state;
}
function ports(original, prepared, purpose) {
  const state = runs.get(original);
  if (state === undefined || state.stopped || state.preparedOriginals === undefined ||
      !state.preparedOriginals.has(prepared) || state.purpose !== purpose || state.portsTaken) return null;
  try {originalRun(original, prepared);} catch {return null;}
  // A reentrant selection may have acquired the sole ports during current.
  if (state.portsTaken) return null;
  state.portsTaken = true;
  return retainedPorts(original, state);
}
// Keep the admitted preparation out of every retained port closure. The
// initial ports check has already established its original identity.
function retainedPorts(original, state) {
  const releasePreparation = () => {
    state.preparedOriginals = undefined;
    state.assertCurrent = undefined;
    state.childrenPending = undefined;
  };
  const current = () => {
    if (state.stopped || state.retiring) return 1;
    if (runs.get(original) !== state) return 1;
    try {
      state.assertCurrent();
      return state.stopped || state.retiring || runs.get(original) !== state ? 1 : 0;
    } catch {state.retiring = true; return 1;}
  };
  return freeze({
    cancelUnpublished() {
      if (state.unpublished) return 0;
      if (state.stopped || state.usage !== undefined || state.childrenPending()) return -42;
      state.unpublished = true; state.stopped = true;
      releasePreparation(); return 0;
    },
    status(operation) {
      if (operation === 2) {
        const usage = state.usage;
        // Preserve the original report, including charged uncertain-transfer
        // history at index zero. Only actual live resources block this stop.
        if (!state.admitted || state.stopped || usage === undefined ||
            usage.some((value, index) => index !== 0 && value !== 0n) ||
            state.childrenPending()) return -42;
        state.stopped = true; releasePreparation(); return 0;
      }
      if (operation === 1) return current();
      if (operation !== 0 || state.admitted || current() !== 0) return -42;
      state.admitted = true; return 0;
    },
    limit(ordinal) {return Number.isInteger(ordinal) && ordinal >= 0 && ordinal < 6 ? state.quotas[ordinal] : -42n;},
    report(planning, attempts, holdings, transferred, uncertain, reservedTransfer,
      heldBytes, reservedRetention, reservedExecution, peakRetention, reservedAttempts, liveReservations, liveDelegations) {
      const q = state.quotas;
      if (!state.admitted || state.stopped || ![planning, attempts, holdings, reservedAttempts, liveReservations, liveDelegations].every(value =>
        Number.isSafeInteger(value) && value >= 0 && value <= 2147483647) || BigInt(planning) > q[0] ||
          BigInt(attempts) + BigInt(reservedAttempts) > q[1] || BigInt(holdings) > q[2] ||
          ![transferred, uncertain, reservedTransfer, heldBytes, reservedRetention, reservedExecution, peakRetention]
            .every(value => typeof value === 'bigint' && value >= 0n) ||
          transferred + uncertain + reservedTransfer > q[3] || heldBytes + reservedRetention > q[4] ||
          peakRetention > q[4] || reservedExecution > q[5]) return -42;
      // Spent planning/attempt/wire history remains in Core. Only actual live
      // logical resources block this stop; it supplies no FD/native ACK.
      state.usage = freeze([uncertain, reservedTransfer, heldBytes, reservedRetention, reservedExecution, BigInt(holdings), BigInt(reservedAttempts), BigInt(liveReservations), BigInt(liveDelegations)]);
      return 0;
    },
  });
}
module.exports = {retainOrdinaryManagedRun,
  assertOrdinaryManagedRunCurrent(original, prepared) {originalRun(original, prepared);},
  ordinaryManagedRunStatus(original) {
    const state = runs.get(original);
    if (state === undefined) unavailable();
    return freeze({admitted: state.admitted, stopped: state.stopped, retiring: state.retiring});
  },
  // Distinct original purpose: its imported child is later adopted, never restarted.
  prepareOriginalLocalPreparationPorts(original, input) {return ports(original, input, 'local-preparation');},
  prepareOriginalManagedRunPorts(original, prepared) {return ports(original, prepared, 'source-compute');},
  prepareOriginalLocalMockModelRunPorts(original, prepared) {return ports(original, prepared, 'local-mock-model');},
  prepareOriginalLocalContentRunPorts(original, prepared) {return ports(original, prepared, 'local-content');},
  // Source children of the shared parent never import another Ledger. The
  // legacy Source-only entry remains unavailable on this ordinary bridge.
  prepareOriginalSourceChildPorts() {return null;},
};
freeze(module.exports);
