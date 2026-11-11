// Optional observations are projections, never execution or cleanup authority.
// Only small copied metadata enters this queue; user delivery runs on a later
// event-loop turn and can overlap an active public operation.
import {AsyncLocalStorage} from 'node:async_hooks';
import {randomUUID, createHash} from 'node:crypto';
import {ledgerLimitsFields, ledgerUsageFields} from './ledger-contract.generated.mjs';

export const observationVersion = 'actql-observation/0.1';
export const observationLimits = Object.freeze({
  recordBytes: 4096, queueRecords: 256, queueBytes: 1048576,
  requestRecords: 128, runRecords: 2048, runBytes: 1048576,
  segmentRecords: 512, activeSegments: 64, shutdownMs: 1000,
  journalRuns: 1024,
});
const connections = new WeakMap();
const projections = new WeakSet();
const contexts = new AsyncLocalStorage();
const cid = value => typeof value === 'string' && /^sha256:[a-f0-9]{64}$/u.test(value);
const outcomes = new Set(['running', 'resuming', 'succeeded', 'failed', 'cancelled',
  'waiting_checkpoint', 'needs_reconciliation', 'unknown', 'pending',
  'confirmed', 'accepted', 'already_terminal', 'committed', 'rejected']);
const operations = new Set(['run', 'check', 'planning', 'source', 'compute',
  'infer', 'effect', 'approval', 'checkpoint', 'recovery', 'publication', 'cleanup']);
const measurements = ['duration', 'rows', 'bytes', 'requests', 'tokens', 'resources', 'cost'];
const correlations = ['run', 'task', 'attempt', 'external_trace'];
const attributeNames = ['actql.operation', 'actql.event', 'actql.observation.version',
  'actql.outcome', 'actql.check.verdict', 'actql.task.ordinal', 'actql.attempt.ordinal',
  'actql.model.slot.ordinal', 'actql.owner.revision', 'actql.cleanup.pending',
  'actql.physical_stop', 'actql.run.definition_cid', 'actql.run.id',
  'actql.model.attempt_cid', 'http.request.method', 'http.route',
  'http.response.status_code', 'error.type', 'service.name', 'service.version',
  'deployment.environment.name'];
const mandatoryAttributes = ['actql.operation', 'actql.event', 'actql.observation.version'];
// These are presentation-only public spellings. Field membership, primitive
// width and private snapshot order belong to the actual Core declaration.
const resourceUsageAttributeAliases = Object.freeze({
  planning_work: 'planning', transferred_bytes: 'transferred',
  uncertain_transfer_bytes: 'uncertain', reserved_transfer_bytes: 'reserved_transfer',
  reserved_retention_bytes: 'reserved_retention', reserved_execution_bytes: 'reserved_execution',
  peak_retention_bytes: 'peak_retention',
});
const resourceFields = Object.freeze([
  ...ledgerLimitsFields.map(field => Object.freeze({...field,
    attribute: `actql.resource.limit.${field.name}`})),
  ...ledgerUsageFields.map(field => Object.freeze({...field,
    attribute: `actql.resource.usage.${Object.hasOwn(resourceUsageAttributeAliases, field.name)
      ? resourceUsageAttributeAliases[field.name] : field.name}`})),
].map(field => Object.freeze({...field, maximum: (1n << BigInt(field.bits - 1)) - 1n})));
if (new Set(resourceFields.map(field => field.attribute)).size !== resourceFields.length ||
    Object.keys(resourceUsageAttributeAliases).some(name => !ledgerUsageFields.some(field => field.name === name))) {
  throw new TypeError('InvalidManagedResourceObservationPresentation');
}
const managedResourceSnapshots = new WeakSet();
const selectedRowSnapshots = new WeakMap();
attributeNames.push('actql.resource.scope', ...resourceFields.map(field => field.attribute));
attributeNames.push(...['owner', 'selection', 'kind', 'returned', 'unrelated', 'coverage']
  .map(name => `actql.rows.${name}`));
