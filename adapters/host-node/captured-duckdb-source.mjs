// Physical acquisition for a Host-authorized DuckDB source. The checked
// Program and MoonBit acquisition planner own the source request and query;
// this adapter supplies only the approved database grant and bounded I/O.
import {readFile} from 'node:fs/promises';
import {duckDBPhysicalTarget} from './duckdb-physical-target.mjs';
import {validateLimits} from '../connectors/duckdb/node/configuration.mjs';
import {checkDuckDBAcquisitionPlanning, freezeAcquisitionDiagnostic, selectInstalledDuckDBAcquisition} from '../connectors/duckdb/node/acquisition-planning.mjs';
import {computePhysicalCapacity} from '../connectors/duckdb/node/physical-capacity.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {acquisitionFailure, acquisitionOutcome} from '../host-common/acquisition-outcome.mjs';
import {ExecutionAuthorizationError} from
  '../host-common/authorization-gate.mjs';
import {authorizeLocalDatabase} from
  '../connectors/duckdb/node/session.mjs';
import {runNativeHostQuery, runBroadHostQuery, runStrategyNativeHostQuery,
  nativeSourceIdentityMatches, issueNativeSourceEvidence} from
  '../connectors/duckdb/node/host.mjs';

const contractRoot = new URL('../../spec/contracts/', import.meta.url);
const contractFiles = [
  'actql-query-acquisition.json',
  'actql-query-process-evidence.json',
  'actql-query-two-receipt.json',
];
const preparations = new WeakMap();
const transportLimitKeys = Object.freeze(['maxRows', 'maxCells', 'maxTransportBytes',
  'maxSqlBytes', 'maxParameters', 'maxColumns', 'memoryBytes', 'threads',
  'cancelWaitMs', 'maxChunkRows', 'maxChunkBytes']);
function admittedTransportPolicy(limits) {
  const validated = validateLimits(limits);
  computePhysicalCapacity(validated);
  return Object.freeze(Object.fromEntries(transportLimitKeys.map(key => [key, validated[key]])));
}

// This pure authorization check precedes comparison. The provider still
// checks the current gate again immediately before opening its read session.
async function currentReadDecision(database, access, signal) {
  if (typeof access?.authorization?.authorize !== 'function') {
    return {action: 'deny', basis: 'account', reason: 'configuration_missing'};
  }
  return access.authorization.authorize('acquisition', {
    connection: access.connection ?? 'local-database',
    resource: access.resource ?? database, operation: 'read',
  }, {subjectCid: access.subjectCid, signal});
}

function selectAcquisition(inputs) {
  const chosen = selectInstalledDuckDBAcquisition(inputs);
  if (chosen.native === undefined && chosen.broad === undefined) {
    const code = chosen.selection.status === 'deferred'
      ? 'InstalledSourceSelectionDeferred' : 'InstalledSourceNoEligibleCandidate';
    throw Object.assign(new Error(code), {code, selection: chosen.selection});
  }
  return {acquisition: chosen.native ?? chosen.broad,
    broad: chosen.native === undefined, selection: chosen.selection};
}

