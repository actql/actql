import {createRequire} from 'node:module';
import {types} from 'node:util';
import {prepareOrdinarySourceManagedInstallation, prepareOrdinaryProjectSourceManagedInstallation,
  assertOrdinarySourcePreparationCurrent}
  // @ts-expect-error TS7016: the ordinary Source owner is still authored in JavaScript.
  from './ordinary-source-managed.mjs';
import {assertSourceManagedHostPreparation, assertRetainedSourceManagedHost, prepareInstalledMockSourcePreparation,
  readInstalledMockPreparation, readInstalledProjectSourcePreparation,
  originalSourceManagedHostRequest, sourceManagedSubmittedIntentCid,
  managedComputeSubmittedIntentCid, readSourceManagedRunRequirements, readManagedComputeRunRequirements,
  readSourceManagedEffectRunRequirements,
  readLocalMockModelRunRequirements, readLocalContentRunRequirements,
  prepareInstalledSequenceContractOriginal,
  readLocalPreparationContext, retireSourceManagedInitialPreparation}
  // @ts-expect-error TS7016: these fixed Host operations still belong to authored JavaScript.
  from './embedded-local.mjs';

type NativeMethod = (...args: unknown[]) => unknown;
type CallbackTable = readonly (NativeMethod | undefined)[];
type State = {
  installation: unknown; originals: unknown; callbacks: CallbackTable;
  closed: boolean; failure: unknown; flight: Promise<unknown> | undefined;
};
type SelectedInstallation = Awaited<ReturnType<typeof prepareInstallation>>;
type CleanupCarrier = Error & {
  code: string;
  cleanupHandle: Readonly<{status(): Readonly<{pending: boolean}>; retry(): Promise<unknown>}>;
};
type BorrowingHost = Readonly<{
  installation: Readonly<{borrowSourceInitializationMaterial?: NativeMethod}>;
}>;

// The actual ordinary prefix or the unchanged preload initializes this ESM
// namespace. Capture that SAME published receiver before application entry;
// never discover a later callback table or use one entrance's original to
// rescue another entrance. Selection alone supplies no Source admission.
const require = createRequire(import.meta.url);
const explicitStartup = process.execArgv.some(value =>
  value === '@actql/node/selected-infer-startup' || value === '@actql/local-node/selected-infer-startup');
const originalOwner: object = explicitStartup ? require('./infer-trusted-node-preload.cjs') : Object.freeze({});

// Fixed private startup receiver only. A shape, callback supplied by a Client,
// scalar quota or initial-control scope cannot create a Source installation.
const apply = Reflect.apply, descriptor = Object.getOwnPropertyDescriptor;
const hasOwn = Object.hasOwn, freeze = Object.freeze, isPromise = types.isPromise;
const NativeError = Error, NativeWeakMap = WeakMap;
const get = WeakMap.prototype.get, set = WeakMap.prototype.set;
const installations = new NativeWeakMap<object, State>();
const names = freeze(['prepareSourceManagedInstallation', 'assertSourceManagedInstallationCurrent',
  'beforeSourceSnapshot', 'bindSourceSnapshot', 'bindSourceRequest',
  'finishSourceProducer', 'closeSourceManagedInstallation', 'sourceIntentCid', 'prepareSourceManagedRead',
  'prepareSourceManagedRun', 'beforeSourceManagedResultRead', 'assertSourceManagedResultReadCurrent',
  'beforeSourceManagedQuery']);
const callbacks: CallbackTable = names.map(name => {
  const d = descriptor(originalOwner, name);
  return d !== undefined && hasOwn(d, 'value') && typeof d.value === 'function' ? d.value : undefined;
});
const computeNames = freeze(['prepareManagedComputeInstallation', 'assertManagedComputeInstallationCurrent',
  'beforeManagedComputeSnapshot', 'bindManagedComputeSnapshot', 'bindManagedComputeRequest',
  'finishManagedComputeProducer', 'closeManagedComputeInstallation', 'managedComputeIntentCid',
  undefined, 'prepareManagedComputeRun', 'beforeManagedComputeResultRead', 'assertManagedComputeResultReadCurrent',
  'beforeManagedComputeQuery']);