function bindSelectedRequestRows(detail, binding) {
  if (binding === undefined) return undefined;
  const request = detail.requestSelection;
  if (request !== undefined && request.authorityScopeCid === binding.ref.authorityScopeCid &&
      request.requestId === binding.requestId) {
    const selected = detail.selectedRowRef;
    return {...detail, requestSelection: undefined, ref: binding.ref,
      unrelatedRows: detail.returnedRows === 0 ? 0 : Number(
        selected.namespaceId !== binding.ref.namespaceId ||
        selected.authorityScopeCid !== binding.ref.authorityScopeCid ||
        selected.runDefinitionCid !== binding.ref.runDefinitionCid)};
  }
  // A failed uniqueness probe never reaches acceptance. Only actual absence
  // can join the later accepted original; a partial present row stays unknown.
  if (detail.runSelectionCid === binding.ref.runDefinitionCid && detail.returnedRows === 0) {
    return {...detail, runSelectionCid: undefined, ref: binding.ref, unrelatedRows: 0};
  }
  return undefined;
}
function accumulateSelectedRows(context, detail, pendingLimit = 0) {
  if (context === undefined || context.selectedRowsClosed || detail === null ||
      typeof detail !== 'object' || Array.isArray(detail)) return false;
  const {ref, rowOwner, selection, rowKind, returnedRows, unrelatedRows, coverage} = detail;
  if (rowOwner !== 'request-journal' || !['run-definition', 'request'].includes(selection) ||
      rowKind !== 'run' || coverage !== 'selected-returned' ||
      !Number.isSafeInteger(returnedRows) || returnedRows < 0 ||
      unrelatedRows !== undefined && (!Number.isSafeInteger(unrelatedRows) ||
        unrelatedRows < 0 || unrelatedRows > returnedRows)) return false;
  if (pendingLimit > 0 && (detail.requestSelection !== undefined || detail.runSelectionCid !== undefined)) {
    const request = detail.requestSelection, selected = detail.selectedRowRef;
    if (returnedRows > 1 || request !== undefined && (selection !== 'request' ||
        !cid(request.authorityScopeCid) || typeof request.requestId !== 'string' ||
        request.requestId.length === 0 || request.requestId.length > 256 ||
        returnedRows === 1 && (typeof selected?.namespaceId !== 'string' ||
          !cid(selected.authorityScopeCid) || !cid(selected.runDefinitionCid))) ||
        detail.runSelectionCid !== undefined && (selection !== 'run-definition' ||
          !cid(detail.runSelectionCid))) return false;
    const captured = {rowOwner, selection, rowKind, returnedRows, coverage,
      ...(request === undefined ? {} : {requestSelection: {
        authorityScopeCid: request.authorityScopeCid, requestId: request.requestId},
      ...(returnedRows === 0 ? {} : {selectedRowRef: {namespaceId: selected.namespaceId,
        authorityScopeCid: selected.authorityScopeCid, runDefinitionCid: selected.runDefinitionCid}})}),
      ...(detail.runSelectionCid === undefined ? {} : {runSelectionCid: detail.runSelectionCid})};
    const bound = bindSelectedRequestRows(captured, context.selectedRequestBinding);
    if (bound !== undefined) return accumulateSelectedRows(context, bound);
    const pending = context.pendingRequestRows ??= [];
    if (pending.length >= pendingLimit) {context.selectedRowsUnavailable = true; return false;}
    pending.push(captured);
    return true;
  }
  const previous = context.selectedRows;
  if (previous === undefined) {
    context.selectedRows = {ref, rowOwner, selection, rowKind, returnedRows, unrelatedRows, coverage};
    return true;
  }
  const returned = previous.returnedRows + returnedRows;
  const unrelated = previous.unrelatedRows === undefined || unrelatedRows === undefined
    ? undefined : previous.unrelatedRows + unrelatedRows;
  if (!Number.isSafeInteger(returned) || unrelated !== undefined && !Number.isSafeInteger(unrelated)) {
    previous.unavailable = true; return false;
  }
  if (previous.ref === undefined || ref === undefined ||
      previous.ref.namespaceId !== ref.namespaceId || previous.ref.authorityScopeCid !== ref.authorityScopeCid ||
      previous.ref.runDefinitionCid !== ref.runDefinitionCid) previous.ref = undefined;
  if (previous.selection !== selection) previous.selection = 'mixed-selected';
  previous.returnedRows = returned; previous.unrelatedRows = unrelated;
  return true;
}
function managedRunResources(values) {
  if (!Array.isArray(values)) return undefined;
  const length = Object.getOwnPropertyDescriptor(values, 'length');
  if (length?.value !== resourceFields.length ||
      Reflect.ownKeys(values).length !== resourceFields.length + 1) return undefined;
  const snapshot = {'actql.resource.scope': 'managed-run-ledger'};
  for (let index = 0; index < resourceFields.length; index++) {
    const descriptor = Object.getOwnPropertyDescriptor(values, String(index));
    if (!descriptor || !Object.hasOwn(descriptor, 'value')) return undefined;
    const value = descriptor.value, field = resourceFields[index];
    if (typeof value !== 'bigint' || value < 0n || value > field.maximum) return undefined;
    snapshot[field.attribute] = value.toString();
  }
  // Exact copied decimal scalars from the same Core Ledger. The distinct
  // producer capability fixes this declaration-order layout; no old same-size
  // layout is guessed. This never supplies admission or a physical-stop ACK.
  Object.freeze(snapshot);
  managedResourceSnapshots.add(snapshot);
  return snapshot;
}