// Checked preparation for the Host's acquisition Checkpoint. It does not
// open the database or infer authority from the source CID. The returned
// handle can only be consumed with the same checked Program and Host profile.
export async function prepareCapturedDuckDBSource({moon, preparedProgram,
  preparedEffect,
  registry, values, fragment, ordered, database, schema, table,
  sourceAccess, transportLimits, acquisitionPlanning, occurrence = {stage: 0, input: 0, task: 0}}) {
  if (typeof database !== 'string' || typeof schema !== 'string' ||
      typeof table !== 'string' || typeof registry !== 'string' ||
      typeof values !== 'string' || typeof fragment !== 'string' ||
      typeof ordered !== 'string' ||
      (preparedProgram === undefined) ===
        (preparedEffect === undefined)) {
    throw new TypeError('InvalidInstalledSourceConfiguration');
  }
  if (![occurrence.stage, occurrence.input, occurrence.task].every(Number.isSafeInteger) ||
      occurrence.stage < 0 || occurrence.input !== 0 || occurrence.task !== occurrence.stage ||
      occurrence.task > 1) throw new TypeError('InvalidAcquisitionOccurrence');
  const effectful = preparedEffect !== undefined;
  const checkedOwner = preparedEffect ?? preparedProgram;
  // This installed profile has one captured source at the first task. The
  // owner rejects a different checked source rather than using file settings
  // as a substitute for the Program's source declaration.
  checked(effectful
    ? moon.clientProgramEffectPrepareQueryAcquisition(checkedOwner, occurrence.stage, occurrence.input)
    : moon.clientProgramPrepareQueryAcquisition(checkedOwner, occurrence.stage, occurrence.input));
  const requirement = checked(
    effectful
      ? moon.clientProgramEffectPrepareLocalQueryRequirement(checkedOwner,
        occurrence.stage, occurrence.input, registry, values, fragment, ordered)
      : moon.clientProgramPrepareLocalQueryRequirement(checkedOwner,
        occurrence.stage, occurrence.input, registry, values, fragment, ordered));
  const sourceFacts = checked(
    moon.clientProgramQueryRequirementSourceEvidenceFacts(requirement));
  if (!Array.isArray(sourceFacts) || sourceFacts.length !== 6 ||
      !sourceFacts.every(value => typeof value === 'string')) {
    throw new Error('InstalledSourceEvidenceFactsUnavailable');
  }
  const [sourceRef, sourceContractCid, carrierSchemaContractCid,
    sourceDataPolicyCid, dataClassification, sourceViewContractCid] =
    sourceFacts;
  if (sourceRef !== sourceAccess?.sourceRef) {
    throw new Error('InstalledSourceProgramMismatch');
  }
  const checkedSource = Object.freeze({
    requirementCid: moon.clientProgramQueryRequirementCid(requirement),
    sourceRef, sourceContractCid, carrierSchemaContractCid,
    sourceDataPolicyCid, dataClassification, sourceViewContractCid,
    inputContractCid:
      moon.clientProgramQueryRequirementInputContractCid(requirement),
    outputContractCid:
      moon.clientProgramQueryRequirementOutputContractCid(requirement),
  });
  const evidenceContext = checked(
    moon.clientProgramPrepareDuckDBSourceEvidenceContext(requirement));
  const contracts = await Promise.all(contractFiles.map(name =>
    readFile(new URL(name, contractRoot), 'utf8')));
  // Mandatory physical limits are actual Host policy, independent of all
  // optional cost/quantity evidence. Validate them before any comparison.
  const admittedLimits = admittedTransportPolicy(transportLimits);
  const single = effectful || moon.clientProgramAcquisitionCount(checkedOwner) === 1;
  const planning = acquisitionPlanning === undefined ? undefined
    : checkDuckDBAcquisitionPlanning(acquisitionPlanning);
  const selectionInputs = {moon, requirement, schema, table, contracts,
    source: {database, schema, table, sourceRef}, planning};
  let acquisition, broad = false, selection;
  if (single) {
    const decision = await currentReadDecision(database, sourceAccess);
    if (decision.action === 'dispatch') {
      ({acquisition, broad, selection} = selectAcquisition(selectionInputs));
    } else if (decision.action === 'deny') {
      throw new ExecutionAuthorizationError(decision);
    }
    // A delegated/held read has no execution authority yet. Its existing
    // Checkpoint owner handles approval; comparison waits for resumed access.
  } else {
    // The separately bounded plural-Native path keeps its existing
    // sole-candidate preparation and custody. No made-up cost remains.
    const native = moon.clientProgramPrepareDuckDBAcquisition(
      requirement, schema, table, ...contracts);
    broad = moon.clientProgramDuckDBNativeCandidateUnavailable(native);
    acquisition = checked(broad
      ? moon.clientProgramPrepareDuckDBBroadAcquisition(
        requirement, schema, table, ...contracts) : native);
  }
  // The Host-resolved physical target is part of what an approval covers:
  // the same checked source read from another schema or table is another
  // read. Physical names are bound by their exact UTF-8 bytes (hex): the
  // database distinguishes names that ActQL's logical text normalization
  // treats as equal. The readable names are display only.
  const prepared = Object.freeze({checkedSource, selection,
    occurrence: Object.freeze({...occurrence}),
    readTuple: Object.freeze({connection: sourceAccess.connection ??
      'local-database', resource: sourceAccess.resource ?? database,
    operation: 'read'}),
    physicalBinding: duckDBPhysicalTarget({database, schema, table})});
  preparations.set(prepared, Object.freeze({moon, checkedOwner, effectful, registry,
    values, fragment, ordered, database, schema, table, sourceAccess,
    requirement, evidenceContext, acquisition, broad, selection, single, selectionInputs,
    transportLimits: admittedLimits, acquisitionPlanning, occurrence: prepared.occurrence}));
  return prepared;
}

