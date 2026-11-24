// Physical durable storage for an owner-issued Client request and Run ref.
// MoonBit supplies and re-admits the identity and decides intent conflicts.
import './host-journal-facility-fields.cjs';
import {createHash} from 'node:crypto';
import {existsSync, mkdirSync, realpathSync} from 'node:fs';
import {join} from 'node:path';
import {throwSqliteInitializationFailure} from
  '../host-common/sqlite-transaction.mjs';
import {captureOriginalLocalExecutionOwner, originalLocalExecutionOwnerStopped} from '../store-local/prepared-publication-store-ownership.mjs';
import {isHostObservationProjection, type installHostObservation} from '../host-common/observation.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import type {WireRunRef, WireSubmissionRef} from '../../packages/client-wire/index.js';
import {canonicalJson} from './local-account-config.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {clientSourceOperationStorage} from './client-source-operation.mjs';
import {fail, applyOriginal, operationDescriptors, operationKeys, guardJournalCurrentness,
  createJournalPrimaryConnection, createJournalObservationConnection, type JournalSqlConnection} from './client-request-journal-sql.mjs';
import {admission, admissionEvidenceShape, assertKeyedInventoryRequest, assertSourceInventory, checkedIdentity, checkedRunDefinition,
  cid, instant, logicalPlanOriginalShape, retainedIdentity, retainedRunDefinition, retainedRunFacts,
  createJournalKeyedLookupStorage, createJournalRunRecords, createJournalRunStart, createJournalRunObservations,
  admitJournalRunDefinitionRow, readJournalRunDefinitionRow, retainJournalRunStateFrame, sameRunStateRow,
  reinspectJournalRunAfterPhysicalClose, reinspectJournalRunForSigning, reinspectJournalRunStopAfterStatePublication,
  structuralExplanationOriginalShape, text, validateSourceInventory} from './client-request-journal-records.mjs';
import {explanationOriginalTable, explanationContextOriginalTable, admitJournalDirectory, syncDirectory, columns, selectColumns,
  snapshotJournalConfiguration, initializeJournalPrimaryStorage, readJournalExplanationOriginal, probeJournalExplanation, readJournalExplanation,
  insertJournalExplanationOriginal, verifyJournalExplanationContext,
  validLocalExecutionOwnerReceipt, assertJournalSubmissionCustody,
  assertJournalIntentCustody, assertJournalCancellationCustody} from './client-request-journal-format.mjs';
import {captureOriginalClientRequestJournalFacility} from './client-request-journal-facility.mjs';
import {createJournalAttempts, createJournalCancellation} from './client-request-journal-attempts.mjs';
import {createJournalSubmissionOriginals, createJournalSubmissionRows} from './client-request-journal-submission-originals.mjs';
export {validateSourceInventory};

type JournalCustody = Readonly<{
  journalClosed: boolean; databaseClosed: boolean; observationAttempted: boolean; observationDatabaseClosed: boolean;
}>;
type JournalOptions = NonNullable<Parameters<typeof snapshotJournalConfiguration>[1]>;
type JournalStatement = ReturnType<JournalSqlConnection['prepare']>;
type SqlArgument = Parameters<JournalStatement['get']>[number];
type Projection = NonNullable<ReturnType<typeof installHostObservation>>;
type RunRecords = ReturnType<typeof createJournalRunRecords>;
type RunAdmission = Parameters<RunRecords['acceptRecord']>[1];
type RequestControl = Parameters<RunRecords['acceptRecord']>[2];
type RequestKey = Parameters<RunRecords['lookupRecord']>[0];
type RequestReader = Parameters<RunRecords['lookupRecord']>[1];
type DefinitionControl = Parameters<typeof checkedRunDefinition>[1];
type RunDefinition = ReturnType<typeof checkedRunDefinition>;
type AdmissionEvidence = Parameters<typeof admissionEvidenceShape>[0];
type DefinitionAdmission = Omit<RunAdmission, 'runDefinitionCid' | 'runDefinitionWire' | 'runAdmissionEvidence'> &
  Readonly<{runDefinition: unknown; runAdmissionEvidence?: AdmissionEvidence;
    originalPlan?: unknown; originalExplanation?: unknown; originalInferRun?: unknown}>;
type AdmittedDefinition = Omit<ReturnType<RunRecords['acceptRecord']>, 'runDefinitionWire' | 'epochRejected'> &
  Readonly<{runDefinition: RunDefinition | undefined}>;
type AdmissionPublication = DefinitionControl & Readonly<{
  originalRunPlanAdmissionEvidence?(original: unknown, definition: RunDefinition, programCid: unknown, evidence: AdmissionEvidence): unknown;
  originalRunExplanationAdmissionEvidence?(original: unknown, definition: RunDefinition, programCid: unknown, evidence: AdmissionEvidence): unknown;
  originalRunExplanationAdmissionAcknowledged?(original: unknown, definition: RunDefinition, programCid: unknown,
    evidence: AdmissionEvidence): SynchronousRuntimeData;
  originalInferRunAdmissionEvidence?(original: unknown, definition: RunDefinition, identity: unknown, evidence: AdmissionEvidence): unknown;
}>;
type IssuedDefinition = Partial<RunDefinition> & Readonly<{
  runDefinition?: unknown; runAdmissionEvidence?: Readonly<Record<string, unknown>>;
  originalPlan?: unknown; originalExplanation?: unknown; originalInferRun?: unknown; resultNames?: unknown;
}>;
type IssueDefinitionOptions = Pick<RunAdmission, 'namespaceId' | 'lookupExpiresAt' | 'resultNames' | 'submission'> &
  Readonly<{sourceInventory?: string; issueDefinition(): IssuedDefinition | Promise<IssuedDefinition>}>;
type RunFrame = ReturnType<typeof admitJournalRunDefinitionRow>;
type ReadmittedRunFacts = ReturnType<typeof retainedRunFacts>;
type RequestScope = Readonly<{namespaceId: unknown}>;
type StopRequestControl = RequestControl & Parameters<SubmissionRows['retainedIntentOriginal']>[1] & Readonly<{
  clientSubmittedIntentRequestsCommitStop(intent: unknown): unknown;
  clientSubmittedIntentRequestsReadOnly(intent: unknown): unknown;
}>;
type SubmissionRows = ReturnType<typeof createJournalSubmissionRows>;
type SubmissionMethods = SubmissionRows['methods'];
type Attempts = ReturnType<typeof createJournalAttempts>;
type AttemptOptions = Parameters<Attempts['submissionAttempt']>[2];
type UnauthorizedSubmissionAttempt = AttemptOptions & Readonly<{currentAuthorization: false}>;
type AuthorizedSubmissionCheck = Parameters<SubmissionMethods['checkSubmittedIntent']>[2] & AttemptOptions;
type SubmissionCheckOptions = AuthorizedSubmissionCheck | UnauthorizedSubmissionAttempt;
type AuthorizedNamedSubmission = Parameters<SubmissionMethods['resolveOrBindSubmittedName']>[2] & AttemptOptions;
type NamedSubmissionOptions = AuthorizedNamedSubmission | (UnauthorizedSubmissionAttempt &
  Pick<AuthorizedNamedSubmission, 'submissionRef' | 'actorId'>);
