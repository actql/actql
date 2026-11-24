import type {openSqliteCheckpointJournal} from './sqlite-checkpoint-journal.mjs';

// Installation-only physical save observation. Common owns the Entry/view,
// current authority, one-shot send gate, outcome and cleanup responsibility.
// Fund this adapter's handles/closures/Promise in the installed profile before
// connecting it to a public continuation. It installs no capability itself.
type Provenance = 'immediate' | 'deferred';
type EntryOriginal = Readonly<{entry: object; slot: number; attemptWire: string; authorityWire: string}>;
type Journal = Pick<ReturnType<typeof openSqliteCheckpointJournal>,
  'readModelAttemptOriginals' | 'enterImmediateModelCall' | 'enterResumedCall'>;
type ImmediateReference = Parameters<Journal['enterImmediateModelCall']>[0];
type ResumedReference = Parameters<Journal['enterResumedCall']>[1];
type Reference = ImmediateReference | ResumedReference;
type JournalReceipt = ReturnType<Journal['enterImmediateModelCall']> | ReturnType<Journal['enterResumedCall']>;
type ImmediateChoice = Omit<NonNullable<Parameters<Journal['enterImmediateModelCall']>[1]>, 'preparedCallSet'>;
type Runtime<View, Observation> = Readonly<{
  clientProgramCreateInferCallEntryPersistence(entry: object, preparedCallSet: unknown,
    poll: () => Observation): View | undefined;
  clientProgramAcknowledgeSavedInferCallEntry(entry: object, preparedCallSet: unknown): unknown;
  clientProgramInferCallEntryPersistencePending(): Observation;
  clientProgramInferCallEntryPersistenceUnknown(): Observation;
  clientProgramInferCallEntryPersistenceSaved(ack: unknown): Observation;
}>;
type PersistenceOptions<View, Observation> = Readonly<{
  moon: Runtime<View, Observation>; preparedCallSet: unknown; journal: Journal;
  ioNotification: Readonly<{notify(): unknown}>;
  settled?(entry: object | undefined, receipt: JournalReceipt | undefined): void;
}>;
type HeldSave = Readonly<{
  original: Readonly<Pick<EntryOriginal, 'entry' | 'attemptWire' | 'authorityWire'>>;
  reference: Reference; journal: Journal; preparedCallSet: unknown;
}>;

export function createNodeInferEntryPersistence<View, Observation>({moon, preparedCallSet, journal,
  ioNotification, settled}: PersistenceOptions<View, Observation>) {
  if (typeof moon?.clientProgramCreateInferCallEntryPersistence !== 'function' ||
      typeof moon?.clientProgramAcknowledgeSavedInferCallEntry !== 'function' ||
      typeof moon?.clientProgramInferCallEntryPersistencePending !== 'function' ||
      typeof moon?.clientProgramInferCallEntryPersistenceUnknown !== 'function' ||
      typeof moon?.clientProgramInferCallEntryPersistenceSaved !== 'function' ||
      typeof journal?.readModelAttemptOriginals !== 'function' ||
      typeof journal?.enterImmediateModelCall !== 'function' ||
      typeof journal?.enterResumedCall !== 'function' ||
      typeof ioNotification?.notify !== 'function' ||
      settled !== undefined && typeof settled !== 'function') {
    throw new TypeError('InferEntryPersistenceUnavailable');
  }
  const views = new WeakMap<object, View>();
  function begin(original: EntryOriginal, reference: Reference, provenance: Provenance, enter: () => JournalReceipt) {
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
    let held: HeldSave | undefined = {original: Object.freeze({entry: original.entry,
      attemptWire: original.attemptWire, authorityWire: original.authorityWire}),
      reference: Object.freeze({...reference}), journal, preparedCallSet};
    const unknown = () => {
      observation = moon.clientProgramInferCallEntryPersistenceUnknown();
    };
    // The installed continuation records physical custody after the journal
    // operation, never inside its transaction. This observer cannot issue ACK
    // or grant execution; Common independently checks the retained Entry.
    const retireSave = (receipt: JournalReceipt | undefined) => {
      const original = held?.original;
      held = undefined;
      try { settled?.(original?.entry, receipt); }
      catch { /* Physical notification is not durable proof or authority. */ }
      try { ioNotification.notify(); } catch { /* Wake is not authority. */ }
    };
    const finish = (receipt: JournalReceipt) => {
      let accepted: JournalReceipt | undefined;
      try {
        const saved = held!.journal.readModelAttemptOriginals(receipt);
        if ((receipt as JournalReceipt | undefined)?.state !== 'EnteredUnknown' ||
            (receipt as JournalReceipt).provenance !== provenance ||
            saved.attemptWire !== held!.original.attemptWire ||
            saved.authorityWire !== held!.original.authorityWire ||
            Object.entries(held!.reference).some(([key, value]) =>
              key !== 'attemptWire' && key !== 'authorityWire' &&
              ((receipt as JournalReceipt & Readonly<Record<string, unknown>>)[key] !== value || (saved.entry as typeof saved.entry & Readonly<Record<string, unknown>>)[key] !== value))) {
          unknown();
        } else {
          accepted = receipt;
          const ack = moon.clientProgramAcknowledgeSavedInferCallEntry(
            held!.original.entry, held!.preparedCallSet);
          observation = ack === undefined
            ? moon.clientProgramInferCallEntryPersistenceUnknown()
            : moon.clientProgramInferCallEntryPersistenceSaved(ack);
        }
      } catch {
        // No exception proves that the original durable write was absent.
        unknown();
      } finally {
        retireSave(accepted);
      }
    };
    let saved: JournalReceipt;
    try {
      saved = enter();
    } catch {
      // Keep the same unknown attempt; never re-enter or infer NotRecorded.
      unknown();
      retireSave(undefined);
      return view;
    }
    Promise.resolve(saved).then(finish, () => {
      unknown();
      retireSave(undefined);
    });
    return view;
  }
  // The installed journal performs the write. A caller cannot substitute a
  // saved receipt or callback and thereby authorize re-entry of an old attempt.
  return Object.freeze({
    beginImmediate(original: EntryOriginal, reference: ImmediateReference, {decision, parentResume}: ImmediateChoice = {}) {
      return begin(original, reference, 'immediate', () =>
        journal.enterImmediateModelCall(reference, {decision, preparedCallSet, parentResume}));
    },
    beginResumed(original: EntryOriginal, reference: ResumedReference, claim: Parameters<Journal['enterResumedCall']>[0]) {
      return begin(original, reference, 'deferred', () =>
        journal.enterResumedCall(claim, reference));
    },
  });
}
