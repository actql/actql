// Ordinary Local-only custody. Generic PreparedClientProgram and Workers APIs
// remain unchanged. Selection is supplied by the original installed compiler.
import {createLocalPreparationCustody} from './local-preparation-custody.mjs';
export function installLocalPreparationRegistry(select, retirePrepared) {
  if (typeof select !== 'function') throw new TypeError('InvalidLocalPreparationSelection');
  if (retirePrepared !== undefined && typeof retirePrepared !== 'function') throw new TypeError('InvalidLocalPreparationRetirement');
  const originals = new WeakMap(), handles = new WeakMap(), submissions = new WeakMap();
  const create = payload => {
    const custody = createLocalPreparationCustody(payload);
    const entry = {custody, owner: custody.borrow(custody.handle), ownerActive: true,
      dispatch: undefined, handlerOwned: false, selected: false, dispatched: false, retired: false};
    handles.set(custody.handle, entry);
    return entry;
  };
  const payload = entry => entry.ownerActive ? entry.owner.prepared :
    entry.dispatch === undefined ? (() => {throw new Error('LocalPreparationRetired');})() : entry.dispatch.prepared;
  const copy = (value, changes = {}) => {
    if (['input', 'parameters', 'preparedProgram'].some(name => Object.hasOwn(changes, name))) {
      throw new TypeError('LocalPreparationSnapshotMutation');
    }
    const descriptors = Object.getOwnPropertyDescriptors(value);
    for (const descriptor of Object.values(descriptors)) descriptor.configurable = true;
    for (const [key, value] of Object.entries(changes)) descriptors[key] =
      {value, enumerable: true, configurable: true, writable: true};
    const result = Object.defineProperties({}, descriptors);
    const handle = submissions.get(value);
    if (handle !== undefined) submissions.set(result, handle);
    return result;
  };
  const bindPayload = (value, entry) => {
    for (const name of ['input', 'parameters']) if (Object.hasOwn(value, name)) {
      Object.defineProperty(value, name, {enumerable: true, configurable: true,
        get: () => payload(entry)[name]});
    }
    submissions.set(value, entry.custody.handle);
    return value;
  };
  const adopt = (prepared, request) => {
    if (originals.has(prepared)) return originals.get(prepared);
    if (!select(prepared)) return prepared;
    const entry = handles.get(submissions.get(request)) ?? create({input: request?.input, parameters: request?.parameters});
    payload(entry).prepared = prepared;
    entry.selected = true;
    originals.set(prepared, entry.custody.handle);
    return entry.custody.handle;
  };
  const read = value => handles.has(value) ? payload(handles.get(value)).prepared : value;
  return Object.freeze({
    adopt, read, copy,
    capture(value) {
      if (!['aql', 'program'].includes(value.kind) || !Object.hasOwn(value, 'input')) return value;
      const entry = create({input: value.input, parameters: value.parameters});
      entry.handlerOwned = true;
      return Object.freeze(bindPayload(copy(value), entry));
    },
    finishHandler(value) {
      const entry = handles.get(submissions.get(value));
      // Unselected Source/Effect/Model retain their existing ownership. This
      // Pure slice does not infer their stop from handler completion. Before
      // dispatch owns cleanup, a failed/unknown setup may still need this
      // original snapshot; preserve it until that owner provides retirement.
      if (entry === undefined || !entry.selected || !entry.ownerActive || !entry.dispatched) return;
      entry.ownerActive = false;
      entry.owner.release();
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
      const entry = handles.get(submissions.get(submission));
      if (entry === undefined || !entry.selected) return undefined;
      if (entry.dispatched || entry.retired) throw new Error('LocalPreparationAlreadyDispatched');
      const borrower = entry.custody.borrow(entry.custody.handle);
      entry.dispatch = borrower;
      entry.dispatched = true;
      if (!entry.handlerOwned) { entry.ownerActive = false; entry.owner.release(); }
      return Object.freeze({
        get preparedProgram() { return borrower.prepared.prepared; },
        retire() {
          if (entry.retired) return;
          // Only the existing dispatch cleanup owner receives this capability.
          retirePrepared?.(borrower.prepared.prepared);
          entry.custody.requestRetirement();
          borrower.release();
          entry.dispatch = undefined;
          entry.custody.confirmRetired();
          entry.retired = true;
        },
      });
    },
  });
}