function selection(value, names, defaults) {
  if (value === undefined) return defaults;
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).some(key => !['include', 'exclude'].includes(key))) {
    throw new TypeError('InvalidHostObservationSelection');
  }
  const include = value.include ?? defaults, exclude = value.exclude ?? [];
  for (const items of [include, exclude]) {
    if (!Array.isArray(items) || items.length > names.length ||
        new Set(items).size !== items.length || items.some(item => !names.includes(item))) {
      throw new TypeError('InvalidHostObservationSelection');
    }
  }
  return include.filter(item => !exclude.includes(item));
}
const events = Object.freeze({
  definition_admitted: ['run', 'definition_admitted'],
  dispatch_reserved: ['run', 'dispatch_reserved'],
  physical_start_reserved: ['run', 'physical_start_reserved'],
  acquisition_started: ['source', 'attempt_started'],
  acquisition_completed: ['source', 'attempt_completed'],
  acquisition_cleanup_started: ['cleanup', 'cleanup_started'],
  acquisition_cleanup_completed: ['cleanup', 'cleanup_completed'],
  computed: ['publication', 'result_committed'],
  dispatch_cleanup_completed: ['cleanup', 'cleanup_completed'],
  dispatch_failed: ['run', 'dispatch_failed'],
  infer_waiting_checkpoint: ['approval', 'waiting_checkpoint'],
  infer_needs_reconciliation: ['infer', 'needs_reconciliation'],
  resume_claimed: ['recovery', 'resume_claimed'],
  recovery_failed: ['recovery', 'recovery_failed'],
  resume_failed: ['recovery', 'resume_failed'],
  model_resume_failed: ['recovery', 'model_resume_failed'],
  model_call_entered: ['infer', 'attempt_started'],
  model_call_observed: ['infer', 'attempt_observed'],
  model_call_replayed: ['recovery', 'attempt_replayed'],
  checkpoint_resolved: ['approval', 'checkpoint_resolved'],
  effect_application_observed: ['effect', 'application_observed'],
  effect_write_observed: ['effect', 'write_observed'],
});
const recordEvents = new Set(['segment_started', 'segment_ended', 'check_completed',
  'owner_observed', 'cancellation_requested', 'task_started', 'task_completed',
  'transport_completed', 'acquisition_interval', 'resources_observed', 'selected_rows_observed',
  ...Object.values(events).map(value => value[1])]);

export function validObservationContext(value) {
  return value !== null && typeof value === 'object' &&
    typeof value.traceId === 'string' && /^[a-f0-9]{32}$/u.test(value.traceId) && !/^0+$/u.test(value.traceId) &&
    typeof value.spanId === 'string' && /^[a-f0-9]{16}$/u.test(value.spanId) && !/^0+$/u.test(value.spanId) &&
    Number.isInteger(value.traceFlags) && value.traceFlags >= 0 && value.traceFlags <= 255;
}
export function snapshotObservationContext(value) {
  try {
    if (value === null || typeof value !== 'object') return undefined;
    const {traceId, spanId, traceFlags} = value;
    const copied = {traceId, spanId, traceFlags};
    if (!validObservationContext(copied)) return undefined;
    // Snapshot getters once. Neither baggage nor tracestate is durable input.
    return Object.freeze({traceId, spanId, traceFlags: traceFlags & 1});
  } catch { return undefined; }
}
export function observationTraceParent(headers) {
  const value = headers?.traceparent;
  if (typeof value !== 'string' || value.length !== 55) return undefined;
  const match = /^00-([a-f0-9]{32})-([a-f0-9]{16})-([a-f0-9]{2})$/u.exec(value);
  return match && snapshotObservationContext({traceId: match[1], spanId: match[2],
    traceFlags: Number.parseInt(match[3], 16)}) || undefined;
}

