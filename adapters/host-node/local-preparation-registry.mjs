// Ordinary Local-only custody. Generic PreparedClientProgram and Workers APIs
// remain unchanged. Selection is supplied by the original installed compiler.
import {createLocalPreparationCustody} from './local-preparation-custody.mjs';
import {checked} from '../host-common/runtime-result.mjs';
const payloadFields = Object.freeze(['input', 'parameters']);
export function installLocalPreparationRegistry(select, retirePrepared, resource, retireInitialAliases) {
  if (typeof select !== 'function') throw new TypeError('InvalidLocalPreparationSelection');
  if (retirePrepared !== undefined && typeof retirePrepared !== 'function') throw new TypeError('InvalidLocalPreparationRetirement');
  if (retireInitialAliases !== undefined && typeof retireInitialAliases !== 'function') throw new TypeError('InvalidLocalPreparationRetirement');
  if (resource !== undefined && (typeof resource.borrow !== 'function' ||
      typeof resource.runtime?.clientProgramPreparationBorrowRead !== 'function' ||
      typeof resource.runtime?.clientProgramPreparationBorrowReturn !== 'function' ||
      typeof resource.runtime?.clientProgramPreparationBorrowSibling !== 'function')) {
    throw new TypeError('InvalidLocalPreparationResourceCustody');
  }
  const returnCore = (entry, field) => {
    const holder = entry[field];
    if (holder === undefined) return;
    entry[field] = undefined;
    // Original Core return consumes the token before a possible settlement
    // failure. The separate retirement receipt retains any pending debit.
    checked(resource.runtime.clientProgramPreparationBorrowReturn(holder));
  };
  const originals = new WeakMap(), handles = new WeakMap(), submissions = new WeakMap();
  // Installation-owned pending membership keeps an undispatched original until
  // fixed Host close, not until a possibly uncertain submission handler ends.
  const undispatched = new Set();
  let closing = false;
  const requireOpen = () => { if (closing) throw new Error('LocalPreparationRegistryClosing'); };
  const create = payload => {
    const custody = createLocalPreparationCustody(payload);
    const entry = {custody, owner: custody.borrow(custody.handle), ownerActive: true,
      dispatch: undefined, handlerOwned: false, handlerFinished: false, selected: false, dispatched: false, retired: false,
      retirementStarted: false, finishRetirement: undefined,
      coreHandler: undefined, coreDispatch: undefined};
    handles.set(custody.handle, entry);
    return entry;
  };
  const payload = entry => entry.ownerActive ? entry.owner.prepared :
    entry.dispatch === undefined ? (() => {throw new Error('LocalPreparationRetired');})() : entry.dispatch.prepared;
  const copy = (value, changes = {}) => {
    if (Object.hasOwn(changes, 'input') || Object.hasOwn(changes, 'parameters') ||
        Object.hasOwn(changes, 'preparedProgram')) {
      throw new TypeError('LocalPreparationSnapshotMutation');
    }
    const descriptors = Object.getOwnPropertyDescriptors(value);
    for (const key in descriptors) if (Object.hasOwn(descriptors, key)) {
      descriptors[key].configurable = true;
    }
    for (const key in changes) if (Object.hasOwn(changes, key)) descriptors[key] =
      {value: changes[key], enumerable: true, configurable: true, writable: true};
    const result = Object.defineProperties({}, descriptors);
    const handle = submissions.get(value);
    if (handle !== undefined) submissions.set(result, handle);
    return result;
  };
  const bindPayload = (value, entry) => {
    for (const name of payloadFields) if (Object.hasOwn(value, name)) {
      Object.defineProperty(value, name, {enumerable: true, configurable: true,
        get: () => payload(entry)[name]});
    }
    submissions.set(value, entry.custody.handle);
    return value;
  };
  const adopt = (prepared, request) => {
    requireOpen();
    if (originals.has(prepared)) return originals.get(prepared);
    if (!select(prepared)) return prepared;
    const entry = handles.get(submissions.get(request)) ?? create({input: request?.input, parameters: request?.parameters});
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
  const read = value => handles.has(value) ? payload(handles.get(value)).prepared : value;
  const retireUndispatched = (entry, retiringOriginal = false) => {
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
      entry.finishRetirement = finish;
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
    capture(value) {
      requireOpen();
      if (!['aql', 'program'].includes(value.kind) || !Object.hasOwn(value, 'input')) return value;
      const entry = create({input: value.input, parameters: value.parameters});
      entry.handlerOwned = true;
      return Object.freeze(bindPayload(copy(value), entry));
    },
    finishHandler(value) {
      const entry = handles.get(submissions.get(value));
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
    retireRetiringOriginal(prepared) {
      const entry = handles.get(originals.get(prepared));
      if (entry === undefined || entry.retired) return;
      if (entry.dispatched || (entry.handlerOwned && !entry.handlerFinished)) {
        throw new Error('LocalPreparationHandlerCleanupPending');
      }
      if (!entry.retirementStarted && (entry.coreHandler === undefined ||
          resource.runtime.clientProgramPreparationBorrowRead(entry.coreHandler) !== prepared ||
          resource.runtime.clientProgramPreparationBorrowRetirementStarted(entry.coreHandler) !== true)) {
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
    attach(submission, value) {
      const entry = handles.get(value);
      if (entry === undefined) {
        submission.preparedProgram = value;
        return submission;
      }
      if (Object.hasOwn(submission, 'preparedProgram')) throw new TypeError('DuplicateLocalPreparation');
      bindPayload(submission, entry);
      Object.defineProperty(submission, 'preparedProgram', {
        enumerable: true, configurable: false, get: () => payload(entry).prepared,
      });
      return submission;
    },
    begin(submission) {
      requireOpen();
      const entry = handles.get(submissions.get(submission));
      if (entry === undefined || !entry.selected) return undefined;
      if (entry.dispatched || entry.retired) throw new Error('LocalPreparationAlreadyDispatched');
      if (entry.coreHandler !== undefined) {
        entry.coreDispatch = checked(resource.runtime.clientProgramPreparationBorrowSibling(entry.coreHandler));
      }
      let borrower;
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
            entry.finishRetirement = finish;
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
