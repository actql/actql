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
import type {WireControlCommand, WireControlOperationReceipt} from
  '../../packages/client-wire/interactive-control.generated.js';
import type {runtimeCore} from '../host-common/runtime-core.mjs';
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
  structuralExplanationOriginalShape, text, validateSourceInventory,
  type InteractivePhysicalStart, type SampleStartClaim} from './client-request-journal-records.mjs';
import {explanationOriginalTable, explanationContextOriginalTable, explanationPlanOriginalTable,
  admitJournalDirectory, syncDirectory, columns, selectColumns,
  snapshotJournalConfiguration, initializeJournalPrimaryStorage, readJournalExplanationOriginal,
  explanationReadSelection, probeJournalExplanation, readJournalExplanation,
  insertJournalExplanationOriginal, verifyJournalExplanationContext, verifyJournalExplanationPlan,
  validLocalExecutionOwnerReceipt, assertJournalSubmissionCustody,
  assertJournalIntentCustody, assertJournalCancellationCustody} from './client-request-journal-format.mjs';
import {captureOriginalClientRequestJournalFacility} from './client-request-journal-facility.mjs';
import {createJournalAttempts, createJournalCancellation} from './client-request-journal-attempts.mjs';
import {createJournalSubmissionOriginals, createJournalSubmissionRows} from './client-request-journal-submission-originals.mjs';
export {validateSourceInventory};
import {relationSampleAdoptionTable, relationSampleStartTable, inspectRelationSampleStartStorage,
  clientRelationSampleAdoptionStorage} from './client-relation-sample-adoption.mjs';

type JournalCustody = Readonly<{
  journalClosed: boolean; databaseClosed: boolean; observationAttempted: boolean; observationDatabaseClosed: boolean;
}>;
type JournalOptions = NonNullable<Parameters<typeof snapshotJournalConfiguration>[1]>;
type JournalStatement = ReturnType<JournalSqlConnection['prepare']>;
type SqlRow = NonNullable<ReturnType<JournalStatement['get']>>;
type SqlArgument = Parameters<JournalStatement['get']>[number];
type Projection = NonNullable<ReturnType<typeof installHostObservation>>;
type RunRecords = ReturnType<typeof createJournalRunRecords>;
type RunAdmission = Parameters<RunRecords['acceptRecord']>[1];
type RequestControl = Parameters<RunRecords['acceptRecord']>[2];
type RequestKey = Parameters<RunRecords['lookupRecord']>[0];
type OwnedDefinitionKey = RequestKey & Partial<Pick<WireRunRef, 'runDefinitionCid'>>;
type RequestReader = Parameters<RunRecords['lookupRecord']>[1];
type DefinitionControl = Parameters<typeof checkedRunDefinition>[1];
type RunDefinition = ReturnType<typeof checkedRunDefinition>;
type AdmissionEvidence = Parameters<typeof admissionEvidenceShape>[0];
type DefinitionAdmission = Omit<RunAdmission, 'runDefinitionCid' | 'runDefinitionWire' | 'runAdmissionEvidence'> &
  Readonly<{runDefinition: unknown; runAdmissionEvidence?: AdmissionEvidence;
    originalPlan?: unknown; originalExplanation?: unknown; originalInferRun?: unknown}>;
type AdmittedDefinition = Omit<ReturnType<RunRecords['acceptRecord']>, 'runDefinitionWire' | 'epochRejected'> &
  Readonly<{runDefinition: RunDefinition | undefined;
    physicalStartReserved?: never; observedTerminalOutcome?: never; cancellationRequested?: never;
  }>;
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
type SampleRequestScope = RequestScope & Readonly<{
  sampleRunRef?: WireRunRef;
  reserveSampleRead?: (bytes: number, previousBytes?: number) => unknown;
}>;
type StopRequestControl = RequestControl & Parameters<SubmissionRows['retainedIntentOriginal']>[1] & Readonly<{
  clientSubmittedIntentRequestsCommitStop(intent: unknown): unknown;
  clientSubmittedIntentRequestsReadOnly(intent: unknown): unknown;
  clientSubmittedIntentRequestsDebug?(intent: unknown): unknown;
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
type Current = () => unknown;
type Reserve = (bytes: number) => unknown;
type PublicationControl = ReturnType<typeof runtimeCore>['publicationControl'];
type RelationSampleControl = DefinitionControl & Partial<Pick<PublicationControl, 'checkClientRelationSampleProfile'>>;
type RelationSampleStorage = ReturnType<typeof clientRelationSampleAdoptionStorage>;
type SampleReadCustody = Parameters<RelationSampleStorage['readRetained']>[3];
type SampleReadSelection = Parameters<RelationSampleStorage['readRetained']>[1] & Readonly<{nextStepId?: string}>;
type SampleNextCustody = SampleReadCustody & Readonly<{debugPause?: {
  parked: DebugTaskParked; startRevision: number; producer: {
    stepId: string; outputPortId: string; carrierContractCid: string; generation: number; attemptSequence: number
  }
}}>;
type DebugLimits = Parameters<PublicationControl['admitRunEvidence']>[2];
type DebugCommandControl = Pick<PublicationControl, 'admitRunEvidence'>;
type DebugReceiptControl = DebugCommandControl & Pick<PublicationControl,
  'admit' | 'issueLocalDebugResumeReceipt' | 'runDefinitionRunId' | 'localDebugResumeReceiptConstructionBytes'>;
type DebugResumeCommand = WireControlCommand & {operation: 'resume'; interval: {until: 'step' | 'terminal'; guards: null}};
type DebugOriginalCommon = Readonly<{paused_at: number; expires_at: number}> & (
  Readonly<{resume_wire: null; resume_accepted_at: null}> |
  Readonly<{resume_wire: string; resume_accepted_at: number}>
);
type DebugEntryOriginal = SqlRow & DebugOriginalCommon & Readonly<{
  resume_source?: 'entry'; submitted_intent_cid: string; parked_revision: number; resume_revision: number | null;
}>;
type DebugTaskOriginal = SqlRow & DebugOriginalCommon & Readonly<{
  resume_source?: 'task'; control_revision: number; step_id: string; next_step_id: string | null;
  committed_generation: number; paused_revision: number; start_revision: number; operation_id: string | null;
}>;
type DebugReceiptSelection = Readonly<{runDefinition: RunDefinition; logicalMapCid: string; reserve: Reserve}>;
type DebugReceiptIssue = Omit<DebugReceiptSelection, 'reserve'> & Readonly<{limits: DebugLimits}>;
type DebugEntryParked = Readonly<{kind: 'parked'; revision: number; expiresAt: number; pausedAt: number}>;
type DebugTaskPosition = Readonly<{stepId: string; nextStepId: string | null; committedGeneration: number}>;
type DebugTaskParked = DebugEntryParked & DebugTaskPosition & Readonly<{controlRevision: number}>;
type DebugEntryAccepted = Readonly<{kind: 'resume_accepted'; revision: number; commandCid: string;
  until: 'step' | 'terminal'; acceptedAt: number}>;
type DebugTaskAccepted = DebugEntryAccepted & DebugTaskPosition & Readonly<{controlRevision: number}>;
type DebugResumeLookup = Readonly<{kind: 'unobserved'}> |
  ((DebugEntryAccepted | DebugTaskAccepted) & Readonly<{receipt?: WireControlOperationReceipt}>);
type DebugTaskPauseInput = DebugTaskPosition & Readonly<{startRevision: number; expectedRevision: number;
  controlRevision: number; expiresAt?: number; current: Current}>;
type DebugEntryResumeInput = Readonly<{commandWire: string; current: Current;
  capture?: (value: DebugEntryAccepted) => unknown; receiptOriginal?: DebugReceiptSelection}>;
type DebugTaskResumeInput = Omit<DebugEntryResumeInput, 'capture'> & DebugTaskPosition & Readonly<{
  startRevision: number; capture: (value: DebugTaskAccepted) => unknown}>;
type DebugPauseInput = Readonly<{parked: (DebugEntryParked & {controlRevision?: undefined}) | DebugTaskParked;
  startRevision?: number; current: Current; requireEntryDeadline?: boolean}>;
type DebugLookupInput = Readonly<{operationId: string; commandCid: string; acceptedFromRevision: number;
  current: Current; reserve?: Reserve; reserveConstruction?: Reserve}>;

function integer(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value);
}