const computeCallbacks: CallbackTable = computeNames.map(name => {
  const d = name === undefined ? undefined : descriptor(originalOwner, name);
  return d !== undefined && hasOwn(d, 'value') && typeof d.value === 'function' ? d.value : undefined;
});
const unavailable: () => never = () => {throw Object.assign(new NativeError('SourceManagedPreparationUnavailable'),
  {code: 'SourceManagedPreparationUnavailable'});};
function invoke(index: number, args: readonly unknown[], selected = callbacks): unknown {
  const callback = selected[index];
  if (callback === undefined) unavailable();
  return apply(callback, originalOwner, args);
}
function original(view: unknown, originals: unknown) {
  const state = apply(get, installations, [view]) as State | undefined;
  if (state === undefined || state.closed || state.originals !== originals) unavailable();
  return state;
}
function current(state: State) {
  if (state.closed) unavailable();
  if (state.failure !== undefined) throw state.failure;
  // Fixed actual Owner checks nominal installation, shared runtime/domain,
  // Host/generation and currentness; the view's own fields are not evidence.
  if (invoke(1, [state.installation, state.originals], state.callbacks) !== undefined) unavailable();
}
async function close(state: State): Promise<unknown> {
  if (state.closed) return freeze({pending: false});
  if (state.flight !== undefined) return state.flight;
  const flight = (async () => {
    const observation = await invoke(6, [state.installation, state.originals], state.callbacks);
    const d = observation !== null && typeof observation === 'object'
      ? descriptor(observation, 'pending') : undefined;
    if (d !== undefined && hasOwn(d, 'value') && d.value === false) {
      state.closed = true; state.installation = undefined; state.originals = undefined;
    }
    return observation;
  })();
  state.flight = flight;
  try { return await flight; }
  finally { if (state.flight === flight) state.flight = undefined; }
}
function syncVoid(state: State, index: 3 | 4 | 10 | 11, args: readonly unknown[]) {
  current(state);
  const result = invoke(index, [state.installation, state.originals, ...args], state.callbacks);
  if (result !== undefined) {
    // Retain the unexpected observation, including a live Promise, rather than
    // awaiting it and moving the original synchronous snapshot boundary.
    state.failure = Object.assign(new NativeError('SourceManagedSynchronousProtocolChanged', {cause: result}),
      {code: 'SourceManagedSynchronousProtocolChanged'});
    throw state.failure;
  }
}
function synchronousReceipt(state: State, index: 2 | 12, args: readonly unknown[]) {
  current(state);
  const receipt = invoke(index, [state.installation, state.originals, ...args], state.callbacks);
  if (receipt === null || (typeof receipt !== 'object' && typeof receipt !== 'function') || isPromise(receipt)) {
    state.failure = Object.assign(new NativeError('SourceManagedSynchronousProtocolChanged', {cause: receipt}),
      {code: 'SourceManagedSynchronousProtocolChanged'});
    throw state.failure;
  }
  return receipt;
}

// The selected Root may retain a partial original while its fixed Host
// metadata operation is still running. Check that SAME nominal original in
// the captured Owner before/after each metadata await, without constructing a
// view early, issuing a child or treating a callback/Boolean as admission.
// Its constructor keeps partial cleanup if this observation refuses.
export function assertSourceManagedPreparationCurrent(originalInstallation: unknown, sameOriginals: unknown): void {
  if (!explicitStartup) return assertOrdinarySourcePreparationCurrent(originalInstallation, sameOriginals, true);
  if (invoke(1, [originalInstallation, sameOriginals]) !== undefined) unavailable();
}

export function assertManagedComputePreparationCurrent(originalInstallation: unknown, sameOriginals: unknown): void {
  if (!explicitStartup) return assertOrdinarySourcePreparationCurrent(originalInstallation, sameOriginals, false);
  if (invoke(1, [originalInstallation, sameOriginals], computeCallbacks) !== undefined) unavailable();
}

