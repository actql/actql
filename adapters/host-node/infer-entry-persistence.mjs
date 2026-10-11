// Installation-only physical save observation. Common owns the Entry/view,
// current authority, one-shot send gate, outcome and cleanup responsibility.
// Fund this adapter's handles/closures/Promise in the installed profile before
// connecting it to a public continuation. It installs no capability itself.
export function createNodeInferEntryPersistence({moon, preparedCallSet, journal,
  ioNotification}) {
  if (typeof moon?.clientProgramCreateInferCallEntryPersistence !== 'function' ||
      typeof moon?.clientProgramAcknowledgeSavedInferCallEntry !== 'function' ||
      typeof moon?.clientProgramInferCallEntryPersistencePending !== 'function' ||
      typeof moon?.clientProgramInferCallEntryPersistenceUnknown !== 'function' ||
      typeof moon?.clientProgramInferCallEntryPersistenceSaved !== 'function' ||
      typeof journal?.readModelAttemptOriginals !== 'function' ||
      typeof journal?.enterImmediateModelCall !== 'function' ||
      typeof journal?.enterResumedCall !== 'function' ||
      typeof ioNotification?.notify !== 'function') {
    throw new TypeError('InferEntryPersistenceUnavailable');
  }
  const views = new WeakMap();
  function begin(original, reference, provenance, enter) {
    if (original?.entry === undefined || reference?.ordinal !== original.slot ||
        reference.attemptWire !== original.attemptWire ||
        reference.authorityWire !== original.authorityWire) {
      throw new TypeError('InferEntryPersistenceBindingMismatch');
    }
    const existing = views.get(original.entry);
    if (existing !== undefined) return existing;
    let observation = moon.clientProgramInferCallEntryPersistencePending();
    const view = moon.clientProgramCreateInferCallEntryPersistence(
      original.entry, preparedCallSet, () => observation);
    if (view === undefined) return undefined;
    views.set(original.entry, view);
    // Hold original bytes/owner until physical persistence settles. The
    // existing journal, not a caller's callback, owns the transaction.
    let held = {original: Object.freeze({entry: original.entry,
      attemptWire: original.attemptWire, authorityWire: original.authorityWire}),
      reference: Object.freeze({...reference}), journal, preparedCallSet};
    const unknown = () => {
      observation = moon.clientProgramInferCallEntryPersistenceUnknown();
    };
    const finish = receipt => {
      try {
        const saved = held.journal.readModelAttemptOriginals(receipt);
        if (receipt?.state !== 'EnteredUnknown' ||
            receipt.provenance !== provenance ||
            saved.attemptWire !== held.original.attemptWire ||
            saved.authorityWire !== held.original.authorityWire ||
            Object.entries(held.reference).some(([key, value]) =>
              key !== 'attemptWire' && key !== 'authorityWire' &&
              (receipt[key] !== value || saved.entry[key] !== value))) {
          unknown();
        } else {
          const ack = moon.clientProgramAcknowledgeSavedInferCallEntry(
            held.original.entry, held.preparedCallSet);
          observation = ack === undefined
            ? moon.clientProgramInferCallEntryPersistenceUnknown()
            : moon.clientProgramInferCallEntryPersistenceSaved(ack);
        }
      } catch {
        // No exception proves that the original durable write was absent.
        unknown();
      } finally {
        held = undefined;
        try { ioNotification.notify(); } catch { /* Wake is not authority. */ }
      }
    };
    let saved;
    try {
      saved = enter();
    } catch {
      // Keep the same unknown attempt; never re-enter or infer NotRecorded.
      unknown();
      held = undefined;
      try { ioNotification.notify(); } catch { /* Wake is not authority. */ }
      return view;
    }
    Promise.resolve(saved).then(finish, () => {
      unknown();
      held = undefined;
      try { ioNotification.notify(); } catch { /* Wake is not authority. */ }
    });
    return view;
  }
  // The installed journal performs the write. A caller cannot substitute a
  // saved receipt or callback and thereby authorize re-entry of an old attempt.
  return Object.freeze({
    beginImmediate(original, reference, {decision, parentResume} = {}) {
      return begin(original, reference, 'immediate', () =>
        journal.enterImmediateModelCall(reference, {decision, preparedCallSet, parentResume}));
    },
    beginResumed(original, reference, claim) {
      return begin(original, reference, 'deferred', () =>
        journal.enterResumedCall(claim, reference));
    },
  });
}
