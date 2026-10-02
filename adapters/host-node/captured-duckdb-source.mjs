// Physical acquisition for a Host-authorized DuckDB source. The checked
// Program and MoonBit acquisition planner own the source request and query;
// this adapter supplies only the approved database grant and bounded I/O.
import {readFile} from 'node:fs/promises';
import {checked} from '../host-common/runtime-result.mjs';
import {acquisitionFailure, acquisitionOutcome} from '../host-common/acquisition-outcome.mjs';
import {ExecutionAuthorizationError} from
  '../host-common/authorization-gate.mjs';
import {authorizeLocalDatabase} from
  '../connectors/duckdb/node/session.mjs';
import {runNativeHostQuery, runBroadHostQuery,
  nativeSourceIdentityMatches, issueNativeSourceEvidence} from
  '../connectors/duckdb/node/host.mjs';

const contractRoot = new URL('../../spec/contracts/', import.meta.url);
const contractFiles = [
  'actql-query-acquisition.json',
  'actql-query-process-evidence.json',
  'actql-query-two-receipt.json',
];
const preparations = new WeakMap();

// Checked preparation for the Host's acquisition Checkpoint. It does not
// open the database or infer authority from the source CID. The returned
// handle can only be consumed with the same checked Program and Host profile.
export async function prepareCapturedDuckDBSource({moon, preparedProgram,
  preparedEffect,
  registry, values, fragment, ordered, database, schema, table,
  sourceAccess}) {
  if (typeof database !== 'string' || typeof schema !== 'string' ||
      typeof table !== 'string' || typeof registry !== 'string' ||
      typeof values !== 'string' || typeof fragment !== 'string' ||
      typeof ordered !== 'string' ||
      (preparedProgram === undefined) ===
        (preparedEffect === undefined)) {
    throw new TypeError('InvalidInstalledSourceConfiguration');
  }
  const effectful = preparedEffect !== undefined;
  const checkedOwner = preparedEffect ?? preparedProgram;
  // This installed profile has one captured source at the first task. The
  // owner rejects a different checked source rather than using file settings
  // as a substitute for the Program's source declaration.
  checked(effectful
    ? moon.clientProgramEffectPrepareQueryAcquisition(checkedOwner, 0, 0)
    : moon.clientProgramPrepareQueryAcquisition(checkedOwner, 0, 0));
  const requirement = checked(
    effectful
      ? moon.clientProgramEffectPrepareLocalQueryRequirement(checkedOwner,
        0, 0, registry, values, fragment, ordered)
      : moon.clientProgramPrepareLocalQueryRequirement(checkedOwner,
        0, 0, registry, values, fragment, ordered));
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
  const native = moon.clientProgramPrepareDuckDBAcquisition(
    requirement, schema, table, ...contracts);
  const broad = moon.clientProgramDuckDBNativeCandidateUnavailable(native);
  const acquisition = checked(broad
    ? moon.clientProgramPrepareDuckDBBroadAcquisition(
      requirement, schema, table, ...contracts) : native);
  // The Host-resolved physical target is part of what an approval covers:
  // the same checked source read from another schema or table is another
  // read. Physical names are bound by their exact UTF-8 bytes (hex): the
  // database distinguishes names that ActQL's logical text normalization
  // treats as equal. The readable names are display only.
  const exact = name => Buffer.from(name, 'utf8').toString('hex');
  const prepared = Object.freeze({checkedSource,
    readTuple: Object.freeze({connection: sourceAccess.connection ??
      'local-database', resource: sourceAccess.resource ?? database,
    operation: 'read'}),
    physicalBinding: Object.freeze({version:
      'actql-installed-duckdb-target/0.1', database, schema, table,
      utf8_hex: Object.freeze({database: exact(database),
        schema: exact(schema), table: exact(table)})})});
  preparations.set(prepared, Object.freeze({moon, checkedOwner, effectful, registry,
    values, fragment, ordered, database, schema, table, sourceAccess,
    requirement, evidenceContext, acquisition, broad}));
  return prepared;
}

// A failure states how the acquisition ended: nothing before the native read
// starts it (a denied read is decided before any session opens). Native/broad
// reads transfer physical session observations and unresolved recovery owners.
// A capture's successful close is required before reporting its stop.
export async function openCapturedDuckDBSource({moon, preparedProgram,
  preparedEffect,
  registry, values, fragment, ordered, database, schema, table,
  sourceAccess, transportLimits, signal, preparedSource,
  reportAcquisitionFailure}) {
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
  try {
    prepared = preparedSource ?? await prepareCapturedDuckDBSource({moon,
      preparedProgram, preparedEffect, registry, values, fragment, ordered,
      database, schema, table, sourceAccess});
    owner = preparations.get(prepared);
    const effectful = preparedEffect !== undefined;
    if (owner === undefined || owner.moon !== moon ||
        owner.checkedOwner !== (preparedEffect ?? preparedProgram) ||
        owner.effectful !== effectful ||
        owner.registry !== registry || owner.values !== values ||
        owner.fragment !== fragment || owner.ordered !== ordered ||
        owner.database !== database || owner.schema !== schema ||
        owner.table !== table || owner.sourceAccess !== sourceAccess) {
      throw new Error('InstalledSourcePreparationMismatch');
    }
    grant = await authorizeLocalDatabase(database, sourceAccess);
  } catch (cause) {
    failAcquisition(cause, 'not_started');
  }
  const {checkedSource} = prepared;
  const {requirement, evidenceContext, acquisition} = owner;
  let capture;
  try {
    const acquire = owner.broad ? runBroadHostQuery : runNativeHostQuery;
    capture = await acquire(grant, acquisition, transportLimits,
      signal);
  } catch (cause) {
    const ended = acquisitionOutcome(cause);
    failAcquisition(cause, cause instanceof
      ExecutionAuthorizationError ? 'not_started' : ended.outcome,
      ended.recovery);
  }
  try {
    const capturedSource = capture.source();
    if ((owner.effectful
      ? moon.clientProgramEffectCapturedSourceMatches(owner.checkedOwner,
        capturedSource)
      : moon.clientProgramCapturedSourceMatches(owner.checkedOwner,
        capturedSource)) !== true) {
      throw new Error('InstalledSourceProgramMismatch');
    }
    const identity = checked(owner.effectful
      ? moon.clientProgramIdentifyCapturedEffectSourceRelation(capturedSource)
      : moon.clientProgramIdentifyCapturedSourceRelation(capturedSource));
    if (!nativeSourceIdentityMatches(capture, identity)) {
      throw new Error('InstalledSourceObservationMismatch');
    }
    const logicalInput = checked(owner.effectful
      ? moon.clientProgramEffectIssueCapturedSourceLogical(owner.checkedOwner,
        capturedSource, identity, requirement)
      : moon.clientProgramIssueCapturedSourceLogical(owner.checkedOwner,
        capturedSource, identity, requirement));
    // An Effect Run is opened only after durable Run admission. Acquisition
    // cannot mint that owner or begin its computation as a read-only Run.
    const inferStep = owner.effectful ? undefined :
      moon.clientProgramSelectedInferStep(owner.checkedOwner);
    const setup = owner.effectful || inferStep !== undefined ? undefined :
      moon.clientProgramOpenCapturedLocalHost(owner.checkedOwner,
        capturedSource, registry, values, 1n, 0n, 0n, 0n,
        fragment, ordered);
    if (!owner.effectful && inferStep === undefined && setup === undefined) {
      throw new Error('InstalledSourceHostUnavailable');
    }
    return Object.freeze({capture, identity, logicalInput, requirement,
      checkedSource, setup, inferStep, capturedSource,
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