type CancellationMethods = ReturnType<typeof createJournalCancellation>;
type CancelRecord = CancellationMethods['recordCancellationOperation'];
type CancelAttemptOptions = Parameters<CancelRecord>[1] & Readonly<{attemptRef?: Parameters<Attempts['cancellationAttempt']>[2]}>;
type Failure = Readonly<{code?: string}> | null | undefined;

const originalJournalCustodies = new WeakMap<object, () => JournalCustody>();
const originalJournalCustodyGet = WeakMap.prototype.get;
const originalJournalCustodySet = WeakMap.prototype.set;
const {facilityNativeRealpath, facilityRealpath, nativePathOptions,
  assertOriginalClientRequestJournalFacilityCurrent} = captureOriginalClientRequestJournalFacility();
export {assertOriginalClientRequestJournalFacilityCurrent};

// Private physical-facility observation, not request/Run authority or a
// capacity issuer. Only this module's actual constructor can install a member.
// Logical close, native connection close and optional observation ownership
// are distinct; a copied object cannot attest any of them.
export function observeOriginalClientRequestJournalCustody(journal: unknown): JournalCustody {
  const read = applyOriginal(originalJournalCustodyGet, originalJournalCustodies, [journal]) as (() => JournalCustody) | undefined;
  if (read === undefined) fail('ForeignClientRequestJournalCustody');
  return read();
}

// Membership only, without constructing an observation before its caller's
// optional metadata admission. This supplies no currentness or capacity.
export function assertOriginalClientRequestJournal(journal: unknown): void {
  if (applyOriginal(originalJournalCustodyGet, originalJournalCustodies, [journal]) === undefined) {
    fail('ForeignClientRequestJournalCustody');
  }
}

// The existing observation key already retains every non-clock state field.
// Reuse only its closed budget message for this SAME failed Run/control frame;
// no second store, error chain, execution owner or status inference is added.