// Same private Host preparation and already-opened Source successor. A missing
// fixed supplier is unavailable; it cannot select a raw Environment fallback.
function borrowSourceInitializationMaterial(originals: BorrowingHost): unknown {
  assertSourceManagedHostPreparation(originals);
  const borrow = originals.installation.borrowSourceInitializationMaterial;
  if (typeof borrow !== 'function') unavailable();
  return apply(borrow,originals.installation,[]);
}

// Selection is private and fixed by these two exported consumer entries,
// never a callback table or purpose Boolean supplied by an application.
export function prepareSourceManagedInstallation(originals: unknown): Promise<SelectedInstallation> {
  if (!explicitStartup) return prepareOrdinarySourceManagedInstallation(originals, {
    validator: assertSourceManagedHostPreparation, retainedValidator: assertRetainedSourceManagedHost, borrowSourceInitializationMaterial, prepare: prepareInstalledMockSourcePreparation,
    read: readInstalledMockPreparation, request: originalSourceManagedHostRequest,
    intent: sourceManagedSubmittedIntentCid, requirements: readSourceManagedRunRequirements,
    effectRequirements: readSourceManagedEffectRunRequirements,
    preparationContext: readLocalPreparationContext,
    retireInitialPreparation: retireSourceManagedInitialPreparation,
    mockRequirements: readLocalMockModelRunRequirements,
  }, true);
  return prepareInstallation(originals, callbacks);
}
export function prepareManagedComputeInstallation(originals: unknown): Promise<SelectedInstallation> {
  if (!explicitStartup) {
    prepareInstalledSequenceContractOriginal(originals);
    return prepareOrdinarySourceManagedInstallation(originals, {
    validator: assertSourceManagedHostPreparation, retainedValidator: assertRetainedSourceManagedHost, borrowSourceInitializationMaterial, request: originalSourceManagedHostRequest,
    intent: managedComputeSubmittedIntentCid, requirements: readManagedComputeRunRequirements,
    effectRequirements: readSourceManagedEffectRunRequirements,
    preparationContext: readLocalPreparationContext,
    retireInitialPreparation: retireSourceManagedInitialPreparation,
    mockRequirements: readLocalMockModelRunRequirements,
  }, false);
  }
  return prepareInstallation(originals, computeCallbacks);
}

// The ordinary Host already retained the existing Connector's nominal Project
// preparation. Its real Root/readers are acquired by that same consumer, not
// by the Mock document reader or an unrelated selected-preload callback table.
export function prepareProjectSourceManagedInstallation(originals: unknown): Promise<SelectedInstallation> {
  if (explicitStartup) unavailable();
  return prepareOrdinaryProjectSourceManagedInstallation(originals, {
    validator: assertSourceManagedHostPreparation, retainedValidator: assertRetainedSourceManagedHost, borrowSourceInitializationMaterial,
    prepare: () => {readInstalledProjectSourcePreparation(originals);},
    read: readInstalledProjectSourcePreparation, request: originalSourceManagedHostRequest,
    intent: sourceManagedSubmittedIntentCid, requirements: readSourceManagedRunRequirements,
    effectRequirements: readSourceManagedEffectRunRequirements,
    preparationContext: readLocalPreparationContext,
    retireInitialPreparation: retireSourceManagedInitialPreparation,
    contentRequirements: readLocalContentRunRequirements,
  });
}

