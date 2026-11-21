// Ordinary Local-only custody. Generic PreparedClientProgram and Workers APIs
// remain unchanged. Selection is supplied by the original installed compiler.
import {createLocalPreparationCustody} from './local-preparation-custody.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import type {SynchronousAction} from './installed-host-cleanup.mjs';

type Payload<Prepared> = {input?: unknown; parameters?: unknown; prepared?: Prepared};
type Submission = {kind?: string; input?: unknown; parameters?: unknown; preparedProgram?: unknown};
type Custody<Prepared> = ReturnType<typeof createLocalPreparationCustody<Payload<Prepared>>>;
type Borrow<Prepared> = ReturnType<Custody<Prepared>['borrow']>;
type CoreBorrow = object;
type BorrowField = 'coreHandler' | 'coreDispatch';
type PreparationResource<Prepared> = {
  borrow(prepared: Prepared, request: object | undefined): CoreBorrow | undefined;
  runtime: {
    clientProgramPreparationBorrowRead(original: CoreBorrow): unknown;
    clientProgramPreparationBorrowReturn(original: CoreBorrow): unknown;
    clientProgramPreparationBorrowSibling(original: CoreBorrow): unknown;
    clientProgramPreparationBorrowRetirementStarted?(original: CoreBorrow): unknown;
  };
};
type Entry<Prepared> = {
  custody: Custody<Prepared>; owner: Borrow<Prepared>; dispatch?: Borrow<Prepared>;
  ownerActive: boolean; handlerOwned: boolean; handlerFinished: boolean; selected: boolean;
  dispatched: boolean; retired: boolean; retirementStarted: boolean;
  finishRetirement?: SynchronousAction; coreHandler?: CoreBorrow; coreDispatch?: CoreBorrow;
};

