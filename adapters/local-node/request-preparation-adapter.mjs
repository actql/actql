import resources from '../host-node/ordinary-node-resource-runtime.cjs';
import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeIsError,runtimeField} from '../host-common/compiler-binding.generated.mjs';
// Only fixed ClientClosedValuesPreparationIssue results reach this projection.
// The Common owner supplies immutable failure facts from its attempted phase;
// these amounts are diagnostic DATA, never caller options or a resource grant.
export function checkedPreparation(moon,result) {
  if(runtimeIsError(result)) {
    const issue=runtimeField(result,0);
    const value=moon.clientProgramPreparationCapacityRefusal(issue);
    if(value!==undefined) {
      const phase=runtimeField(value,0),dimension=runtimeField(value,1);
      const requiredR=runtimeField(value,2),requiredE=runtimeField(value,3);
      const availableR=runtimeField(value,4),availableE=runtimeField(value,5);
      if(typeof phase!=='string' || (dimension!=='retention' && dimension!=='execution') ||
          typeof requiredR!=='bigint' || typeof requiredE!=='bigint' ||
          typeof availableR!=='bigint' || typeof availableE!=='bigint') {
        throw Object.assign(new Error('InvalidHostRuntimeResult'),{code:'InvalidHostRuntimeResult'});
      }
      const capacity=Object.freeze({phase,dimension,
        requiredRetentionBytes:requiredR.toString(),requiredExecutionBytes:requiredE.toString(),
        availableRetentionBytes:availableR.toString(),availableExecutionBytes:availableE.toString()});
      const error=new Error('PreparationCapacityExceeded');
      error.cause=issue;
      error.code='PreparationCapacityExceeded';
      error.capacity=capacity;
      throw error;
    }
  }
  return checked(result);
}

// Fixed ordinary Local protocol adapter, not a second lease or numeric budget.
// The caller stores this same state before the first fallible constructor.
const noPhysicalChildren = () => false;
const invalid = () => {throw Object.assign(new Error('NodeLocalPreparationAdmissionUnavailable'),
  {code:'NodeLocalPreparationAdmissionUnavailable'});};
export function requestPreparationAvailable(context) {
  if(context===null || typeof context!=='object' || nodeTypes.isProxy(context)) return false;
  const own = (object,name) => {
    const field=Object.getOwnPropertyDescriptor(object,name);
    return field!==undefined && Object.hasOwn(field,'value') ? field.value : undefined;
  };
  const moon=own(context,'runtime');
  if(moon===null || typeof moon!=='object' || nodeTypes.isProxy(moon) ||
      own(context,'preparedEnvironment')===undefined ||
      typeof own(context,'retainedRelationOutput')!=='boolean') return false;
  const rowField=Object.getOwnPropertyDescriptor(context,'valuesMaxRows');
  if (rowField!==undefined && !Object.hasOwn(rowField,'value')) return false;
  const rows=rowField?.value;
  if (rows!==undefined && (!Number.isSafeInteger(rows) || rows<1 || rows>2147483647)) return false;
  return typeof own(moon,'clientProgramRequestPreparationControl')==='function' &&
    typeof own(moon,'clientProgramBeginRequestPreparation')==='function' &&
    typeof own(moon,'clientLocalPreparationResourceLimits')==='function' &&
    typeof own(moon,'clientProgramAbortRequestPreparation')==='function' &&
    typeof own(moon,'clientProgramPrepareRequestNativeComputation')==='function' &&
    typeof own(moon,'clientProgramPrepareRequestSourceComputation')==='function' &&
    typeof own(moon,'clientProgramFinishRequestComputation')==='function' &&
    typeof own(moon,'clientProgramPrepareRequestPolicySubjects')==='function' &&
    typeof own(moon,'clientProgramReadRequestPolicySubject')==='function' &&
    typeof own(moon,'clientProgramBindRequestPolicySubject')==='function' &&
    typeof own(moon,'clientProgramFinishRequestPolicySubjects')==='function' &&
    typeof own(moon,'clientProgramPrepareRequestProgramModuleBody')==='function' &&
    typeof own(moon,'clientProgramRequestProgramModuleIssueCode')==='function' &&
    typeof own(moon,'clientProgramBorrowRequestProgramPlanInput')==='function' &&
    typeof own(moon,'clientProgramAcquisitionCount')==='function' &&
    typeof own(moon,'clientProgramAdoptRequestProgramPreparation')==='function' &&
    typeof own(moon,'clientProgramReserveRequestSnapshot')==='function';
}

