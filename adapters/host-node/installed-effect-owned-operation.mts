// The same installed Effect occurrence backs an already-owned physical child.
// Its request/Content owner keeps physical cleanup; this adapter never issues a
// grant, substitutes a writer, closes it twice, or creates a Resource root.
import {checked} from '../host-common/runtime-result.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';

type CoreResult = Extract<SynchronousRuntimeData, object>;
type CoreRuntime = {
  clientProgramInstalledEffectManagedPlanOperation(plan: unknown, memberIndex: number, perRow: boolean,
    operationIndex: number, operation: string): CoreResult;
  clientProgramInstalledEffectOperationExtentPhysical(extent: unknown): boolean;
  clientProgramInstalledEffectOperationExtentTransfer(extent: unknown): bigint;
  clientProgramInstalledEffectOperationBorrow(owner: unknown, prepared: unknown, request: unknown, plan: unknown,
    memberIndex: number, perRow: boolean, operationIndex: number, rowIndex: number, operation: string): CoreResult;
  clientProgramInstalledEffectOperationStart(token: unknown): CoreResult;
  clientProgramInstalledEffectOperationCharge(token: unknown, bytes: bigint): CoreResult;
  clientProgramInstalledEffectOperationInputBegin?(token: unknown, extent: unknown): CoreResult;
  clientProgramInstalledEffectOperationResponseProjectionComplete?(token: unknown): CoreResult;
  clientProgramInstalledEffectOwnedPhysicalOperationComplete?(token: unknown): CoreResult;
  clientProgramInstalledEffectOperationRetire(token: unknown, cleanupConfirmed: boolean): CoreResult;
};
type ManagedRun = {
  runtime: CoreRuntime;
  value: unknown;
  prepared: unknown;
  request: unknown;
  operationPlan: unknown;
  readPlan(owner: unknown, prepared: unknown, request: unknown): CoreResult;
  closed?: boolean;
  failure?: unknown;
};
type InputExtent = (bytes: number, requestUnits: number) => unknown;
type PhysicalChild = Readonly<{status(): Readonly<{pending: boolean}>}>;
export type InstalledEffectPhysicalOperation = Readonly<{
  retainPhysicalChild(original: PhysicalChild): undefined;
  chargeBytes(bytes: bigint): undefined;
  admitInput?: (bytes: number, requestUnits: number) => undefined;
}>;
type OwnedPhysicalOptions<Result> = {
  run: ManagedRun;
  memberIndex: number;
  rowIndex: number;
  operationIndex: number;
  operation: string;
  transferBytes: bigint;
  invoke(context: InstalledEffectPhysicalOperation): Result | PromiseLike<Result>;
  requestsRetired(): boolean;
  inputExtent?: InputExtent;
};
type OwnedPhysicalChild<Result> = Readonly<{
  prepare(): Promise<Awaited<Result>>;
  release(): boolean;
  retry(): boolean;
  status(): Readonly<{pending: boolean}>;
}>;

const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};

export function prepareInstalledEffectOwnedPhysicalChild<Result>(
  options: OwnedPhysicalOptions<Result>): OwnedPhysicalChild<Result>;
