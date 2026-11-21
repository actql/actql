import {retainedBudgetFailureMessage} from './client-dispatch-diagnostic.mjs';
// Physical durable storage for an owner-issued Client request and Run ref.
// MoonBit supplies and re-admits the identity and decides intent conflicts.
import './host-journal-facility-fields.cjs';
import {prepareInstalledRunStateObservation, issueInstalledRunControlObservation}
  from '../host-common/run-state-observation.mjs';
import {existsSync, mkdirSync, realpathSync} from 'node:fs';
import {join} from 'node:path';
import {throwSqliteInitializationFailure} from
  '../host-common/sqlite-transaction.mjs';
import {captureOriginalLocalExecutionOwner, originalLocalExecutionOwnerStopped}
  from '../store-local/publication-store.mjs';
import {isHostObservationProjection} from '../host-common/observation.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {clientSourceOperationStorage} from './client-source-operation.mjs';
import {fail, applyOriginal, operationDescriptors, operationKeys, guardJournalCurrentness,
  createJournalPrimaryConnection, createJournalObservationConnection} from './client-request-journal-sql.mjs';
import {admission, admissionEvidenceShape, assertKeyedInventoryRequest, assertSourceInventory, checkedIdentity, checkedRunDefinition,
  cid, instant, logicalPlanOriginalShape, retainedIdentity, retainedRunDefinition, retainedRunFacts,
  createJournalKeyedLookupStorage, createJournalRunRecords, createJournalRunStart,
  admitJournalRunDefinitionRow, readJournalRunDefinitionRow, retainJournalRunStateFrame, sameRunStateRow,
  reinspectJournalRunAfterPhysicalClose, reinspectJournalRunForSigning, reinspectJournalRunStopAfterStatePublication,
  structuralExplanationOriginalShape, text, validateSourceInventory} from './client-request-journal-records.mjs';
import {explanationOriginalTable, admitJournalDirectory, syncDirectory, columns, selectColumns,
  snapshotJournalConfiguration, initializeJournalPrimaryStorage, readJournalExplanationOriginal, probeJournalExplanation, readJournalExplanation,
  insertJournalExplanationOriginal,
  validLocalExecutionOwnerReceipt, assertJournalSubmissionCustody,
  assertJournalIntentCustody, assertJournalCancellationCustody} from './client-request-journal-format.mjs';
import {captureOriginalClientRequestJournalFacility} from './client-request-journal-facility.mjs';
import {createJournalAttempts, createJournalCancellation} from './client-request-journal-attempts.mjs';
import {createJournalSubmissionOriginals, createJournalSubmissionRows} from './client-request-journal-submission-originals.mjs';
export {validateSourceInventory};

const originalJournalCustodies = new WeakMap();
const originalJournalCustodyGet = WeakMap.prototype.get;
const originalJournalCustodySet = WeakMap.prototype.set;
const {facilityNativeRealpath, facilityRealpath, nativePathOptions,
  assertOriginalClientRequestJournalFacilityCurrent} = captureOriginalClientRequestJournalFacility();
export {assertOriginalClientRequestJournalFacilityCurrent};

// Private physical-facility observation, not request/Run authority or a
// capacity issuer. Only this module's actual constructor can install a member.
// Logical close, native connection close and optional observation ownership
// are distinct; a copied object cannot attest any of them.
export function observeOriginalClientRequestJournalCustody(journal) {
  const read = applyOriginal(originalJournalCustodyGet, originalJournalCustodies, [journal]);
  if (read === undefined) fail('ForeignClientRequestJournalCustody');
  return read();
}

// Membership only, without constructing an observation before its caller's
// optional metadata admission. This supplies no currentness or capacity.
export function assertOriginalClientRequestJournal(journal) {
  if (applyOriginal(originalJournalCustodyGet, originalJournalCustodies, [journal]) === undefined) {
    fail('ForeignClientRequestJournalCustody');
  }
}

// The existing observation key already retains every non-clock state field.
// Reuse only its closed budget message for this SAME failed Run/control frame;
// no second store, error chain, execution owner or status inference is added.