const payloadFields = Object.freeze(['input', 'parameters'] as const);
export function installLocalPreparationRegistry<Prepared extends object>(
  select: (prepared: Prepared) => boolean,
  retirePrepared?: (prepared: Prepared | undefined) => SynchronousAction | void,
  resource?: PreparationResource<Prepared>,
  retireInitialAliases?: (prepared: Prepared | undefined) => ReturnType<SynchronousAction>,
) {
  if (typeof select !== 'function') throw new TypeError('InvalidLocalPreparationSelection');
  if (retirePrepared !== undefined && typeof retirePrepared !== 'function') throw new TypeError('InvalidLocalPreparationRetirement');
  if (retireInitialAliases !== undefined && typeof retireInitialAliases !== 'function') throw new TypeError('InvalidLocalPreparationRetirement');
  if (resource !== undefined && (typeof resource.borrow !== 'function' ||
      typeof resource.runtime?.clientProgramPreparationBorrowRead !== 'function' ||
      typeof resource.runtime?.clientProgramPreparationBorrowReturn !== 'function' ||
      typeof resource.runtime?.clientProgramPreparationBorrowSibling !== 'function')) {
    throw new TypeError('InvalidLocalPreparationResourceCustody');
  }
  const returnCore = (entry: Entry<Prepared>, field: BorrowField) => {
    const holder = entry[field];
    if (holder === undefined) return;
    entry[field] = undefined;
    // Original Core return consumes the token before a possible settlement
    // failure. The separate retirement receipt retains any pending debit.
    checked(resource!.runtime.clientProgramPreparationBorrowReturn(holder));
  };
  const originals = new WeakMap<object, object>(), handles = new WeakMap<object, Entry<Prepared>>(),
    submissions = new WeakMap<object, object>();
  // Installation-owned pending membership keeps an undispatched original until
  // fixed Host close, not until a possibly uncertain submission handler ends.
  const undispatched = new Set<Entry<Prepared>>();
  let closing = false;
  const requireOpen = () => { if (closing) throw new Error('LocalPreparationRegistryClosing'); };
  const create = (payload: Payload<Prepared>) => {
    const custody = createLocalPreparationCustody(payload);
    const entry: Entry<Prepared> = {custody, owner: custody.borrow(custody.handle), ownerActive: true,
      dispatch: undefined, handlerOwned: false, handlerFinished: false, selected: false, dispatched: false, retired: false,
      retirementStarted: false, finishRetirement: undefined,
      coreHandler: undefined, coreDispatch: undefined};
    handles.set(custody.handle, entry);
    return entry;
  };
  const payload = (entry: Entry<Prepared>) => entry.ownerActive ? entry.owner.prepared :
    entry.dispatch === undefined ? (() => {throw new Error('LocalPreparationRetired');})() : entry.dispatch.prepared;
  const copy = <Value extends object, Changes extends Record<string, unknown> = Record<never, never>>(
    value: Value, changes: Changes = {} as Changes,
  ) => {
    if (Object.hasOwn(changes, 'input') || Object.hasOwn(changes, 'parameters') ||
        Object.hasOwn(changes, 'preparedProgram')) {
      throw new TypeError('LocalPreparationSnapshotMutation');
    }
    const descriptors: PropertyDescriptorMap = Object.getOwnPropertyDescriptors(value);
    for (const key in descriptors) if (Object.hasOwn(descriptors, key)) {
      descriptors[key].configurable = true;
    }
    for (const key in changes) if (Object.hasOwn(changes, key)) descriptors[key] =
      {value: changes[key], enumerable: true, configurable: true, writable: true};
    const result = Object.defineProperties({}, descriptors);
    const handle = submissions.get(value);
    if (handle !== undefined) submissions.set(result, handle);
    return result as Omit<Value, keyof Changes> & Changes;
  };
  const bindPayload = <Value extends object>(value: Value, entry: Entry<Prepared>) => {
    for (const name of payloadFields) if (Object.hasOwn(value, name)) {
      Object.defineProperty(value, name, {enumerable: true, configurable: true,
        get: () => payload(entry)[name]});
    }
    submissions.set(value, entry.custody.handle);
    return value;
  };
  const adopt = (prepared: Prepared, request?: object) => {
    requireOpen();
    if (originals.has(prepared)) return originals.get(prepared)!;
    if (!select(prepared)) return prepared;
    const entry = handles.get(submissions.get(request!)!) ?? create({input: (request as Submission | undefined)?.input, parameters: (request as Submission | undefined)?.parameters});
    payload(entry).prepared = prepared;
    if (resource !== undefined) {
      try {
        entry.coreHandler = resource.borrow(prepared, request);
        if (entry.coreHandler === undefined) {
          // A custody selector is not a Request-domain witness. Unbound and
          // legacy preparations retain their original owner; no handler or
          // dispatch capability is fabricated from an absent Core borrow.
          delete payload(entry).prepared;
          return prepared;
        }
        if (resource.runtime.clientProgramPreparationBorrowRead(entry.coreHandler) !== prepared) {
          throw new Error('ForeignLocalPreparationResource');
        }
      } catch (error) {
        // A failed adoption must not install a new unselected Prepared alias.
        // The original working-phase owner still retains snapshot/error cleanup.
        delete payload(entry).prepared;
        returnCore(entry, 'coreHandler');
        throw error;
      }
    }
    entry.selected = true;
    undispatched.add(entry);
    originals.set(prepared, entry.custody.handle);
    return entry.custody.handle;
  };
  const read = <Value,>(value: Value) => handles.has(value as object) ? payload(handles.get(value as object)!).prepared : value;
  const retireUndispatched = (entry: Entry<Prepared>, retiringOriginal = false) => {
    if (entry.handlerOwned && !entry.handlerFinished) {
      throw new Error('LocalPreparationHandlerCleanupPending');
    }
    if (!entry.retirementStarted) {
      const prepared = entry.owner.prepared.prepared;
      const finish = retirePrepared?.(prepared);
      if (finish !== undefined && typeof finish !== 'function') {
        throw new TypeError('InvalidLocalPreparationRetirementContinuation');
      }
      // Only retireRetiringOriginal reaches this fixed cut after checking the
      // SAME Core handler's retirement phase. A pre-record constructor failure
      // has no managed Run or Content record to carry its early Plan alias.
      // Spend that alias before the original handler return can consume/throw.
      if (retiringOriginal) retireInitialAliases?.(prepared);
      entry.finishRetirement = finish as SynchronousAction | undefined;
      entry.retirementStarted = true;
      entry.custody.requestRetirement();
      entry.ownerActive = false;
      entry.owner.release();
      entry.custody.confirmRetired();
      // A consumed Core return can throw. The entry and light continuation
      // remain pending, but neither body nor consumed token is read again.
      returnCore(entry, 'coreHandler');
    }
    entry.finishRetirement?.();
    entry.finishRetirement = undefined;
    entry.retired = true;
    undispatched.delete(entry);
  };
  return Object.freeze({
    adopt, read, copy,
    capture<Value extends object>(value: Value) {
      requireOpen();
      if (!['aql', 'program'].includes((value as Submission).kind!) || !Object.hasOwn(value, 'input')) return value;
      const entry = create({input: (value as Submission).input, parameters: (value as Submission).parameters});
      entry.handlerOwned = true;
      return Object.freeze(bindPayload(copy(value), entry));
    },
    finishHandler(value: object) {
      const entry = handles.get(submissions.get(value)!);
      if (entry !== undefined) entry.handlerFinished = true;
      // Unselected Source/Effect/Model retain their existing ownership. This
      // Pure slice does not infer their stop from handler completion. Before
      // dispatch owns cleanup, a failed/unknown setup may still need this
      // original snapshot; preserve it until that owner provides retirement.
      if (entry === undefined || !entry.selected || !entry.ownerActive || !entry.dispatched) return;
      entry.ownerActive = false;
      entry.owner.release();
      returnCore(entry, 'coreHandler');
    },
    // The initial Core owner has already fenced this exact body. Unlike Host
    // close, this scoped cut cannot revoke another connection or preparation.
    retireRetiringOriginal(prepared: Prepared) {
      const entry = handles.get(originals.get(prepared)!);
      if (entry === undefined || entry.retired) return;
      if (entry.dispatched || (entry.handlerOwned && !entry.handlerFinished)) {
        throw new Error('LocalPreparationHandlerCleanupPending');
      }
      if (!entry.retirementStarted && (entry.coreHandler === undefined ||
          resource!.runtime.clientProgramPreparationBorrowRead(entry.coreHandler) !== prepared ||
          resource!.runtime.clientProgramPreparationBorrowRetirementStarted!(entry.coreHandler) !== true)) {
        throw new Error('LocalPreparationRetirementNotStarted');
      }
      retireUndispatched(entry, true);
    },
    // Fixed installation-close hook only: callers first stop new operations and
    // await handler/dispatch quiescence. Handler completion alone is NOT an ACK
    // that an unknown journal claim may be discarded while the Host is open.
    retireQuiescentUndispatched() {
      closing = true;
      for (const entry of undispatched) retireUndispatched(entry);
    },
    attach<Value extends object>(submission: Value, value: unknown) {
      const entry = handles.get(value as object);
      if (entry === undefined) {
        (submission as Submission).preparedProgram = value;
        return submission as Value & {preparedProgram: unknown};
      }
      if (Object.hasOwn(submission, 'preparedProgram')) throw new TypeError('DuplicateLocalPreparation');
      bindPayload(submission, entry);
      Object.defineProperty(submission, 'preparedProgram', {
        enumerable: true, configurable: false, get: () => payload(entry).prepared,
      });
      return submission as Value & {preparedProgram: unknown};
    },
    begin(submission: object) {
      requireOpen();
      const entry = handles.get(submissions.get(submission)!);
      if (entry === undefined || !entry.selected) return undefined;
      if (entry.dispatched || entry.retired) throw new Error('LocalPreparationAlreadyDispatched');
      if (entry.coreHandler !== undefined) {
        entry.coreDispatch = checked(resource!.runtime.clientProgramPreparationBorrowSibling(entry.coreHandler)) as CoreBorrow;
      }
      let borrower: Borrow<Prepared>;
      try { borrower = entry.custody.borrow(entry.custody.handle); }
      catch (error) { returnCore(entry, 'coreDispatch'); throw error; }
      entry.dispatch = borrower;
      entry.dispatched = true;
      undispatched.delete(entry);
      if (!entry.handlerOwned || entry.handlerFinished) {
        entry.ownerActive = false; entry.owner.release();
        returnCore(entry, 'coreHandler');
      }
      return Object.freeze({
        get preparedProgram() { return borrower.prepared.prepared; },
        retire() {
          if (entry.retired) return;
          if (!entry.retirementStarted) {
            // The fixed original cleanup may begin Core retirement while its
            // own handler/dispatch holders still exist. Its optional returned
            // continuation owns only the light cleanup receipt, never a new
            // preparation or permission to dispatch. Do not re-read a returned
            // borrower on retry or restart the original retirement operation.
            const finish = retirePrepared?.(borrower.prepared.prepared);
            if (finish !== undefined && typeof finish !== 'function') {
              throw new TypeError('InvalidLocalPreparationRetirementContinuation');
            }
            entry.finishRetirement = finish as SynchronousAction | undefined;
            entry.retirementStarted = true;
            entry.custody.requestRetirement();
            borrower.release();
            entry.dispatch = undefined;
            entry.custody.confirmRetired();
            returnCore(entry, 'coreDispatch');
          }
          entry.finishRetirement?.();
          entry.finishRetirement = undefined;
          entry.retired = true;
        },
      });
    },
  });
}