// A failure states how the acquisition ended: nothing before the native read
// starts it (a denied read is decided before any session opens). Native/broad
// reads transfer physical session observations and unresolved recovery owners.
// A capture's successful close is required before reporting its stop.
export async function openCapturedDuckDBSource({moon, preparedProgram,
  preparedEffect,
  registry, values, fragment, ordered, database, schema, table,
  sourceAccess, transportLimits, acquisitionPlanning, signal, preparedSource,
  reportAcquisitionFailure, occurrence = {stage: 0, input: 0, task: 0}, ledger}) {
  if (reportAcquisitionFailure !== undefined &&
      typeof reportAcquisitionFailure !== 'function') {
    throw new TypeError('InvalidAcquisitionEndReceiver');
  }
  const failAcquisition = (cause, outcome, recovery) => {
    const failure = acquisitionFailure(cause, outcome, recovery);
    reportAcquisitionFailure?.(failure);
    throw failure;
  };
  let owner;
  let prepared;
  let grant;
  let authorizedSelection;
  try {
    prepared = preparedSource ?? await prepareCapturedDuckDBSource({moon,
      preparedProgram, preparedEffect, registry, values, fragment, ordered,
      database, schema, table, sourceAccess, transportLimits, acquisitionPlanning, occurrence});
    owner = preparations.get(prepared);
    const effectful = preparedEffect !== undefined;
    if (owner === undefined || owner.moon !== moon ||
        owner.checkedOwner !== (preparedEffect ?? preparedProgram) ||
        owner.effectful !== effectful ||
        owner.occurrence.stage !== occurrence.stage ||
        owner.occurrence.input !== occurrence.input ||
        owner.occurrence.task !== occurrence.task ||
        owner.registry !== registry || owner.values !== values ||
        owner.fragment !== fragment || owner.ordered !== ordered ||
        owner.database !== database || owner.schema !== schema ||
        owner.table !== table || owner.sourceAccess !== sourceAccess ||
        owner.acquisitionPlanning !== acquisitionPlanning) {
      throw new Error('InstalledSourcePreparationMismatch');
    }
    const currentLimits = admittedTransportPolicy(transportLimits);
    if (transportLimitKeys.some(key => currentLimits[key] !== owner.transportLimits[key])) {
      throw new Error('InstalledSourceResourcePolicyMismatch');
    }
    if (owner.single) {
      const decision = await currentReadDecision(database, sourceAccess, signal);
      if (decision.action !== 'dispatch') throw new ExecutionAuthorizationError(decision);
      if (owner.acquisition === undefined) {
        authorizedSelection = selectAcquisition(owner.selectionInputs);
      }
    }
    grant = await authorizeLocalDatabase(database, sourceAccess);
  } catch (cause) {
    failAcquisition(cause, 'not_started');
  }
  const {checkedSource} = prepared;
  const {requirement, evidenceContext} = owner;
  const {acquisition, broad, selection} = authorizedSelection ?? owner;
  let capture;
  try {
    capture = broad
      ? await runBroadHostQuery(grant, acquisition, owner.transportLimits,
        signal, moon, ledger)
      : ledger === undefined
        ? await runNativeHostQuery(grant, acquisition, owner.transportLimits, signal)
        : await runStrategyNativeHostQuery(grant, acquisition, ledger,
          owner.transportLimits, signal);
  } catch (cause) {
    const ended = acquisitionOutcome(cause);
    failAcquisition(cause, cause instanceof
      ExecutionAuthorizationError ? 'not_started' : ended.outcome,
      ended.recovery);
  }
  try {
    const capturedSource = capture.source();
    if ((owner.effectful
      ? (owner.occurrence.task === 0
        ? moon.clientProgramEffectCapturedSourceMatches(owner.checkedOwner, capturedSource)
        : moon.clientProgramEffectCapturedSourceMatchesAt(owner.checkedOwner,
          capturedSource, owner.occurrence.task))
      : moon.clientProgramCapturedTaskSourceMatches(owner.checkedOwner,
        capturedSource, owner.occurrence.task)) !== true) {
      throw new Error('InstalledSourceProgramMismatch');
    }
    const identity = checked(owner.effectful
      ? moon.clientProgramIdentifyCapturedEffectSourceRelation(capturedSource)
      : moon.clientProgramIdentifyCapturedSourceRelation(capturedSource));
    if (!nativeSourceIdentityMatches(capture, identity)) {
      throw new Error('InstalledSourceObservationMismatch');
    }
    const logicalInput = checked(owner.effectful
      ? (owner.occurrence.task === 0
        ? moon.clientProgramEffectIssueCapturedSourceLogical(owner.checkedOwner,
          capturedSource, identity, requirement)
        : moon.clientProgramEffectIssueCapturedSourceLogicalAt(owner.checkedOwner,
          capturedSource, identity, requirement, owner.occurrence.task))
      : moon.clientProgramIssueCapturedTaskSourceLogical(owner.checkedOwner,
        capturedSource, identity, requirement, owner.occurrence.task));
    // An Effect Run is opened only after durable Run admission. Acquisition
    // cannot mint that owner or begin its computation as a read-only Run.
    const inferStep = owner.effectful || ledger !== undefined ? undefined :
      moon.clientProgramSelectedInferStep(owner.checkedOwner);
    const setup = owner.effectful || ledger !== undefined ||
      inferStep !== undefined ? undefined :
      moon.clientProgramOpenCapturedLocalHost(owner.checkedOwner,
        capturedSource, registry, values, 1n, 0n, 0n, 0n,
        fragment, ordered);
    if (!owner.effectful && ledger === undefined &&
        inferStep === undefined && setup === undefined) {
      throw new Error('InstalledSourceHostUnavailable');
    }
    return Object.freeze({capture, identity, logicalInput, requirement,
      checkedSource, setup, inferStep, capturedSource,
      occurrence: owner.occurrence,
      acquisition: selection === undefined ? undefined : freezeAcquisitionDiagnostic({
        selection, observation: JSON.parse(capture.document())}),
      issueSourceEvidence: options => issueNativeSourceEvidence(capture,
        {...options, context: evidenceContext, identity, logicalInput}),
      close: () => capture.close()});
  } catch (cause) {
    try { await capture.close(); }
    catch (cleanup) {
      let pending = true;
      const recovery = Object.freeze({
        close() {},
        async cleanup() { await capture.close(); pending = false; return true; },
        cleanupPending: () => pending,
      });
      const failure = Object.assign(new Error(cause?.message ?? 'AcquisitionFailed', {cause}), {
        code: cause?.code, primaryFailure: cause,
        cleanupErrors: Object.freeze([cleanup]),
      });
      failAcquisition(failure, 'unknown', recovery);
    }
    failAcquisition(cause, 'stopped');
  }
}

