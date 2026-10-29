import resources from '../host-node/ordinary-node-resource-runtime.cjs';
import {types as nodeTypes} from 'node:util';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeIsError,runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {probeClosedValuesOwnDataHeader,closedValuesOwnDataHeaderFields,
  closedValuesOwnDataHeaderRows,scanClosedValuesOwnData,scanClosedValuesOwnDataAscii}
  from '../host-node/closed-values-own-data-scan.mjs';

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
const commonInt = value => {
  if (!Number.isSafeInteger(value) || value < 0 || value > 2147483647) invalid();
  return value;
};
const phaseAdapter = (moon, token) => ({spendWork(amount) {
  checked(moon.clientProgramSpendPreparationPhaseWork(token, amount));
}});

export function closedValuesPreparationAvailable(context) {
  if(context===null || typeof context!=='object' || nodeTypes.isProxy(context)) return false;
  const own = (object,name) => {
    const field=Object.getOwnPropertyDescriptor(object,name);
    return field!==undefined && Object.hasOwn(field,'value') ? field.value : undefined;
  };
  const moon=own(context,'runtime');
  if(moon===null || typeof moon!=='object' || nodeTypes.isProxy(moon) ||
      own(context,'preparedEnvironment')===undefined ||
      typeof own(context,'retainedRelationOutput')!=='boolean') return false;
  return typeof own(moon,'clientProgramRequestPreparationControl')==='function' &&
    typeof own(moon,'clientProgramBeginRequestPreparation')==='function' &&
    typeof own(moon,'clientProgramSelectClosedValuesPreparation')==='function' &&
    typeof own(moon,'clientProgramAbortRequestPreparation')==='function' &&
    typeof own(moon,'clientProgramPrepareClosedValuesModuleBody')==='function' &&
    typeof own(moon,'clientProgramCompleteClosedValuesBody')==='function' &&
    typeof own(moon,'clientProgramAdoptClosedValuesPreparation')==='function' &&
    typeof own(moon,'clientProgramReserveClosedValuesSnapshot')==='function';
}

// Fixed supplier precondition before receipt/state/native Root construction.
// This control quote grants no body bytes and observes no caller input.
export function assertRequestPreparationControl(context) {
  const moon=context.runtime;
  const control=moon.clientProgramRequestPreparationControl(moon.clientLocalResourcePolicyOriginal());
  if(!Array.isArray(control) || control.length!==2 || typeof control[0]!=='bigint' ||
      control[0]<=0n || control[1]!==0n) invalid();
}

// General Request admission observes no caller options, Parameters or source.
// Actual SDK capture below grows this same parent before its detached data.
export function beginRequestInput(state, receipt, connection, requirements, assertCurrent) {
  const moon=state.context.runtime;
  if(typeof moon.clientProgramReserveRequestSnapshot!=='function') invalid();
  if (!Object.isFrozen(connection) || connection.mode !== 'local' ||
      connection.owner !== 'local' || !Array.isArray(connection.consentRefs) ||
      !Array.isArray(connection.runners)) return false;
  state.original=resources.retainOrdinaryManagedRun(receipt,requirements,
    assertCurrent,noPhysicalChildren,'local-preparation');
  state.admission=checked(moon.clientProgramPrepareLocalPreparationAdmission(state.original,receipt));
  state.parent=checked(moon.clientProgramBeginRequestPreparation(state.admission,receipt,
    moon.clientLocalResourcePolicyOriginal()));
  return true;
}