// Fixed supplier precondition before receipt/state/native Root construction.
// This control quote grants no body bytes and observes no caller input.
export function assertRequestPreparationControl(context) {
  const moon=context.runtime;
  const control=moon.clientProgramRequestPreparationControl(moon.clientLocalResourcePolicyOriginal());
  if(!Array.isArray(control) || control.length!==2 || typeof control[0]!=='bigint' ||
      control[0]<=0n || control[1]!==0n) invalid();
}

// The existing actual Resource/initial admission entrance. It needs no Source
// environment, local-connection label or checked Program. The caller MUST
// retain this same state before entry and supply its original current/physical
// child observation; a profile or cleanup registry is not admitted backing.
// Both existing Request callers use this exact opening, never a second owner.
function openPreparationAdmission(state, moon, input, assertCurrent, childrenPending) {
    const policy=moon.clientLocalResourcePolicyOriginal();
    const limits=moon.clientLocalPreparationResourceLimits(policy);
    if (!Array.isArray(limits) || limits.length!==6 ||
        limits.some(value => typeof value!=='bigint' || value<0n || value>9223372036854775807n) ||
        limits.slice(0,3).some(value => value>2147483647n)) invalid();
    // The original policy's immutable DATA selects the existing initial
    // supplier. No Source installation, caller estimate or second quote is
    // needed before that supplier owns the first constructor.
    const requirements=Object.freeze({planningWork:Number(limits[0]),attempts:Number(limits[1]),
      holdings:Number(limits[2]),transferBytes:limits[3],retainedBytes:limits[4],executionBytes:limits[5]});
    state.original=resources.retainOrdinaryManagedRun(input,requirements,
      assertCurrent,childrenPending,'local-preparation');
    state.admission=checked(moon.clientProgramPrepareLocalPreparationAdmission(state.original,input));
  return policy;
}

export function openRequestPreparation(state, input, assertCurrent, childrenPending) {
  if (state.opening || state.original!==undefined || state.admission!==undefined ||
      state.parent!==undefined ||
      typeof assertCurrent!=='function' || typeof childrenPending!=='function') invalid();
  const moon=state.context.runtime;
  state.opening=true;
  try {
    const policy=openPreparationAdmission(state,moon,input,assertCurrent,childrenPending);
    state.parent=checked(moon.clientProgramBeginRequestPreparation(state.admission,input,
      policy));
    return state.parent;
  } finally {state.opening=false;}
}

// SAME actual Host initialization owner, independent of late Environment and
// sequence contracts. The fixed caller retains state before this entrance.
export function openHostInitializationPreparation(state, moon, input, assertCurrent, childrenPending) {
  if (state.opening || state.original!==undefined || state.admission!==undefined ||
      state.parent!==undefined || state.runtime!==undefined ||
      typeof assertCurrent!=='function' || typeof childrenPending!=='function') invalid();
  state.runtime=moon;
  state.opening=true;
  try {
    const policy=openPreparationAdmission(state,moon,input,assertCurrent,childrenPending);
    state.parent=checked(moon.clientProgramBeginHostInitializationPreparation(state.admission,input,policy));
    return state.parent;
  } finally {state.opening=false;}
}

// Caller has retired its SAME Source material and physical children first.
// A failed/uncertain original remains owned; no status/Promise is made an ACK.
export function closeHostInitializationPreparation(state) {
  if (state.opening) invalid();
  const moon=state.runtime;
  if (state.parent!==undefined) {
    checked(moon.clientProgramCloseHostInitializationPreparation(state.parent));
    state.parent=state.admission=undefined;
  } else if (state.admission!==undefined) {
    checked(moon.clientProgramCleanupLocalPreparationAdmission(state.admission));
    state.admission=undefined;
  }
  if (state.original!==undefined && !resources.ordinaryManagedRunStatus(state.original).stopped) invalid();
  state.original=state.runtime=undefined;
}