export function prepareInstalledEffectOwnedPhysicalChild<Result>({run, memberIndex, rowIndex,
  operationIndex, operation, transferBytes, invoke, requestsRetired, inputExtent}:
  Omit<OwnedPhysicalOptions<Result>, 'invoke'> & {invoke?: OwnedPhysicalOptions<Result>['invoke']}) {
  if (run === undefined || typeof invoke !== 'function' || typeof requestsRetired !== 'function' ||
      typeof transferBytes !== 'bigint' || transferBytes < 0n) fail('InvalidInstalledEffectOwnedOperation');
  const {runtime, value: parent, prepared, request, operationPlan: plan, readPlan} = run;
  const select = runtime?.clientProgramInstalledEffectManagedPlanOperation;
  const physical = runtime?.clientProgramInstalledEffectOperationExtentPhysical;
  const transfer = runtime?.clientProgramInstalledEffectOperationExtentTransfer;
  const borrow = runtime?.clientProgramInstalledEffectOperationBorrow;
  const start = runtime?.clientProgramInstalledEffectOperationStart;
  const charge = runtime?.clientProgramInstalledEffectOperationCharge;
  const beginInput = runtime?.clientProgramInstalledEffectOperationInputBegin;
  const complete = inputExtent === undefined
    ? runtime?.clientProgramInstalledEffectOwnedPhysicalOperationComplete
    : runtime?.clientProgramInstalledEffectOperationResponseProjectionComplete;
  const retire = runtime?.clientProgramInstalledEffectOperationRetire;
  if (![select, physical, transfer, borrow, start, charge, retire, readPlan]
      .every(method => typeof method === 'function') || (inputExtent !== undefined &&
        ![inputExtent, beginInput, complete].every(method => typeof method === 'function'))) {
    fail('InstalledEffectOperationRuntimeUnavailable');
  }
  const current = () => {
    if (Object.hasOwn(run, 'failure')) throw run.failure;
    if (run.closed || run.runtime !== runtime || run.value !== parent || run.prepared !== prepared ||
        run.request !== request || run.operationPlan !== plan || run.readPlan !== readPlan) {
      fail('ForeignInstalledEffectManagedRun');
    }
  };
  current();
  const extent = checked(Reflect.apply(select, runtime, [plan, memberIndex, true, operationIndex, operation]));
  const declaredTransfer = Reflect.apply(transfer, runtime, [extent]);
  if (Reflect.apply(physical, runtime, [extent]) !== true ||
      typeof declaredTransfer !== 'bigint' || declaredTransfer < transferBytes) {
    current(); fail('InsufficientInstalledEffectOperationTransfer');
  }
  let token = checked(Reflect.apply(borrow, runtime,
    [parent, prepared, request, plan, memberIndex, true, operationIndex, rowIndex, operation]));
  let attempted = false, preparing = false, stopping = false, releasing = false, retired = false, started = false;
  let child: PhysicalChild | undefined, status: PhysicalChild['status'] | undefined, accountingFailed = false;
  let inputSelectionStarted = false, inputSelected = false;
  const retainPhysicalChild = (original: PhysicalChild): undefined => {
    current();
    if (!preparing || stopping || child !== undefined || started || original === null ||
        typeof original !== 'object') fail('ForeignInstalledEffectPhysicalChild');
    child = original; // Before any fallible observation or the first acquisition.
    status = child.status;
    if (typeof status !== 'function') fail('InvalidInstalledEffectPhysicalChild');
    current();
    if (stopping) fail('InstalledEffectOperationAlreadyPrepared');
    checked(Reflect.apply(start, runtime, [token]));
    current();
    if (stopping) fail('InstalledEffectOperationAlreadyPrepared');
    started = true;
  };
  const admitInput = (bytes: number, requestUnits: number): undefined => {
    current();
    if (!preparing || stopping || !started || inputExtent === undefined || inputSelectionStarted) fail('ForeignInstalledEffectPhysicalChild');
    inputSelectionStarted = true;
    const selected = inputExtent(bytes, requestUnits);
    current();
    if (stopping) fail('InstalledEffectOperationAlreadyPrepared');
    checked(Reflect.apply(beginInput!, runtime, [token, selected]));
    current();
    if (stopping) fail('InstalledEffectOperationAlreadyPrepared');
    inputSelected = true;
  };
  const chargeBytes = (bytes: bigint): undefined => {
    current();
    if (!preparing || stopping || !started || (inputExtent !== undefined && !inputSelected) ||
        typeof bytes !== 'bigint' || bytes < 0n) {
      fail('ForeignInstalledEffectPhysicalChild');
    }
    try {checked(Reflect.apply(charge, runtime, [token, bytes]));}
    catch (error) {accountingFailed = true; throw error;}
    // A later current refusal does not make this successful charge unknown.
    // Original physical cleanup and request retirement still gate release.
    current();
  };
  const release = () => {
    if (retired) return true;
    stopping = true;
    if (preparing || accountingFailed || releasing) return false;
    releasing = true;
    try {
      if (child !== undefined) {
        // A failed getter can be retried only on this same retained original.
        if (status === undefined) status = child.status;
        if (typeof status !== 'function') fail('InvalidInstalledEffectPhysicalChild');
        if (Reflect.apply(status, child, [])?.pending !== false) return false;
      }
      if (requestsRetired() !== true) return false;
      child = status = invoke = undefined;
      if (checked(Reflect.apply(retire, runtime, [token, true])) !== true) return false;
      token = undefined; retired = true; return true;
    } finally {
      releasing = false;
    }
  };
  return Object.freeze({
    async prepare() {
      if (attempted || stopping) fail('InstalledEffectOperationAlreadyPrepared');
      attempted = true; preparing = true;
      try {
        current();
        const result = await invoke!(Object.freeze({retainPhysicalChild, chargeBytes,
          ...(inputExtent === undefined ? {} : {admitInput})}));
        current();
        if (!started || (inputExtent !== undefined && !inputSelected)) fail('InstalledEffectPhysicalChildUnavailable');
        if (typeof complete === 'function' && !stopping && !accountingFailed) {
          // The same writer has already performed its own close. Return only
          // ended workspace; keep its object, output and request aliases until
          // the original release path can retire the full reservation.
          const pending = Reflect.apply(status!, child, [])?.pending;
          current();
          if (pending === false && !stopping && !accountingFailed) {
            checked(Reflect.apply(complete, runtime, [token]));
            current();
          }
        }
        return result;
      } finally {preparing = false;}
    },
    release, retry: release, status: () => Object.freeze({pending: !retired}),
  });
}