export function openClientRequestJournal(directory: string, options: JournalOptions = {}, ownedOriginal?: object) {
  const configuration = snapshotJournalConfiguration(directory, options, ownedOriginal);
  const {maxInspectionEntries, maxInspectionBytes, maxDatabaseBytes,
    primarySqlLimits, primaryExecutionLimits, primarySchemaLimits, primarySchemaSqlSupport,
    primaryCurrent, primaryDirectoryInspection, inspectionTemporaryDirectory,
    maxRunDefinitionWireBytes, submissionEpochNow, updateOriginalControl,
    sourceOperationLimits, inspectionBytes, walFrames} = configuration;
  const maxOriginalExplanationWireBytes = Math.min(65536, maxRunDefinitionWireBytes);
  // Only the actual selected Root supplies this captured current fence. It
  // does not issue capacity; execute it before the first original directory,
  // copy or native acquisition, and again at each covered SQL boundary.
  primaryCurrent?.();
  if (primaryCurrent !== undefined && typeof facilityNativeRealpath !== 'function') {
    fail('ClientRequestJournalFacilityUnavailable');
  }
  const directoryAdmission = admitJournalDirectory(directory, maxInspectionEntries, inspectionBytes,
    primarySqlLimits, primaryExecutionLimits, primarySchemaLimits, primarySchemaSqlSupport, primaryCurrent,
    primaryDirectoryInspection, inspectionTemporaryDirectory, ownedOriginal);
  const current = directoryAdmission !== false;
  mkdirSync(directory, {recursive: true, mode: 0o700});
  // Avoid the stock JS symlink walk's intermediate path/Map/Set history in
  // the selected recipe. Native libc/libuv path holdings remain distinct
  // terms of that recipe; selecting this original does not supply them.
  const root = primaryCurrent === undefined ? realpathSync(directory) :
    applyOriginal(facilityNativeRealpath!, facilityRealpath, [directory, nativePathOptions]) as string;
  const path = join(root, 'client-requests.sqlite3');
  const existed = existsSync(path);
  if (current !== existed) fail('UnknownClientRequestJournalFormat');
  primaryCurrent?.();
  const initializationCleanup = createJournalPrimaryConnection(path, primaryCurrent);
  let closed = false;
  let databaseClosed = false;
  try {
    const transaction = initializationCleanup.open(primarySqlLimits, primaryExecutionLimits, walFrames);
    const {database, selectedSql} = initializationCleanup;
    initializeJournalPrimaryStorage(database, transaction, root, directory, existed,
      directoryAdmission, configuration, selectedSql, ownedOriginal);
  // Statement preparation is part of initialization: no journal owner has
  // been returned yet. Keep it under the same single cleanup boundary.
  const ensureOpen = (): undefined => {
    if (closed) fail('ClientRequestJournalClosed');
    primaryCurrent?.();
    transaction.assertUsable();
  };
  const {rejectSubmission, submissionTransaction, submissionAttempt, rejectSubmissionEpoch,
    rejectCancellation, transact, cancellationAttempt} = createJournalAttempts(transaction, ensureOpen);
  let observationProjection: Projection | undefined;
  // Count only rows actually returned by these selected native reads. This
  // neither visits other Runs nor measures SQLite's internal page traversal.
  // The existing observation context aggregates scalars without per-get I/O.
  const selectedRequestStatement = (statement: JournalStatement, selection: 'request' | 'run-definition', completeRef = false,
    completeRow = false) => {
    const get = statement.get;
    return Object.freeze({get(...parameters: SqlArgument[]) {
      const row = applyOriginal(get, statement, parameters) as ReturnType<typeof get>;
      if (observationProjection !== undefined) {
        try {
          const ref = completeRef ? {namespaceId: parameters[0],
            authorityScopeCid: parameters[1], runDefinitionCid: parameters[2]} : undefined;
          observationProjection.diagnostic('selected_rows_observed', {
            ref: ref as WireRunRef | undefined, rowOwner: 'request-journal', selection, rowKind: 'run',
            returnedRows: row === undefined ? 0 : 1,
            ...(selection === 'request' ? {requestSelection: {
              authorityScopeCid: parameters[0] as string, requestId: parameters[1] as string},
            ...(row === undefined ? {} : {selectedRowRef: {namespaceId: row.namespace_id as string,
              authorityScopeCid: row.authority_scope_cid as string, runDefinitionCid: row.run_definition_cid as string}})} :
              !completeRef ? {runSelectionCid: parameters[0] as string} : {}),
            // Partial projections and pre-Run request keys cannot classify a
            // complete returned Run identity. Absence here means unknown.
            unrelatedRows: !completeRow ? undefined : row === undefined ? 0 :
              Number(row.namespace_id !== ref!.namespaceId ||
                row.authority_scope_cid !== ref!.authorityScopeCid ||
                row.run_definition_cid !== ref!.runDefinitionCid),
            coverage: 'selected-returned',
          });
        } catch { /* Optional diagnostics never replace a native result. */ }
      }
      return row;
    }});
  };
  const select = selectedRequestStatement(database.prepare(`SELECT ${selectColumns} FROM client_requests
    WHERE authority_scope_cid = ? AND caller_request_id = ?`), 'request');
  const selectRef = selectedRequestStatement(database.prepare(`SELECT ${selectColumns} FROM client_requests
    WHERE namespace_id = ? AND authority_scope_cid = ? AND
      run_definition_cid = ?`), 'run-definition', true, true);
  const {persistOriginalKeyedLookupActivation, persistOriginalKeyedLookupPage} =
    createJournalKeyedLookupStorage(database, selectRef, ensureOpen, transact);
  const sourceOperations = clientSourceOperationStorage(database, {ensureOpen,
    transact, limits: sourceOperationLimits,
    readRun: ref => selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid)});
  // The FK and unique Run key bound this table by the existing admitted
  // request rows. SQL substr bounds materialization of corrupt old records.
  const localExecutionOwnerInsert = ownedOriginal === undefined ? undefined : database.prepare(`
    INSERT INTO client_local_execution_owners VALUES (?, ?, ?, ?, ?, ?, ?)`);
  const localExecutionOwnerLookup = ownedOriginal === undefined ? undefined : database.prepare(`
    SELECT substr(owner_token, 1, 37) AS owner_token,
      substr(anchor_identity, 1, 37) AS anchor_identity,
      substr(anchor_device, 1, 33) AS anchor_device,
      substr(anchor_inode, 1, 33) AS anchor_inode
    FROM client_local_execution_owners
    WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?`);
  // These observation frames belong to this exact journal instance. They are
  // not authority and cannot be reconstituted from a copied DATA response.
  const runStateFrames: Parameters<typeof admitJournalRunDefinitionRow>[0] = new WeakMap();
  const readRunDefinitionRow = (ref: WireRunRef, requestControl: Parameters<typeof readJournalRunDefinitionRow>[1]) =>
    readJournalRunDefinitionRow(ref, requestControl, ensureOpen, selectRef);
  const retainRunStateFrame = (frame: object, selected: WireRunRef) =>
    retainJournalRunStateFrame(runStateFrames, frame, selected);
  const admitRunDefinitionRow = (row: Parameters<typeof admitJournalRunDefinitionRow>[1],
    requestControl: Parameters<typeof admitJournalRunDefinitionRow>[2], publicationControl: DefinitionControl) =>
    admitJournalRunDefinitionRow(runStateFrames, row, requestControl, publicationControl,
      maxRunDefinitionWireBytes, updateOriginalControl as Parameters<typeof admitJournalRunDefinitionRow>[5]);
  const selectRun = selectedRequestStatement(database.prepare(`SELECT run_definition_cid
    FROM client_requests WHERE run_definition_cid = ?`), 'run-definition');
  const requestUsage = database.prepare('SELECT * FROM client_request_row_usage WHERE singleton=1');
  const submissionIssued = database.prepare('SELECT issued_count FROM client_submission_custody WHERE singleton = 1');
  const advanceSubmissionCustody = database.prepare('UPDATE client_submission_custody SET issued_count = issued_count + 1 WHERE singleton = 1 AND issued_count = ?');
  const epochAuthority = database.prepare('SELECT * FROM client_submission_epoch_authority WHERE singleton = 1');
  const advanceEpochTime = database.prepare('UPDATE client_submission_epoch_authority SET observed_at = ? WHERE singleton = 1');
  const submissionOriginals = createJournalSubmissionOriginals(epochAuthority, advanceEpochTime,
    transaction, ensureOpen, submissionEpochNow, configuration);
  const {admitIntentOriginal, originalIntent,
    retainSubmissionOperation} = submissionOriginals;
  const intentSelect = database.prepare('SELECT * FROM client_submitted_intents WHERE submission_id = ?');
  const intentUsage = database.prepare(`SELECT retained_count AS n,retained_bytes AS bytes,revision
    FROM client_submitted_intent_usage WHERE singleton=1`);
  const intentIssued = database.prepare('SELECT issued_count FROM client_submitted_intent_custody WHERE singleton = 1');
  const intentRetired = database.prepare('SELECT retired_count FROM client_submitted_intent_retirement WHERE singleton = 1');
  const restartSelect = database.prepare('SELECT * FROM client_submission_restarts WHERE fresh_submission_id = ?');
  const restartUsage = database.prepare(`SELECT retained_count AS n,retained_bytes AS bytes,revision
    FROM client_submission_restart_usage WHERE singleton=1`);
  const restartIssued = database.prepare('SELECT issued_count FROM client_submission_restart_custody WHERE singleton = 1');
  const nameSelect = database.prepare(`SELECT * FROM client_submission_names
    WHERE namespace_id = ? AND actor_id = ? AND name = ?`);
  const nameCustody = database.prepare('SELECT * FROM client_submission_name_custody WHERE singleton = 1');
  const {checkSubmissionBinding, refuseEpoch, retainedIntentOriginal, retainedIntent, methods} =
    createJournalSubmissionRows(database, select, {epochAuthority, requestUsage, submissionIssued,
      intentSelect, intentUsage, intentIssued, intentRetired, restartSelect, restartUsage, restartIssued,
      nameSelect, nameCustody}, submissionOriginals, transaction, ensureOpen,
      {rejectSubmission, submissionTransaction, rejectSubmissionEpoch}, configuration);
  const {resolveOrBindSubmittedName, checkSubmittedIntent, recordSubmittedIntent, lookupSubmittedIntent,
    retireSubmittedIntent, completeSubmittedIntent, issueSubmissionEpoch, verifySubmissionEpoch,
    submissionIdentity} = methods;
  const cancellationUsage = database.prepare('SELECT * FROM client_cancellation_row_usage WHERE singleton=1');
  const cancellationIssued = database.prepare('SELECT issued_count FROM client_cancellation_custody WHERE singleton = 1');
  const cancellationSelect = database.prepare(`SELECT * FROM client_cancellation_operations
    WHERE namespace_id = ? AND authority_scope_cid = ? AND cancel_id = ?`);
  const cancellationInsert = database.prepare(`INSERT INTO client_cancellation_operations
    (namespace_id, authority_scope_cid, cancel_id, run_definition_cid,
     expected_revision, intent_fingerprint_cid) VALUES (?, ?, ?, ?, ?, ?)`);
  const insert = database.prepare(`INSERT INTO client_requests (${columns})
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
  const reserve = database.prepare(`UPDATE client_requests
    SET dispatch_reserved = 1, revision = revision + 1
    WHERE authority_scope_cid = ? AND caller_request_id = ? AND
      dispatch_reserved = 0`);
  const confirmPreDispatchFailure = database.prepare(`UPDATE client_requests
    SET pre_dispatch_failure_confirmed = 1, revision = revision + 1
    WHERE namespace_id = ? AND authority_scope_cid = ? AND
      run_definition_cid = ? AND dispatch_reserved = 1 AND
      pre_dispatch_failure_confirmed = 0 AND physical_start_reserved = 0 AND
      cancellation_requested = 0`);
  const reservePhysicalStart = database.prepare(`UPDATE client_requests
    SET physical_start_reserved = 1, revision = revision + 1
    WHERE namespace_id = ? AND authority_scope_cid = ? AND
      run_definition_cid = ? AND dispatch_reserved = 1 AND
      pre_dispatch_failure_confirmed = 0 AND physical_start_reserved = 0 AND
      cancellation_requested = 0`);

  const {reserveDispatch, reservePhysicalStart: startPhysical} =
    createJournalRunStart({select, selectRef, reserve, reservePhysicalStart, localExecutionOwnerInsert},
      {ensureOpen, transact, getDeliveredJournal: () => deliveredJournal, sourceOperations,
        ownedOriginal, captureOriginalLocalExecutionOwner, validLocalExecutionOwnerReceipt},
      maxRunDefinitionWireBytes);

  const {publishRunState, observeRunCancellation, observeStoppedLocalExecutionOwner, markPhysicalClose,
    markPreDispatchFailure, recordReconciliationState, lookupReconciliationState} =
    createJournalRunObservations(database,
      {selectRef, selectedRequestStatement, localExecutionOwnerLookup, confirmPreDispatchFailure},
      {ensureOpen, transact, runStateFrames, retainRunStateFrame, readRunDefinitionRow,
        admitRunDefinitionRow, ownedOriginal, validLocalExecutionOwnerReceipt, originalLocalExecutionOwnerStopped},
      maxRunDefinitionWireBytes);

  const {requestCancellation, recordCancellationOperation, lookupCancellationOperation} =
    createJournalCancellation(database, {selectRef, requestUsage, submissionIssued, cancellationUsage,
      cancellationIssued, cancellationSelect, cancellationInsert}, ensureOpen,
    {transact, rejectCancellation}, configuration as Parameters<typeof createJournalCancellation>[4]);

  const readExplanationOriginal = (ref: WireRunRef) =>
    readJournalExplanationOriginal(database, ref, maxRunDefinitionWireBytes);
  const probeExplanationRead = (ref: WireRunRef, includeContext: boolean) =>
    probeJournalExplanation(database, ensureOpen, ref, maxRunDefinitionWireBytes, includeContext);
  const readExplanationSelection = (ref: WireRunRef, extent: Parameters<typeof readJournalExplanation>[3], includeContext: boolean) =>
    readJournalExplanation(database, ensureOpen, ref, extent, maxRunDefinitionWireBytes, includeContext);
  const insertExplanationOriginal = (ref: WireRunRef, original: Parameters<typeof insertJournalExplanationOriginal>[2]) =>
    insertJournalExplanationOriginal(database, ref, original);

  const {acceptRecord, lookupRecord, resolveOriginalDefinition} =
    createJournalRunRecords({select, selectRun, requestUsage, submissionIssued, cancellationUsage,
      cancellationIssued, intentSelect, insert, advanceSubmissionCustody},
    {ensureOpen, transact, checkSubmissionBinding, refuseEpoch, retainedIntent,
      assertJournalSubmissionCustody, assertJournalCancellationCustody,
      readExplanationOriginal, insertExplanationOriginal,
      verifyExplanationContext: (runDefinitionCid, original) =>
        verifyJournalExplanationContext(database, runDefinitionCid, original)},
    {...configuration, maxOriginalExplanationWireBytes} as Parameters<typeof createJournalRunRecords>[2]);

  const observationConnection = createJournalObservationConnection(path, ensureOpen, primaryCurrent,
    primarySqlLimits, primaryExecutionLimits, walFrames, maxDatabaseBytes);
  const closeObservationStorage = observationConnection.closeObservationStorage;
  const journal = Object.freeze({
    retainSubmissionOperation,
    prepareSubmittedIntent(epoch: unknown, wire: unknown, control: Parameters<typeof admitIntentOriginal>[1]) {
      ensureOpen();
      // This admission is not cached. An explicit original preparation borrow
      // is registered separately and released by the active operation.
      return admitIntentOriginal(wire, control, epoch, 'InvalidClientSubmittedIntent', false).intent;
    },
    closeObservationStorage,
    observationStorage: observationConnection.observationStorage,
    installObservationProjection(projection: unknown) {
      if (!isHostObservationProjection(projection) || observationProjection !== undefined) {
        throw new TypeError('ForeignHostObservationProjection');
      }
      observationProjection = projection;
    },
    resolveOrBindSubmittedName,
    resolveNamedSubmissionAttempt(name: unknown, intent: unknown,
      options: NamedSubmissionOptions,
      control: Parameters<SubmissionMethods['resolveOrBindSubmittedName']>[3]): ReturnType<Attempts['submissionAttempt']> {
      return submissionAttempt(options.submissionRef, intent, options, control,
        () => journal.resolveOrBindSubmittedName(name, intent, options as AuthorizedNamedSubmission, control), 'recorded', originalIntent);
    },
    checkSubmittedIntent,
    recordSubmittedIntent,
    // Invocation facts are projections of the existing admission boundary,
    // never replacement receipts or proof that another invocation did not run.
    checkSubmissionAttempt(submissionRef: WireSubmissionRef, intent: unknown,
      options: SubmissionCheckOptions,
      control: Parameters<SubmissionMethods['checkSubmittedIntent']>[3]): ReturnType<Attempts['submissionAttempt']> {
      return submissionAttempt(submissionRef, intent, options, control,
        () => journal.checkSubmittedIntent(submissionRef, intent, options as AuthorizedSubmissionCheck, control), 'checked', originalIntent);
    },
    recordSubmissionAttempt(submissionRef: WireSubmissionRef, intent: unknown,
      options: Parameters<SubmissionMethods['recordSubmittedIntent']>[2] & AttemptOptions,
      control: Parameters<SubmissionMethods['recordSubmittedIntent']>[3]): ReturnType<Attempts['submissionAttempt']> {
      return submissionAttempt(submissionRef, intent, options, control,
        () => journal.recordSubmittedIntent(submissionRef, intent, options, control), 'recorded', originalIntent);
    },
    lookupSubmittedIntent,
    retireSubmittedIntent,
    completeSubmittedIntent,
    issueSubmissionEpoch,
    verifySubmissionEpoch,
    submissionIdentity,
    // The transaction owns uniqueness and durable acceptance; no task is
    // started here. A duplicate is interpreted only by the common MoonBit
    // relation, never by comparing transport JSON or a local retry counter.
    accept(identity: unknown, {namespaceId, runDefinitionCid, revision = 0,
      lookupExpiresAt, submission}: RunAdmission, control: RequestControl) {
      return acceptRecord(identity, {namespaceId, runDefinitionCid,
        revision, lookupExpiresAt, submission}, control);
    },
    // The complete canonical Run Definition is retained in the same
    // transaction as the request. The caller must have obtained it from the
    // shared Run issuer; re-admission here checks identity, not authority.
    // Reattachment never reissues this identity.
    supportsOriginalExplanation() {
      ensureOpen();
      // Selected facility DATA only. The fixed Host checks this before the
      // optional compiler quote; it grants neither a Run nor read authority.
      return primarySchemaSqlSupport === undefined ||
        primarySchemaSqlSupport.includes(explanationOriginalTable);
    },
    supportsOriginalExplanationContext() {
      ensureOpen();
      return primarySchemaSqlSupport === undefined ||
        primarySchemaSqlSupport.includes(explanationOriginalTable) &&
        primarySchemaSqlSupport.includes(explanationContextOriginalTable);
    },
    originalExplanationContextLimit(): number | undefined {
      return journal.supportsOriginalExplanationContext() ? maxOriginalExplanationWireBytes : undefined;
    },
    acceptDefinition(identity: unknown, {namespaceId, runDefinition, resultNames, runAdmissionEvidence, originalPlan, originalExplanation, originalInferRun,
      revision = 0, lookupExpiresAt, submission}: DefinitionAdmission,
      requestControl: RequestControl, publicationControl: AdmissionPublication): AdmittedDefinition {
      ensureOpen();
      const definition = checkedRunDefinition(runDefinition,
        publicationControl, maxRunDefinitionWireBytes);
      // Only the existing compiler control can issue the first original. A
      // wire copy is not an opaque compiler selection. No later transaction
      // fills missing evidence in an already accepted Run.
      if (runAdmissionEvidence !== null && typeof runAdmissionEvidence === 'object' &&
          Object.hasOwn(runAdmissionEvidence, 'logicalPlanOriginal')) {
        fail('InvalidClientRunPlanOriginal');
      }
      if (runAdmissionEvidence !== null && typeof runAdmissionEvidence === 'object' &&
          Object.hasOwn(runAdmissionEvidence, 'inferRunOriginal')) {
        fail('InvalidClientInferRunOriginal');
      }
      if (runAdmissionEvidence !== null && typeof runAdmissionEvidence === 'object' &&
          Object.hasOwn(runAdmissionEvidence, 'structuralExplanationOriginal')) {
        fail('InvalidClientRunExplanationOriginal');
      }
      let explanationOriginal: Parameters<RunRecords['acceptRecord']>[3];
      let acknowledgeExplanation: AdmissionPublication['originalRunExplanationAdmissionAcknowledged'];
      if (originalExplanation !== undefined) {
        if (originalPlan === undefined || typeof publicationControl.originalRunExplanationAdmissionEvidence !== 'function' ||
            !admissionEvidenceShape(runAdmissionEvidence, updateOriginalControl as Parameters<typeof admissionEvidenceShape>[1])) fail('InvalidClientRunExplanationOriginal');
        acknowledgeExplanation = publicationControl.originalRunExplanationAdmissionAcknowledged;
        if (typeof acknowledgeExplanation !== 'function') fail('InvalidClientRunExplanationOriginal');
        // Exact selected facility support is a prerequisite, not permission or
        // a fallback grant. Normal optional capture must preflight it BEFORE
        // producing a ticket; a supplied unsupported ticket is not discarded.
        if (primarySchemaSqlSupport !== undefined && !primarySchemaSqlSupport.includes(explanationOriginalTable)) {
          fail('ClientRequestExplanationStorageUnavailable');
        }
        try {
          const original = publicationControl.originalRunExplanationAdmissionEvidence(originalExplanation,
            definition, requestControl.clientRequestProgramCid(identity), runAdmissionEvidence);
          if (original === null || typeof original !== 'object' || Array.isArray(original)) fail('InvalidClientRunExplanationOriginal');
          const fields = operationDescriptors(original), field = fields.factsWire;
          const companion = fields.contextWire;
          const template = fields.invocationTemplateWire;
          if (operationKeys(fields).length !== (companion === undefined ? 1 : 3) || field === undefined ||
              !Object.hasOwn(field, 'value') || typeof field.value !== 'string' || field.value.length === 0) {
            fail('InvalidClientRunExplanationOriginal');
          }
          const factsWire = field.value;
          let bytes = Buffer.byteLength(factsWire);
          const captured: {factsWire: string; contextWire?: string; contextWireSha256?: string; invocationTemplateWire?: string} = {factsWire};
          if (companion !== undefined) {
            if (!Object.hasOwn(companion, 'value') || typeof companion.value !== 'string' || companion.value.length === 0 ||
                template === undefined || !Object.hasOwn(template, 'value') ||
                typeof template.value !== 'string' || template.value.length === 0) {
              fail('InvalidClientRunExplanationOriginal');
            }
            if (primarySchemaSqlSupport !== undefined && !primarySchemaSqlSupport.includes(explanationContextOriginalTable)) {
              fail('ClientRequestExplanationStorageUnavailable');
            }
            captured.contextWire = companion.value;
            captured.invocationTemplateWire = template.value;
            bytes += Buffer.byteLength(captured.contextWire) + Buffer.byteLength(captured.invocationTemplateWire);
          }
          if (bytes > (companion === undefined ? maxRunDefinitionWireBytes : maxOriginalExplanationWireBytes)) {
            fail('InvalidClientRunAdmissionEvidence');
          }
          if (companion !== undefined) {
            // Preserve the first committed bytes for the authorized cold
            // validator. Prefix the fixed 71-byte original Run CID so a
            // companion copied from another Run also fails this comparison.
            captured.contextWireSha256 = createHash('sha256')
              .update(definition.identity).update(captured.contextWire!).digest('hex');
          }
          explanationOriginal = Object.freeze(captured);
        } catch (cause) {
          if ((cause as Failure)?.code === 'InvalidClientRunAdmissionEvidence' ||
              (cause as Failure)?.code === 'ClientRequestExplanationStorageUnavailable') throw cause;
          fail('InvalidClientRunExplanationOriginal', cause);
        }
      }
      if (originalInferRun !== undefined) {
        if (typeof publicationControl.originalInferRunAdmissionEvidence !== 'function' ||
            !admissionEvidenceShape(runAdmissionEvidence, updateOriginalControl as Parameters<typeof admissionEvidenceShape>[1])) {
          fail('InvalidClientInferRunOriginal');
        }
        let original;
        try {
          original = publicationControl.originalInferRunAdmissionEvidence(originalInferRun,
            definition, identity, runAdmissionEvidence);
        } catch (cause) { fail('InvalidClientInferRunOriginal', cause); }
        runAdmissionEvidence = {...runAdmissionEvidence, inferRunOriginal: original};
      }
      if (originalPlan !== undefined) {
        if (typeof publicationControl.originalRunPlanAdmissionEvidence !== 'function' ||
            !admissionEvidenceShape(runAdmissionEvidence, updateOriginalControl as Parameters<typeof admissionEvidenceShape>[1])) fail('InvalidClientRunPlanOriginal');
        let original;
        try {
          original = publicationControl.originalRunPlanAdmissionEvidence(originalPlan,
            definition, requestControl.clientRequestProgramCid(identity), runAdmissionEvidence);
          if (!logicalPlanOriginalShape(original)) fail('InvalidClientRunPlanOriginal');
          if (Buffer.byteLength(original.compiledPlanWire) > maxRunDefinitionWireBytes ||
              Buffer.byteLength(original.planViewWire) > maxRunDefinitionWireBytes) {
            fail('InvalidClientRunAdmissionEvidence');
          }
          // This nominal compiler selection already checked Plan/map/Run
          // binding before issuance. Adopting its exact original is not a
          // second stored-map read or another execution permission.
        } catch (cause) {
          if ((cause as Failure)?.code === 'InvalidClientRunAdmissionEvidence') throw cause;
          fail('InvalidClientRunPlanOriginal', cause);
        }
        runAdmissionEvidence = {...runAdmissionEvidence,
          logicalPlanOriginal: Object.freeze({...original})};
      }
      const accepted = acceptRecord(identity, {namespaceId,
        runDefinitionCid: definition.identity,
        runDefinitionWire: definition.wire,
        resultNames, runAdmissionEvidence, revision, lookupExpiresAt, submission}, requestControl, explanationOriginal);
      // acceptRecord returned only after this SAME transaction's native
      // COMMIT ACK (or its acknowledged selection of the existing winner).
      // Unknown/rollback throws never reach this release. Drop the
      // transient Facts wrapper before the compiler owner cuts its last alias
      // and returns the same funded loan; it may still report cleanup failure.
      explanationOriginal = undefined;
      if (acknowledgeExplanation !== undefined) applyOriginal(acknowledgeExplanation,
        publicationControl, [originalExplanation, definition,
          requestControl.clientRequestProgramCid(identity), runAdmissionEvidence]);
      // This optional projection runs after the semantic transaction. Only
      // its branded bounded queue is reachable here, never user delivery.
      observationProjection?.accepted(accepted,
        requestControl.clientRequestCallerId(identity) as string);
      observationProjection?.emit('run', 'definition_admitted',
        {ref: accepted.ref, revision: accepted.revision});
      return Object.freeze({
        inserted: accepted.inserted,
        ref: accepted.ref,
        durability: accepted.durability,
        revision: accepted.revision,
        lookupExpiresAt: accepted.lookupExpiresAt,
        resultNames: accepted.resultNames,
        runAdmissionEvidence: accepted.runAdmissionEvidence,
        // The acknowledged winner may be this operation's already admitted
        // original. A different selected body still follows full admission.
        runDefinition: accepted.ref.runDefinitionCid === definition.identity &&
          accepted.runDefinitionWire === definition.wire ? definition : retainedRunDefinition({
          run_definition_cid: accepted.ref.runDefinitionCid,
          run_definition_wire: accepted.runDefinitionWire,
        }, publicationControl, maxRunDefinitionWireBytes),
      });
    },
    // Authorization and retention policy are performed by the Host before
    // exposing a found record. Physical lookup never starts Compute.
    lookup(key: RequestKey, control: RequestReader) {
      return lookupRecord(key, control)?.found;
    },
    // Internal owner recovery, not a wire credential or current permission.
    // Both logical keys are re-admitted before the caller can reuse the scope.
    lookupIdentity(key: RequestKey, control: RequestReader) {
      return lookupRecord(key, control)?.identity;
    },
    lookupDefinition(key: RequestKey, requestControl: RequestReader, publicationControl: DefinitionControl) {
      const retained = lookupRecord(key, requestControl);
      if (retained === undefined) return undefined;
      return Object.freeze({...retained.found,
        ...retainedRunFacts(retained.row, publicationControl,
          maxRunDefinitionWireBytes, updateOriginalControl as Parameters<typeof retainedRunFacts>[3]),
      });
    },
    // Attach reads the original accepted Run Definition by its exact ref.
    // It does not infer authority from a CID alone or create another Run.
    lookupRunDefinition(ref: WireRunRef, requestControl: Parameters<typeof admitJournalRunDefinitionRow>[2],
      publicationControl: DefinitionControl, originalFrame?: RunFrame) {
      let original;
      if(originalFrame!==undefined) {
        ensureOpen();
        original=retainRunStateFrame(originalFrame,ref);
        if(original.requestControl!==requestControl || original.publicationControl!==publicationControl) {
          fail('ForeignRunStateObservation');
        }
      }
      const row = readRunDefinitionRow(ref, requestControl);
      if (row === undefined) return undefined;
      if(original!==undefined && sameRunStateRow(row,original.row)) return originalFrame;
      return admitRunDefinitionRow(row, requestControl, publicationControl);
    },
    // Internal retained facet read. Current Run/Plan and egress admission must
    // precede this operation in the existing Host service. It issues no Run,
    // compiler token or permission, and never repairs a legacy absence.
    lookupRunExplanationOriginal(ref: WireRunRef, requestControl: Parameters<typeof admitJournalRunDefinitionRow>[2],
      publicationControl: DefinitionControl) {
      const row = readRunDefinitionRow(ref, requestControl);
      if (row === undefined) return undefined;
      // Admit the SAME original Run before reading its associated facet.
      admitRunDefinitionRow(row, requestControl, publicationControl);
      return readExplanationOriginal(ref);
    },
    // Private explicit-read DATA only. The installed caller must admit entry
    // before probe, then the complete original/codec overlap before full read.
    probeRunExplanationOriginal(ref: WireRunRef) {return probeExplanationRead(ref, false);},
    readRunExplanationOriginal(ref: WireRunRef, extent: Parameters<typeof readJournalExplanation>[3]) {return readExplanationSelection(ref, extent, false);},
    probeRunExplanationContextOriginal(ref: WireRunRef) {return probeExplanationRead(ref, true);},
    readRunExplanationContextOriginal(ref: WireRunRef, extent: Parameters<typeof readJournalExplanation>[3]) {return readExplanationSelection(ref, extent, true);},
    canReinspectRunStopAfterStatePublication(beforeFrame: object, afterFrame: object) {
      ensureOpen();
      return reinspectJournalRunStopAfterStatePublication(runStateFrames, beforeFrame, afterFrame);
    },
    canReinspectRunAfterPhysicalClose(beforeFrame: object, afterFrame: object) {
      ensureOpen();
      return reinspectJournalRunAfterPhysicalClose(runStateFrames, beforeFrame, afterFrame);
    },
    canReinspectRunForSigning(beforeFrame: object, afterFrame: object) {
      ensureOpen();
      return reinspectJournalRunForSigning(runStateFrames, beforeFrame, afterFrame);
    },
    // Private original-content projection for this journal's admitted Run.
    // It grants neither current authorization nor a physical/resume claim.
    // Historical unselected Runs remain readable without a new reference;
    // missing selected custody cannot be repaired from current caller options.
    originalSubmittedIntent(identity: unknown, {namespaceId}: RequestScope, requestControl: StopRequestControl,
      publicationControl: DefinitionControl) {
      ensureOpen();
      if (!text(namespaceId) ||
          typeof requestControl?.clientSubmittedIntentRequestsCommitStop !== 'function') {
        fail('InvalidClientRequestJournalControl');
      }
      const fields = checkedIdentity(identity, requestControl);
      const requestOriginal = Object.freeze({identity, fields});
      let previousRunRow: NonNullable<ReturnType<RunRecords['lookupRecord']>>['row'] | undefined;
      let previousRunFacts: ReadmittedRunFacts | undefined;
      let previousIntent: ReturnType<SubmissionRows['retainedIntentOriginal']> | undefined;
      let previousReference: Readonly<{epochWire: unknown; nonce: unknown; wire: string}> | undefined;
      const readOriginal = () => {
        try {
          assertJournalSubmissionCustody(requestUsage, submissionIssued);
          assertJournalIntentCustody(intentUsage, intentIssued, intentRetired, inspectionBytes);
          const run = lookupRecord({namespaceId, authorityScopeCid: fields.authorityScopeCid,
            requestId: fields.requestId}, requestControl, requestOriginal);
          if (run === undefined || requestControl.clientRequestRelation(identity,
            run.identity) !== 1) fail('ClientRequestSubmittedIntentMismatch');
          // This existing handle retains only typed facts for exact unchanged
          // scalar rows. Storage/custody is still observed in this transaction;
          // an actual change re-enters the original admission path below.
          if (previousRunRow === undefined ||
              Object.keys(run.row).length !== Object.keys(previousRunRow).length ||
              Object.keys(run.row).some(key => run.row[key as keyof typeof run.row] !== previousRunRow![key as keyof typeof run.row])) {
            previousRunFacts = retainedRunFacts(run.row, publicationControl,
              maxRunDefinitionWireBytes, updateOriginalControl as Parameters<typeof retainedRunFacts>[3]);
            previousRunRow = Object.freeze({...run.row});
          }
          const facts = previousRunFacts!;
          const expectedCid = facts.runAdmissionEvidence?.submittedIntentCid;
          const row = intentSelect.get(fields.requestId);
          if (row === undefined) {
            if (expectedCid !== undefined) fail('ClientSubmittedIntentCustodyLost');
            return undefined;
          }
          previousIntent = retainedIntentOriginal(row as Parameters<typeof retainedIntentOriginal>[0], requestControl, undefined, previousIntent);
          const {intent, value: original} = previousIntent;
          if (intent === undefined || !['preparing', 'held', 'ready'].includes(original.phase)) {
            fail('ClientRequestSubmittedIntentMismatch');
          }
          if (expectedCid === undefined) {
            if (requestControl.clientSubmittedIntentRequestsCommitStop(intent) ||
                requestControl.clientSubmittedIntentRequestsReadOnly(intent)) {
              fail('ClientRequestSubmittedIntentBindingMissing');
            }
            return undefined;
          }
          if (expectedCid !== original.intentCid) fail('ClientRequestSubmittedIntentMismatch');
          if (previousReference === undefined || previousReference.epochWire !== row.epoch_wire ||
              previousReference.nonce !== row.nonce) {
            previousReference = Object.freeze({epochWire: row.epoch_wire, nonce: row.nonce,
              wire: canonicalValueJson(original.submissionRef, {dataKeys: true})});
          }
          return {intent, intentCid: original.intentCid, intentWire: original.intentWire,
            referenceWire: previousReference.wire,
            runDefinitionCid: run.row.run_definition_cid};
        } catch (error) {
          previousRunRow = previousRunFacts = previousIntent = previousReference = undefined;
          throw error;
        }
      };
      const original = transaction.run(readOriginal);
      if (original === undefined) return undefined;
      return Object.freeze({intent: original.intent, referenceWire: original.referenceWire,
        assertCurrent() {
          try {
            ensureOpen();
            const current = transaction.run(readOriginal);
            if (current === undefined || current.intentCid !== original.intentCid ||
                current.intentWire !== original.intentWire ||
                current.referenceWire !== original.referenceWire ||
                current.runDefinitionCid !== original.runDefinitionCid) {
              fail('ClientRequestSubmittedIntentMismatch');
            }
          } catch (error) {
            previousRunRow = previousRunFacts = previousIntent = previousReference = undefined;
            throw error;
          }
        }});
    },
    publishRunState,
    observeRunCancellation,
    // Recover identity and Definition from one physical journal observation.
    // This internal owner must not be projected as a Client wire response.
    lookupOwnedDefinition(key: RequestKey, requestControl: RequestReader, publicationControl: DefinitionControl) {
      const retained = lookupRecord(key, requestControl);
      if (retained === undefined) return undefined;
      return Object.freeze({...retained.found,
        requestIdentity: retained.identity,
        ...retainedRunFacts(retained.row, publicationControl,
          maxRunDefinitionWireBytes, updateOriginalControl as Parameters<typeof retainedRunFacts>[3]),
      });
    },
    // A resend can resolve an already accepted request before issuing a new
    // plan or Run Definition. The shared owner compares the checked intent;
    // absence does not prove that a concurrent submission cannot still land.
    resolveDefinition(identity: unknown, {namespaceId}: RequestScope,
      requestControl: RequestControl, publicationControl: DefinitionControl) {
      ensureOpen();
      if (!text(namespaceId) || !requestControl ||
          typeof requestControl.clientRequestRelation !== 'function') {
        fail('InvalidClientRequestLookup');
      }
      const fields = checkedIdentity(identity, requestControl);
      return resolveOriginalDefinition(identity, fields, namespaceId,
        requestControl, publicationControl);
    },
    // Physical admit-or-lookup ordering for a checked request. The common
    // MoonBit relation decides whether a retained intent is the same request;
    // the callback may issue authority but must not start Compute. A racing
    // issuer is discarded when the atomic insert finds an existing Run.
    async admitOrLookupDefinition(identity: unknown, {namespaceId, lookupExpiresAt,
      issueDefinition, resultNames, sourceInventory, submission}: IssueDefinitionOptions,
      requestControl: RequestControl, publicationControl: AdmissionPublication): Promise<AdmittedDefinition |
        (NonNullable<ReturnType<RunRecords['resolveOriginalDefinition']>> & Readonly<{inserted: false}>)> {
      if (!text(namespaceId) || !instant(lookupExpiresAt) ||
          Date.parse(lookupExpiresAt) <= Date.now() ||
          typeof issueDefinition !== 'function') {
        fail('InvalidClientRequestAdmission');
      }
      if (sourceInventory !== undefined) validateSourceInventory(sourceInventory);
      ensureOpen();
      assertJournalSubmissionCustody(requestUsage, submissionIssued);
      const fields = checkedIdentity(identity, requestControl);
      assertKeyedInventoryRequest(sourceInventory, fields);
      const epochValidity = checkSubmissionBinding(fields, submission, requestControl as Parameters<typeof checkSubmissionBinding>[2]);
      const retained = resolveOriginalDefinition(identity, fields, namespaceId,
        requestControl, publicationControl);
      if (retained !== undefined) {
        assertSourceInventory(retained, sourceInventory);
        return Object.freeze({inserted: false, ...retained});
      }
      refuseEpoch(epochValidity);
      const issued = await issueDefinition();
      const runDefinition = issued.runDefinition ?? issued;
      if (issued.runAdmissionEvidence?.sourceInventory !== sourceInventory) {
        fail('ClientRequestSourceInventoryMismatch');
      }
      return journal.acceptDefinition(identity, {namespaceId, runDefinition,
        runAdmissionEvidence: issued.runAdmissionEvidence,
        originalPlan: issued.originalPlan,
        originalExplanation: issued.originalExplanation,
        originalInferRun: issued.originalInferRun,
        lookupExpiresAt, resultNames: issued.resultNames ?? resultNames, submission}, requestControl, publicationControl);
    },
    reserveDispatch,
    reservePhysicalStart: startPhysical,
    persistOriginalKeyedLookupActivation,
    persistOriginalKeyedLookupPage,
    lookupOriginalSourceOperation(ref: WireRunRef, occurrence: unknown) {
      if (sourceOperations === undefined) fail('ClientSourceOperationUnavailable');
      return sourceOperations.lookup(ref, occurrence);
    },
    // Readiness only: the original physical-start transaction still issues
    // each live scope. This value cannot bind a Run or enable a POST.
    sourceOperationConfigured: sourceOperations !== undefined,
    requestCancellation,
    recordCancellationOperation,
    // Per-invocation public facts are deliberately not persisted as operation
    // outcomes. Refused consumes no identity; another invocation can already
    // own the same cancellation. Pending custody and uncertain COMMIT never
    // produce this certificate. The durable original remains unchanged.
    recordCancellationAttempt(ref: Parameters<CancelRecord>[0], {attemptRef, ...options}: CancelAttemptOptions,
      requestControl: Parameters<CancelRecord>[2], publicationControl: Parameters<CancelRecord>[3]): ReturnType<Attempts['cancellationAttempt']> {
      return cancellationAttempt(journal, ref, attemptRef, options, requestControl, publicationControl);
    },
    lookupCancellationOperation,
    observeStoppedLocalExecutionOwner,
    markPhysicalClose,
    markPreDispatchFailure,
    recordReconciliationState,
    lookupReconciliationState,
    close(): undefined {
      closed = true;
      if (!databaseClosed) {
        initializationCleanup.close();
        databaseClosed = true;
      }
      // Observation cleanup is optional and never changes Run cleanup facts.
      // Its projection retains the handle and may retry after this close.
      try { closeObservationStorage(); }
      catch { /* The observation projection owns this separate connection. */ }
    },
  });
  const deliveredJournal = guardJournalCurrentness(journal, primaryCurrent);
  applyOriginal(originalJournalCustodySet, originalJournalCustodies, [deliveredJournal, () =>
    Object.freeze({journalClosed: closed, databaseClosed,
      observationAttempted: observationConnection.observationAttempted,
      observationDatabaseClosed: observationConnection.observationDatabaseClosed})]);
  if (!existed) syncDirectory(root);
  return deliveredJournal;
  } catch (error) {
    throwSqliteInitializationFailure(initializationCleanup, error, 'client-request-journal');
  }
}