export function createHostObservationConnection(options = {}) {
  if (options === null || typeof options !== 'object' || Array.isArray(options) ||
      Object.keys(options).some(key => !['deliver', 'currentContext', 'scope',
        'revision', 'limits', 'include', 'exclude', 'correlation',
        'measurements', 'attributes', 'events'].includes(key))) {
    throw new TypeError('InvalidHostObservationConfiguration');
  }
  const {deliver, currentContext,
  scope = 'local', revision = 'metadata/0.1', limits = {},
    include = [...operations], exclude = [], correlation = true} = options;
  if (typeof deliver !== 'function' || currentContext !== undefined &&
      typeof currentContext !== 'function' ||
      typeof scope !== 'string' || !/^[a-zA-Z0-9._-]{1,64}$/u.test(scope) ||
      typeof revision !== 'string' || !/^[a-zA-Z0-9._/-]{1,64}$/u.test(revision) ||
      !Array.isArray(include) ||
      !Array.isArray(exclude) || include.length > operations.size ||
      exclude.length > operations.size || new Set(include).size !== include.length ||
      new Set(exclude).size !== exclude.length ||
      [...include, ...exclude].some(x => !operations.has(x)) ||
      limits === null || typeof limits !== 'object' || Array.isArray(limits) ||
      Object.keys(limits).some(x => !Object.hasOwn(observationLimits, x))) {
    throw new TypeError('InvalidHostObservationConfiguration');
  }
  const selectedCorrelation = correlation === true ? correlations : correlation === false ? [] :
    selection(correlation, correlations, correlations);
  const selectedMeasurements = selection(options.measurements, measurements,
    measurements.filter(item => item !== 'cost'));
  // No pricing source is admitted by this metadata-only profile.
  if (selectedMeasurements.includes('cost')) throw new TypeError('UnsupportedObservationCostSource');
  selection(options.attributes === undefined ? undefined :
    {include: [], ...options.attributes}, attributeNames, []);
  if (options.attributes !== undefined && (!options.attributes ||
      typeof options.attributes !== 'object' || Array.isArray(options.attributes) ||
      Object.keys(options.attributes).some(key => key !== 'exclude'))) {
    throw new TypeError('InvalidHostObservationSelection');
  }
  const attributeExclusions = options.attributes?.exclude ?? [];
  const eventLevel = options.events?.level ?? 'lifecycle';
  if (options.events !== undefined && (!options.events ||
      typeof options.events !== 'object' || Array.isArray(options.events) ||
      Object.keys(options.events).some(key => key !== 'level')) ||
      !['lifecycle', 'diagnostic'].includes(eventLevel)) {
    throw new TypeError('InvalidHostObservationSelection');
  }
  const selected = Object.freeze({...observationLimits, ...limits});
  for (const [key, value] of Object.entries(selected)) {
    if (!Number.isSafeInteger(value) || value < 1 || value > observationLimits[key]) {
      throw new TypeError('InvalidHostObservationLimit');
    }
  }
  const allowed = new Set(include.filter(x => !exclude.includes(x)));
  const boundRevision = createHash('sha256').update(JSON.stringify({scope, revision,
    limits: selected, operations: [...allowed].sort(), correlations: selectedCorrelation,
    measurements: selectedMeasurements, attributeExclusions, eventLevel})).digest('hex');
  const config = {deliver, currentContext, scope, revision: boundRevision, selected,
    allowed, correlation: selectedCorrelation.includes('external_trace'),
    correlations: new Set(selectedCorrelation), measurements: new Set(selectedMeasurements),
    attributeExclusions: new Set(attributeExclusions), eventLevel};
  const token = Object.freeze({status: () => config.status?.(),
    configuration: () => Object.freeze({scope, revision: boundRevision,
      limits: selected, operations: Object.freeze([...allowed]),
      correlation: selectedCorrelation.length !== 0,
      correlations: Object.freeze([...selectedCorrelation]),
      measurements: Object.freeze({selected: Object.freeze([...selectedMeasurements]),
        available: Object.freeze(['duration', 'resources', 'rows'])}),
      attributes: Object.freeze({exclude: Object.freeze([...attributeExclusions])}),
      events: Object.freeze({level: eventLevel})})});
  connections.set(token, config);
  return token;
}

export const isHostObservationProjection = value => projections.has(value);

// Copy only the common receipt/publication Owner's returned disposition. This
// does not interpret transport errors or call an arbitrary completion hook.
export function projectEffectApplication(projection, ref, result) {
  if (!projections.has(projection)) return;
  try {
    const outcome = {published: 'committed', waiting: 'waiting_checkpoint',
      needs_reconciliation: 'needs_reconciliation', failed: 'failed'}[result.status];
    if (outcome !== undefined) projection.diagnostic('effect_application_observed', {ref, outcome});
  } catch { /* Optional metadata cannot change receipt or cleanup custody. */ }
}

// The installed Host supplies a captured original Core reader. Public callers
// cannot acquire a Ledger or execution authority through this projection.
export function captureManagedRunObservation(projection, ref, readUsage) {
  if (!projections.has(projection)) return undefined;
  return projection.captureManagedRun(ref, readUsage);
}

