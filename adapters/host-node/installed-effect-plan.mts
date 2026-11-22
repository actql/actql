import {registerInstalledEffectDependencyOriginal,retireInstalledEffectDependencyOriginal} from '../host-common/installed-effect-dependency-original.mjs';
// Pure composition inside the existing installed Effect owner. Original
// Core extents/Plan are DATA until the SAME Request completes and adopts them.
import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import {isEffectPreparationRefusal} from '../host-common/effect-preparation-result.mjs';
import {rejectInstalledEffectPlan as fail} from './installed-effect-recipe.mjs';
export {captureInstalledEffectPlanRecipe, selectInstalledEffectCredentialOperation,
  installedEffectSavedControlEntryLimit, installedEffectSavedControlResponseLimit,
  installedEffectRecipeForControlEntryLimit} from './installed-effect-recipe.mjs';
export {prepareInstalledEffectManagedPlan} from './installed-effect-managed-plan.mjs';
export {effectRecoveryPreviewBounds, captureInstalledStandardCreateLimits, prepareInstalledStandardCreatePlanRecipe,
  prepareInstalledDeclaredUpdatePlanRecipe, prepareInstalledPhysicalWritePlanRecipe,
  captureDeclaredUpdateTargetCapacity} from './installed-effect-recipe-construction.mjs';
import {NativePromise, nativePromiseThen} from './installed-effect-child-construction.mjs';
export {prepareInstalledEffectOwnedRequestChild, prepareInstalledEffectRequestChild,
  prepareInstalledEffectCaptureChild} from './installed-effect-child-construction.mjs';

export {prepareInstalledEffectCredentialChild} from './installed-effect-credential-child.mjs';


type CoreResult = Extract<SynchronousRuntimeData, object>;
type OriginalInput = [owner: unknown, prepared: unknown, request: unknown, plan: unknown];
type OriginalPort<Args extends unknown[] = []> = (...args: [...OriginalInput, ...Args]) => CoreResult;
type RequestProjection = [member: number, operation: number, row: number];
type FootprintProjection = [member: number, operation: number];
type LedgerFamily = [counts: readonly number[], entries: number, bytes: number, nodes: number, depth: number];
type LedgerRow = [kind: string, bytes: number, nodes: number, depth: number, responseBytes: number];
type Runtime = Readonly<{
  clientProgramInstalledEffectOperationControlConstructionBegin: OriginalPort;
  clientProgramInstalledEffectOperationNativeConstructionBegin?: OriginalPort<[native: unknown]>;
  clientProgramInstalledEffectOperationMemberReceiptConstructionBegin?: OriginalPort<[scratch: unknown]>;
  clientProgramInstalledEffectOperationControlConstructionComplete: OriginalPort;
  clientProgramInstalledEffectOperationGrantConstructionBegin?: OriginalPort;
  clientProgramInstalledEffectOperationRequestProjectionBegin?: OriginalPort<RequestProjection>;
  clientProgramInstalledEffectOperationFootprintConstructionBegin?: OriginalPort<FootprintProjection>;
  clientProgramInstalledEffectOperationLedgerOpenBegin?: OriginalPort<[root: string]>;
  clientProgramInstalledEffectOperationLedgerFamilyBegin?: OriginalPort<LedgerFamily>;
  clientProgramInstalledEffectOperationLedgerRowBegin?: OriginalPort<LedgerRow>;
  clientProgramInstalledEffectOperationLedgerHistoryGrow?: OriginalPort<[count: number, wireUnits: bigint]>;
  clientProgramInstalledEffectOperationControlInputBegin?: OriginalPort<[wire: string]>;
  clientProgramInstalledEffectOperationLedgerCodecBegin?: OriginalPort<[wire: string | undefined, nodes: number, depth: number]>;
  clientProgramInstalledEffectOperationReceiptCodecBegin?: OriginalPort<[wire: string, nodes: number, depth: number, receiptWire: boolean]>;
  clientProgramInstalledEffectOperationLedgerCodecComplete?: OriginalPort;
  clientProgramInstalledEffectManagedPlanHasHostInput?(plan: unknown): boolean;
  clientProgramInstalledEffectCapturedInputInventoryRetain?: OriginalPort<[inputs: unknown]>;
  clientProgramInstalledEffectManagedPlanShape?(plan: unknown): readonly [
    rows: number, operations: number, heldChildren: number];
  clientProgramAuthorInstalledEffectPreview?: OriginalPort<[allowed: unknown, definition: unknown,
    invocation: unknown, templateWire: string, expectedRunIdentityCid: string, expectedAuthoringContextCid: string,
    requestScope: unknown, maxWireBytes: number, maxNodes: number, maxDepth: number, maxMembers: number,
    maxRows: number, maxKeyBytes: number, maxKeyNodes: number, maxKeyDepth: number]>;
  clientProgramInstalledEffectRecoveredPreviewKeys?: OriginalPort<[allowed: unknown, definition: unknown,
    invocation: unknown, preview: unknown, scope: unknown, maxMembers: number, maxRows: number,
    maxWork: number, maxKeyBytes: number, maxKeyNodes: number, maxKeyDepth: number]>;
}>;
type RecoveredInputControl = Readonly<{
  retainInstalledEffectRecoveredInputInventory?(...args: [...OriginalInput, allowed: unknown,
    definition: unknown, invocation: unknown, preview: unknown]): undefined;
}>;
type SyncMethod<Receiver, Args extends readonly unknown[], Value extends SynchronousRuntimeData> =
  (this: Receiver, ...args: Args) => Value;
