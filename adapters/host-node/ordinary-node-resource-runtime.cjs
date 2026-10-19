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
      !['source-compute', 'local-mock-model'].includes(purpose)) unavailable();
  const quotas = ['planningWork', 'attempts', 'holdings', 'transferBytes', 'retainedBytes', 'executionBytes']
    .map((name, index) => {
      const amount = requirements[name];
      if (index < 3 ? !Number.isSafeInteger(amount) || amount < 0 || amount > 2147483647 :
          typeof amount !== 'bigint' || amount < 0n || amount > 9223372036854775807n) unavailable();
      return BigInt(amount);
    });
  assertCurrent();
  const original = freeze(Object.create(null));
  runs.set(original, {prepared, quotas: freeze(quotas), assertCurrent, childrenPending, purpose,
    portsTaken: false, admitted: false, stopped: false, retiring: false, usage: undefined});
  return original;
}
function originalRun(original, prepared) {
  const state = runs.get(original);
  if (state === undefined || state.prepared !== prepared || state.stopped || state.retiring) unavailable();
  try {state.assertCurrent();} catch (cause) {state.retiring = true; throw cause;}
  return state;
}
function ports(original, prepared, purpose) {
  const state = runs.get(original);
  if (state === undefined || state.prepared !== prepared || state.purpose !== purpose ||
      state.portsTaken || state.stopped) return null;
  try {originalRun(original, prepared);} catch {return null;}
  state.portsTaken = true;
  const current = () => {
    if (state.stopped || state.retiring) return 1;
    try {originalRun(original, prepared); return 0;} catch {return 1;}
  };
  return freeze({
    cancelUnpublished() {
      if (state.unpublished) return 0;
      if (state.stopped || state.usage !== undefined || state.childrenPending()) return -42;
      state.unpublished = true; state.stopped = true; return 0;
    },
    status(operation) {
      if (operation === 2) {
        const usage = state.usage;
        if (!state.admitted || state.stopped || usage === undefined || usage.some(value => value !== 0n) ||
            state.childrenPending()) return -42;
        state.stopped = true; return 0;
      }
      if (operation === 1) return current();
      if (operation !== 0 || state.admitted || current() !== 0) return -42;
      state.admitted = true; return 0;
    },
    limit(ordinal) {return Number.isInteger(ordinal) && ordinal >= 0 && ordinal < 6 ? state.quotas[ordinal] : -42n;},
    report(planning, attempts, holdings, transferred, uncertain, reservedTransfer,
      heldBytes, reservedRetention, reservedExecution, peakRetention) {
      const q = state.quotas;
      if (!state.admitted || state.stopped || ![planning, attempts, holdings].every(value =>
        Number.isSafeInteger(value) && value >= 0) || BigInt(planning) > q[0] ||
          BigInt(attempts) > q[1] || BigInt(holdings) > q[2] ||
          ![transferred, uncertain, reservedTransfer, heldBytes, reservedRetention, reservedExecution, peakRetention]
            .every(value => typeof value === 'bigint' && value >= 0n) ||
          transferred + uncertain + reservedTransfer > q[3] || heldBytes + reservedRetention > q[4] ||
          peakRetention > q[4] || reservedExecution > q[5]) return -42;
      // Spent planning/attempt/wire history remains in Core. Only actual live
      // logical resources block this stop; it supplies no FD/native ACK.
      state.usage = freeze([uncertain, reservedTransfer, heldBytes, reservedRetention, reservedExecution]);
      return 0;
    },
  });
}
module.exports = freeze({retainOrdinaryManagedRun,
  assertOrdinaryManagedRunCurrent(original, prepared) {originalRun(original, prepared);},
  ordinaryManagedRunStatus(original) {
    const state = runs.get(original);
    if (state === undefined) unavailable();
    return freeze({admitted: state.admitted, stopped: state.stopped, retiring: state.retiring});
  },
  prepareOriginalManagedRunPorts(original, prepared) {return ports(original, prepared, 'source-compute');},
  prepareOriginalLocalMockModelRunPorts(original, prepared) {return ports(original, prepared, 'local-mock-model');},
  // Source children of the shared parent never import another Ledger. The
  // legacy Source-only entry remains unavailable on this ordinary bridge.
  prepareOriginalSourceChildPorts() {return null;},
});