const originalJournalCustodies = new WeakMap<object, () => JournalCustody>();
// One entry gate and first resume per original Run, under the same revision
// and physical-start transaction as the existing cancellation fence.
const debugEntryTable = `CREATE TABLE client_debug_entry_parks (
  run_definition_cid TEXT PRIMARY KEY REFERENCES client_requests(run_definition_cid) ON DELETE CASCADE,
  submitted_intent_cid TEXT NOT NULL,
  parked_revision INTEGER NOT NULL CHECK (parked_revision BETWEEN 1 AND 2147483645),
  expires_at INTEGER NOT NULL CHECK (expires_at > 0),
  paused_at INTEGER NOT NULL CHECK (paused_at >= 0 AND paused_at < expires_at),
  resume_wire TEXT,
  receipt_wire TEXT CHECK (receipt_wire IS NULL OR
    (resume_wire IS NOT NULL AND length(CAST(receipt_wire AS BLOB)) BETWEEN 1 AND 4096)),
  receipt_cid TEXT CHECK (length(CAST(receipt_cid AS BLOB)) = 71),
  resume_revision INTEGER,
  resume_accepted_at INTEGER,
  CHECK ((resume_wire IS NULL) = (resume_accepted_at IS NULL)),
  CHECK ((receipt_wire IS NULL) = (receipt_cid IS NULL)),
  CHECK (resume_accepted_at >= paused_at AND resume_accepted_at < expires_at),
  CHECK ((resume_wire IS NULL AND resume_revision IS NULL) OR
    (resume_wire IS NOT NULL AND resume_revision IS NOT NULL AND resume_revision = parked_revision + 1))
) STRICT`;
const debugTaskPauseTable = `CREATE TABLE client_debug_task_pauses (
  run_definition_cid TEXT NOT NULL REFERENCES client_debug_entry_parks(run_definition_cid) ON DELETE CASCADE,
  control_revision INTEGER NOT NULL CHECK (control_revision BETWEEN 2 AND 2147483646 AND control_revision % 2 = 0),
  step_id TEXT NOT NULL,
  next_step_id TEXT CHECK (next_step_id IS NULL OR length(CAST(next_step_id AS BLOB)) = 71),
  committed_generation INTEGER NOT NULL CHECK (committed_generation BETWEEN 1 AND 2147483647),
  paused_revision INTEGER NOT NULL CHECK (paused_revision BETWEEN 1 AND 2147483646),
  expires_at INTEGER NOT NULL CHECK (expires_at > 0),
  paused_at INTEGER NOT NULL CHECK (paused_at >= 0 AND paused_at < expires_at),
  journal_ordinal INTEGER NOT NULL UNIQUE CHECK (journal_ordinal > 0),
  operation_id TEXT,
  resume_wire TEXT,
  receipt_wire TEXT CHECK (receipt_wire IS NULL OR
    (resume_wire IS NOT NULL AND length(CAST(receipt_wire AS BLOB)) BETWEEN 1 AND 4096)),
  receipt_cid TEXT CHECK (length(CAST(receipt_cid AS BLOB)) = 71),
  resume_accepted_at INTEGER,
  CHECK ((resume_wire IS NULL) = (resume_accepted_at IS NULL)),
  CHECK ((receipt_wire IS NULL) = (receipt_cid IS NULL)),
  CHECK (resume_accepted_at >= paused_at AND resume_accepted_at < expires_at),
  CHECK ((resume_wire IS NULL) = (operation_id IS NULL)),
  PRIMARY KEY (run_definition_cid, control_revision),
  UNIQUE (run_definition_cid, operation_id)
) STRICT`;
const debugCommandLimits = Object.freeze({maxWireBytes: 4096, maxNodes: 64, maxDepth: 8});
const debugReceiptLimits = Object.freeze({maxWireBytes: 4096, maxNodes: 64, maxDepth: 8});
const debugReceiptColumns = `CASE WHEN length(CAST(p.receipt_wire AS BLOB)) = ? AND p.receipt_cid = ?
  THEN p.receipt_wire END AS receipt_wire, length(CAST(p.receipt_wire AS BLOB)) AS receipt_bytes,
  CASE WHEN length(CAST(p.receipt_cid AS BLOB)) = 71 THEN p.receipt_cid
    WHEN p.receipt_cid IS NOT NULL THEN '' END AS receipt_cid,
  length(CAST(r.run_definition_wire AS BLOB)) AS definition_bytes,
  CASE WHEN length(CAST(r.run_definition_wire AS BLOB)) = ?
    THEN r.run_definition_wire END AS run_definition_wire`;
const validCommittedGeneration = (value: unknown): value is number => integer(value) && value >= 1 && value <= 2147483647;

function validDebugPauseTime(row: SqlRow) {
  return integer(row.paused_at) && row.paused_at >= 0 &&
    integer(row.expires_at) && row.paused_at < row.expires_at;
}

function validDebugResumeTime(row: SqlRow) {
  const acceptedAt = row.resume_accepted_at;
  return row.resume_wire === null ? acceptedAt === null :
    typeof row.resume_wire === 'string' && integer(acceptedAt) && integer(row.paused_at) &&
    integer(row.expires_at) && acceptedAt >= row.paused_at && acceptedAt < row.expires_at;
}

function requireDebugEntryAuthority(current: Current) {
  const outcome = current();
  if (typeof (outcome as {then?: unknown} | undefined)?.then === 'function') void Promise.resolve(outcome).catch(() => {});
  if (outcome !== true) fail('ClientRunDebugEntryDenied');
}

function readDebugEntryCommand(wire: unknown, ref: WireRunRef, control: DebugCommandControl): DebugResumeCommand {
  if (typeof wire !== 'string' || wire.length > debugCommandLimits.maxWireBytes ||
      Buffer.byteLength(wire) > debugCommandLimits.maxWireBytes) fail('ClientRunDebugEntryInvalidCommand');
  let command: WireControlCommand;
  try {
    command = JSON.parse(control.admitRunEvidence('control_command', wire, debugCommandLimits).wire) as WireControlCommand;
  } catch (cause) {fail('ClientRunDebugEntryInvalidCommand', cause);}
  if (command.run_ref.namespaceId !== ref.namespaceId ||
      command.run_ref.authorityScopeCid !== ref.authorityScopeCid ||
      command.run_ref.runDefinitionCid !== ref.runDefinitionCid) fail('ClientRunDebugEntryForeignCommand');
  if (command.operation !== 'resume' || !text(command.operation_id) ||
      command.interval === undefined || (command.interval.until !== 'step' && command.interval.until !== 'terminal') ||
      command.interval.guards !== null) {
    fail('ClientRunDebugEntryUnsupportedCommand');
  }
  return command as DebugResumeCommand;
}