export function beginClosedValuesInput(state, input, receipt, connection, requirements, assertCurrent) {
  const moon=state.context.runtime;
  // This is the already frozen SDK connection of THIS call, not the first
  // connection that happened to open a shared installed Host.
  if (!Object.isFrozen(connection) || connection.mode !== 'local' ||
      connection.owner !== 'local' || !Array.isArray(connection.consentRefs) ||
      !Array.isArray(connection.runners) || connection.runners.length !== 0) return false;
  state.original=resources.retainOrdinaryManagedRun(receipt,requirements,
    assertCurrent,noPhysicalChildren,'local-preparation');
  state.admission=checked(moon.clientProgramPrepareLocalPreparationAdmission(state.original,receipt));
  state.parent=checked(moon.clientProgramBeginRequestPreparation(state.admission,receipt,
    moon.clientLocalResourcePolicyOriginal()));
  // Store the same-reservation successor before cutting its consumed parent.
  state.phase=checked(moon.clientProgramSelectClosedValuesPreparation(state.parent,receipt));
  state.parent=undefined;
  const headerWork=checkedPreparation(moon,moon.clientProgramBeginClosedValuesHeader(state.phase));
  const header=probeClosedValuesOwnDataHeader(input,undefined,phaseAdapter(moon,headerWork));
  if(header===undefined){cleanupClosedValuesInput(state);return false;}
  const work=checkedPreparation(moon,moon.clientProgramBeginClosedValuesScan(state.phase,
    commonInt(closedValuesOwnDataHeaderFields(header,input)),commonInt(closedValuesOwnDataHeaderRows(header,input))));
  const facts=scanClosedValuesOwnData(input,undefined,phaseAdapter(moon,work),header);
  if(facts===undefined){cleanupClosedValuesInput(state);return false;}
  checkedPreparation(moon,moon.clientProgramFinishClosedValuesScan(state.phase));
  const textWork=checkedPreparation(moon,moon.clientProgramBeginClosedValuesTextCheck(state.phase,commonInt(facts.quotedUtf16Units)));
  const eligible=scanClosedValuesOwnDataAscii(input,undefined,phaseAdapter(moon,textWork));
  if(eligible===undefined){cleanupClosedValuesInput(state);return false;}
  checkedPreparation(moon,moon.clientProgramFinishClosedValuesTextCheck(state.phase));
  // Avoid silent Int truncation at the JS/Common ABI. This is a real
  // representation boundary, not a language cardinality/profile ceiling.
  for(const key in eligible) if(!Number.isSafeInteger(eligible[key]) ||
      eligible[key]<0 || eligible[key]>2147483647) invalid();
  if(connection.consentRefs.length>2147483647) invalid();
  checkedPreparation(moon,moon.clientProgramReserveClosedValuesSnapshot(state.phase,
    eligible.inputBytesUpper,eligible.nodeUpper,eligible.objects,eligible.arrays,
    eligible.fieldsUpper,eligible.quotedTokens,eligible.quotedUtf16Units,
    eligible.longestQuotedUtf16,eligible.longestAtomUtf16,eligible.depthUpper,
    eligible.fieldCount,eligible.rowCount,connection.consentRefs.length));
  return true;
}

export function bindClosedValuesSnapshot(state, body) {
  if(state.phase===undefined || body.kind!=='program' || body.parameters!==null) invalid();
  // This single program-only document was included in the original snapshot
  // phase. Common retains it before any subsequent lexical/parser rejection.
  const document=JSON.stringify(body.input);
  checkedPreparation(state.context.runtime,state.context.runtime.clientProgramBindClosedValuesDocument(state.phase,document));
}

export function cleanupClosedValuesInput(state, retireInitialPreparation) {
  if(state.adopting || state.snapshotting) invalid();
  const moon=state.context.runtime;
  if(state.holder!==undefined) {
    try {checkedPreparation(moon,moon.clientProgramAbortClosedValuesPreparationAfterCleanup(state.phase));}
    catch(cause) {
      if(moon.clientProgramClosedValuesInitialRetirementStarted(state.phase,state.holder)!==true) throw cause;
    }
    if(moon.clientProgramClosedValuesInitialRetirementStarted(state.phase,state.holder)!==true) invalid();
    if(state.prepared!==undefined) {
      if(typeof retireInitialPreparation!=='function') invalid();
      retireInitialPreparation(state.prepared);
    }
    state.prepared=undefined;
    const holder=state.holder;state.holder=undefined;
    checked(moon.clientProgramPreparationBorrowReturn(holder));
  }
  if(state.phase!==undefined) {
    checkedPreparation(moon,moon.clientProgramAbortClosedValuesPreparationAfterCleanup(state.phase));
    state.phase=undefined;state.admission=undefined;
  } else if(state.parent!==undefined) {
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
}
