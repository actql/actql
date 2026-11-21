// Private bindings inside the existing request Journal/dispatch/row-source
// owners. These tables retain original identity, not another Run, retry state
// machine, capacity issuer or permission decision.
import type {DatabaseSync} from 'node:sqlite';

type Occurrence = Readonly<{stage: number; input: number; task: number}>;
type RunReference = Readonly<{namespaceId: string; authorityScopeCid: string; runDefinitionCid: string}>;
type SourceOperationLimits = Readonly<{maxRecords: number; maxWireBytes: number}>;
type RunRow = Readonly<Record<string, unknown>>;
type StorageOptions = Readonly<{
  ensureOpen: () => undefined;
  transact(operation: 'source_operation', unknownCode: string, known: (error: unknown) => boolean,
    action: () => undefined): undefined;
  readRun(ref: RunReference): RunRow | undefined;
  limits?: SourceOperationLimits;
}>;
type JobRuntime = Readonly<{
  clientProgramBigQueryJobReadMatchesRowRun?(jobRead: unknown, run: unknown, acquisition: unknown): boolean;
  clientProgramBigQueryJobOriginalRecordMatchesRequest(jobRead: unknown, request: unknown, record: unknown): boolean;
  clientProgramBigQueryJobOriginalRecordWire(record: unknown): string;
}>;
type RunOriginal = Readonly<{
  ref: RunReference; compiled: unknown; program: unknown; identity: unknown;
  definition: Readonly<{identity: string; wire: string}>;
  requestControl: JobRuntime & Readonly<{
    clientProgramMatchesRequestIdentity(program: unknown, identity: unknown): boolean;
  }>;
  publicationControl: Readonly<{
    checkClientCompiledRunOwner(compiled: unknown, program: unknown): undefined;
    checkClientCompiledRunDefinition(compiled: unknown, definition: RunOriginal['definition']): undefined;
  }>;
  checkStore: () => number; journal: object; store: object;
  requestId: string; requestScopeCid: string; intentCid: string;
}>;
type RowFrame = Readonly<{
  run: unknown; acquisition: unknown; requestId: string; runInvocationCid: string; dispatchRequestCid: string;
}>;
type JobOriginal = Readonly<{
  jobRead: unknown; request: unknown; record: unknown; wire: string; frame: RowFrame;
}>;
type JobPort = <Result>(original: JobOriginal, sendOriginal: () => Result) => Result;
type RunBinding = Readonly<{
  original: RunOriginal; current: () => undefined;
  persist(occurrence: Occurrence, frame: RowFrame, wire: string): undefined;
  bindings: Map<string, object>; maximumRecords: number;
}>;
type SourceBinding = {
  readonly original: RunBinding;
  readonly program: unknown;
  readonly preparedSource: unknown;
  readonly occurrence: Occurrence;
  frame?: RowFrame;
  moon?: JobRuntime;
  port?: JobPort;
};

const runs = new WeakMap<object, RunBinding>();
const sources = new WeakMap<object, SourceBinding>();
const fail: (code: string, cause?: unknown, facts?: Readonly<Record<string, unknown>>) => never =
  (code, cause, facts = {}) => {
  throw Object.assign(new Error(code, {cause}), {code, ...facts});
};
const ordinal = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) >= 0;
const coordinate = (value: unknown): value is Occurrence => value !== null && typeof value === 'object' &&
  ['stage', 'input', 'task'].every(key => ordinal((value as Readonly<Record<string, unknown>>)[key]));

export const sourceOperationTable = `CREATE TABLE client_source_operation_originals (
  namespace_id TEXT NOT NULL,
  authority_scope_cid TEXT NOT NULL,
  run_definition_cid TEXT NOT NULL REFERENCES client_requests(run_definition_cid),
  stage INTEGER NOT NULL CHECK (stage >= 0),
  input_index INTEGER NOT NULL CHECK (input_index >= 0),
  task INTEGER NOT NULL CHECK (task >= 0),
  source_attempt_id TEXT NOT NULL,
  run_invocation_cid TEXT NOT NULL,
  dispatch_request_cid TEXT NOT NULL,
  original_wire TEXT NOT NULL,
  PRIMARY KEY (namespace_id, authority_scope_cid, run_definition_cid, stage, input_index, task)
) STRICT`;

// Absence is compatible with old journals, not proof of an unattempted Source.
// The existing physical-start fence still prevents issuing a fresh live scope
// for a restored/Unknown Run, whether this optional DATA table exists or not.
export function inspectClientSourceOperationStorage(database: Pick<DatabaseSync, 'prepare'>) {
  const row = database.prepare("SELECT substr(sql, 1, ?) AS sql FROM sqlite_master WHERE type = 'table' AND name = 'client_source_operation_originals'")
    .get(sourceOperationTable.length + 1);
  if (row !== undefined && row.sql !== sourceOperationTable) {
    fail('UnknownClientRequestJournalFormat');
  }
}

