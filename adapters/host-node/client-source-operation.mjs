// Private bindings inside the existing request Journal/dispatch/row-source
// owners. These tables retain original identity, not another Run, retry state
// machine, capacity issuer or permission decision.
const runs = new WeakMap();
const sources = new WeakMap();
const fail = (code, cause, facts = {}) => {
  throw Object.assign(new Error(code, {cause}), {code, ...facts});
};
const ordinal = value => Number.isSafeInteger(value) && value >= 0;
const coordinate = value => value !== null && typeof value === 'object' &&
  ['stage', 'input', 'task'].every(key => ordinal(value[key]));

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
export function inspectClientSourceOperationStorage(database) {
  const row = database.prepare("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'client_source_operation_originals'").get();
  if (row !== undefined && row.sql !== sourceOperationTable) {
    fail('UnknownClientRequestJournalFormat');
  }
}

export function snapshotClientSourceOperationLimits(limits) {
  if (limits === undefined) return undefined;
  if (limits === null || typeof limits !== 'object') fail('InvalidClientSourceOperationLimits');
  const fields = Object.getOwnPropertyDescriptors(limits);
  if (Reflect.ownKeys(fields).sort().join(',') !== 'maxRecords,maxWireBytes' ||
      ['maxRecords', 'maxWireBytes'].some(key => !Object.hasOwn(fields[key], 'value') ||
        !Number.isSafeInteger(fields[key].value) || fields[key].value < 1)) {
    fail('InvalidClientSourceOperationLimits');
  }
  return Object.freeze({maxRecords: fields.maxRecords.value, maxWireBytes: fields.maxWireBytes.value});
}

export function clientSourceOperationStorage(database, {ensureOpen, transact,
  readRun, limits}) {
  if (limits === undefined) return undefined;
  const maximumRecords = limits.maxRecords, maximumWireBytes = limits.maxWireBytes;
  const lookup = database.prepare(`SELECT * FROM client_source_operation_originals
    WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?
      AND stage = ? AND input_index = ? AND task = ?`);
  const count = database.prepare('SELECT COUNT(*) AS n FROM client_source_operation_originals');
  const insert = database.prepare(`INSERT INTO client_source_operation_originals
    (namespace_id, authority_scope_cid, run_definition_cid, stage, input_index, task,
      source_attempt_id, run_invocation_cid, dispatch_request_cid, original_wire)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
  const key = (ref, occurrence) => [ref.namespaceId, ref.authorityScopeCid,
    ref.runDefinitionCid, occurrence.stage, occurrence.input, occurrence.task];
  const currentRun = original => {
    ensureOpen();
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
    issue(original) {
      currentRun(original);
      const scope = Object.freeze({});
      const persist = (occurrence, frame, wire) => {
        if (typeof wire !== 'string' || Buffer.byteLength(wire, 'utf8') > maximumWireBytes) {
          fail('ClientSourceOperationCapacity');
        }
        return transact('source_operation', 'ClientSourceOperationUnknown',
          error => ['ClientSourceOperationOriginalChanged', 'ClientSourceOperationCapacity',
            'ClientSourceOperationUnresolved'].includes(error?.code), () => {
            currentRun(original);
            const prior = lookup.get(...key(original.ref, occurrence));
            if (prior !== undefined) {
              fail('ClientSourceOperationUnresolved', undefined, {
                outcome: 'unknown', originalWire: prior.original_wire,
              });
            }
            if (Number(count.get().n) >= maximumRecords) fail('ClientSourceOperationCapacity');
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
    lookup(ref, occurrence) {
      ensureOpen();
      if (!coordinate(occurrence)) fail('InvalidClientSourceOperationOccurrence');
      const retained = readRun(ref);
      if (retained === undefined) return undefined;
      const row = lookup.get(...key(ref, occurrence));
      if (row === undefined) return undefined;
      if (typeof row.original_wire !== 'string' ||
          Buffer.byteLength(row.original_wire, 'utf8') > maximumWireBytes) {
        fail('ClientSourceOperationCorrupt');
      }
      return Object.freeze({kind: 'unresolved_original', originalWire: row.original_wire,
        sourceAttemptId: row.source_attempt_id, runInvocationCid: row.run_invocation_cid,
        dispatchRequestCid: row.dispatch_request_cid});
    },
  });
}

export function bindClientSourceOperation(scope, program, preparedSource, occurrence) {
  const original = runs.get(scope);
  if (original === undefined || original.original.program !== program || !coordinate(occurrence)) {
    fail('ForeignClientSourceOperation');
  }
  original.current();
  const key = [occurrence.stage, occurrence.input, occurrence.task].join(':');
  const prior = original.bindings.get(key);
  if (prior !== undefined) {
    if (sources.get(prior).preparedSource !== preparedSource) fail('ForeignClientSourceOperation');
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
export function bindClientSourceOperationRowRun(source, moon, program,
  preparedSource, frame) {
  const binding = sources.get(source);
  if (binding === undefined || binding.program !== program ||
      binding.preparedSource !== preparedSource) fail('ForeignClientSourceOperation');
  binding.original.current();
  if (binding.frame !== undefined) {
    if (binding.moon !== moon || ['run', 'acquisition', 'requestId', 'runInvocationCid', 'dispatchRequestCid']
      .some(key => binding.frame[key] !== frame[key])) fail('ForeignClientSourceOperation');
    return binding.port;
  }
  const originalFrame = Object.freeze({...frame});
  let entered = false;
  const port = function withOriginalJob(original, sendOriginal) {
    if (entered) fail('ClientSourceOperationAlreadyEntered');
    binding.original.current();
    if (original === null || typeof original !== 'object' || typeof sendOriginal !== 'function' ||
        original.frame?.run !== originalFrame.run ||
        original.frame?.acquisition !== originalFrame.acquisition ||
        ['requestId', 'runInvocationCid', 'dispatchRequestCid']
          .some(key => original.frame[key] !== originalFrame[key])) {
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