export type ControlWork = <Receiver, Args extends readonly unknown[], Value extends SynchronousRuntimeData>(
  receiver: Receiver, method: SyncMethod<Receiver, Args, Value>, args: Args,
  nativeConstruction?: unknown, memberReceipt?: boolean) => Value;
type Run = Readonly<{
  runtime: Runtime;
  value: unknown;
  prepared: unknown;
  request: unknown;
  operationPlan: unknown;
  readPlan(parent: unknown, prepared: unknown, request: unknown): CoreResult;
  closed?: boolean;
  failure?: unknown;
}> & {
  controlConstruction?: ControlWork;
  retireControlConstruction?: () => boolean;
  recoveredRequestInput?: Readonly<{retire(): boolean}>;
  selecting?: boolean;
};

// The existing Run owns this synchronous control frame, its original methods
// and any invalid borrowed task. This is not a grant, new owner or caller fee.
export function prepareInstalledEffectControlConstruction(run: Run) {
  const {runtime, value: parent, prepared, request, operationPlan: plan, readPlan} = run ?? {};
  const begin = runtime?.clientProgramInstalledEffectOperationControlConstructionBegin;
  const nativeBegin = runtime?.clientProgramInstalledEffectOperationNativeConstructionBegin;
  const receiptBegin = runtime?.clientProgramInstalledEffectOperationMemberReceiptConstructionBegin;
  const complete = runtime?.clientProgramInstalledEffectOperationControlConstructionComplete;
  const grantBegin = runtime?.clientProgramInstalledEffectOperationGrantConstructionBegin;
  const requestProjectionBegin = runtime?.clientProgramInstalledEffectOperationRequestProjectionBegin;
  const footprintBegin = runtime?.clientProgramInstalledEffectOperationFootprintConstructionBegin;
  const ledgerOpenBegin = runtime?.clientProgramInstalledEffectOperationLedgerOpenBegin;
  const ledgerFamilyBegin = runtime?.clientProgramInstalledEffectOperationLedgerFamilyBegin;
  const ledgerRowBegin = runtime?.clientProgramInstalledEffectOperationLedgerRowBegin;
  const ledgerHistoryGrow = runtime?.clientProgramInstalledEffectOperationLedgerHistoryGrow;
  const beginInput = runtime?.clientProgramInstalledEffectOperationControlInputBegin;
  const codecBegin = runtime?.clientProgramInstalledEffectOperationLedgerCodecBegin;
  const receiptCodecBegin = runtime?.clientProgramInstalledEffectOperationReceiptCodecBegin;
  const codecComplete = runtime?.clientProgramInstalledEffectOperationLedgerCodecComplete;
  const hasHostInput = runtime?.clientProgramInstalledEffectManagedPlanHasHostInput;
  const retainInventory = runtime?.clientProgramInstalledEffectCapturedInputInventoryRetain;
  const shape = runtime?.clientProgramInstalledEffectManagedPlanShape;
  const keyAuthor = runtime?.clientProgramAuthorInstalledEffectPreview;
  const keyRecovery = runtime?.clientProgramInstalledEffectRecoveredPreviewKeys;
  const parseJson: (wire: string) => SynchronousRuntimeData = JSON.parse;
  const jsonReceiver = JSON;
  if (![begin, complete, readPlan].every(method => typeof method === 'function') || parent === undefined || plan === undefined) {
    fail('InstalledEffectControlRuntimeUnavailable');
  }
  let working = false, codecWorking = false, historyWorking = false, failed = false, retired = false, primary: unknown, pending: unknown, work: ControlWork;
  let previewInputWire: string | undefined, previewInput: SynchronousRuntimeData;
  const sameRecord = () => !run.closed && run.runtime === runtime && run.value === parent &&
    run.prepared === prepared && run.request === request && run.operationPlan === plan &&
    run.readPlan === readPlan && run.controlConstruction === work;
  const originalRecord = () => {
    if (Object.hasOwn(run, 'failure')) throw run.failure;
    if (!sameRecord()) fail('ForeignInstalledEffectManagedRun');
  };
  const retainInvalid = (value: unknown) => {
    if (value === null || !['object', 'function'].includes(typeof value)) return;
    pending = value;
    const settled = () => {pending = undefined; run.selecting = false;};
    if (nodeTypes.isPromise(value)) {
      // Native original first. A species/join refusal leaves the same task
      // unobserved and the existing Run retirement latch held, never an ACK.
      Reflect.apply(nativePromiseThen, value, [settled, settled]);
      fail('InvalidInstalledEffectControlConstruction');
    }
    const then = (value as {then?: unknown}).then;
    if (typeof then !== 'function') {pending = undefined; return;}
    const joined = new NativePromise((yes, no) => Reflect.apply(then, value, [yes, no]));
    Reflect.apply(nativePromiseThen, joined, [settled, settled]);
    fail('InvalidInstalledEffectControlConstruction');
  };
  const invoke = <Receiver, Args extends readonly unknown[], Value extends SynchronousRuntimeData>(
    receiver: Receiver, method: SyncMethod<Receiver, Args, Value>, args: Args,
    inputWire?: string, grant = false, requestProjection?: RequestProjection, footprintProjection?: FootprintProjection,
    ledgerRoot?: string, ledgerFamily?: LedgerFamily, nativeConstruction?: unknown, memberReceipt = false, ledgerRow?: LedgerRow,
  ): Value => {
    if (retired) fail('InstalledEffectControlConstructionRetired');
    if (failed) throw primary;
    if (working || run.selecting) fail('InstalledEffectControlConstructionPending');
    if (typeof method !== 'function' || !Array.isArray(args)) fail('InvalidInstalledEffectControlConstruction');
    if (nativeConstruction !== undefined && (nativeConstruction === null || typeof nativeConstruction !== 'object' || nodeTypes.isProxy(nativeConstruction))) {
      fail('InvalidInstalledEffectControlConstruction');
    }
    if (typeof memberReceipt !== 'boolean' || memberReceipt && nativeConstruction === undefined) fail('InvalidInstalledEffectControlConstruction');
    if (nativeConstruction !== undefined && typeof (memberReceipt ? receiptBegin : nativeBegin) !== 'function') fail('InstalledEffectControlRuntimeUnavailable');
    // These exact installing Core entrances own their Resource cut: the
    // borrowed Plan getter, or a key constructor that grows this SAME parent
    // before allocation. No arbitrary callback or Host count selects it.
    const metadata = nativeConstruction === undefined && ledgerRow === undefined && ledgerFamily === undefined && ledgerRoot === undefined && !grant && requestProjection === undefined && footprintProjection === undefined && inputWire === undefined && receiver === runtime &&
      !nodeTypes.isProxy(method) && !nodeTypes.isProxy(args) &&
      ((method as Function) === shape && Object.getOwnPropertyDescriptor(args, 'length')?.value === 1 &&
        Object.getOwnPropertyDescriptor(args, '0')?.value === plan ||
       ((method as Function) === keyAuthor && Object.getOwnPropertyDescriptor(args, 'length')?.value === 19 ||
        (method as Function) === keyRecovery && Object.getOwnPropertyDescriptor(args, 'length')?.value === 15) &&
        Object.getOwnPropertyDescriptor(args, '0')?.value === parent &&
        Object.getOwnPropertyDescriptor(args, '1')?.value === prepared &&
        Object.getOwnPropertyDescriptor(args, '2')?.value === request &&
        Object.getOwnPropertyDescriptor(args, '3')?.value === plan);
    const observePlan = () => {
      const current = Reflect.apply(readPlan, runtime, [parent, prepared, request]);
      retainInvalid(current);
      if (checked(current) !== plan) fail('ForeignInstalledEffectManagedRun');
      originalRecord();
    };
    working = true;
    let invoking = false;
    // The existing parent retirement already refuses this latch. Retain it
    // through native-task settlement if an invalid asynchronous result escapes.
    run.selecting = true;
    try {
      originalRecord();
      if (metadata) observePlan();
      else checked(Reflect.apply((nativeConstruction !== undefined ? memberReceipt ? receiptBegin : nativeBegin :
        ledgerRow !== undefined && ledgerRowBegin !== undefined ? ledgerRowBegin :
        ledgerFamily !== undefined && ledgerFamilyBegin !== undefined ? ledgerFamilyBegin :
        ledgerRoot !== undefined && ledgerOpenBegin !== undefined ? ledgerOpenBegin :
        footprintProjection !== undefined && footprintBegin !== undefined ? footprintBegin :
        requestProjection !== undefined && requestProjectionBegin !== undefined ? requestProjectionBegin :
        grant && grantBegin !== undefined ? grantBegin :
        inputWire === undefined ? begin : beginInput) as Function, runtime,
        [parent, prepared, request, plan, ...(ledgerRow !== undefined && ledgerRowBegin !== undefined
          ? ledgerRow : ledgerFamily !== undefined && ledgerFamilyBegin !== undefined
          ? ledgerFamily : ledgerRoot !== undefined && ledgerOpenBegin !== undefined
          ? [ledgerRoot] : footprintProjection !== undefined && footprintBegin !== undefined
          ? footprintProjection : requestProjection !== undefined && requestProjectionBegin !== undefined
            ? requestProjection : inputWire === undefined ? [] : [inputWire]),
          ...(nativeConstruction === undefined ? [] : [nativeConstruction])]));
      originalRecord();
      invoking = true;
      const value = Reflect.apply(method as Function, receiver, metadata && (method as Function) === shape ? [plan] : args) as Value;
      invoking = false;
      if (failed) throw primary;
      retainInvalid(value);
      // These closed key entrances return Core Results. Preserve an actual
      // resource/semantic refusal before another current callback can replace
      // its cause; a later call cannot reconstruct the failed key cohort.
      if (metadata && (method as Function) !== shape) checked(value);
      originalRecord();
      if (metadata) observePlan();
      else checked(Reflect.apply(complete, runtime, [parent, prepared, request, plan]));
      originalRecord();
      return value;
    } catch (cause) {
      if (invoking && !failed && pending === undefined && !codecWorking &&
          isEffectPreparationRefusal(cause)) {
        // This observed semantic refusal is the synchronous projector's
        // original DATA result. Its retained output stays on the SAME token;
        // only a successful original completion returns constructor scratch.
        // Keep the error for the existing Ledger/CAS/no-send decision outside
        // this frame. It grants neither a terminal Run nor physical cleanup.
        try {
          originalRecord();
          if (metadata) observePlan();
          else checked(Reflect.apply(complete, runtime, [parent, prepared, request, plan]));
          originalRecord();
        } catch (completionFailure) {
          // Scratch retirement is a separate result. Preserve even a thrown
          // undefined alongside the original refusal; the aggregate is NOT
          // marked as a completed semantic result and keeps this frame failed.
          failed = true;
          primary = Object.assign(new AggregateError([cause, completionFailure],
            'InstalledEffectControlConstructionPending', {cause}),
          {code: 'InstalledEffectControlConstructionPending',
            primaryFailure: cause, cleanupPending: true});
          throw primary;
        }
        throw cause;
      }
      failed = true; primary = cause;
      // Failed-prefix workspace remains on the SAME Core control reservation.
      throw cause;
    } finally {
      working = false;
      if (pending === undefined) run.selecting = false;
    }
  };
  // The installing constructor owns this optional opaque Common quote. No
  // Host scalar pricing or provider-runtime opaque value crosses the seam.
  work = (receiver, method, args, nativeConstruction, memberReceipt = false) =>
    invoke(receiver, method, args, undefined, false, undefined, undefined, undefined, undefined, nativeConstruction, memberReceipt);
  // Installing Site issuers alone use this fixed Core constructor family.
  // Legacy runtimes keep the complete generic frame; JS quotes no quantities.
  const grant = <Receiver, Args extends readonly unknown[], Value extends SynchronousRuntimeData>(receiver: Receiver, method: SyncMethod<Receiver, Args, Value>, args: Args) => invoke(receiver, method, args, undefined, true);
  // Core resolves these SAME Plan coordinates to its completed original
  // request child. JavaScript selects no quantity or replacement capability.
  // A legacy runtime still reserves the complete generic control frame.
  const requestProjection = <Receiver, Args extends readonly unknown[], Value extends SynchronousRuntimeData>(
    member: number, operation: number, row: number, receiver: Receiver, method: SyncMethod<Receiver, Args, Value>, args: Args,
  ) => {
    if (![member, operation, row].every(value => Number.isSafeInteger(value) && value >= 0)) {
      fail('InvalidInstalledEffectControlConstruction');
    }
    return invoke(receiver, method, args, undefined, false, [member, operation, row]);
  };
  // Fixed declared member footprint only; Core reads its original scratch.
  const footprint = <Receiver, Args extends readonly unknown[], Value extends SynchronousRuntimeData>(
    member: number, operation: number, receiver: Receiver, method: SyncMethod<Receiver, Args, Value>, args: Args,
  ) => {
    if (![member, operation].every(value => Number.isSafeInteger(value) && value >= 0)) fail('InvalidInstalledEffectControlConstruction');
    return invoke(receiver, method, args, undefined, false, undefined, [member, operation]);
  };
  // Exact original openEffectLedger caller; Common owns all quantity math.
  const ledgerOpen = <Receiver, Args extends readonly unknown[], Value extends SynchronousRuntimeData>(root: string, receiver: Receiver, method: SyncMethod<Receiver, Args, Value>, args: Args) => {
    if (typeof root !== 'string' || !Array.isArray(args) || nodeTypes.isProxy(args) ||
        Object.getOwnPropertyDescriptor(args, 'length')?.value !== 1) {
      fail('InvalidInstalledEffectControlConstruction');
    }
    const options = Object.getOwnPropertyDescriptor(args, '0')?.value;
    if (options === null || typeof options !== 'object' || nodeTypes.isProxy(options) ||
        Object.getOwnPropertyDescriptor(options, 'root')?.value !== root) {
      fail('InvalidInstalledEffectControlConstruction');
    }
    return invoke(receiver, method, args, undefined, false, undefined, undefined, root);
  };
  // Called only by the closed standard Ledger wrapper below. The frozen
  // lengths/policy scalars are geometry, not permission or completed checks.
  // All byte pricing, policy-family selection and coheld lifetimes are Core.
  const ledgerFamily = <Receiver, Args extends readonly unknown[], Value extends SynchronousRuntimeData>(
    receiver: Receiver, method: SyncMethod<Receiver, Args, Value>, args: Args,
    counts: readonly number[], entries: number, bytes: number, nodes: number, depth: number,
  ) =>
    invoke(receiver, method, args, undefined, false, undefined, undefined,
      undefined, [counts, entries, bytes, nodes, depth]);
  const ledgerRow = <Receiver, Args extends readonly unknown[], Value extends SynchronousRuntimeData>(
    receiver: Receiver, method: SyncMethod<Receiver, Args, Value>, args: Args,
    kind: string, bytes: number, nodes: number, depth: number, responseBytes: number,
  ) => {
    if (!['entry', 'response', 'receipt', 'quantity'].includes(kind) ||
        ![bytes, nodes, depth, responseBytes].every(value => Number.isSafeInteger(value) && value > 0)) {
      fail('InvalidInstalledEffectControlConstruction');
    }
    return invoke(receiver, method, args, undefined, false, undefined, undefined,
      undefined, undefined, undefined, false, [kind, bytes, nodes, depth, responseBytes]);
  };
  // The original SQLite history reader invokes this before materializing its
  // same-transaction rows. It extends the active frame, never another owner.
  const ledgerHistory = (count: number, wireUnits: number) => {
    if (retired) fail('InstalledEffectControlConstructionRetired');
    if (failed) throw primary;
    if (!working || !run.selecting || codecWorking || historyWorking) fail('InstalledEffectControlConstructionPending');
    if (!Number.isSafeInteger(count) || count < 0 || count > 2147483647 || !Number.isSafeInteger(wireUnits) || wireUnits < 0 ||
        typeof ledgerHistoryGrow !== 'function') fail('InstalledEffectControlRuntimeUnavailable');
    historyWorking = true;
    try {
      originalRecord();
      checked(Reflect.apply(ledgerHistoryGrow, runtime, [parent, prepared, request, plan, count, BigInt(wireUnits)]));
      originalRecord();
    } catch (cause) {
      failed = true; primary = cause;
      throw cause;
    } finally { historyWorking = false; }
  };
  // Only the original Ledger invokes this nested synchronous seam. The outer
  // control frame retains every output. The selected Ledger family adds its
  // coheld snapshot/array demand; generic frames retain the full family floor.
  // No Preview one-use identity or physical occurrence is reused.
  const ledgerCodec = <Receiver, Args extends readonly unknown[], Value extends SynchronousRuntimeData>(
    receiver: Receiver, method: SyncMethod<Receiver, Args, Value>, args: Args, wire?: string, nodes = 512, depth = 16, receiptWire?: boolean,
  ): Value => {
    if (retired) fail('InstalledEffectControlConstructionRetired');
    if (failed) throw primary;
    if (!working || !run.selecting || codecWorking) fail('InstalledEffectControlConstructionPending');
    if (typeof method !== 'function' || !Array.isArray(args) ||
        wire !== undefined && typeof wire !== 'string' ||
        !Number.isSafeInteger(nodes) || nodes < 1 || nodes > 4096 ||
        !Number.isSafeInteger(depth) || depth < 1 || depth > 32 ||
        receiptWire !== undefined && (typeof receiptWire !== 'boolean' || typeof wire !== 'string') ||
        typeof (receiptWire === undefined ? codecBegin : receiptCodecBegin) !== 'function' || typeof codecComplete !== 'function') {
      fail('InstalledEffectControlRuntimeUnavailable');
    }
    codecWorking = true;
    try {
      originalRecord();
      checked(Reflect.apply((receiptWire === undefined ? codecBegin : receiptCodecBegin) as Function, runtime,
        [parent, prepared, request, plan, wire, nodes, depth, ...(receiptWire === undefined ? [] : [receiptWire])]));
      originalRecord();
      const value = Reflect.apply(method, receiver, args);
      if (failed) throw primary;
      retainInvalid(value);
      originalRecord();
      checked(Reflect.apply(codecComplete, runtime, [parent, prepared, request, plan]));
      originalRecord();
      return value;
    } catch (cause) {
      failed = true; primary = cause;
      throw cause;
    } finally { codecWorking = false; }
  };
  const receiptCodec = <Receiver, Args extends readonly unknown[], Value extends SynchronousRuntimeData>(
    receiver: Receiver, method: SyncMethod<Receiver, Args, Value>, args: Args,
    wire: string, nodes: number, depth: number, receiptWire: boolean,
  ) => {
    if (typeof receiptWire !== 'boolean') fail('InstalledEffectControlRuntimeUnavailable');
    return ledgerCodec(receiver, method, args, wire, nodes, depth, receiptWire);
  };
  const parsePreview = (wire: string, borrowOriginal = false) => {
    if (retired) fail('InstalledEffectControlConstructionRetired');
    if (failed) throw primary;
    if (working || run.selecting) fail('InstalledEffectControlConstructionPending');
    originalRecord();
    if (typeof wire !== 'string' || typeof borrowOriginal !== 'boolean' || typeof hasHostInput !== 'function') {
      fail('InstalledEffectControlRuntimeUnavailable');
    }
    // Hot recovery borrows the SAME funded forest. A cold owner has no such
    // original and must enter its first one-use constructor below.
    if (borrowOriginal && previewInputWire !== undefined) {
      if (wire !== previewInputWire) fail('ForeignInstalledEffectManagedRun');
      working = true;
      run.selecting = true;
      try {
        const current = Reflect.apply(readPlan, runtime, [parent, prepared, request]);
        retainInvalid(current);
        if (checked(current) !== plan) fail('ForeignInstalledEffectManagedRun');
        originalRecord();
        return previewInput;
      } catch (cause) {
        if (pending !== undefined) {failed = true; primary = cause;}
        throw cause;
      } finally {
        working = false;
        if (pending === undefined) run.selecting = false;
      }
    }
    // Other installed recipes retain their unchanged fixed parser envelope.
    // Only the typed opted-in Plan can refine this existing control token.
    const selected = Reflect.apply(hasHostInput, runtime, [plan]);
    if (typeof selected !== 'boolean') fail('InvalidHostRuntimeResult');
    if (!selected) {
      originalRecord();
      return Reflect.apply(parseJson, jsonReceiver, [wire]);
    }
    if (typeof beginInput !== 'function') fail('InstalledEffectControlRuntimeUnavailable');
    const parsed = invoke(jsonReceiver, parseJson, [wire], wire);
    previewInputWire = wire;
    previewInput = parsed;
    return parsed;
  };
  const retainInputs = (inputs: unknown) => {
    if (retired) fail('InstalledEffectControlConstructionRetired');
    if (failed) throw primary;
    if (working || run.selecting) fail('InstalledEffectControlConstructionPending');
    if (typeof retainInventory !== 'function') fail('InstalledEffectControlRuntimeUnavailable');
    working = true;
    run.selecting = true;
    try {
      originalRecord();
      const result = Reflect.apply(retainInventory, runtime, [parent, prepared, request, plan, inputs]);
      retainInvalid(result);
      checked(result);
      originalRecord();
    } catch (cause) {
      failed = true; primary = cause;
      throw cause;
    } finally {
      working = false;
      if (pending === undefined) run.selecting = false;
    }
  };
  const retainRecoveredInputs = (control: RecoveredInputControl, allowed: unknown, definition: unknown,
    invocation: unknown, preview: unknown) => {
    if (retired) fail('InstalledEffectControlConstructionRetired');
    if (failed) throw primary;
    if (working || run.selecting) fail('InstalledEffectControlConstructionPending');
    const retain = control?.retainInstalledEffectRecoveredInputInventory;
    if (typeof retain !== 'function') fail('InstalledEffectControlRuntimeUnavailable');
    working = true;
    run.selecting = true;
    try {
      originalRecord();
      // This grows the existing control token before entering a constructor;
      // invoking work() here would incorrectly open that constructor first.
      const result = Reflect.apply(retain, control,
        [parent, prepared, request, plan, allowed, definition, invocation, preview]);
      retainInvalid(result);
      originalRecord();
    } catch (cause) {
      failed = true; primary = cause;
      throw cause;
    } finally {
      working = false;
      if (pending === undefined) run.selecting = false;
    }
  };
  const retire = () => {
    if (retired) return true;
    if (!sameRecord() || run.retireControlConstruction !== retire) fail('ForeignInstalledEffectManagedRun');
    if (working || pending !== undefined || run.selecting) return false;
    // Recovered requests remain on their original member constructor tokens
    // while any hot observation can borrow them. A stage close is not their
    // final retirement. Drop aliases and retire those SAME children before
    // returning this control/parent backing; pending cleanup stays pending.
    const recovery = run.recoveredRequestInput;
    if (recovery !== undefined) {
      if (recovery.retire() !== true) return false;
      if (run.recoveredRequestInput !== recovery || !sameRecord()) fail('ForeignInstalledEffectManagedRun');
      run.recoveredRequestInput = undefined;
    }
    // Actual complete dispatch retirement calls this before returning its
    // Core control backing. A retained Error may itself keep a heavy prefix.
    primary = undefined;
    previewInputWire = previewInput = undefined;
    retireInstalledEffectDependencyOriginal(work);
    retired = true;
    return true;
  };
  registerInstalledEffectDependencyOriginal(work,{runtime,parent,prepared,request,plan,current:originalRecord});
  return Object.freeze(Object.assign(work, {retire, parsePreview, ledgerCodec, grant, requestProjection, footprint, ledgerOpen, ledgerFamily,
    ...(typeof ledgerRowBegin === 'function' ? {ledgerRow} : {}),
    ...(typeof ledgerHistoryGrow === 'function' ? {ledgerHistory} : {}),
    ...(typeof receiptCodecBegin === 'function' ? {receiptCodec} : {}),
    retainInputs, retainRecoveredInputs}));
}