// The checked native preparation contributes its already-admitted capacity to
// the one Run ledger before any source starts. Foreign/closed handles cannot
// manufacture a configuration or bypass the occurrence owner.
export function capturedDuckDBNativeConfiguration(prepared) {
  const owner = preparations.get(prepared);
  if (owner === undefined || owner.broad || owner.acquisition === undefined) {
    throw new TypeError('InstalledMultiSourceNativeAcquisitionRequired');
  }
  return owner.acquisition;
}

// Keep the selected configuration's typed owner. Broad remains Broad, with
// the existing Client/Local residual represented in capacity admission.
export function capturedDuckDBConfiguration(prepared) {
  const owner = preparations.get(prepared);
  if (owner === undefined) {
    throw new TypeError('InstalledSourcePreparationMismatch');
  }
  if (owner.acquisition === undefined) {
    throw new TypeError('InstalledSourceSelectionRequired');
  }
  return (owner.broad ? owner.moon.clientProgramCapturedBroadConfiguration
    : owner.moon.clientProgramCapturedNativeConfiguration)(owner.acquisition);
}

export function capturedDuckDBPhysicalCapacity(prepared) {
  const owner = preparations.get(prepared);
  if (owner === undefined || owner.transportLimits === undefined) {
    throw new TypeError('InstalledSourcePreparationMismatch');
  }
  return computePhysicalCapacity(owner.transportLimits);
}