// General Request admission observes no caller options, Parameters or source.
// Actual SDK capture below grows this same parent before its detached data.
export function beginRequestInput(state, receipt, connection, assertCurrent, childrenPending = noPhysicalChildren) {
  const moon=state.context.runtime;
  if(typeof moon.clientProgramReserveRequestSnapshot!=='function') invalid();
  if (!Object.isFrozen(connection) || !['local', 'remote'].includes(connection.mode) ||
      connection.owner !== connection.mode || !Array.isArray(connection.consentRefs) ||
      !Array.isArray(connection.runners)) return false;
  openRequestPreparation(state,receipt,assertCurrent,childrenPending);
  return true;
}

export function cleanupRequestInput(state, retireInitialPreparation) {
  if(state.opening || state.adopting || state.snapshotting || state.preparing) invalid();
  const moon=state.context.runtime;
  const borrow = state.effectBorrowMethods;
  if(state.compilationKind==='effectful' && state.holder!==undefined && borrow===undefined) invalid();
  const retirementStarted = holder => borrow===undefined
    ? moon.clientProgramPreparationBorrowRetirementStarted(holder)
    : borrow.clientProgramEffectPreparationInputRetirementStarted(holder);
  if((state.holder!==undefined || state.inventoryHolder!==undefined) && state.parent!==undefined) {
    // The same generic Request retains failed construction and every borrow.
    // Only the original retirement phase permits the selected holder return.
    try {checked(moon.clientProgramAbortRequestPreparation(state.parent));}
    catch(cause) {
      if([state.holder,state.inventoryHolder].some(holder => holder!==undefined && retirementStarted(holder)!==true)) throw cause;
    }
    if([state.holder,state.inventoryHolder].some(holder => holder!==undefined && retirementStarted(holder)!==true)) invalid();
    if(state.prepared!==undefined) {
      if(typeof retireInitialPreparation!=='function') invalid();
      retireInitialPreparation(state.prepared);
    }
    if (state.contentPreparation !== undefined) {
      const original = state.contentPreparation;
      Reflect.apply(original.releaseAliases, original, [undefined, state.holder]);
      state.contentPreparation = undefined;
      state.contentPlan = state.contentCompilation = state.contentGraph = undefined;
    }
    state.prepared=state.parametersCursor=undefined;
    // A failed family selection handoff can retain its original inventory
    // borrower as well. Core consumes each holder before attempting owner
    // settlement; false is a live owner, and settlement failure retains the
    // parent duty without making the consumed token returnable again.
    for(const field of ['inventoryHolder','holder']) {
      const holder=state[field];
      if(holder===undefined) continue;
      state[field]=undefined;
      checked(borrow===undefined ? moon.clientProgramPreparationBorrowReturn(holder)
        : borrow.clientProgramEffectPreparationInputReturn(holder));
    }
  }
  if(state.parent!==undefined) {
    checked(moon.clientProgramAbortRequestPreparation(state.parent));
    state.parent=state.admission=undefined;
  } else if(state.admission!==undefined) {
    checked(moon.clientProgramCleanupLocalPreparationAdmission(state.admission));
    state.admission=undefined;
  }
  // Clear only after the original stop is confirmed. No caller snapshot is
  // revoked, and no local Promise completion stands in for physical cleanup.
  if(state.original!==undefined && !resources.ordinaryManagedRunStatus(state.original).stopped) invalid();
  state.original=state.prepared=state.snapshot=state.snapshotDocument=undefined;
  state.parametersCursor=state.compilationKind=state.preparationFailure=undefined;
  state.compilationFamily=undefined;
  state.modelCompilation=state.modelGraph=state.modelPlan=state.modelProviderBinding=state.contentPlan=state.contentCompilation=state.contentGraph=undefined;
  state.capturePlan=state.acquisitionCount=undefined;
  state.policyVerifier=state.policySignal=undefined;state.policyVerifierSelected=false;
  state.parameterMetadataLoaded=false;state.preparationFailed=false;
}