export function openClientRequestJournal(directory, options = {}, ownedOriginal) {
  const configuration = snapshotJournalConfiguration(directory, options, ownedOriginal);
  const {maxInspectionEntries, maxInspectionBytes, maxDatabaseBytes,
    primarySqlLimits, primaryExecutionLimits, primarySchemaLimits, primarySchemaSqlSupport,
    primaryCurrent, primaryDirectoryInspection, inspectionTemporaryDirectory,
    maxRunDefinitionWireBytes, submissionEpochNow, updateOriginalControl,
    sourceOperationLimits, inspectionBytes, walFrames} = configuration;
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
    applyOriginal(facilityNativeRealpath, facilityRealpath, [directory, nativePathOptions]);
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
  const ensureOpen = () => {
    if (closed) fail('ClientRequestJournalClosed');
    primaryCurrent?.();
    transaction.assertUsable();
  };
  const {rejectSubmission, submissionTransaction, submissionAttempt, rejectSubmissionEpoch,
    rejectCancellation, transact, cancellationAttempt} = createJournalAttempts(transaction, ensureOpen);
  let observationProjection;
  // Count only rows actually returned by these selected native reads. This
  // neither visits other Runs nor measures SQLite's internal page traversal.
  // The existing observation context aggregates scalars without per-get I/O.
  const selectedRequestStatement = (statement, selection, completeRef = false,
    completeRow = false) => {
    const get = statement.get;
    return Object.freeze({get(...parameters) {
      const row = applyOriginal(get, statement, parameters);
      if (observationProjection !== undefined) {
        try {
          const ref = completeRef ? {namespaceId: parameters[0],
            authorityScopeCid: parameters[1], runDefinitionCid: parameters[2]} : undefined;
          observationProjection.diagnostic('selected_rows_observed', {
            ref, rowOwner: 'request-journal', selection, rowKind: 'run',
            returnedRows: row === undefined ? 0 : 1,
            ...(selection === 'request' ? {requestSelection: {
              authorityScopeCid: parameters[0], requestId: parameters[1]},
            ...(row === undefined ? {} : {selectedRowRef: {namespaceId: row.namespace_id,
              authorityScopeCid: row.authority_scope_cid, runDefinitionCid: row.run_definition_cid}})} :
              !completeRef ? {runSelectionCid: parameters[0]} : {}),
            // Partial projections and pre-Run request keys cannot classify a
            // complete returned Run identity. Absence here means unknown.
            unrelatedRows: !completeRow ? undefined : row === undefined ? 0 :
              Number(row.namespace_id !== ref.namespaceId ||
                row.authority_scope_cid !== ref.authorityScopeCid ||
                row.run_definition_cid !== ref.runDefinitionCid),
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
  const runStateFrames = new WeakMap();
  const readRunDefinitionRow = (ref, requestControl) =>
    readJournalRunDefinitionRow(ref, requestControl, ensureOpen, selectRef);
  const retainRunStateFrame = (frame, selected) =>
    retainJournalRunStateFrame(runStateFrames, frame, selected);
  const admitRunDefinitionRow = (row, requestControl, publicationControl) =>
    admitJournalRunDefinitionRow(runStateFrames, row, requestControl, publicationControl,
      maxRunDefinitionWireBytes, updateOriginalControl);
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

  const {requestCancellation, recordCancellationOperation, lookupCancellationOperation} =
    createJournalCancellation(database, {selectRef, requestUsage, submissionIssued, cancellationUsage,
      cancellationIssued, cancellationSelect, cancellationInsert}, ensureOpen,
    {transact, rejectCancellation}, configuration);

  const readExplanationOriginal = ref =>
    readJournalExplanationOriginal(database, ref, maxRunDefinitionWireBytes);
  const probeExplanationRead = ref =>
    probeJournalExplanation(database, ensureOpen, ref, maxRunDefinitionWireBytes);
  const readExplanationSelection = (ref, extent) =>
    readJournalExplanation(database, ensureOpen, ref, extent, maxRunDefinitionWireBytes);
  const insertExplanationOriginal = (ref, original) =>
    insertJournalExplanationOriginal(database, ref, original);

  const {acceptRecord, lookupRecord, resolveOriginalDefinition} =
    createJournalRunRecords({select, selectRun, requestUsage, submissionIssued, cancellationUsage,
      cancellationIssued, intentSelect, insert, advanceSubmissionCustody},
    {ensureOpen, transact, checkSubmissionBinding, refuseEpoch, retainedIntent,
      assertJournalSubmissionCustody, assertJournalCancellationCustody,
      readExplanationOriginal, insertExplanationOriginal}, configuration);

  const observationConnection = createJournalObservationConnection(path, ensureOpen, primaryCurrent,
    primarySqlLimits, primaryExecutionLimits, walFrames, maxDatabaseBytes);
  const closeObservationStorage = observationConnection.closeObservationStorage;
  const journal = Object.freeze({
    retainSubmissionOperation,
    prepareSubmittedIntent(epoch, wire, control) {
      ensureOpen();
      // This admission is not cached. An explicit original preparation borrow
      // is registered separately and released by the active operation.
      return admitIntentOriginal(wire, control, epoch, 'InvalidClientSubmittedIntent', false).intent;
    },
    closeObservationStorage,
    observationStorage: observationConnection.observationStorage,
    installObservationProjection(projection) {
      if (!isHostObservationProjection(projection) || observationProjection !== undefined) {
        throw new TypeError('ForeignHostObservationProjection');
      }
      observationProjection = projection;
    },
    resolveOrBindSubmittedName,
    resolveNamedSubmissionAttempt(name, intent, options, control) {
      return submissionAttempt(options.submissionRef, intent, options, control,
        () => journal.resolveOrBindSubmittedName(name, intent, options, control), 'recorded', originalIntent);
    },
    checkSubmittedIntent,
    recordSubmittedIntent,
    // Invocation facts are projections of the existing admission boundary,
    // never replacement receipts or proof that another invocation did not run.
    checkSubmissionAttempt(submissionRef, intent, options, control) {
      return submissionAttempt(submissionRef, intent, options, control,
        () => journal.checkSubmittedIntent(submissionRef, intent, options, control), 'checked', originalIntent);
    },
    recordSubmissionAttempt(submissionRef, intent, options, control) {
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
    accept(identity, {namespaceId, runDefinitionCid, revision = 0,
      lookupExpiresAt, submission}, control) {
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
    acceptDefinition(identity, {namespaceId, runDefinition, resultNames, runAdmissionEvidence, originalPlan, originalExplanation, originalInferRun,
      revision = 0, lookupExpiresAt, submission}, requestControl, publicationControl) {
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
      let explanationOriginal;
      let acknowledgeExplanation;
      if (originalExplanation !== undefined) {
        if (originalPlan === undefined || typeof publicationControl.originalRunExplanationAdmissionEvidence !== 'function' ||
            !admissionEvidenceShape(runAdmissionEvidence, updateOriginalControl)) fail('InvalidClientRunExplanationOriginal');
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
          if (operationKeys(fields).length !== 1 || field === undefined ||
              !Object.hasOwn(field, 'value') || typeof field.value !== 'string' || field.value.length === 0) {
            fail('InvalidClientRunExplanationOriginal');
          }
          const factsWire = field.value;
          if (Buffer.byteLength(factsWire) > maxRunDefinitionWireBytes) fail('InvalidClientRunAdmissionEvidence');
          explanationOriginal = Object.freeze({factsWire});
        } catch (cause) {
          if (cause?.code === 'InvalidClientRunAdmissionEvidence') throw cause;
          fail('InvalidClientRunExplanationOriginal', cause);
        }
      }
      if (originalInferRun !== undefined) {
        if (typeof publicationControl.originalInferRunAdmissionEvidence !== 'function' ||
            !admissionEvidenceShape(runAdmissionEvidence, updateOriginalControl)) {
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
            !admissionEvidenceShape(runAdmissionEvidence, updateOriginalControl)) fail('InvalidClientRunPlanOriginal');
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
          if (cause?.code === 'InvalidClientRunAdmissionEvidence') throw cause;
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
      // COMMIT ACK. Unknown/rollback throws never reach this release. Drop the
      // transient Facts wrapper before the compiler owner cuts its last alias
      // and returns the same funded loan; it may still report cleanup failure.
      explanationOriginal = undefined;
      if (acknowledgeExplanation !== undefined) applyOriginal(acknowledgeExplanation,
        publicationControl, [originalExplanation, definition,
          requestControl.clientRequestProgramCid(identity), runAdmissionEvidence]);
      // This optional projection runs after the semantic transaction. Only
      // its branded bounded queue is reachable here, never user delivery.
      observationProjection?.accepted(accepted,
        requestControl.clientRequestCallerId(identity));
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
    lookup(key, control) {
      return lookupRecord(key, control)?.found;
    },
    // Internal owner recovery, not a wire credential or current permission.
    // Both logical keys are re-admitted before the caller can reuse the scope.
    lookupIdentity(key, control) {
      return lookupRecord(key, control)?.identity;
    },
    lookupDefinition(key, requestControl, publicationControl) {
      const retained = lookupRecord(key, requestControl);
      if (retained === undefined) return undefined;
      return Object.freeze({...retained.found,
        ...retainedRunFacts(retained.row, publicationControl,
          maxRunDefinitionWireBytes, updateOriginalControl),
      });
    },
    // Attach reads the original accepted Run Definition by its exact ref.
    // It does not infer authority from a CID alone or create another Run.
    lookupRunDefinition(ref, requestControl, publicationControl, originalFrame) {
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
    lookupRunExplanationOriginal(ref, requestControl, publicationControl) {
      const row = readRunDefinitionRow(ref, requestControl);
      if (row === undefined) return undefined;
      // Admit the SAME original Run before reading its associated facet.
      admitRunDefinitionRow(row, requestControl, publicationControl);
      return readExplanationOriginal(ref);
    },
    // Private explicit-read DATA only. The installed caller must admit entry
    // before probe, then the complete original/codec overlap before full read.
    probeRunExplanationOriginal: probeExplanationRead,
    readRunExplanationOriginal: readExplanationSelection,
    canReinspectRunStopAfterStatePublication(beforeFrame, afterFrame) {
      ensureOpen();
      return reinspectJournalRunStopAfterStatePublication(runStateFrames, beforeFrame, afterFrame);
    },
    canReinspectRunAfterPhysicalClose(beforeFrame, afterFrame) {
      ensureOpen();
      return reinspectJournalRunAfterPhysicalClose(runStateFrames, beforeFrame, afterFrame);
    },
    canReinspectRunForSigning(beforeFrame, afterFrame) {
      ensureOpen();
      return reinspectJournalRunForSigning(runStateFrames, beforeFrame, afterFrame);
    },
    // Private original-content projection for this journal's admitted Run.
    // It grants neither current authorization nor a physical/resume claim.
    // Historical unselected Runs remain readable without a new reference;
    // missing selected custody cannot be repaired from current caller options.
    originalSubmittedIntent(identity, {namespaceId}, requestControl,
      publicationControl) {
      ensureOpen();
      if (!text(namespaceId) ||
          typeof requestControl?.clientSubmittedIntentRequestsCommitStop !== 'function') {
        fail('InvalidClientRequestJournalControl');
      }
      const fields = checkedIdentity(identity, requestControl);
      const requestOriginal = Object.freeze({identity, fields});
      let previousRunRow, previousRunFacts, previousIntent;
      let previousReference;
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
              Object.keys(run.row).some(key => run.row[key] !== previousRunRow[key])) {
            previousRunFacts = retainedRunFacts(run.row, publicationControl,
              maxRunDefinitionWireBytes, updateOriginalControl);
            previousRunRow = Object.freeze({...run.row});
          }
          const facts = previousRunFacts;
          const expectedCid = facts.runAdmissionEvidence?.submittedIntentCid;
          const row = intentSelect.get(fields.requestId);
          if (row === undefined) {
            if (expectedCid !== undefined) fail('ClientSubmittedIntentCustodyLost');
            return undefined;
          }
          previousIntent = retainedIntentOriginal(row, requestControl, undefined, previousIntent);
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
    // Advance only published logical/control/availability facts. The same
    // original accepted row, complete observation fence and confirmed COMMIT
    // own this counter. Neither reading nor wall-clock time increments it.
    publishRunState(frame, state, requestControl, publicationControl) {
      ensureOpen();
      const retained = runStateFrames.get(frame);
      if (retained === undefined || retained.requestControl !== requestControl ||
          retained.publicationControl !== publicationControl) fail('ForeignRunStateObservation');
      const expected = retained.row;
      if (!Number.isSafeInteger(expected.state_revision) || expected.state_revision < 0 ||
          expected.state_observation_key !== null &&
            (typeof expected.state_observation_key !== 'string' || expected.state_observation_key.length === 0)) {
        fail('ClientRequestJournalCorrupt');
      }
      // The frame already admitted this complete original row. Reuse its
      // typed Run/control facts, not a decode/encode/hash of identical bytes.
      const control = issueInstalledRunControlObservation(requestControl, {
          revision: frame.revision,
          cancellationRequested: frame.cancellationRequested,
          physicallyUnstarted: frame.physicalStartReserved === false,
          preDispatchFailureConfirmed: frame.preDispatchFailureConfirmed,
          physicalCloseConfirmed: frame.physicalCloseConfirmed,
        });
      const runId = publicationControl.runDefinitionRunId(frame.runDefinition);
      const originalMessage = retainedBudgetFailureMessage(expected.state_observation_key,
        state, runId, control, publicationControl.executionFailureExplanation);
      const projection = prepareInstalledRunStateObservation(requestControl, {
        state: {...state, ...(originalMessage === undefined ? {} : {
          terminal_error: {...state.terminal_error, message: originalMessage},
        }), control}, runId,
        revision: expected.state_revision, priorKey: expected.state_observation_key,
      });
      const currentRow = () => {
        const row = readRunDefinitionRow(frame.ref, requestControl);
        if (row === undefined || Object.keys(row).length !== Object.keys(expected).length ||
            Object.keys(expected).some(key => row[key] !== expected[key])) {
          fail('RunStateObservationChanged');
        }
        return row;
      };
      // This read follows projection/callback work and is the unchanged
      // observation's linearization point. No mutation means no write TX or
      // COMMIT. Changed observations still use the original atomic CAS below.
      const observed = currentRow();
      if (projection.key === observed.state_observation_key) return projection.wire;
      return transact('run_state_observation', 'ClientRunStateObservationUnknown',
        error => ['RunStateObservationChanged', 'ClientRequestJournalCorrupt',
          'ForeignRunStateObservation', 'MoonBitHostFailure'].includes(error?.code), () => {
          const row = currentRow();
          if (projection.key !== row.state_observation_key) {
            const result = database.prepare(`UPDATE client_requests SET
              state_revision = ?, state_observation_key = ?
              WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?
                AND state_revision = ? AND state_observation_key IS ?`).run(
              projection.revision, projection.key, row.namespace_id, row.authority_scope_cid,
              row.run_definition_cid, row.state_revision, row.state_observation_key);
            if (Number(result.changes) !== 1) fail('RunStateObservationChanged');
          }
          // transaction.run exposes this value only after confirmed COMMIT.
          return projection.wire;
        });
    },
    // One observation frame for an already selected Run, not an authority
    // cache. Every call reads committed storage and checks connection health.
    // Reuse admission only for an exactly unchanged complete row, including
    // cancellation and payload bytes; revision alone is not sufficient.
    observeRunCancellation(ref, requestControl, publicationControl, originalFrame) {
      const selected = Object.freeze({namespaceId: ref?.namespaceId,
        authorityScopeCid: ref?.authorityScopeCid, runDefinitionCid: ref?.runDefinitionCid});
      let previousRow;
      let previousFacts;
      if (originalFrame !== undefined) {
        ensureOpen();
        const retained = retainRunStateFrame(originalFrame,selected);
        if (retained.requestControl !== requestControl ||
            retained.publicationControl !== publicationControl) {
          fail('ForeignRunStateObservation');
        }
        // The same observation already admitted this complete original row.
        // The first probe still reads and compares every current scalar field.
        previousRow = retained.row;
        previousFacts = Object.freeze({revision: originalFrame.revision,
          cancellationRequested: originalFrame.cancellationRequested});
      }
      return () => {
        try {
          const row = readRunDefinitionRow(selected, requestControl);
          if (row === undefined) {
            previousRow = previousFacts = undefined;
            return undefined;
          }
          if (previousRow !== undefined && sameRunStateRow(row,previousRow)) {
            return previousFacts;
          }
          const facts = admitRunDefinitionRow(row, requestControl, publicationControl);
          previousRow = row;
          // Do not expose cached mutable nested evidence or a Definition as
          // permission. The caller receives only the current cancellation fact.
          previousFacts = Object.freeze({revision: facts.revision,
            cancellationRequested: facts.cancellationRequested});
          return previousFacts;
        } catch (error) {
          previousRow = previousFacts = undefined;
          throw error;
        }
      };
    },
    // Recover identity and Definition from one physical journal observation.
    // This internal owner must not be projected as a Client wire response.
    lookupOwnedDefinition(key, requestControl, publicationControl) {
      const retained = lookupRecord(key, requestControl);
      if (retained === undefined) return undefined;
      return Object.freeze({...retained.found,
        requestIdentity: retained.identity,
        ...retainedRunFacts(retained.row, publicationControl,
          maxRunDefinitionWireBytes, updateOriginalControl),
      });
    },
    // A resend can resolve an already accepted request before issuing a new
    // plan or Run Definition. The shared owner compares the checked intent;
    // absence does not prove that a concurrent submission cannot still land.
    resolveDefinition(identity, {namespaceId}, requestControl,
      publicationControl) {
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
    async admitOrLookupDefinition(identity, {namespaceId, lookupExpiresAt,
      issueDefinition, resultNames, sourceInventory, submission}, requestControl, publicationControl) {
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
      const epochValidity = checkSubmissionBinding(fields, submission, requestControl);
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
    lookupOriginalSourceOperation(ref, occurrence) {
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
    recordCancellationAttempt(ref, {attemptRef, ...options}, requestControl, publicationControl) {
      return cancellationAttempt(journal, ref, attemptRef, options, requestControl, publicationControl);
    },
    lookupCancellationOperation,
    // This observation is only available to the SAME original Store owner
    // holding its stable lease. It never starts work, marks a stop or claims
    // cleanup. The caller must still inspect publication and revalidate this
    // nominal frame before recording the existing terminal observation.
    observeStoppedLocalExecutionOwner(ref, originalFrame) {
      ensureOpen();
      const original = retainRunStateFrame(originalFrame, ref);
      if (localExecutionOwnerLookup === undefined) return false;
      const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
      if (!sameRunStateRow(row, original.row)) fail('ClientRunStopObservationChanged');
      if (row.physical_start_reserved !== 1 || row.physical_close_confirmed !== 0 ||
          row.observed_terminal_outcome !== null) return false;
      const stored = localExecutionOwnerLookup.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
      if (stored === undefined) return false;
      const receipt = {token: stored.owner_token, anchor: {identity: stored.anchor_identity,
        device: stored.anchor_device, inode: stored.anchor_inode}};
      if (!validLocalExecutionOwnerReceipt(receipt)) return false;
      const stopped = originalLocalExecutionOwnerStopped(ownedOriginal, receipt);
      // The native owner observation must not make a stale frame current.
      if (!sameRunStateRow(selectRef.get(ref.namespaceId, ref.authorityScopeCid,
        ref.runDefinitionCid), original.row)) fail('ClientRunStopObservationChanged');
      return stopped === true;
    },
    // Only original execution custody may report a completed physical close.
    // A successor needs the retained native lease, publication and cleanup
    // observations; an empty worker map never establishes any of them.
    markPhysicalClose(ref, terminalOutcome = null, originalFrame) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid) ||
          terminalOutcome !== null &&
            !['failed', 'cancelled'].includes(terminalOutcome)) {
        fail('InvalidClientRunStopObservation');
      }
      const original=originalFrame===undefined?undefined:retainRunStateFrame(originalFrame,ref);
      return transact('stop_observation', 'ClientRunStopObservationUnknown',
        error => ['ClientRunStopObservationDenied','ClientRunStopObservationChanged'].includes(error?.code), () => {
        const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid,
          ref.runDefinitionCid);
        if(original!==undefined && !sameRunStateRow(row,original.row)) {
          fail('ClientRunStopObservationChanged');
        }
        if (row === undefined || row.physical_start_reserved !== 1 ||
            row.physical_close_confirmed === 1 &&
              row.observed_terminal_outcome !== terminalOutcome) {
          fail('ClientRunStopObservationDenied');
        }
        if (row.physical_close_confirmed === 0) {
          const changed=database.prepare(`UPDATE client_requests SET
            physical_close_confirmed = 1, observed_terminal_outcome = ?,
            revision = revision + 1
            WHERE namespace_id = ? AND authority_scope_cid = ? AND
              run_definition_cid = ? AND physical_start_reserved = 1 AND
              physical_close_confirmed = 0`).run(terminalOutcome,
            ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
          if(Number(changed.changes)!==1)fail('ClientRunStopObservationChanged');
        }
      });
    },
    // Physical Host evidence only: a failure before invoking Site execution
    // is confirmed. A lost reply or absent worker cannot call this method.
    markPreDispatchFailure(ref) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid)) {
        fail('InvalidClientRunFailureObservation');
      }
      return transact('failure_observation',
        'ClientRunFailureObservationUnknown',
        error => typeof error?.code === 'string' &&
          (error.code.startsWith('ClientRun') ||
            error.code.startsWith('ClientRequest')), () => {
        const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid,
          ref.runDefinitionCid);
        if (row === undefined || row.dispatch_reserved !== 1 ||
            row.pre_dispatch_failure_confirmed === 0 &&
            row.physical_start_reserved !== 0) {
          fail('ClientRunFailureObservationDenied');
        }
        if (row.pre_dispatch_failure_confirmed === 0 &&
            confirmPreDispatchFailure.run(ref.namespaceId,
              ref.authorityScopeCid, ref.runDefinitionCid).changes !== 1) {
          fail('ClientRequestJournalCorrupt');
        }
      });
    },
    // Keep the owner-issued `needs_reconciliation` state of a started Run
    // whose Effect outcomes are unknown. It is recorded once and never
    // replaced: a different state for the same Run is a conflict.
    recordReconciliationState(ref, wire) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid) || typeof wire !== 'string' ||
          Buffer.byteLength(wire, 'utf8') > maxRunDefinitionWireBytes) {
        fail('InvalidClientRunReconciliation');
      }
      let state;
      try { state = JSON.parse(wire); }
      catch { fail('InvalidClientRunReconciliation'); }
      if (state?.status !== 'needs_reconciliation' ||
          state?.next_action?.kind !== 'reconcile') {
        fail('InvalidClientRunReconciliation');
      }
      return transact('reconciliation', 'ClientRunReconciliationUnknown',
        error => typeof error?.code === 'string' &&
          error.code.startsWith('ClientRun'), () => {
        const row = selectedRequestStatement(database.prepare(`SELECT physical_start_reserved,
          reconciliation_state_wire FROM client_requests
          WHERE namespace_id = ? AND authority_scope_cid = ? AND
            run_definition_cid = ?`), 'run-definition', true).get(ref.namespaceId, ref.authorityScopeCid,
          ref.runDefinitionCid);
        if (row === undefined || row.physical_start_reserved !== 1) {
          fail('ClientRunReconciliationDenied');
        }
        if (row.reconciliation_state_wire !== null &&
            row.reconciliation_state_wire !== wire) {
          fail('ClientRunReconciliationConflict');
        }
        if (row.reconciliation_state_wire === null) {
          database.prepare(`UPDATE client_requests SET
            reconciliation_state_wire = ?, revision = revision + 1
            WHERE namespace_id = ? AND authority_scope_cid = ? AND
              run_definition_cid = ?`).run(wire, ref.namespaceId,
            ref.authorityScopeCid, ref.runDefinitionCid);
        }
      });
    },
    lookupReconciliationState(ref) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid)) {
        fail('InvalidClientRunLookup');
      }
      const row = selectedRequestStatement(database.prepare(`SELECT reconciliation_state_wire
        FROM client_requests WHERE namespace_id = ? AND
          authority_scope_cid = ? AND run_definition_cid = ?`), 'run-definition', true).get(
        ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
      return row?.reconciliation_state_wire ?? undefined;
    },
    close() {
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