async function prepareInstallation(originals: unknown, selectedCallbacks: CallbackTable) {
  // This connect-time initialization may await. None of the four submission
  // operations below may await before the SDK's original snapshot/clone.
  const installation = await invoke(0, [originals], selectedCallbacks);
  if (installation === undefined) unavailable();
  const state: State = {installation, originals, callbacks: selectedCallbacks,
    closed: false, failure: undefined, flight: undefined};
  try { current(state); }
  catch (cause) {
    // Initialization acquired an original before its final current fence.
    // Forward the SAME original close, retaining partial custody on refusal;
    // neither rejection nor a failed current check acknowledges that child.
    const carrier = new NativeError('SourceManagedInstallationCleanupPending', {cause}) as CleanupCarrier;
    carrier.code = 'SourceManagedInstallationCleanupPending';
    carrier.cleanupHandle = freeze({status: () => freeze({pending: !state.closed}),
      retry: () => close(state)});
    throw carrier;
  }
  const view = freeze({
    beforeSourceSnapshot(kind: unknown, input: unknown, options: unknown) {
      // This wrapper does not admit a receipt by shape. Each later operation
      // rechecks that exact receipt in the original private Root's inventory.
      return synchronousReceipt(state, 2, [kind, input, options]);
    },
    beforeSourceQuery(format: unknown, text: unknown, parameters: unknown, options: unknown) {
      return synchronousReceipt(state, 12, [format, text, parameters, options]);
    },
    bindSourceSnapshot(receipt: unknown, body: unknown) {syncVoid(state, 3, [receipt, body]);},
    bindSourceRequest(receipt: unknown, body: unknown, request: unknown) {syncVoid(state, 4, [receipt, body, request]);},
    intentCid(receipt: unknown, originalFrozenBody: unknown) {
      current(state);
      // The fixed Root binds this exact receipt/body before using the same
      // Common submitted-intent Owner. This result is DATA, not an issuer or
      // permission. A selected Source never falls back to a native hash task
      // whose separate allocator/work lifetime has not been supplied.
      const result = invoke(7, [state.installation, state.originals, receipt, originalFrozenBody], state.callbacks);
      if (typeof result !== 'string' || !/^sha256:[0-9a-f]{64}$/u.test(result)) {
        state.failure = Object.assign(new NativeError('SourceManagedSynchronousProtocolChanged', {cause: result}),
          {code: 'SourceManagedSynchronousProtocolChanged'});
        throw state.failure;
      }
      current(state);
      return result;
    },
    finishSourceProducer(receipt: unknown, terminal: unknown) {
      // Producer retirement may follow lost currentness. Only the original
      // Owner can cut this producer's aliases; this is no child/physical ACK.
      const result = invoke(5, [state.installation, state.originals, receipt, terminal], state.callbacks);
      if (result !== undefined) unavailable();
    },
    assertCurrent() {current(state);},
    beforeResultRead(schemaOrOptions: unknown, options: unknown) {syncVoid(state, 10, [schemaOrOptions, options]);},
    assertResultReadCurrent() {syncVoid(state, 11, []);},
    prepareRun(originalCheckedPrepared: unknown) {
      current(state);
      // The fixed Root returns its pre-snapshot original only after the actual
      // Host resolves the same pending SDK request and checked preparation.
      const result=invoke(9,[state.installation,state.originals,originalCheckedPrepared],state.callbacks);
      if (result===null || typeof result!=='object' || isPromise(result)) unavailable();
      // Return the acquired original before the consumer's post-factory
      // current fence. Throwing here would lose its partial cleanup carrier.
      // The same Host retains it before any typed preparation or use.
      return result;
    },
    prepareRead(originalDerivedRequest: unknown, originalDeclaration: unknown, originalRun: unknown) {
      current(state);
      // The same captured Root follows the actual Host's retained transform
      // binding, then checks its own receipt and declaration originals. This
      // wrapper cannot construct a child from a declaration label or ordinal.
      const read = invoke(8, [state.installation, state.originals,
        originalDerivedRequest, originalDeclaration, originalRun], state.callbacks);
      if (read === null || typeof read !== 'object' || isPromise(read)) unavailable();
      // The same Host must retain this child's original close receiver before
      // its post-factory current check, then refuse before Core/physical use.
      return read;
    },
    // A single original close flight. Cutting these aliases cannot return
    // shared VM byte credit; failure observations retain their real lifetime.
    close() {return close(state);},
  });
  apply(set, installations, [view, state]);
  return view;
}

export function assertSourceManagedInstallationCurrent(view: unknown, sameOriginals: unknown): void {
  if (!explicitStartup) return assertOrdinarySourcePreparationCurrent(view, sameOriginals, true);
  const state = original(view, sameOriginals);
  if (state.callbacks !== callbacks) unavailable();
  current(state);
}

export function assertManagedComputeInstallationCurrent(view: unknown, sameOriginals: unknown): void {
  if (!explicitStartup) return assertOrdinarySourcePreparationCurrent(view, sameOriginals, false);
  const state = original(view, sameOriginals);
  if (state.callbacks !== computeCallbacks) unavailable();
  current(state);
}
