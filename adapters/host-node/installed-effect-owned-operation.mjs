// The same installed Effect occurrence backs an already-owned physical child.
// Its request/Content owner keeps physical cleanup; this adapter never issues a
// grant, substitutes a writer, closes it twice, or creates a Resource root.
import {checked} from '../host-common/runtime-result.mjs';
const fail = code => {throw Object.assign(new Error(code), {code});};

export function prepareInstalledEffectOwnedPhysicalChild({run, memberIndex, rowIndex,
  operationIndex, operation, transferBytes, invoke, requestsRetired}) {
  if (run === undefined || typeof invoke !== 'function' || typeof requestsRetired !== 'function' ||
      typeof transferBytes !== 'bigint' || transferBytes < 0n) fail('InvalidInstalledEffectOwnedOperation');
  const {runtime, value: parent, prepared, request, operationPlan: plan, readPlan} = run;
  const select = runtime?.clientProgramInstalledEffectManagedPlanOperation;
  const physical = runtime?.clientProgramInstalledEffectOperationExtentPhysical;
  const transfer = runtime?.clientProgramInstalledEffectOperationExtentTransfer;
  const borrow = runtime?.clientProgramInstalledEffectOperationBorrow;
  const start = runtime?.clientProgramInstalledEffectOperationStart;
  const charge = runtime?.clientProgramInstalledEffectOperationCharge;
  const retire = runtime?.clientProgramInstalledEffectOperationRetire;
  if (![select, physical, transfer, borrow, start, charge, retire, readPlan]
      .every(method => typeof method === 'function')) fail('InstalledEffectOperationRuntimeUnavailable');
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
  let attempted = false, preparing = false, stopping = false, retired = false, started = false;
  let child, status, accountingFailed = false;
  const retainPhysicalChild = original => {
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
  const chargeBytes = bytes => {
    current();
    if (!preparing || stopping || !started || typeof bytes !== 'bigint' || bytes < 0n) {
      fail('ForeignInstalledEffectPhysicalChild');
    }
    try {checked(Reflect.apply(charge, runtime, [token, bytes])); current();}
    catch (error) {accountingFailed = true; throw error;}
  };
  const release = () => {
    if (retired) return true;
    stopping = true;
    if (preparing || accountingFailed) return false;
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
  };
  return Object.freeze({
    async prepare() {
      if (attempted || stopping) fail('InstalledEffectOperationAlreadyPrepared');
      attempted = true; preparing = true;
      try {
        current();
        const result = await invoke(Object.freeze({retainPhysicalChild, chargeBytes}));
        current();
        if (!started) fail('InstalledEffectPhysicalChildUnavailable');
        return result;
      } finally {preparing = false;}
    },
    release, retry: release, status: () => Object.freeze({pending: !retired}),
  });
}