export function installHostObservation(connection, {journal, runId} = {}) {
  if (connection === undefined) return undefined;
  const config = connections.get(connection);
  if (config === undefined) throw new TypeError('ForeignHostObservationConnection');
  const previous = config.status?.();
  if (previous && (!previous.closed || previous.cleanupPending ||
      previous.active !== 0 || previous.activeSegments !== 0)) {
    throw new TypeError('HostObservationConnectionInUse');
  }
  let storage, storageUnavailable = false, storageClosed = false;
  try { if (config.allowed.size !== 0) storage = journal?.observationStorage(); }
  catch { storageUnavailable = true; }
  const closeStorage = () => {
    if (storageClosed) return;
    if (storage !== undefined) storage.close?.();
    else if (config.allowed.size !== 0) journal?.closeObservationStorage?.();
    storageClosed = true;
  };
  const queue = [], pending = new Set(), activeContexts = new Set();
  const contextOwner = {};
  const runIdentityLimit = Symbol('RunIdentityLimit');
  const observeRows = config.eventLevel === 'diagnostic' && config.allowed.has('run') &&
    config.measurements.has('rows');
  let queuedBytes = 0, closed = false, pumping = false, sequence = 0, activeSegments = 0;
  let activeCallbacks = 0, callbackState = Object.freeze({active: false});
  const enterApplicationCallback = () => {
    activeCallbacks++;
    callbackState = Object.freeze({active: true});
    return () => {
      activeCallbacks--;
      callbackState = Object.freeze({active: activeCallbacks !== 0});
    };
  };
  const counts = {dropped: 0, deliveryFailed: 0, budgetUnavailable: 0,
    queueOverflow: 0, limited: 0, repeated: 0};
  const diagnostics = Object.create(null);
  const drop = reason => {
    counts.dropped++;
    if (Object.hasOwn(counts, reason)) counts[reason]++;
    diagnostics[reason] = (diagnostics[reason] ?? 0) + 1;
  };
  const pump = () => {
    if (closed || pumping || queue.length === 0) return;
    pumping = true;
    setImmediate(() => {
      pumping = false;
      if (closed) return;
      const item = queue.shift();
      if (!item) return;
      queuedBytes -= item.bytes;
      // There is at most one delivery in flight. A nonterminating embedded
      // callback keeps this slot; a timeout cannot prove physical settlement.
      const leaveCallback = enterApplicationCallback();
      let promise;
      try { promise = Promise.resolve(config.deliver(item.record)); }
      catch { promise = Promise.reject(new Error('ObservationDeliveryFailed')); }
      pending.add(promise);
      promise.catch(() => { drop('deliveryFailed'); }).finally(() => {
        leaveCallback(); pending.delete(promise); pump();
      });
    });
  };
  const resolveRunIdentity = (context, ref, terminal = false) => {
    if (ref === undefined || ref === null || typeof ref.namespaceId !== 'string' ||
        !cid(ref.authorityScopeCid) || !cid(ref.runDefinitionCid)) return undefined;
    const original = context?.owner === contextOwner ? context : undefined;
    if (original?.finished && !terminal) return undefined;
    const key = JSON.stringify([ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid]);
    if (original?.runIdentities?.has(key)) return original.runIdentities.get(key);
    if ((original?.runIdentities?.size ?? 0) >=
        Math.min(config.selected.requestRecords, config.selected.segmentRecords)) throw runIdentityLimit;
    const id = runId?.(ref);
    if (typeof id !== 'string' || id.length > 128) return undefined;
    // Only an actual positive result from this installation's resolver is
    // retained, under the complete immutable Run tuple and this operation.
    // Missing/error observations and authority/current facts are not cached.
    if (original) (original.runIdentities ??= new Map()).set(key, id);
    return id;
  };
  const emit = (operation, event, facts = {}, options = {}) => {
    try {
      if (closed || !config.allowed.has(operation)) return;
      if (!recordEvents.has(event)) { drop('limited'); return; }
      if (event === 'selected_rows_observed' && !selectedRowSnapshots.has(options.selectedRows)) {
        drop('rowsUnavailable'); return;
      }
      if (mandatoryAttributes.some(key => config.attributeExclusions.has(key))) {
        drop('requiredAttributeExcluded'); return;
      }
      const current = contexts.getStore();
      const context = current?.owner === contextOwner ? current : undefined;
      if (context && context.records >= Math.min(config.selected.requestRecords,
        config.selected.segmentRecords)) {context.records++; drop('limited'); return;}
      const ref = event === 'selected_rows_observed' ? facts.ref : facts.ref ?? context?.ref;
      if (context && cid(facts.ref?.runDefinitionCid)) context.ref = facts.ref;
      const attributes = { 'actql.operation': operation,
        'actql.event': event, 'actql.observation.version': observationVersion };
      if (outcomes.has(facts.outcome)) attributes['actql.outcome'] = facts.outcome;
      if (['verified', 'invalid', 'undetermined'].includes(facts.checkVerdict)) {
        attributes['actql.check.verdict'] = facts.checkVerdict;
      }
      if (config.correlations.has('task') && Number.isSafeInteger(facts.task) && facts.task >= 0) {
        attributes['actql.task.ordinal'] = facts.task;
      }
      if (config.correlations.has('attempt')) {
        if (Number.isSafeInteger(facts.attempt) && facts.attempt >= 0) attributes['actql.attempt.ordinal'] = facts.attempt;
        if (Number.isSafeInteger(facts.slot) && facts.slot >= 0) attributes['actql.model.slot.ordinal'] = facts.slot;
      }
      if (Number.isSafeInteger(facts.revision) && facts.revision >= 0) attributes['actql.owner.revision'] = facts.revision;
      if (typeof facts.cleanupPending === 'boolean') attributes['actql.cleanup.pending'] = facts.cleanupPending;
      if (outcomes.has(facts.physicalStop)) attributes['actql.physical_stop'] = facts.physicalStop;
      if (managedResourceSnapshots.has(options.resources)) Object.assign(attributes, options.resources);
      if (selectedRowSnapshots.has(options.selectedRows)) Object.assign(attributes, options.selectedRows);
      const record = {version: observationVersion, operation, event,
        sequence: sequence++, observedAt: Date.now(),
        monotonicAt: performance.now(), attributes,
        ...(options.segment === undefined ? {} : {segment: options.segment}),
        ...(!Number.isFinite(options.durationMs) || options.durationMs < 0
          ? {} : {durationMs: options.durationMs}),
        ...(!config.correlation || context?.trace === undefined ? {} : {parent: context.trace}),
      };
      if (config.correlations.has('run') && cid(ref?.runDefinitionCid)) {
        attributes['actql.run.definition_cid'] = ref.runDefinitionCid;
        const id = event === 'selected_rows_observed'
          ? selectedRowSnapshots.get(options.selectedRows) : resolveRunIdentity(context, ref);
        if (typeof id === 'string' && id.length <= 128) attributes['actql.run.id'] = id;
      }
      if (config.correlations.has('attempt') && cid(facts.attemptCid)) attributes['actql.model.attempt_cid'] = facts.attemptCid;
      if (options.ingress === true && context?.http !== undefined) {
        const method = context.http.method;
        if (['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS'].includes(method)) {
          attributes['http.request.method'] = method;
        } else attributes['http.request.method'] = '_OTHER';
        attributes['http.route'] = '/actql/client/0.1/{operation}';
        const code = context.http.response?.statusCode;
        if (event === 'segment_ended' && Number.isInteger(code) && code >= 100 && code <= 599) {
          attributes['http.response.status_code'] = code;
          if (code >= 500) attributes['error.type'] = String(code);
        }
      }
      for (const key of config.attributeExclusions) delete attributes[key];
      // Reserve space for both restored correlation contexts before reading
      // optional journal metadata. Neither contains arbitrary attribute data.
      const bytes = Buffer.byteLength(JSON.stringify(record)) + 384;
      if (bytes > config.selected.recordBytes) { drop('limited'); return; }
      if (context && ++context.records > Math.min(config.selected.requestRecords,
        config.selected.segmentRecords)) { drop('limited'); return; }
      if (cid(ref?.runDefinitionCid)) {
        if (storageUnavailable || storage === undefined) { drop('budgetUnavailable'); return; }
        const budget = storage.consume({ref, scope: config.scope,
          revision: config.revision, bytes, maxRecords: config.selected.runRecords,
          maxBytes: config.selected.runBytes,
          ownerFactKey: event === 'owner_observed' ? options.ownerFactKey : undefined});
        if (budget === undefined) { drop('budgetUnavailable'); return; }
        if (budget.repeated === true) { counts.repeated++; return; }
        if (!budget.accepted) { drop('limited'); return; }
        // A saved caller context is a link, not a resumed lifetime span.
        if (config.correlation && budget.context !== undefined &&
            (record.parent?.spanId !== budget.context.spanId ||
             record.parent?.traceId !== budget.context.traceId)) record.link = budget.context;
      }
      if (queue.length >= config.selected.queueRecords ||
          queuedBytes + bytes > config.selected.queueBytes) { drop('queueOverflow'); return; }
      Object.freeze(attributes);
      queue.push({record: Object.freeze(record), bytes});
      queuedBytes += bytes;
      if (pending.size === 0) pump();
    } catch (cause) { drop(cause === runIdentityLimit ? 'limited' : 'budgetUnavailable'); }
  };
  const flushSelectedRows = context => {
    if (context === undefined || context.selectedRowsClosed) return;
    // A request with no matching successful acceptance remains unbound. Keep
    // its real counts without borrowing an eventual or another operation's Run.
    for (const pending of context.pendingRequestRows ?? []) accumulateSelectedRows(context, pending);
    context.pendingRequestRows = context.selectedRequestBinding = undefined;
    const rows = context.selectedRows;
    if (context.selectedRowsUnavailable && rows !== undefined) rows.unavailable = true;
    let id;
    try {
      if (rows !== undefined && !rows.unavailable && config.correlations.has('run')) {
        // The original resolver may perform a selected Journal read. Count
        // that real read before closing the aggregate; emission must not
        // recursively ask the Journal for metadata about its own record.
        id = resolveRunIdentity(context, rows.ref, true);
      }
    } catch (cause) {
      context.selectedRowsClosed = true; context.selectedRows = undefined;
      drop(cause === runIdentityLimit ? 'limited' : 'budgetUnavailable'); return;
    }
    context.selectedRowsClosed = true; context.selectedRows = undefined;
    if (rows === undefined || rows.unavailable) return;
    try {
      // One bounded record for this existing ingress, not another durable
      // observation transaction for each native get. Unknown classification
      // and missing original correlation remain absent, not zero or a new Run.
      const attributes = Object.freeze({'actql.rows.owner': rows.rowOwner,
        'actql.rows.selection': rows.selection, 'actql.rows.kind': rows.rowKind,
        'actql.rows.returned': rows.returnedRows,
        ...(rows.unrelatedRows === undefined ? {} : {'actql.rows.unrelated': rows.unrelatedRows}),
        'actql.rows.coverage': rows.coverage});
      selectedRowSnapshots.set(attributes, id);
      emit('run', 'selected_rows_observed', {ref: rows.ref}, {selectedRows: attributes});
    } catch {drop('rowsUnavailable');}
  };
  const finishContext = context => {
    if (context.finished || !context.ingressSettled || context.children !== 0) return;
    context.finished = true;
    contexts.run(context, () => flushSelectedRows(context));
    context.runIdentities = undefined;
    if (observeRows) activeContexts.delete(context);
    activeSegments--;
  };
  const captureCurrentOperation = () => {
    if (closed || !observeRows) return undefined;
    const context = contexts.getStore();
    if (context?.owner !== contextOwner || context.finished) return undefined;
    if (context.children >= config.selected.requestRecords) {drop('limited'); return undefined;}
    context.children++;
    let original = context;
    return Object.freeze({
      run(work) {return original === undefined ? work() : contexts.run(original, work);},
      release() {
        if (original === undefined) return;
        const held = original; original = undefined;
        held.children--;
        finishContext(held);
      },
    });
  };
  const retainOperation = promise => {
    if (closed || !observeRows) return;
    const context = contexts.getStore();
    if (context?.owner !== contextOwner || context.finished ||
        promise === null || !['object', 'function'].includes(typeof promise)) return;
    if (context.retainedPromises?.has(promise)) return;
    const captured = captureCurrentOperation();
    if (captured === undefined) return;
    try {
      // Use the original Promise's settlement, not a thenable/application
      // callback or another Run/observation frame. Never await or replace it.
      Promise.prototype.then.call(promise, captured.release, captured.release);
      (context.retainedPromises ??= new WeakSet()).add(promise);
    } catch {captured.release(); drop('rowsUnavailable');}
  };
  const accepted = (result, requestId) => {
    try {
      if (config.allowed.size === 0 || result?.ref === undefined) return;
      const current = contexts.getStore();
      const context = current?.owner === contextOwner ? current : undefined;
      if (context) context.ref = result.ref;
      if (observeRows && context && !context.finished && typeof requestId === 'string' &&
          typeof result.ref.namespaceId === 'string' && cid(result.ref.authorityScopeCid) &&
          cid(result.ref.runDefinitionCid)) {
        // This hook follows the actual Journal acceptance transaction. It is
        // only original correspondence, never a permission or row read ACK.
        context.selectedRequestBinding = {requestId, ref: Object.freeze({
          namespaceId: result.ref.namespaceId, authorityScopeCid: result.ref.authorityScopeCid,
          runDefinitionCid: result.ref.runDefinitionCid})};
        const pending = [];
        for (const detail of context.pendingRequestRows ?? []) {
          const bound = bindSelectedRequestRows(detail, context.selectedRequestBinding);
          if (bound === undefined) pending.push(detail);
          else accumulateSelectedRows(context, bound);
        }
        context.pendingRequestRows = pending;
      }
      if (result.inserted && storage !== undefined) {
        storage.initialize({ref: result.ref, requestId,
          scope: config.scope, revision: config.revision,
          maxRuns: config.selected.journalRuns,
          context: config.correlation ? context?.trace : undefined});
      }
    } catch { drop('budgetUnavailable'); }
  };
  const run = async (operation, trace, work, {http} = {}) => {
    if (closed || config.allowed.size === 0) return work();
    let parent = trace;
    if (config.correlation && parent === undefined) {
      if (config.currentContext !== undefined) {
        const leaveCallback = enterApplicationCallback();
        try { parent = config.currentContext(); } catch { /* Optional context. */ }
        finally {leaveCallback();}
      }
    }
    if (activeSegments >= config.selected.activeSegments) {
      drop('limited'); return work();
    }
    activeSegments++;
    const context = {owner: contextOwner, trace: config.correlation ? snapshotObservationContext(parent) : undefined,
      records: 0, http, children: 0, ingressSettled: false, finished: false};
    if (observeRows) activeContexts.add(context);
    try { return await contexts.run(context, async () => {
      const category = operation === 'check' || operation === 'prepareSubmit' ? 'check' : 'run';
      const segment = randomUUID(), started = performance.now();
      emit(category, 'segment_started', {}, {segment, ingress: true});
      try {
        const result = await work();
        context.ingressSettled = true;
        const selectedRef = context.selectedRows?.ref;
        if (cid(selectedRef?.runDefinitionCid)) context.ref = selectedRef;
        emit(category, 'segment_ended', {outcome: http?.response?.statusCode >= 400
          ? 'failed' : 'succeeded'},
          {segment, ingress: true, durationMs: performance.now() - started});
        finishContext(context);
        return result;
      } catch (cause) {
        context.ingressSettled = true;
        const selectedRef = context.selectedRows?.ref;
        if (cid(selectedRef?.runDefinitionCid)) context.ref = selectedRef;
        emit(category, 'segment_ended', {outcome: 'failed'},
          {segment, ingress: true, durationMs: performance.now() - started});
        finishContext(context);
        throw cause;
      }
    }); } finally {context.ingressSettled = true; finishContext(context);}
  };
  const projection = Object.freeze({run, accepted, emit, retainOperation, captureCurrentOperation,
    // Identity changes only at actual application callback boundaries. This
    // copied state is not authorization or an observation-delivery ACK.
    applicationCallbackState: () => callbackState,
    canMeasureResources: () => !closed && config.allowed.has('compute') && config.measurements.has('resources'),
    captureManagedRun(ref, readUsage) {
      if (closed || !config.allowed.has('compute') || !config.measurements.has('resources')) return undefined;
      if (!cid(ref?.runDefinitionCid) || typeof readUsage !== 'function') {
        drop('resourceUnavailable'); return undefined;
      }
      // A row response is consumed after ingress returns. Retain this same
      // operation's bounded correlation, not a new frame or authorization.
      const context = contexts.getStore();
      const originalRef = Object.freeze({namespaceId: ref.namespaceId,
        authorityScopeCid: ref.authorityScopeCid, runDefinitionCid: ref.runDefinitionCid});
      let observed = false;
      return () => {
        if (observed || closed) return;
        observed = true;
        let resources;
        try {resources = managedRunResources(readUsage());}
        catch {drop('resourceUnavailable'); return;}
        if (resources === undefined) {drop('resourceUnavailable'); return;}
        contexts.run(context, () => emit('compute', 'resources_observed',
          {ref: originalRef}, {resources}));
      };
    },
    canMeasure: operation => !closed && config.allowed.has(operation) &&
      config.measurements.has('duration'),
    noteLoss: () => drop('budgetUnavailable'),
    diagnostic(name, detail) {
      if (name === 'selected_rows_observed') {
        if (closed || config.eventLevel !== 'diagnostic' || !config.allowed.has('run') ||
            !config.measurements.has('rows')) return;
        let captured = false;
        try {
          const context = contexts.getStore();
          if (context?.owner === contextOwner) captured = accumulateSelectedRows(context, detail,
            Math.min(config.selected.requestRecords, config.selected.segmentRecords));
        }
        catch { /* Optional unreadable facts remain unavailable. */ }
        if (!captured) drop('rowsUnavailable');
        return;
      }
      const mapping = events[name];
      if (mapping) emit(mapping[0], mapping[1], {ref: detail?.ref,
        task: detail?.task, attempt: detail?.attempt, slot: detail?.slot,
        attemptCid: detail?.attemptCid, outcome: detail?.outcome});
    },
    status: () => Object.freeze({...counts, queued: queue.length,
      queuedBytes, active: pending.size, activeSegments, closed,
      cleanupPending: closed && !storageClosed,
      loss: Object.freeze({...diagnostics})}),
    async close() {
      if (closed) {
        try { closeStorage(); } catch {
          drop('budgetUnavailable');
          throw new Error('HostObservationCleanupPending');
        }
        return;
      }
      const deadline = Date.now() + config.selected.shutdownMs;
      while ((pending.size !== 0 || queue.length !== 0) && Date.now() < deadline) {
        await new Promise(resolve => setTimeout(resolve, 5));
      }
      closed = true;
      for (const context of activeContexts) {
        // Detach optional copied metadata, not the original work or its real
        // cleanup duty. An unfinished observation is unavailable, not zero.
        drop('rowsUnavailable');
        context.finished = true; context.selectedRowsClosed = true;
        context.selectedRows = context.pendingRequestRows = context.selectedRequestBinding =
          context.trace = context.ref = context.http = undefined;
        context.retainedPromises = undefined;
        context.runIdentities = undefined;
      }
      activeContexts.clear(); if (observeRows) activeSegments = 0;
      for (const _ of queue) drop('shutdown');
      queue.length = 0; queuedBytes = 0;
      try { closeStorage(); } catch {
        drop('budgetUnavailable');
        throw new Error('HostObservationCleanupPending');
      }
    },
  });
  projections.add(projection);
  config.status = projection.status;
  return projection;
}