export function snapshotClientSourceOperationLimits(limits: unknown): SourceOperationLimits | undefined {
  if (limits === undefined) return undefined;
  if (limits === null || typeof limits !== 'object') fail('InvalidClientSourceOperationLimits');
  const fields = Object.getOwnPropertyDescriptors(limits);
  const keys = Reflect.ownKeys(fields);
  if (keys.length !== 2 || keys.some(key => typeof key !== 'string' || !['maxRecords', 'maxWireBytes'].includes(key)) ||
      ['maxRecords', 'maxWireBytes'].some(key => !Object.hasOwn(fields[key], 'value') ||
        !Number.isSafeInteger(fields[key].value) || fields[key].value < 1) ||
      fields.maxWireBytes.value > 2_147_483_647) {
    fail('InvalidClientSourceOperationLimits');
  }
  return Object.freeze({maxRecords: fields.maxRecords.value, maxWireBytes: fields.maxWireBytes.value});
}

export function clientSourceOperationStorage(database: Pick<DatabaseSync, 'prepare'>, {ensureOpen, transact,
  readRun, limits}: StorageOptions) {
  limits = snapshotClientSourceOperationLimits(limits);
  if (limits === undefined) return undefined;
  const maximumRecords = limits.maxRecords, maximumWireBytes = limits.maxWireBytes;
  // Bound JS materialization even if a retained record is corrupt. SQLite's
  // original file/statement work remains its physical owner's responsibility.
  const lookup = database.prepare(`SELECT
    substr(source_attempt_id, 1, 257) AS source_attempt_id,
    substr(run_invocation_cid, 1, 72) AS run_invocation_cid,
    substr(dispatch_request_cid, 1, 72) AS dispatch_request_cid,
    CASE WHEN length(CAST(original_wire AS BLOB)) <= ? THEN original_wire ELSE NULL END AS original_wire
    FROM client_source_operation_originals
    WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?
      AND stage = ? AND input_index = ? AND task = ?`);
  const count = database.prepare('SELECT COUNT(*) AS n FROM client_source_operation_originals');
  const insert = database.prepare(`INSERT INTO client_source_operation_originals
    (namespace_id, authority_scope_cid, run_definition_cid, stage, input_index, task,
      source_attempt_id, run_invocation_cid, dispatch_request_cid, original_wire)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
  const key = (ref: RunReference, occurrence: Occurrence) => [ref.namespaceId, ref.authorityScopeCid,
    ref.runDefinitionCid, occurrence.stage, occurrence.input, occurrence.task];
  const currentRun = (original: RunOriginal): undefined => {
    ensureOpen();
    Reflect.apply(original.checkStore, original.store, []);
    original.publicationControl.checkClientCompiledRunOwner(original.compiled, original.program);
    original.publicationControl.checkClientCompiledRunDefinition(original.compiled, original.definition);
    if (original.requestControl.clientProgramMatchesRequestIdentity(original.program,
      original.identity) !== true) fail('ClientSourceOperationOriginalChanged');
    const retained = readRun(original.ref);
    if (retained === undefined || retained.caller_request_id !== original.requestId ||
        retained.logical_request_scope_cid !== original.requestScopeCid ||
        retained.intent_fingerprint_cid !== original.intentCid ||
        retained.run_definition_cid !== original.definition.identity ||
        retained.run_definition_wire !== original.definition.wire ||
        retained.physical_start_reserved !== 1 ||
        retained.cancellation_requested !== 0 ||
        retained.physical_close_confirmed !== 0 ||
        retained.observed_terminal_outcome !== null) {
      fail('ClientSourceOperationOriginalChanged');
    }
  };
  return Object.freeze({
    // Called only by the Journal after its original physical-start transaction
    // has returned confirmed success. Public DATA/lookup cannot call this path.
    issue(original: RunOriginal) {
      currentRun(original);
      const scope = Object.freeze({});
      const persist = (occurrence: Occurrence, frame: RowFrame, wire: string) => {
        if (typeof wire !== 'string' || Buffer.byteLength(wire, 'utf8') > maximumWireBytes) {
          fail('ClientSourceOperationCapacity');
        }
        return transact('source_operation', 'ClientSourceOperationUnknown',
          error => ['ClientSourceOperationOriginalChanged', 'ClientSourceOperationCapacity',
            'ClientSourceOperationUnresolved'].includes((error as {code?: string} | null | undefined)?.code as string), () => {
            currentRun(original);
            const prior = lookup.get(maximumWireBytes, ...key(original.ref, occurrence));
            if (prior !== undefined) {
              fail('ClientSourceOperationUnresolved', undefined, {
                outcome: 'unknown', originalWire: prior.original_wire,
              });
            }
            const records = Number(count.get()!.n);
            if (!Number.isSafeInteger(records) || records >= maximumRecords) fail('ClientSourceOperationCapacity');
            insert.run(...key(original.ref, occurrence), frame.requestId,
              frame.runInvocationCid, frame.dispatchRequestCid, wire);
          });
      };
      runs.set(scope, {original, current: () => currentRun(original), persist,
        bindings: new Map(), maximumRecords});
      return scope;
    },
    // A cold record is Unresolved DATA only, including after a successful
    // historical read. It never issues a scope, request, grant or POST.
    lookup(ref: RunReference, occurrence: unknown) {
      ensureOpen();
      if (!coordinate(occurrence)) fail('InvalidClientSourceOperationOccurrence');
      const retained = readRun(ref);
      if (retained === undefined) return undefined;
      const row = lookup.get(maximumWireBytes, ...key(ref, occurrence));
      if (row === undefined) return undefined;
      if (typeof row.original_wire !== 'string' ||
          Buffer.byteLength(row.original_wire, 'utf8') > maximumWireBytes ||
          typeof row.source_attempt_id !== 'string' || row.source_attempt_id.length === 0 ||
          Buffer.byteLength(row.source_attempt_id, 'utf8') > 256 ||
          !/^sha256:[0-9a-f]{64}$/u.test(row.run_invocation_cid as string) ||
          !/^sha256:[0-9a-f]{64}$/u.test(row.dispatch_request_cid as string)) {
        fail('ClientSourceOperationCorrupt');
      }
      return Object.freeze({kind: 'unresolved_original', originalWire: row.original_wire,
        sourceAttemptId: row.source_attempt_id, runInvocationCid: row.run_invocation_cid,
        dispatchRequestCid: row.dispatch_request_cid});
    },
  });
}

export function bindClientSourceOperation(scope: object, journal: object, store: object,
  program: unknown, preparedSource: unknown, occurrence: unknown) {
  const original = runs.get(scope);
  if (original === undefined || original.original.journal !== journal ||
      original.original.store !== store || original.original.program !== program || !coordinate(occurrence)) {
    fail('ForeignClientSourceOperation');
  }
  original.current();
  const key = [occurrence.stage, occurrence.input, occurrence.task].join(':');
  const prior = original.bindings.get(key);
  if (prior !== undefined) {
    if (sources.get(prior)!.preparedSource !== preparedSource) fail('ForeignClientSourceOperation');
    return prior;
  }
  if (original.bindings.size >= original.maximumRecords) fail('ClientSourceOperationCapacity');
  const source = Object.freeze({});
  sources.set(source, {original, program, preparedSource,
    occurrence: Object.freeze({stage: occurrence.stage, input: occurrence.input, task: occurrence.task})});
  original.bindings.set(key, source);
  return source;
}

// The installed row-source owner calls this only after its existing preparation
// identity checks and original RowRun constructor. Its own live pair, not a
// caller's copied frame or equal identity text, supplies the driver binding.
export function bindClientSourceOperationRowRun(source: object, moon: JobRuntime, program: unknown,
  preparedSource: unknown, frame: RowFrame): JobPort {
  const binding = sources.get(source);
  if (binding === undefined || binding.program !== program ||
      binding.preparedSource !== preparedSource ||
      binding.original.original.requestControl !== moon) fail('ForeignClientSourceOperation');
  binding.original.current();
  if (binding.frame !== undefined) {
    if (binding.moon !== moon || ['run', 'acquisition', 'requestId', 'runInvocationCid', 'dispatchRequestCid']
      .some(key => binding.frame![key as keyof RowFrame] !== frame[key as keyof RowFrame])) fail('ForeignClientSourceOperation');
    return binding.port!;
  }
  const originalFrame = Object.freeze({...frame});
  let entered = false;
  const port = function withOriginalJob<Result>(original: JobOriginal, sendOriginal: () => Result) {
    if (entered) fail('ClientSourceOperationAlreadyEntered');
    binding.original.current();
    if (original === null || typeof original !== 'object' || typeof sendOriginal !== 'function' ||
        original.frame?.run !== originalFrame.run ||
        original.frame?.acquisition !== originalFrame.acquisition ||
        ['requestId', 'runInvocationCid', 'dispatchRequestCid']
          .some(key => original.frame[key as keyof RowFrame] !== originalFrame[key as keyof RowFrame])) {
      fail('ForeignClientSourceOperation');
    }
    if (typeof moon.clientProgramBigQueryJobReadMatchesRowRun !== 'function') {
      fail('ClientSourceOperationBindingUnavailable');
    }
    if (moon.clientProgramBigQueryJobReadMatchesRowRun(original.jobRead,
      originalFrame.run, originalFrame.acquisition) !== true) {
      fail('ForeignClientSourceOperation');
    }
    if (!moon.clientProgramBigQueryJobOriginalRecordMatchesRequest(
      original.jobRead, original.request, original.record) ||
        moon.clientProgramBigQueryJobOriginalRecordWire(original.record) !== original.wire) {
      fail('ForeignClientSourceOperation');
    }
    entered = true;
    binding.original.persist(binding.occurrence, originalFrame, original.wire);
    binding.original.current();
    // No await separates confirmed original CAS/currentness from entering the
    // existing driver. The driver retains current authorization/physical I/O.
    return sendOriginal();
  };
  binding.frame = originalFrame;
  binding.moon = moon;
  binding.port = port;
  return port;
}