function readDebugEntryResume(entry: DebugEntryOriginal, ref: WireRunRef, control: DebugCommandControl) {
  const command = readDebugEntryCommand(entry.resume_wire, ref, control);
  if (command.expected_control_revision !== entry.parked_revision) fail('ClientRunDebugEntryCorrupt');
  return command;
}

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
  const {maxRecords, maxInspectionEntries, maxInspectionBytes, maxDatabaseBytes,
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
  let relationSampleStarts: WeakMap<object, SampleStartClaim> | undefined;
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
    retainSubmissionOperation, epochClock} = submissionOriginals;
  let relationSampleStorage: ReturnType<typeof clientRelationSampleAdoptionStorage> | undefined;
  const sampleStorage = () => relationSampleStorage ??=
    clientRelationSampleAdoptionStorage(database, {
      ensureOpen, transact, maxRecords, maxWireBytes: inspectionBytes,
      now: () => epochClock().observed_at,
      createSupported: primarySchemaSqlSupport === undefined ||
        primarySchemaSqlSupport.includes(relationSampleAdoptionTable),
    });
  const intentSelect = database.prepare('SELECT * FROM client_submitted_intents WHERE submission_id = ?');
  let sampleOriginalExtent: JournalStatement | undefined;
  // This selected probe returns only a scalar. Use the same checked schema
  // and exact keys as the retained reads, including restart and epoch inputs.
  function sampleOriginalStoredBytes(namespaceId: string,
    fields: Readonly<{authorityScopeCid: string; requestId: string}>, definition: string) {
    sampleOriginalExtent ??= database.prepare(`SELECT
      i.phase AS phase,
      COALESCE(length(CAST(r.run_definition_wire AS BLOB)), 0) +
      COALESCE(length(CAST(r.run_admission_evidence_json AS BLOB)), 0) +
      COALESCE(length(CAST(r.result_names_json AS BLOB)), 0) +
      COALESCE(length(CAST(i.intent_wire AS BLOB)), 0) +
      COALESCE(length(CAST(i.epoch_wire AS BLOB)), 0) +
      COALESCE(length(CAST(s.link_wire AS BLOB)), 0) AS original_bytes,
      ${([
        ['r', selectColumns.split(',').map(field => field.trim())],
        ['i', ['submission_id', 'authority_scope_cid', 'nonce', 'epoch_wire',
          'intent_cid', 'intent_wire', 'accepted_at', 'phase', 'outcome_wire', 'revision']],
        ['s', ['fresh_submission_id', 'original_submission_id', 'link_wire']],
        ['e', ['authentication_key', 'observed_at']],
      ] as const).flatMap(([table, fields]) => fields.map(field =>
        `COALESCE(length(CAST(${table}.${field} AS BLOB)), 0)`)).join(' + ')} AS stored_bytes
      FROM client_requests r LEFT JOIN client_submitted_intents i
        ON i.submission_id = r.caller_request_id
      LEFT JOIN client_submission_restarts s ON s.fresh_submission_id = r.caller_request_id
      LEFT JOIN client_submission_epoch_authority e ON e.singleton = 1
      WHERE r.authority_scope_cid = ? AND r.caller_request_id = ? AND
        r.namespace_id = ? AND r.run_definition_cid = ?`);
    const row = sampleOriginalExtent.get(fields.authorityScopeCid, fields.requestId, namespaceId, definition);
    if (row === undefined) fail('ClientRunSampleStartOriginalUnavailable');
    const {stored_bytes, original_bytes, phase} = row;
    if (typeof stored_bytes !== 'number' || !Number.isSafeInteger(stored_bytes) ||
        stored_bytes < 1 || stored_bytes > 2147483519) fail('ClientRunSampleOriginalCapacity');
    if (typeof original_bytes !== 'number' || !Number.isSafeInteger(original_bytes) ||
        original_bytes < 0 || original_bytes > stored_bytes) fail('ClientRunSampleOriginalCapacity');
    return {stored_bytes, original_bytes, phase};
  }
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

  let debugEntrySchema: JournalStatement | undefined, readDebugEntry: JournalStatement | undefined;
  const hasDebugEntryStorage = () => {
    debugEntrySchema ??= database.prepare(`SELECT substr(sql, 1, ?) AS sql FROM sqlite_master
      WHERE type = 'table' AND name = 'client_debug_entry_parks'`);
    const row = debugEntrySchema.get(debugEntryTable.length + 1);
    if (row !== undefined && row.sql !== debugEntryTable) fail('UnknownClientRequestJournalFormat');
    return row !== undefined;
  };
  const selectDebugEntry = `SELECT ${debugReceiptColumns}, p.submitted_intent_cid, p.parked_revision, p.expires_at, p.paused_at,
    p.resume_revision, p.resume_accepted_at, CASE WHEN length(CAST(p.resume_wire AS BLOB)) <= ?
      THEN p.resume_wire END AS resume_wire
    FROM client_debug_entry_parks p JOIN client_requests r USING (run_definition_cid)
    WHERE r.namespace_id = ? AND r.authority_scope_cid = ? AND r.run_definition_cid = ?`;
  const checkedDebugEntry = (entry: SqlRow | undefined): DebugEntryOriginal | undefined => {
    if (entry !== undefined && (!cid(entry.submitted_intent_cid) ||
        !validDebugPauseTime(entry) || !validDebugResumeTime(entry) ||
        !integer(entry.parked_revision) || entry.parked_revision < 1 || entry.parked_revision > 2147483645 ||
        (entry.resume_wire === null) !== (entry.resume_revision === null) ||
        entry.resume_revision !== null && entry.resume_revision !== entry.parked_revision + 1)) {
      fail('ClientRunDebugEntryCorrupt');
    }
    return entry as DebugEntryOriginal | undefined;
  };
  const debugEntry = (ref: WireRunRef, receiptBytes = 0, receiptCid: string | null = null, definitionBytes = 0) => {
    if (!hasDebugEntryStorage()) return undefined;
    readDebugEntry ??= database.prepare(selectDebugEntry);
    return checkedDebugEntry(readDebugEntry.get(receiptBytes, receiptCid, definitionBytes, debugCommandLimits.maxWireBytes,
      ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid));
  };
  const debugEntryTransaction = <Result extends SynchronousRuntimeData>(action: () => Result) =>
    transact('debug_entry', 'ClientRunDebugEntryUnknown', error => {
      const code = (error as Failure)?.code;
      return typeof code === 'string' && (code.startsWith('ClientRunDebugEntry') ||
        code === 'ControlRevisionExhausted' || code === 'UnknownClientRequestJournalFormat');
    }, action);
  const validDebugEntryRef = (ref: WireRunRef | undefined): ref is WireRunRef =>
    text(ref?.namespaceId) && cid(ref?.authorityScopeCid) && cid(ref?.runDefinitionCid);
  const advanceDebugRevision = (ref: WireRunRef, revision: number, started = 0) => {
    const advanced = database.prepare(`UPDATE client_requests SET revision = revision + 1
      WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?
      AND revision = ? AND dispatch_reserved = 1 AND physical_start_reserved = ?
      AND pre_dispatch_failure_confirmed = 0 AND cancellation_requested = 0
      AND physical_close_confirmed = 0 AND observed_terminal_outcome IS NULL`)
      .run(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid, revision, started);
    if (advanced.changes !== 1) fail('ClientRunDebugEntryRevisionConflict');
  };
  function debugEntryResult(entry: DebugEntryOriginal, command?: undefined): DebugEntryParked;
  function debugEntryResult(entry: DebugEntryOriginal, command: DebugResumeCommand, revision?: number,
    acceptedAt?: number): DebugEntryAccepted;
  function debugEntryResult(entry: DebugEntryOriginal, command?: DebugResumeCommand,
    revision = entry.resume_revision, acceptedAt = entry.resume_accepted_at): DebugEntryParked | DebugEntryAccepted {
    if (command === undefined) {
      return Object.freeze({kind: 'parked', revision: entry.parked_revision, expiresAt: entry.expires_at, pausedAt: entry.paused_at});
    }
    if (revision === null || acceptedAt === null) fail('ClientRunDebugEntryCorrupt');
    return Object.freeze({kind: 'resume_accepted', revision, commandCid: command.self_cid,
      until: command.interval.until, acceptedAt});
  }

  let liveDebugEntry: JournalStatement | undefined, liveDebugTask: JournalStatement | undefined;
  let debugTaskPauseSchema: JournalStatement | undefined, latestDebugTaskPause: JournalStatement | undefined;
  let debugTaskPauseByOperation: JournalStatement | undefined;
  const hasDebugTaskPauseStorage = () => {
    debugTaskPauseSchema ??= database.prepare(`SELECT substr(sql, 1, ?) AS sql FROM sqlite_schema
      WHERE type = 'table' AND name = 'client_debug_task_pauses'`);
    const row = debugTaskPauseSchema.get(debugTaskPauseTable.length + 1);
    if (row !== undefined && row.sql !== debugTaskPauseTable) fail('UnknownClientRequestJournalFormat');
    return row !== undefined;
  };
  // A task with missing or foreign start evidence stays a selected row so
  // validation rejects it instead of falling through to the entry history.
  const selectDebugTaskPause = `SELECT ${debugReceiptColumns}, p.control_revision, p.step_id,
    CASE WHEN p.next_step_id IS NULL OR length(CAST(p.next_step_id AS BLOB)) = 71
      THEN p.next_step_id ELSE '' END AS next_step_id,
    p.committed_generation, p.paused_revision, s.start_revision,
    p.expires_at, p.paused_at, p.operation_id, p.resume_accepted_at,
    CASE WHEN length(CAST(p.resume_wire AS BLOB)) <= ? THEN p.resume_wire END AS resume_wire
    FROM client_debug_task_pauses p JOIN client_requests r USING (run_definition_cid)
      LEFT JOIN client_debug_entry_parks e ON e.run_definition_cid = r.run_definition_cid
      LEFT JOIN client_relation_sample_starts s ON s.run_definition_cid = r.run_definition_cid
        AND s.namespace_id = r.namespace_id AND s.authority_scope_cid = r.authority_scope_cid
        AND s.submitted_intent_cid = e.submitted_intent_cid AND s.start_revision = e.resume_revision + 1
    WHERE r.namespace_id = ? AND r.authority_scope_cid = ? AND r.run_definition_cid = ?`;
  const checkedDebugTaskPause = (pause: SqlRow | undefined): DebugTaskOriginal | undefined => {
    if (pause !== undefined && (!integer(pause.control_revision) ||
        pause.control_revision < 2 || pause.control_revision > 2147483646 || pause.control_revision % 2 !== 0 ||
        !cid(pause.step_id) || (pause.next_step_id !== null && !cid(pause.next_step_id)) ||
        !validCommittedGeneration(pause.committed_generation) ||
        !integer(pause.paused_revision) ||
        !integer(pause.start_revision) || pause.start_revision < 1 ||
        pause.paused_revision <= pause.start_revision || pause.paused_revision > 2147483646 ||
        !validDebugPauseTime(pause) || !validDebugResumeTime(pause) ||
        (pause.resume_wire === null) !== (pause.operation_id === null) ||
        (pause.operation_id !== null && !text(pause.operation_id)))) {
      fail('ClientRunDebugEntryCorrupt');
    }
    return pause as DebugTaskOriginal | undefined;
  };
  const readDebugTaskPause = (ref: WireRunRef, operationId?: string) => {
    if (!hasDebugTaskPauseStorage()) return undefined;
    if (operationId === undefined) {
      latestDebugTaskPause ??= database.prepare(selectDebugTaskPause + ' ORDER BY p.control_revision DESC LIMIT 1');
      return checkedDebugTaskPause(latestDebugTaskPause.get(0, null, 0, debugCommandLimits.maxWireBytes,
        ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid));
    }
    debugTaskPauseByOperation ??= database.prepare(selectDebugTaskPause + ' AND p.operation_id = ?');
    return checkedDebugTaskPause(debugTaskPauseByOperation.get(0, null, 0, debugCommandLimits.maxWireBytes,
      ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid, operationId));
  };
  let readDebugResumeOriginal: JournalStatement | undefined;
  const debugResumeOriginal = (ref: WireRunRef, operationId: string, receiptBytes = 0,
    receiptCid: string | null = null, definitionBytes = 0):
    DebugEntryOriginal | (DebugTaskOriginal & {resume_source: 'task'}) | undefined => {
    // The table formats are immutable after creation. Once installed, use
    // one SQLite statement snapshot for the indexed task and entry arms.
    if (!hasDebugTaskPauseStorage()) return debugEntry(ref, receiptBytes, receiptCid, definitionBytes);
    if (!hasDebugEntryStorage()) fail('ClientRunDebugEntryCorrupt');
    readDebugResumeOriginal ??= database.prepare(`
      WITH task AS (${selectDebugTaskPause} AND p.operation_id = ?)
      SELECT 'task' AS resume_source, receipt_wire, receipt_bytes, receipt_cid, definition_bytes, run_definition_wire,
        control_revision, step_id, next_step_id, committed_generation, paused_revision,
        start_revision, expires_at, paused_at, operation_id, resume_accepted_at, resume_wire,
        NULL AS submitted_intent_cid, NULL AS parked_revision, NULL AS resume_revision
      FROM task
      UNION ALL
      SELECT 'entry', receipt_wire, receipt_bytes, receipt_cid, definition_bytes, run_definition_wire,
        NULL, NULL, NULL, NULL, NULL, NULL, expires_at, paused_at, NULL, resume_accepted_at, resume_wire,
        submitted_intent_cid, parked_revision, resume_revision
      FROM (${selectDebugEntry}) WHERE NOT EXISTS (SELECT 1 FROM task)`);
    const original = readDebugResumeOriginal.get(receiptBytes, receiptCid, definitionBytes, debugCommandLimits.maxWireBytes,
      ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid, operationId,
      receiptBytes, receiptCid, definitionBytes, debugCommandLimits.maxWireBytes, ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
    return original?.resume_source === 'task'
      ? checkedDebugTaskPause(original) as DebugTaskOriginal & {resume_source: 'task'}
      : checkedDebugEntry(original);
  };
  const readDebugTaskCommand = (pause: DebugTaskOriginal, ref: WireRunRef, publicationControl: DebugCommandControl) => {
    const command = readDebugEntryCommand(pause.resume_wire, ref, publicationControl);
    if (command.operation_id !== pause.operation_id ||
        command.expected_control_revision !== pause.paused_revision) fail('ClientRunDebugEntryCorrupt');
    return command;
  };
  const liveDebugTaskRun = (ref: WireRunRef, startRevision: number, publicationControl: DebugCommandControl) => {
    const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
    const entry = debugEntry(ref);
    if (row?.physical_start_reserved !== 1 || row.cancellation_requested !== 0 ||
        row.physical_close_confirmed !== 0 || row.observed_terminal_outcome !== null ||
        entry?.resume_wire == null || entry.resume_revision === null || entry.resume_revision + 1 !== startRevision ||
        !inspectRelationSampleStartStorage(database)) fail('ClientRunDebugEntryOriginalUnavailable');
    const sample = database.prepare(`SELECT start_revision, submitted_intent_cid FROM client_relation_sample_starts
      WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?`)
      .get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
    if (sample?.start_revision !== startRevision || sample.submitted_intent_cid !== entry.submitted_intent_cid) {
      fail('ClientRunDebugEntryOriginalUnavailable');
    }
    return {row, entry, entryCommand: readDebugEntryResume(entry, ref, publicationControl)};
  };
  const debugTaskPauseResult = (pause: Pick<DebugTaskOriginal, 'paused_revision' | 'control_revision' |
    'step_id' | 'next_step_id' | 'expires_at' | 'paused_at' | 'committed_generation'>): DebugTaskParked => Object.freeze({
    kind: 'parked', revision: pause.paused_revision,
    controlRevision: pause.control_revision, stepId: pause.step_id, nextStepId: pause.next_step_id, expiresAt: pause.expires_at,
    pausedAt: pause.paused_at, committedGeneration: pause.committed_generation});
  const debugTaskResumeResult = (pause: DebugTaskOriginal, command: DebugResumeCommand,
    acceptedAt = pause.resume_accepted_at): DebugTaskAccepted => {
    if (acceptedAt === null) fail('ClientRunDebugEntryCorrupt');
    return Object.freeze({kind: 'resume_accepted', revision: pause.paused_revision + 1,
      controlRevision: pause.control_revision, stepId: pause.step_id, nextStepId: pause.next_step_id,
      commandCid: command.self_cid, until: command.interval.until, committedGeneration: pause.committed_generation,
      acceptedAt});
  };

  const reserveDebugReceipt = (reserve: Reserve, current: Current, control: DebugReceiptControl, limits: DebugLimits, issuing: boolean) => {
    const reserved = reserve(control.localDebugResumeReceiptConstructionBytes(limits, issuing));
    if (typeof (reserved as {then?: unknown} | undefined)?.then === 'function') {
      void Promise.resolve(reserved).catch(() => {});
      fail('ClientRunDebugEntryInvalidSelection');
    }
    requireDebugEntryAuthority(current);
  };
  const prepareDebugReceiptIssue = (selection: DebugReceiptSelection | undefined, ref: WireRunRef,
    commandWire: unknown, current: Current, control: DebugReceiptControl): DebugReceiptIssue | undefined => {
    if (selection === undefined) return undefined;
    const {runDefinition, logicalMapCid, reserve} = selection;
    if (runDefinition?.identity !== ref.runDefinitionCid || !cid(logicalMapCid) ||
        typeof reserve !== 'function') fail('ClientRunDebugEntryInvalidSelection');
    if (typeof commandWire !== 'string' || commandWire.length > debugCommandLimits.maxWireBytes ||
        Buffer.byteLength(commandWire) > debugCommandLimits.maxWireBytes) fail('ClientRunDebugEntryInvalidCommand');
    // The receipt reuses the admitted command's RunRef and operation ID. Its
    // fixed replacement fields and additional preimages need at most 1024
    // further UTF-8 bytes, besides the original Run ID carried in the receipt.
    const runId = control.runDefinitionRunId(runDefinition);
    const limits = {...debugReceiptLimits, maxWireBytes: Math.min(debugReceiptLimits.maxWireBytes,
      Buffer.byteLength(commandWire) + 1024 + 6 * runId.length)};
    reserveDebugReceipt(reserve, current, control, limits, true);
    return {runDefinition, logicalMapCid, limits};
  };
  const issueDebugReceipt = (selection: DebugReceiptIssue | undefined, ref: WireRunRef,
    original: DebugEntryOriginal | DebugTaskOriginal, commandWire: string, acceptedAt: number,
    control: DebugReceiptControl, later: boolean) => {
    if (selection === undefined) return undefined;
    const revision = later ? original.paused_revision : original.parked_revision;
    if (!integer(revision)) fail('ClientRunDebugEntryCorrupt');
    try {
      const parkWire = JSON.stringify({
        kind: later ? 'logical_step' : 'entry', run_ref: ref, revision,
        logical_map_cid: selection.logicalMapCid, ttl_policy: 'original_debug_entry_deadline',
        paused_at: new Date(original.paused_at).toISOString(),
        expires_at: new Date(original.expires_at).toISOString(),
        ...(later ? {start_revision: original.start_revision, control_revision: original.control_revision,
          committed_generation: original.committed_generation, completed_step_id: original.step_id,
          next_step_id: original.next_step_id} : {}),
      });
      const evidence = control.admitRunEvidence('control_command', commandWire, debugCommandLimits);
      return control.issueLocalDebugResumeReceipt(selection.runDefinition, evidence, parkWire,
        revision + 1, new Date(acceptedAt).toISOString(), selection.limits);
    } catch (cause) {fail('ClientRunDebugEntryReceiptRejected', cause);}
  };
  const readDebugReceipt = (original: DebugEntryOriginal | DebugTaskOriginal,
    summary: Readonly<{revision: number; acceptedAt: number}>, command: DebugResumeCommand,
    limits: DebugLimits, definitionLimits: DebugLimits, control: DebugReceiptControl) => {
    if (typeof original.receipt_wire !== 'string' || typeof original.run_definition_wire !== 'string') {
      fail('ClientRunDebugEntryCorrupt');
    }
    let receipt: WireControlOperationReceipt, runId: string;
    try {
      const run = control.admit('run_definition', original.run_definition_wire, definitionLimits);
      if (run.identity !== command.run_ref.runDefinitionCid || run.wire !== original.run_definition_wire) {
        fail('ClientRunDebugEntryCorrupt');
      }
      runId = control.runDefinitionRunId(run);
      const admitted = control.admitRunEvidence('control_operation_receipt', original.receipt_wire, limits);
      if (admitted.identity !== original.receipt_cid) fail('ClientRunDebugEntryCorrupt');
      receipt = JSON.parse(admitted.wire) as WireControlOperationReceipt;
    } catch (cause) {fail('ClientRunDebugEntryCorrupt', cause);}
    const operation = receipt.operation_ref, state = receipt.observed_state;
    if (receipt.outcome !== 'accepted' || operation.operation_id !== command.operation_id ||
        operation.command_cid !== command.self_cid ||
        operation.accepted_from_revision !== command.expected_control_revision ||
        operation.run_ref.namespaceId !== command.run_ref.namespaceId ||
        operation.run_ref.authorityScopeCid !== command.run_ref.authorityScopeCid ||
        operation.run_ref.runDefinitionCid !== command.run_ref.runDefinitionCid ||
        state.run_id !== runId || state.status !== 'resuming' || state.resume_origin?.kind !== 'manual' ||
        state.resume_origin.command_cid !== command.self_cid ||
        state.control_revision !== summary.revision ||
        state.updated_at !== new Date(summary.acceptedAt).toISOString()) {
      fail('ClientRunDebugEntryCorrupt');
    }
    return receipt;
  };

  const interactiveStart: InteractivePhysicalStart = {
    takeSample(ticket, match) {
      const claim = relationSampleStarts?.get(ticket);
      if (claim === undefined || !match(claim)) fail('ClientRunSampleStartOriginalUnavailable');
      relationSampleStarts!.delete(ticket);
      return claim;
    },
    selectDebug(ref, revision, selection, publication) {
      const parked = debugEntry(ref);
      if (parked === undefined) {
        if (selection !== undefined) fail('ClientRunDebugEntryOriginalUnavailable');
        return undefined;
      }
      if (selection === undefined) return false;
      requireDebugEntryAuthority(selection.current);
      if (epochClock().observed_at >= parked.expires_at || parked.resume_wire === null ||
          revision !== parked.resume_revision) return false;
      const commandControl = publication as typeof publication & Partial<DebugCommandControl>;
      if (typeof commandControl.admitRunEvidence !== 'function') fail('ClientRunDebugEntryOriginalUnavailable');
      const command = readDebugEntryResume(parked, ref, commandControl as DebugCommandControl);
      if (command.self_cid !== selection.commandCid) fail('ClientRunDebugEntryForeignCommand');
      return Object.freeze({commandCid: command.self_cid, until: command.interval.until,
        acceptedRevision: parked.resume_revision, physicalStartRevision: revision + 1});
    },
    persistSample(row, claim, revision) {
      if (!cid(row.run_definition_cid) || !text(row.namespace_id) || !cid(row.authority_scope_cid)) {
        fail('ClientRunSampleStartOriginalUnavailable');
      }
      if (primarySchemaSqlSupport !== undefined && !primarySchemaSqlSupport.includes(relationSampleStartTable)) {
        fail('ClientRunSampleStartOriginalUnavailable');
      }
      if (!inspectRelationSampleStartStorage(database)) database.exec(relationSampleStartTable);
      database.prepare(`INSERT INTO client_relation_sample_starts (run_definition_cid, namespace_id,
        authority_scope_cid, submitted_intent_cid, control_admission_cid, resolved_profile_cid,
        start_revision) VALUES (?, ?, ?, ?, ?, ?, ?)`).run(row.run_definition_cid, row.namespace_id,
          row.authority_scope_cid, claim.intentCid, claim.controlAdmissionCid, claim.resolvedProfileCid, revision);
    },
    sampleWriter(ref, claim, revision, publication) {
      // The installed visitor is the only route to the scoped original
      // prefix. The writer carries scalars and the original accessors only.
      const {matchesAdoption, visitAdoption} = claim;
      const control = publication as typeof publication & Partial<Parameters<RelationSampleStorage['writer']>[2]>;
      if (typeof matchesAdoption !== 'function' || typeof visitAdoption !== 'function' ||
          typeof control.admitRunEvidence !== 'function' || typeof control.sealRunEvidence !== 'function') {
        fail('ClientRunSampleStartOriginalUnavailable');
      }
      const original = Object.freeze({revision, controlAdmissionCid: claim.controlAdmissionCid,
        resolvedProfileCid: claim.resolvedProfileCid, matchesAdoption, visitAdoption});
      return sampleStorage().writer(ref, original, control as Parameters<RelationSampleStorage['writer']>[2]);
    },
    requireDebugCurrent: requireDebugEntryAuthority,
  };
  const {reserveDispatch, reservePhysicalStart: startPhysical} =
    createJournalRunStart({select, selectRef, reserve, reservePhysicalStart, localExecutionOwnerInsert},
      {ensureOpen, transact, getDeliveredJournal: () => deliveredJournal, sourceOperations,
        ownedOriginal, captureOriginalLocalExecutionOwner, validLocalExecutionOwnerReceipt,
        interactive: interactiveStart},
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
    probeJournalExplanation(database, ensureOpen, ref, maxRunDefinitionWireBytes,
      includeContext, maxOriginalExplanationWireBytes);
  const readExplanationSelection = (ref: WireRunRef, extent: Parameters<typeof readJournalExplanation>[3], includeContext: boolean) =>
    readJournalExplanation(database, ensureOpen, ref, extent, maxRunDefinitionWireBytes,
      includeContext, maxOriginalExplanationWireBytes);
  const insertExplanationOriginal = (ref: WireRunRef, original: Parameters<typeof insertJournalExplanationOriginal>[2]) =>
    insertJournalExplanationOriginal(database, ref, original);

  const {acceptRecord, lookupRecord, resolveOriginalDefinition} =
    createJournalRunRecords({select, selectRun, requestUsage, submissionIssued, cancellationUsage,
      cancellationIssued, intentSelect, insert, advanceSubmissionCustody},
    {ensureOpen, transact, checkSubmissionBinding, refuseEpoch, retainedIntent,
      assertJournalSubmissionCustody, assertJournalCancellationCustody,
      readExplanationOriginal, insertExplanationOriginal,
      verifyExplanationContext: (runDefinitionCid, original) =>
        verifyJournalExplanationContext(database, runDefinitionCid, original),
      verifyExplanationPlan: (runDefinitionCid, original) =>
        verifyJournalExplanationPlan(database, runDefinitionCid, original)},
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
        primarySchemaSqlSupport.includes(explanationContextOriginalTable) &&
        primarySchemaSqlSupport.includes(explanationPlanOriginalTable);
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
            if (!journal.supportsOriginalExplanationContext()) {
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
        if (explanationOriginal?.contextWire !== undefined) {
          if (explanationOriginal.invocationTemplateWire === undefined) fail('InvalidClientRunExplanationOriginal');
          const bytes = Buffer.byteLength(original.compiledPlanWire) + Buffer.byteLength(original.planViewWire) +
            Buffer.byteLength(explanationOriginal.factsWire) + Buffer.byteLength(explanationOriginal.contextWire) +
            Buffer.byteLength(explanationOriginal.invocationTemplateWire);
          if (bytes > maxOriginalExplanationWireBytes) fail('InvalidClientRunAdmissionEvidence');
          explanationOriginal = Object.freeze({...explanationOriginal, plan: Object.freeze({...original})});
        } else {
          runAdmissionEvidence = {...runAdmissionEvidence,
            logicalPlanOriginal: Object.freeze({...original})};
        }
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
    // Only the explicit authorized original Plan operation selects the
    // structural companion. Ordinary Run state and replay keep their old row.
    lookupRunPlanOriginal(ref: WireRunRef, requestControl: Parameters<typeof admitJournalRunDefinitionRow>[2],
      publicationControl: DefinitionControl) {
      const original = journal.lookupRunDefinition(ref, requestControl, publicationControl);
      if (original === undefined) return undefined;
      const sql = explanationReadSelection(database, ensureOpen, ref, false);
      const row = database.prepare(`SELECT ${sql.matches} AS original_ref_matches,
        ${sql.planMatches} AS plan_matches, ${sql.plan} AS plan_present,
        CASE WHEN ${sql.plan} AND typeof(${sql.compiledPlan})='text'
          AND length(CAST(${sql.compiledPlan} AS BLOB)) > 0
          AND length(CAST(${sql.compiledPlan} AS BLOB)) + length(CAST(${sql.planView} AS BLOB)) <= ?
          THEN ${sql.compiledPlan} ELSE NULL END AS compiled_plan_wire,
        CASE WHEN ${sql.plan} AND typeof(${sql.planView})='text'
          AND length(CAST(${sql.planView} AS BLOB)) > 0
          AND length(CAST(${sql.compiledPlan} AS BLOB)) + length(CAST(${sql.planView} AS BLOB)) <= ?
          THEN ${sql.planView} ELSE NULL END AS plan_view_wire
        ${sql.from}`).get(maxOriginalExplanationWireBytes, maxOriginalExplanationWireBytes,
          ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
      if (row === undefined || row.original_ref_matches !== 1 || row.plan_matches !== 1) {
        fail('ClientRequestJournalCorrupt');
      }
      if (row.plan_present === 0) return original;
      const plan = Object.freeze({compiledPlanWire: row.compiled_plan_wire, planViewWire: row.plan_view_wire});
      if (original.runAdmissionEvidence?.logicalPlanOriginal !== undefined ||
          !logicalPlanOriginalShape(plan)) fail('ClientRequestJournalCorrupt');
      return Object.freeze({...original, runAdmissionEvidence: Object.freeze(
        {...original.runAdmissionEvidence, logicalPlanOriginal: plan})});
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
    originalSubmittedIntent(identity: unknown, {namespaceId, sampleRunRef, reserveSampleRead}: SampleRequestScope,
      requestControl: StopRequestControl, publicationControl: RelationSampleControl) {
      ensureOpen();
      if (!text(namespaceId) ||
          typeof requestControl?.clientSubmittedIntentRequestsCommitStop !== 'function' ||
          sampleRunRef !== undefined && (typeof requestControl.clientSubmittedIntentRequestsDebug !== 'function' ||
            typeof reserveSampleRead !== 'function')) {
        fail('InvalidClientRequestJournalControl');
      }
      const fields = checkedIdentity(identity, requestControl);
      let sampleDefinitionCid: string | undefined, sampleStoredBytes: number | undefined;
      let sampleInitialExtent: ReturnType<typeof sampleOriginalStoredBytes> | undefined;
      const reserveSampleOriginalExtent = (bytes: number) => {
        if (reserveSampleRead === undefined) fail('InvalidClientRunSampleReadReservation');
        const reserved = sampleStoredBytes === undefined ? reserveSampleRead(bytes) :
          reserveSampleRead(bytes, sampleStoredBytes);
        if (reserved !== undefined) {
          if (typeof (reserved as {then?: unknown} | null)?.then === 'function') void Promise.resolve(reserved).catch(() => {});
          fail('InvalidClientRunSampleReadReservation');
        }
        sampleStoredBytes = bytes;
      };
      if (sampleRunRef !== undefined) {
        sampleDefinitionCid = sampleRunRef?.runDefinitionCid;
        if (sampleRunRef?.namespaceId !== namespaceId ||
            sampleRunRef?.authorityScopeCid !== fields.authorityScopeCid || !cid(sampleDefinitionCid)) {
          fail('ClientRunSampleStartOriginalUnavailable');
        }
        sampleInitialExtent = sampleOriginalStoredBytes(namespaceId, fields, sampleDefinitionCid);
        reserveSampleOriginalExtent(sampleInitialExtent.stored_bytes);
      }
      const requestOriginal = Object.freeze({identity, fields});
      let previousRunRow: NonNullable<ReturnType<RunRecords['lookupRecord']>>['row'] | undefined;
      let previousRunFacts: ReadmittedRunFacts | undefined;
      let previousIntent: ReturnType<SubmissionRows['retainedIntentOriginal']> | undefined;
      let previousReference: Readonly<{epochWire: unknown; nonce: unknown; wire: string}> | undefined;
      const readOriginal = () => {
        try {
          // Repeat inside the actual retained read transaction, including
          // every freshness probe. A resize callback can observe the Journal
          // but cannot admit a larger original than the funded extent.
          if (sampleDefinitionCid !== undefined) {
            const extent = sampleOriginalStoredBytes(namespaceId, fields, sampleDefinitionCid);
            if (sampleStoredBytes === undefined || sampleInitialExtent === undefined ||
                extent.stored_bytes > sampleStoredBytes || extent.original_bytes !== sampleInitialExtent.original_bytes) {
              fail('ClientRunSampleOriginalCapacity');
            }
          }
          assertJournalSubmissionCustody(requestUsage, submissionIssued);
          assertJournalIntentCustody(intentUsage, intentIssued, intentRetired, inspectionBytes);
          const run = lookupRecord({namespaceId, authorityScopeCid: fields.authorityScopeCid,
            requestId: fields.requestId}, requestControl, requestOriginal);
          if (run === undefined || requestControl.clientRequestRelation(identity,
            run.identity) !== 1) fail('ClientRequestSubmittedIntentMismatch');
          if (sampleDefinitionCid !== undefined && run.row.run_definition_cid !== sampleDefinitionCid) {
            fail('ClientRunSampleStartOriginalUnavailable');
          }
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
            if (sampleDefinitionCid !== undefined) fail('ClientRequestSubmittedIntentBindingMissing');
            return undefined;
          }
          // A ready outcome rechecks its Run by the intent's own key. For
          // this funded read that key must name the same measured Run row.
          if (sampleDefinitionCid !== undefined && row.authority_scope_cid !== fields.authorityScopeCid) {
            fail('ClientSubmittedIntentCorrupt');
          }
          previousIntent = retainedIntentOriginal(row as Parameters<typeof retainedIntentOriginal>[0], requestControl, undefined, previousIntent);
          const {intent, value: original} = previousIntent;
          if (intent === undefined || !['preparing', 'held', 'ready'].includes(original.phase)) {
            fail('ClientRequestSubmittedIntentMismatch');
          }
          if (expectedCid === undefined) {
            if (sampleDefinitionCid !== undefined || requestControl.clientSubmittedIntentRequestsCommitStop(intent) ||
                requestControl.clientSubmittedIntentRequestsReadOnly(intent)) {
              fail('ClientRequestSubmittedIntentBindingMissing');
            }
            return undefined;
          }
          if (expectedCid !== original.intentCid) fail('ClientRequestSubmittedIntentMismatch');
          // Run acceptance commits the intent CID before dispatch. The
          // submission outcome may still be preparing until dispatch returns.
          if (sampleDefinitionCid !== undefined && requestControl.clientSubmittedIntentRequestsDebug?.(intent) !== true) {
            fail('ClientRunSampleStartOriginalUnavailable');
          }
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
      const checkOriginal = (current: ReturnType<typeof readOriginal>) => {
        if (current === undefined || current.intentCid !== original.intentCid ||
            current.intentWire !== original.intentWire ||
            current.referenceWire !== original.referenceWire ||
            current.runDefinitionCid !== original.runDefinitionCid) {
          previousRunRow = previousRunFacts = previousIntent = previousReference = undefined;
          fail('ClientRequestSubmittedIntentMismatch');
        }
      };
      const originalView: Readonly<{intent: typeof original.intent; referenceWire: string;
        assertCurrent(): void; checkSampleProfile?: never}> = {intent: original.intent, referenceWire: original.referenceWire,
        assertCurrent() {
          try {
            ensureOpen();
            checkOriginal(transaction.run(readOriginal));
          } catch (error) {
            previousRunRow = previousRunFacts = previousIntent = previousReference = undefined;
            throw error;
          }
        }};
      if (sampleDefinitionCid !== undefined) {
        const definitionCid = sampleDefinitionCid;
        const initialExtent = sampleInitialExtent;
        if (initialExtent === undefined) fail('ClientRunSampleOriginalCapacity');
        // Only this selected Journal original can supply its authenticated
        // reference. The installed checker still owns the exact live Run and
        // logical observation. Neither check grants capture or disclosure.
        let checking = false;
        const checkSampleProfile = (owner: unknown, definition: unknown, observation: unknown,
          records: unknown, limits: DebugLimits) => {
          if (checking) fail('ClientRunSampleProfileCheckActive');
          if (typeof publicationControl.checkClientRelationSampleProfile !== 'function') {
            fail('ClientRunSampleStartOriginalUnavailable');
          }
          checking = true;
          try {
            originalView.assertCurrent();
            const checked = publicationControl.checkClientRelationSampleProfile(owner, identity, definition,
              observation, original.referenceWire, records, limits);
            if (typeof (checked as {then?: unknown} | undefined)?.then === 'function') {
              void Promise.resolve(checked).catch(() => {});
              fail('InvalidClientRunSampleProfileCheck');
            }
            if (checked?.profile === null || typeof checked?.profile !== 'object' ||
                !cid(checked.controlAdmissionCid) || !cid(checked.resolvedProfileCid) ||
                typeof checked.matchesStart !== 'function') {
              fail('InvalidClientRunSampleProfileCheck');
            }
            originalView.assertCurrent();
            const startTicket = Object.freeze({});
            relationSampleStarts ??= new WeakMap();
            relationSampleStarts.set(startTicket, {
              identity, requestControl, publicationControl, namespaceId, sampleDefinitionCid: definitionCid,
              intentCid: original.intentCid,
              controlAdmissionCid: checked.controlAdmissionCid,
              resolvedProfileCid: checked.resolvedProfileCid,
              matchesStart: checked.matchesStart,
              matchesAdoption: checked.matchesAdoption,
              visitAdoption: checked.visitAdoption,
              reserveCurrentRow() {
                // Inspect can publish a larger observation key while the
                // original entry waits. Submission can also become ready.
                // Fund the larger row before the start transaction, which
                // rechecks the exact extent and authenticates the originals.
                const next = sampleOriginalStoredBytes(namespaceId, fields, definitionCid);
                if (sampleStoredBytes !== undefined && (next.phase === 'ready' ||
                    initialExtent.phase === 'preparing' && next.phase === 'preparing') &&
                    next.original_bytes === initialExtent.original_bytes && next.stored_bytes > sampleStoredBytes) {
                  reserveSampleOriginalExtent(next.stored_bytes);
                }
              },
              currentRow() {
                // The caller already owns the start transaction. Keep the
                // measured read, authenticated epoch and bound intent together.
                checkOriginal(readOriginal());
                return previousRunRow;
              },
            });
            return Object.freeze({profile: checked.profile, startTicket, withAdoption: checked.withAdoption,
              logicalMapCid: checked.logicalMapCid});
          } finally {
            checking = false;
          }
        };
        return Object.freeze({...originalView, checkSampleProfile});
      }
      return Object.freeze(originalView);
    },
    publishRunState,
    observeRunCancellation,
    // Recover identity and Definition from one physical journal observation.
    // This internal owner must not be projected as a Client wire response.
    lookupOwnedDefinition(key: OwnedDefinitionKey, requestControl: RequestReader, publicationControl: DefinitionControl) {
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
    parkDebugEntry(identity: unknown, {ref, expectedRevision, expiresAt, current}: Readonly<{
      ref: WireRunRef; expectedRevision: number; expiresAt: number; current: Current}>,
      requestControl: StopRequestControl & Required<Pick<StopRequestControl, 'clientSubmittedIntentRequestsDebug'>>,
      publicationControl: DefinitionControl) {
      ensureOpen();
      if (!validDebugEntryRef(ref) || !Number.isInteger(expectedRevision) || expectedRevision < 0 ||
          !Number.isSafeInteger(expiresAt) || expiresAt <= 0 || typeof current !== 'function') {
        fail('ClientRunDebugEntryInvalidSelection');
      }
      requireDebugEntryAuthority(current);
      const fields = checkedIdentity(identity, requestControl);
      const original = journal.originalSubmittedIntent(identity, {namespaceId: ref.namespaceId},
        requestControl, publicationControl);
      if (original === undefined || requestControl.clientSubmittedIntentRequestsDebug(original.intent) !== true ||
          fields.authorityScopeCid !== ref.authorityScopeCid) fail('ClientRunDebugEntryOriginalUnavailable');
      const intent = requestControl.clientSubmittedIntentCid(original.intent);
      original.assertCurrent();
      return debugEntryTransaction(() => {
        const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
        if (row === undefined) fail('ClientRunDebugEntryOriginalUnavailable');
        const definition = retainedRunDefinition(row as SqlRow & Parameters<typeof retainedRunDefinition>[0],
          publicationControl, maxRunDefinitionWireBytes);
        if (row.caller_request_id !== fields.requestId || typeof row.run_admission_evidence_json !== 'string' ||
            JSON.parse(row.run_admission_evidence_json)?.submittedIntentCid !== intent ||
            typeof row.lookup_expires_at !== 'string') fail('ClientRunDebugEntryOriginalUnavailable');
        const validUntil = Math.min(Date.parse(row.lookup_expires_at), Date.parse(JSON.parse(definition.wire).valid_until));
        if (!Number.isSafeInteger(validUntil) || expiresAt > validUntil) fail('ClientRunDebugEntryInvalidSelection');
        const entry = debugEntry(ref);
        if (entry !== undefined) {
          if (entry.parked_revision !== expectedRevision + 1 || entry.submitted_intent_cid !== intent ||
              entry.expires_at !== expiresAt || row.revision !== entry.parked_revision ||
              entry.resume_wire !== null || row.dispatch_reserved !== 1 || row.physical_start_reserved !== 0 ||
              row.pre_dispatch_failure_confirmed !== 0 || row.cancellation_requested !== 0 ||
              row.physical_close_confirmed !== 0 || row.observed_terminal_outcome !== null) {
            fail('ClientRunDebugEntryRevisionConflict');
          }
          const observedAt = epochClock().observed_at;
          requireDebugEntryAuthority(current);
          return observedAt >= expiresAt ? Object.freeze({kind: 'expired'}) : debugEntryResult(entry);
        }
        if (expectedRevision >= 2147483645) fail('ControlRevisionExhausted');
        const pausedAt = epochClock().observed_at;
        if (pausedAt >= expiresAt) {
          requireDebugEntryAuthority(current);
          return Object.freeze({kind: 'expired'});
        }
        if (primarySchemaSqlSupport !== undefined && !primarySchemaSqlSupport.includes(debugEntryTable)) {
          fail('ClientRunDebugEntryOriginalUnavailable');
        }
        advanceDebugRevision(ref, expectedRevision);
        if (!hasDebugEntryStorage()) database.exec(debugEntryTable);
        database.prepare(`INSERT INTO client_debug_entry_parks
          (run_definition_cid, submitted_intent_cid, parked_revision, expires_at, paused_at) VALUES (?, ?, ?, ?, ?)`)
          .run(ref.runDefinitionCid, intent, expectedRevision + 1, expiresAt, pausedAt);
        requireDebugEntryAuthority(current);
        return Object.freeze({kind: 'parked', revision: expectedRevision + 1, expiresAt, pausedAt});
      });
    },
    acceptDebugEntryResume(ref: WireRunRef, {commandWire, current, capture, receiptOriginal}: DebugEntryResumeInput,
      publicationControl: DebugReceiptControl) {
      ensureOpen();
      if (!validDebugEntryRef(ref) || typeof current !== 'function' ||
          (capture !== undefined && typeof capture !== 'function')) fail('ClientRunDebugEntryInvalidSelection');
      requireDebugEntryAuthority(current);
      const receiptSelection = prepareDebugReceiptIssue(receiptOriginal, ref, commandWire, current, publicationControl);
      const command = readDebugEntryCommand(commandWire, ref, publicationControl);
      let handoff: DebugEntryAccepted | undefined;
      const result = debugEntryTransaction(() => {
        const entry = debugEntry(ref);
        if (entry === undefined || command.expected_control_revision !== entry.parked_revision) {
          fail('ClientRunDebugEntryRevisionConflict');
        }
        if (entry.resume_wire !== null) {
          if (entry.resume_wire !== commandWire) fail('ClientRunDebugEntryResumeConflict');
          requireDebugEntryAuthority(current);
          return debugEntryResult(entry, command);
        }
        const acceptedAt = epochClock().observed_at;
        if (acceptedAt >= entry.expires_at) {
          requireDebugEntryAuthority(current);
          return Object.freeze({kind: 'expired'});
        }
        const receipt = issueDebugReceipt(receiptSelection, ref, entry, commandWire, acceptedAt, publicationControl, false);
        if (receiptSelection !== undefined) requireDebugEntryAuthority(current);
        advanceDebugRevision(ref, entry.parked_revision);
        const revision = entry.parked_revision + 1;
        if (database.prepare(`UPDATE client_debug_entry_parks SET resume_wire = ?, resume_revision = ?, resume_accepted_at = ?,
          receipt_wire = ?, receipt_cid = ? WHERE run_definition_cid = ? AND resume_wire IS NULL AND parked_revision = ?`)
          .run(commandWire, revision, acceptedAt, receipt?.wire ?? null, receipt?.identity ?? null,
            ref.runDefinitionCid, entry.parked_revision).changes !== 1) {
          fail('ClientRunDebugEntryResumeConflict');
        }
        requireDebugEntryAuthority(current);
        handoff = debugEntryResult(entry, command, revision, acceptedAt);
        return handoff;
      });
      if (handoff !== undefined) capture?.(handoff);
      return result;
    },
    // Retained acceptance history. The Run owner separately supplies its
    // current phase and any physical completion of the accepted command.
    lookupDebugEntry(ref: WireRunRef, {current}: {current: Current}, publicationControl: DebugCommandControl) {
      ensureOpen();
      if (!validDebugEntryRef(ref) || typeof current !== 'function') fail('ClientRunDebugEntryInvalidSelection');
      requireDebugEntryAuthority(current);
      return debugEntryTransaction(() => {
        const entry = debugEntry(ref);
        const command = entry?.resume_wire == null ? undefined :
          readDebugEntryResume(entry, ref, publicationControl);
        const expired = entry !== undefined && command === undefined && epochClock().observed_at >= entry.expires_at;
        requireDebugEntryAuthority(current);
        if (entry === undefined) return Object.freeze({kind: 'unobserved'});
        if (expired) return Object.freeze({kind: 'expired'});
        return command === undefined ? debugEntryResult(entry) : debugEntryResult(entry, command);
      });
    },
    // The existing Driver owns the live boundary and its cancellation signal.
    // Only a consecutive committed Step can extend this Run's durable history.
    parkDebugTask(ref: WireRunRef, {startRevision, expectedRevision, controlRevision, stepId, nextStepId,
      committedGeneration, expiresAt, current}: DebugTaskPauseInput, publicationControl: DefinitionControl & DebugCommandControl) {
      ensureOpen();
      if (!validDebugEntryRef(ref) || !Number.isInteger(startRevision) || startRevision < 1 ||
          !Number.isInteger(expectedRevision) || expectedRevision < startRevision ||
          !Number.isInteger(controlRevision) || controlRevision < 2 || controlRevision > 2147483646 ||
          controlRevision % 2 !== 0 || !cid(stepId) || (nextStepId !== null && !cid(nextStepId)) ||
          !validCommittedGeneration(committedGeneration) ||
          (expiresAt !== undefined && (!Number.isSafeInteger(expiresAt) || expiresAt <= 0)) ||
          typeof current !== 'function') {
        fail('ClientRunDebugEntryInvalidSelection');
      }
      requireDebugEntryAuthority(current);
      return debugEntryTransaction(() => {
        const {row, entry, entryCommand} = liveDebugTaskRun(ref, startRevision, publicationControl);
        const deadline = expiresAt ?? entry.expires_at;
        const previous = readDebugTaskPause(ref);
        if (previous?.control_revision === controlRevision) {
          if (previous.paused_revision !== expectedRevision + 1 || previous.step_id !== stepId || previous.next_step_id !== nextStepId ||
              previous.committed_generation !== committedGeneration || previous.expires_at !== deadline || previous.resume_wire !== null ||
              row.revision !== previous.paused_revision) fail('ClientRunDebugEntryRevisionConflict');
          const observedAt = epochClock().observed_at;
          requireDebugEntryAuthority(current);
          return observedAt >= deadline ? Object.freeze({kind: 'expired'}) : debugTaskPauseResult(previous);
        }
        if ((previous === undefined
          ? controlRevision !== 2 || expectedRevision !== startRevision || entryCommand.interval.until !== 'step'
          : controlRevision !== previous.control_revision + 2 || previous.resume_wire === null ||
            committedGeneration <= previous.committed_generation || expectedRevision !== previous.paused_revision + 1 ||
            readDebugTaskCommand(previous, ref, publicationControl).interval.until !== 'step') ||
            row.revision !== expectedRevision) fail('ClientRunDebugEntryRevisionConflict');
        if (expectedRevision >= 2147483646) fail('ControlRevisionExhausted');
        const definition = retainedRunDefinition(row as SqlRow & Parameters<typeof retainedRunDefinition>[0],
          publicationControl, maxRunDefinitionWireBytes);
        if (typeof row.lookup_expires_at !== 'string') fail('ClientRunDebugEntryOriginalUnavailable');
        const validUntil = Math.min(Date.parse(row.lookup_expires_at), Date.parse(JSON.parse(definition.wire).valid_until));
        if (!Number.isSafeInteger(validUntil) || deadline > validUntil) fail('ClientRunDebugEntryInvalidSelection');
        const pausedAt = epochClock().observed_at;
        if (pausedAt >= deadline) {
          requireDebugEntryAuthority(current);
          return Object.freeze({kind: 'expired'});
        }
        if (primarySchemaSqlSupport !== undefined && !primarySchemaSqlSupport.includes(debugTaskPauseTable)) {
          fail('ClientRunDebugEntryOriginalUnavailable');
        }
        if (!hasDebugTaskPauseStorage()) database.exec(debugTaskPauseTable);
        const ordinal = database.prepare('SELECT COALESCE(MAX(journal_ordinal), 0) AS ordinal FROM client_debug_task_pauses').get()?.ordinal;
        if (!integer(ordinal) || ordinal >= maxRecords) fail('ClientRunDebugEntryCapacity');
        advanceDebugRevision(ref, expectedRevision, 1);
        const revision = expectedRevision + 1;
        database.prepare(`INSERT INTO client_debug_task_pauses
          (run_definition_cid, control_revision, step_id, next_step_id, committed_generation,
            paused_revision, expires_at, paused_at, journal_ordinal)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(ref.runDefinitionCid, controlRevision, stepId, nextStepId,
            committedGeneration, revision, deadline, pausedAt, ordinal + 1);
        requireDebugEntryAuthority(current);
        return debugTaskPauseResult({paused_revision: revision, control_revision: controlRevision,
          step_id: stepId, next_step_id: nextStepId, expires_at: deadline, paused_at: pausedAt, committed_generation: committedGeneration});
      });
    },
    acceptDebugTaskResume(ref: WireRunRef, {commandWire, startRevision, stepId, nextStepId, committedGeneration, current, capture,
      receiptOriginal}: DebugTaskResumeInput, publicationControl: DebugReceiptControl) {
      ensureOpen();
      if (!validDebugEntryRef(ref) || !Number.isInteger(startRevision) || startRevision < 1 ||
          !cid(stepId) || (nextStepId !== null && !cid(nextStepId)) || !validCommittedGeneration(committedGeneration) ||
          typeof current !== 'function' || typeof capture !== 'function') fail('ClientRunDebugEntryInvalidSelection');
      requireDebugEntryAuthority(current);
      const receiptSelection = prepareDebugReceiptIssue(receiptOriginal, ref, commandWire, current, publicationControl);
      const command = readDebugEntryCommand(commandWire, ref, publicationControl);
      let handoff: DebugTaskAccepted | undefined;
      const result = debugEntryTransaction(() => {
        // Existing acceptance remains lookup history, even if the live Driver
        // has moved or the original COMMIT reply was lost.
        const retained = readDebugTaskPause(ref, command.operation_id);
        if (retained !== undefined) {
          if (retained.start_revision !== startRevision || retained.committed_generation !== committedGeneration ||
              retained.step_id !== stepId || retained.next_step_id !== nextStepId) {
            fail('ClientRunDebugEntryOriginalUnavailable');
          }
          if (retained.resume_wire !== commandWire) fail('ClientRunDebugEntryResumeConflict');
          readDebugTaskCommand(retained, ref, publicationControl);
          requireDebugEntryAuthority(current);
          return debugTaskResumeResult(retained, command);
        }
        const {entry, entryCommand} = liveDebugTaskRun(ref, startRevision, publicationControl);
        if (entryCommand.operation_id === command.operation_id) fail('ClientRunDebugEntryResumeConflict');
        const pause = readDebugTaskPause(ref);
        if (pause === undefined || pause.resume_wire !== null || pause.committed_generation !== committedGeneration ||
            pause.step_id !== stepId || pause.next_step_id !== nextStepId ||
            pause.paused_revision !== command.expected_control_revision) {
          fail('ClientRunDebugEntryRevisionConflict');
        }
        const acceptedAt = epochClock().observed_at;
        if (acceptedAt >= pause.expires_at) {
          requireDebugEntryAuthority(current);
          return Object.freeze({kind: 'expired'});
        }
        if (receiptSelection !== undefined && pause.expires_at !== entry.expires_at) fail('ClientRunDebugEntryReceiptRejected');
        const receipt = issueDebugReceipt(receiptSelection, ref, pause, commandWire, acceptedAt, publicationControl, true);
        if (receiptSelection !== undefined) requireDebugEntryAuthority(current);
        advanceDebugRevision(ref, pause.paused_revision, 1);
        if (database.prepare(`UPDATE client_debug_task_pauses SET resume_wire = ?, operation_id = ?, resume_accepted_at = ?,
          receipt_wire = ?, receipt_cid = ? WHERE run_definition_cid = ? AND control_revision = ? AND resume_wire IS NULL`)
          .run(commandWire, command.operation_id, acceptedAt, receipt?.wire ?? null, receipt?.identity ?? null,
            ref.runDefinitionCid, pause.control_revision).changes !== 1) {
          fail('ClientRunDebugEntryResumeConflict');
        }
        requireDebugEntryAuthority(current);
        handoff = debugTaskResumeResult(pause, command, acceptedAt);
        return handoff;
      });
      if (handoff !== undefined) capture(handoff);
      return result;
    },
    // Only the exact still-unconsumed park can back an actionable live view.
    // Select scalars without opening the stored command or changing the clock.
    debugPauseCurrent(ref: WireRunRef, {parked, startRevision, current, requireEntryDeadline = false}: DebugPauseInput) {
      ensureOpen();
      requireDebugEntryAuthority(current);
      const later = parked.controlRevision !== undefined;
      const observedAt = epochClock(undefined, false).observed_at;
      ensureOpen();
      requireDebugEntryAuthority(current);
      if (database.isTransaction ||
          !(later ? hasDebugTaskPauseStorage() : hasDebugEntryStorage())) return false;
      const select = (table: 'client_debug_entry_parks' | 'client_debug_task_pauses') => `SELECT 1 AS current
        FROM ${table} p JOIN client_requests r USING (run_definition_cid)
        JOIN client_submission_epoch_authority e ON e.singleton = 1
        WHERE r.namespace_id = ? AND r.authority_scope_cid = ? AND r.run_definition_cid = ?
        AND r.revision = ? AND r.dispatch_reserved = 1 AND r.physical_start_reserved = ?
        AND r.pre_dispatch_failure_confirmed = 0 AND r.cancellation_requested = 0
        AND r.physical_close_confirmed = 0 AND r.observed_terminal_outcome IS NULL
        AND p.paused_at = ? AND p.expires_at = ? AND p.expires_at > max(?, e.observed_at)
        AND p.resume_wire IS NULL`;
      const args = [ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid,
        parked.revision, later ? 1 : 0, parked.pausedAt, parked.expiresAt, observedAt];
      let selected;
      if (!later) {
        liveDebugEntry ??= database.prepare(select('client_debug_entry_parks') +
          ' AND p.parked_revision = r.revision');
        selected = liveDebugEntry.get(...args);
      } else {
        if (startRevision === undefined) return false;
        liveDebugTask ??= database.prepare(select('client_debug_task_pauses') + `
          AND p.paused_revision = r.revision AND p.control_revision = ? AND p.step_id = ?
          AND p.next_step_id IS ? AND p.committed_generation = ?
          AND p.operation_id IS NULL AND EXISTS (SELECT 1
            FROM client_relation_sample_starts s JOIN client_debug_entry_parks entry USING (run_definition_cid)
            WHERE s.run_definition_cid = r.run_definition_cid AND s.namespace_id = r.namespace_id
            AND s.authority_scope_cid = r.authority_scope_cid AND s.start_revision = ?
            AND s.submitted_intent_cid = entry.submitted_intent_cid
            AND s.start_revision = entry.resume_revision + 1
            AND (? = 0 OR p.expires_at = entry.expires_at))`);
        selected = liveDebugTask.get(...args, parked.controlRevision, parked.stepId, parked.nextStepId,
          parked.committedGeneration, startRevision, requireEntryDeadline ? 1 : 0);
      }
      requireDebugEntryAuthority(current);
      return selected?.current === 1;
    },
    lookupDebugResume(ref: WireRunRef, {operationId, commandCid, acceptedFromRevision, current, reserve, reserveConstruction}:
      DebugLookupInput, publicationControl: DebugReceiptControl): DebugResumeLookup {
      ensureOpen();
      if (!validDebugEntryRef(ref) || !text(operationId) || !cid(commandCid) ||
          !Number.isInteger(acceptedFromRevision) || acceptedFromRevision < 0 ||
          acceptedFromRevision > 2147483647 || typeof current !== 'function' ||
          reserve !== undefined && typeof reserve !== 'function' ||
          reserveConstruction !== undefined && (typeof reserveConstruction !== 'function' || reserve === undefined)) {
        fail('ClientRunDebugEntryInvalidSelection');
      }
      requireDebugEntryAuthority(current);
      // First select the existing bounded command and scalar receipt extent.
      const commandBytes = 1024 + 2 * debugCommandLimits.maxWireBytes;
      if (reserve !== undefined) {
        reserve(commandBytes);
        requireDebugEntryAuthority(current);
      }
      // A reentrant read on this connection cannot disclose its uncommitted
      // write. A separate WAL writer does not prevent this committed read.
      if (database.isTransaction) fail('ClientRunDebugEntryLookupUnavailable');
      const original = debugResumeOriginal(ref, operationId);
      const later = original?.resume_source === 'task';
      const command = original?.resume_wire == null ? undefined : later
        ? readDebugTaskCommand(original, ref, publicationControl)
        : readDebugEntryResume(original, ref, publicationControl);
      requireDebugEntryAuthority(current);
      if (original === undefined || command === undefined || command.operation_id !== operationId ||
          command.self_cid !== commandCid || command.expected_control_revision !== acceptedFromRevision) {
        return Object.freeze({kind: 'unobserved'});
      }
      const summary = later ? debugTaskResumeResult(original, command) : debugEntryResult(original, command);
      if (reserveConstruction === undefined || original.receipt_cid === null && original.receipt_bytes === null) return summary;
      const {receipt_bytes: bytes, receipt_cid: identity, definition_bytes: definitionBytes} = original;
      if (!cid(identity) || !integer(bytes) || bytes < 1 ||
          bytes > debugReceiptLimits.maxWireBytes || !integer(definitionBytes) ||
          definitionBytes < 1 || definitionBytes > maxRunDefinitionWireBytes) fail('ClientRunDebugEntryCorrupt');
      const limits = {...debugReceiptLimits, maxWireBytes: bytes};
      const definitionLimits = {...debugReceiptLimits, maxWireBytes: definitionBytes};
      // Both original wires and their admitted evidence can coexist. Reserve
      // their cumulative quote before reopening either on the same Read.
      reserveDebugReceipt(reserveConstruction, current, publicationControl, limits, false);
      reserveDebugReceipt(reserveConstruction, current, publicationControl, definitionLimits, false);
      if (database.isTransaction) fail('ClientRunDebugEntryLookupUnavailable');
      const retained = debugResumeOriginal(ref, operationId, bytes, identity, definitionBytes);
      if (retained === undefined || Object.keys(original).some(key =>
        key !== 'receipt_wire' && key !== 'run_definition_wire' && retained[key] !== original[key])) {
        fail('ClientRunDebugEntryCorrupt');
      }
      requireDebugEntryAuthority(current);
      const receipt = readDebugReceipt(retained, summary, command, limits, definitionLimits, publicationControl);
      requireDebugEntryAuthority(current);
      return Object.freeze({...summary, receipt});
    },
    // Private same-operation reconciliation. A missing durable row does not
    // attest that pending physical custody was released.
    lookupRelationSampleAdoption(ref: WireRunRef, sampleRefCid: string, custody: SampleReadCustody,
      publicationControl: Parameters<RelationSampleStorage['lookup']>[2]) {
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) || !cid(ref?.runDefinitionCid)) {
        fail('ClientRelationSampleInvalidOriginal');
      }
      return sampleStorage().lookup(ref, sampleRefCid, publicationControl, custody);
    },
    readRetainedRelationSample(ref: WireRunRef, selected: SampleReadSelection, custody: SampleNextCustody,
      publicationControl: Parameters<RelationSampleStorage['readRetained']>[2]) {
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) || !cid(ref?.runDefinitionCid)) {
        fail('ClientRelationSampleInvalidOriginal');
      }
      const debug = custody.debugPause;
      if (debug === undefined) return sampleStorage().readRetained(ref, selected, publicationControl, custody);

      // The installed controller supplies its checked original Next and
      // parked tuple. The Sample reader never acquires or resumes a task.
      const {parked, startRevision, producer} = debug;
      const {current, reserve} = custody;
      requireDebugEntryAuthority(current);
      if (parked?.kind !== 'parked' || !Object.isFrozen(parked) || !Object.isFrozen(selected) ||
          !Number.isInteger(parked.controlRevision) || parked.controlRevision < 2 ||
          !validCommittedGeneration(parked.committedGeneration) || !validCommittedGeneration(startRevision) ||
          !cid(parked.nextStepId) || parked.nextStepId !== selected.nextStepId ||
          !Object.isFrozen(producer) || !cid(producer?.stepId) || producer.stepId !== selected.stepId ||
          producer.outputPortId !== selected.outputPortId || producer.carrierContractCid !== selected.carrierContractCid ||
          !validCommittedGeneration(producer.generation) || !validCommittedGeneration(producer.attemptSequence)) {
        fail('ClientRunDebugEntryInvalidSelection');
      }
      // Fund the extra scalar pause query and the read controls on the
      // caller's same Read. Check again if funding reenters the owner.
      if (typeof reserve !== 'function') fail('ClientRelationSampleCapacity');
      const quote = reserve(1024);
      if (quote !== undefined) {
        if (typeof (quote as {then?: unknown} | null)?.then === 'function') void Promise.resolve(quote).catch(() => {});
        fail('ClientRelationSampleCapacity');
      }
      const requirePause = () => {
        if (!journal.debugPauseCurrent(ref, {parked, startRevision, current})) {
          fail('ClientRunDebugEntryRevisionConflict');
        }
      };
      requirePause();
      const original = sampleStorage().readRetained(ref, selected, publicationControl, {current,
        reserve(bytes) {
          const result = reserve(bytes);
          requirePause();
          return result;
        },
      }, {startRevision, generation: String(producer.generation), attemptSequence: String(producer.attemptSequence)});
      requirePause();
      return original;
    },
    // Host retention of the same original Sample, independent of public
    // disclosure and the receipt used to reconcile an uncertain adoption.
    retireRelationSamplePayload(ref: WireRunRef, sampleRefCid: string, custody: SampleReadCustody,
      publicationControl: Parameters<RelationSampleStorage['retire']>[2]) {
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) || !cid(ref?.runDefinitionCid)) {
        fail('ClientRelationSampleInvalidOriginal');
      }
      return sampleStorage().retire(ref, sampleRefCid, publicationControl, custody);
    },
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
      requestControl: Parameters<CancelRecord>[2], publicationControl: Parameters<CancelRecord>[3]) {
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
