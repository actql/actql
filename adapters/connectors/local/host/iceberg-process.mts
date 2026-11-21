// Trusted physical Table installation boundary, not a public Effect factory.
// The caller supplies common-admitted operation/materials, current authority,
// approval and a fresh durable Ledger claim before execute. No retry is inferred
// from an absent response or receipt. All process stop facts use the existing
// managed-process owner; none are taken from an IPC acknowledgement.
import {isAbsolute} from 'node:path';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {prepareManagedExecution, startManagedExecution} from '../../../host-node/process-channel.mjs';
import {encodeProcessFrame} from '../../../host-node/process-frames.mjs';
type Configuration = Parameters<typeof prepareManagedExecution>[0];
type ProcessChannel = Awaited<ReturnType<typeof startManagedExecution>>;
type BeforeBodyAllocation = Configuration['beforeBodyAllocation'];
type BodyReceived = Configuration['bodyReceived'];
type BodySnapshot = Configuration['bodySnapshot'];
type ProcessCleanup = ProcessChannel['cleanupHandle'];
type Catalog = Readonly<{database: string; warehouse: string; catalogCid: string;
  limits: Readonly<{bytes: number; files: number; operations: number}>}>;
type PhysicalBridgeOptions = Readonly<{python: URL; run: string; catalog: unknown;
  implementation?: {identity: string; assertCurrent: () => undefined}; entry?: URL}>;
type ReadSelector = Readonly<{catalog_identity_cid: string; namespace: readonly string[];
  table_name: string; table_uuid: string; schema_cid: string}>;
type StorageControl = {
  localTableCommitResponse(responseWire: string, statusCode: number, limits: unknown): unknown;
  localEffectTableStorageMapping(artifact: unknown, limits: unknown): unknown;
  admitLocalTableStorageMapping(mappingWire: string, limits: unknown): unknown;
};
type CommitProjection = {control: Pick<StorageControl, 'localTableCommitResponse'> | null | undefined;
  responseWire: string; statusCode: number; limits: unknown};
type StorageIssue = {control: Pick<StorageControl, 'localEffectTableStorageMapping'>; artifact: unknown; limits: unknown};
type StorageAdmission = {control: Pick<StorageControl, 'admitLocalTableStorageMapping'>; mappingWire: string; limits: unknown};
type PhysicalOperation = {request_cid: string; action: string; schema_cid: string; input_carrier: {kind: unknown; cid: string}};
type WritePayload = {operation: PhysicalOperation; mapping: unknown; rows: unknown; reservation: unknown; schema_wire: string};
type WriteInput = {operation: unknown; mapping: unknown; rows: unknown; reservation: unknown; schemaWire: string;
  beforeBodyAllocation?: BeforeBodyAllocation; bodyReceived?: BodyReceived};
type OwnedPreparation = {bridge: object; payload: WritePayload; attempted: boolean; stopped: boolean;
  beforeBodyAllocation?: BeforeBodyAllocation; bodyReceived?: BodyReceived};
declare const physicalWritePreparationBrand: unique symbol;
type PreparedWrite = Readonly<{[physicalWritePreparationBrand]: true}>;
type PhysicalReply = {ok?: unknown; code?: unknown};
type TableConstructionFacts = Readonly<{
  nodes: bigint; wire: bigint; strings: bigint; serializerText: bigint; then?: never;
}>;

const frames = Object.freeze({maxBytes: 4 * 1024 * 1024, maxNodes: 100000, maxDepth: 32});
const preparations = new WeakMap<object, OwnedPreparation>();
const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };
const snapshot = (value: unknown): unknown => JSON.parse(encodeProcessFrame(value, frames).subarray(4).toString('utf8'));
const cid = (value: unknown): value is string => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const keys = (value: unknown, names: readonly string[]) => value && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join(',') === names.slice().sort().join(',');

// This is the selected Connector's pinned declaration, not a second registry
// or authority grant. Its contract bytes are in the installation inventory.
const operationKinds = JSON.parse(readFileSync(
  new URL('../../../../spec/contracts/actql-local-table-iceberg.json', import.meta.url), 'utf8')).operations as Readonly<Record<string, readonly unknown[]>>;
if (!keys(operationKinds, ['create', 'replace', 'snapshot_read']) ||
    Object.values(operationKinds).some(kinds => !Array.isArray(kinds) ||
      kinds.length !== 1 || kinds[0] !== 'relation')) fail('InvalidLocalTableOperationDeclaration');

export function supportsIcebergTableOperation({action, kind}: {action: string; kind: unknown}) {
  return Object.hasOwn(operationKinds, action) && operationKinds[action].includes(kind);
}

// The selected Local installation admits physical fields through its MoonBit
// contract. Common Table settlement sees only this logical projection; the
// original response remains in the existing Ledger and Catalog.
export function projectIcebergCommitResponse({control, responseWire, statusCode, limits}: CommitProjection) {
  if (typeof control?.localTableCommitResponse !== 'function') {
    fail('InvalidLocalTableCommitProjector');
  }
  return control.localTableCommitResponse(responseWire, statusCode, limits);
}

// These physical-contract hooks are selected with this Connector. Shared
// input/capture owners retain their opaque result, never issue Iceberg fields.
export function issueIcebergStorageMapping({control, artifact, limits}: StorageIssue) {
  return control.localEffectTableStorageMapping(artifact, limits);
}

export function admitIcebergStorageMapping({control, mappingWire, limits}: StorageAdmission) {
  return control.admitLocalTableStorageMapping(mappingWire, limits);
}

// Pure shape checks for an already-owned JSON profile. These do not snapshot,
// retain a physical bridge, prepare a process, or issue read authority. The
// actual bridge below still snapshots before checking and retaining its data.
export function validateIcebergPhysicalConfiguration({python, catalog}: {python: unknown; catalog: Catalog}) {
  if (!(python instanceof URL) || python.protocol !== 'file:' ||
      !keys(catalog, ['database', 'warehouse', 'catalogCid', 'limits']) ||
      !(['database', 'warehouse'] as const).every(key => typeof catalog[key] === 'string' && isAbsolute(catalog[key])) ||
      !cid(catalog.catalogCid) || !keys(catalog.limits, ['bytes', 'files', 'operations']) ||
      Object.values(catalog.limits).some(value => !Number.isSafeInteger(value) || value < 1)) {
    fail('InvalidTablePhysicalConfiguration');
  }
}

export function validateIcebergReadSelector(selector: ReadSelector, catalogCid: string) {
  if (!keys(selector, ['catalog_identity_cid', 'namespace', 'table_name', 'table_uuid', 'schema_cid']) ||
      selector.catalog_identity_cid !== catalogCid || !cid(selector.schema_cid) ||
      !Array.isArray(selector.namespace) || selector.namespace.length < 1 ||
      selector.namespace.length > 32 || selector.namespace.some(part =>
        typeof part !== 'string' || part.length < 1 || part.length > 256 || /[.\0\r\n]/u.test(part)) ||
      typeof selector.table_name !== 'string' || selector.table_name.length < 1 ||
      selector.table_name.length > 256 || /[\0\r\n]/u.test(selector.table_name) ||
      typeof selector.table_uuid !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u.test(selector.table_uuid)) {
    fail('InvalidTableReadSelector');
  }
}

export function createIcebergPhysicalBridge({python, run, catalog,
  implementation,
  entry = new URL('../iceberg/process_worker.py', import.meta.url)}: PhysicalBridgeOptions) {
  const config = snapshot(catalog) as Catalog;
  validateIcebergPhysicalConfiguration({python, catalog: config});
  if (implementation !== undefined && (!cid(implementation.identity) ||
      typeof implementation.assertCurrent !== 'function')) fail('InvalidTableImplementationBinding');
  const assertImplementation = () => {
    if (implementation !== undefined && implementation.assertCurrent() !== undefined) {
      fail('InvalidTableImplementationBinding');
    }
  };
  assertImplementation();
  // Validate and snapshot interpreter/entry/run synchronously, before a durable
  // Effect send claim. Each invocation creates one fresh process preparation.
  prepareManagedExecution({runtime: python, entry, run, frames, maxRequests: 1,
    graceMs: 100, startupMs: 5000});
  const runtime = new URL(python.href), worker = new URL(entry.href);
  const configuration = () => ({runtime, entry: worker, run, frames, maxRequests: 1,
    graceMs: 100, startupMs: 5000});
  const requestFrame = (command: string, payload: unknown) => ({protocol: 'actql-local-execution/0.1',
    session: '00000000-0000-0000-0000-000000000000', run,
    kind: 'execute', sequence: 1, body: {catalog: config, command, payload}});
  const preflight = (command: string, payload: unknown) => snapshot(requestFrame(command, payload));
  const invoke = async (command: string, payload: unknown, signal?: AbortSignal, stopped?: () => undefined,
    beforeBodyAllocation?: BeforeBodyAllocation, bodyReceived?: BodyReceived, bodySnapshot?: BodySnapshot) => {
    assertImplementation();
    let channel: ProcessChannel | undefined, error: {cleanupHandle?: ProcessCleanup} | null | undefined, launchSelected = false;
    // A bounded physical I/O wait does not certify cancellation/noncommit.
    // Deadline failure still waits for actual exit and requires reconciliation.
    const deadline = AbortSignal.timeout(60000);
    const cancellation = signal === undefined ? deadline : AbortSignal.any([signal, deadline]);
    try {
      const prepared = prepareManagedExecution({...configuration(), beforeBodyAllocation, bodyReceived, bodySnapshot});
      cancellation.throwIfAborted();
      launchSelected = true;
      channel = await startManagedExecution(prepared, cancellation);
      return await channel.request({catalog: config, command, payload}, cancellation);
    } catch (caught) {
      error = caught as typeof error;
      throw caught;
    } finally {
      // Retain physical flight until observed exit, including failed handshake,
      // cancellation and unknown replies. The existing cleanup handle performs
      // kill-and-wait where cooperative stop is impossible.
      if (channel) await channel.close();
      else if (error?.cleanupHandle) await error.cleanupHandle.retry();
      // Process exit cannot discharge an unresolved original callback duty.
      const cleanup = channel?.cleanupHandle ?? error?.cleanupHandle;
      if (!launchSelected || cleanup !== undefined && cleanup.status().pending === false) stopped?.();
    }
  };
  const own = (prepared: PreparedWrite): OwnedPreparation => {
    const owned = preparations.get(prepared);
    if (!owned || owned.bridge !== bridge) fail('ForeignTablePhysicalPreparation');
    return owned;
  };
  const reconcileOperation = (operation: unknown, signal?: AbortSignal,
    beforeBodyAllocation?: BeforeBodyAllocation, bodyReceived?: BodyReceived) => {
    const payload = snapshot({operation}) as {operation?: Pick<PhysicalOperation, 'request_cid'>};
    if (!cid(payload.operation?.request_cid)) fail('InvalidTablePhysicalPreparation');
    preflight('reconcile', payload);
    return invoke('reconcile', payload, signal, undefined, beforeBodyAllocation, bodyReceived);
  };
  const bridge = Object.freeze({
    frameLimits: frames,
    // Original implementation geometry for the installed managed Plan. This
    // is constructor DATA, never a process, reservation or permission. The
    // retained payload, preflight/request snapshots and response projection
    // can overlap; each uses this same finite framing implementation.
    effectPlanConstruction: Object.freeze({
      retained: Object.freeze({nodes: 4n * BigInt(frames.maxNodes),
        text: 8n * BigInt(frames.maxBytes), wire: 2n * BigInt(frames.maxBytes)}),
      workspace: Object.freeze({nodes: 2n * BigInt(frames.maxNodes) + 2n * BigInt(frames.maxDepth),
        text: 4n * BigInt(frames.maxBytes), wire: 2n * BigInt(frames.maxBytes) + 8n}),
    }),
    supportsOperation(values: Parameters<typeof supportsIcebergTableOperation>[0]) { assertImplementation(); return supportsIcebergTableOperation(values); },
    issueStorageMapping(values: StorageIssue) { assertImplementation(); return issueIcebergStorageMapping(values); },
    admitStorageMapping(values: StorageAdmission) { assertImplementation(); return admitIcebergStorageMapping(values); },
    projectCommitResponse(values: CommitProjection) { assertImplementation(); return projectIcebergCommitResponse(values); },
    // Pure installed-target validation. A selector binds a Table, not a read
    // grant or a generation; only the authorized resolver freezes a head.
    checkReadSelector(selector: unknown): ReadSelector {
      const payload = snapshot({selector}) as {selector: ReadSelector};
      validateIcebergReadSelector(payload.selector, config.catalogCid);
      Object.freeze(payload.selector.namespace);
      return Object.freeze(payload.selector);
    },
    inspectReadSelectorConstruction(selector: unknown, inspect: (frame: ReturnType<typeof requestFrame>) => TableConstructionFacts) {
      assertImplementation();
      if (typeof inspect !== 'function') fail('InvalidTableReadConstructionInspection');
      // The installed Source owner funds this inspection before entry. Use
      // the SAME selector and first outbound preflight frame, not the full
      // installation's unrelated targets or a guessed numerical allowance.
      const payload = {selector: bridge.checkReadSelector(selector)};
      return inspect(requestFrame('resolve_generation', payload));
    },
    prepareWrite({operation, mapping, rows, reservation, schemaWire, beforeBodyAllocation, bodyReceived}: WriteInput) {
      assertImplementation();
      if (typeof schemaWire !== 'string') fail('InvalidTableLogicalSchema');
      const payload = snapshot({operation, mapping, rows, reservation, schema_wire: schemaWire}) as WritePayload;
      if (!keys(payload.operation?.input_carrier, ['kind', 'cid']) ||
          !cid(payload.operation.input_carrier.cid)) fail('InvalidTableCarrierReference');
      if (!['create', 'replace'].includes(payload.operation.action) ||
          !supportsIcebergTableOperation({action: payload.operation.action,
            kind: payload.operation.input_carrier.kind})) fail('UnsupportedTableCarrierOperation');
      if (!cid(payload.operation?.request_cid) || !Array.isArray(payload.rows)) {
        fail('InvalidTablePhysicalPreparation');
      }
      if (typeof payload.schema_wire !== 'string' || Buffer.byteLength(payload.schema_wire, 'utf8') > 65536 ||
          `sha256:${createHash('sha256').update(payload.schema_wire, 'utf8').digest('hex')}` !== payload.operation.schema_cid) {
        fail('InvalidTableLogicalSchema');
      }
      // Charge/validate the entire transport envelope before claiming a send,
      // including empty typed input. This is a bounded initial I/O profile, not
      // a substitute for common input admission/retention accounting.
      preflight('write', payload);
      const prepared = Object.freeze({}) as PreparedWrite;
      preparations.set(prepared, {bridge, payload, attempted: false, stopped: false, beforeBodyAllocation, bodyReceived});
      return prepared;
    },
    async execute(prepared: PreparedWrite, {useCid, signal}: {useCid?: string; signal?: AbortSignal} = {}) {
      const owned = own(prepared);
      if (!cid(useCid)) fail('InvalidTableCredentialUse');
      signal?.throwIfAborted();
      assertImplementation();
      if (owned.attempted) fail('TablePhysicalReconcileOnly');
      owned.attempted = true;
      const result = await invoke('write', owned.payload, signal, () => { owned.stopped = true; }, owned.beforeBodyAllocation, owned.bodyReceived) as PhysicalReply | null;
      if (typeof result?.ok !== 'boolean' || !(keys(result, ['ok', 'result']) ||
          (!result.ok && keys(result, ['ok', 'code']) && typeof result.code === 'string'))) {
        fail('InvalidTablePhysicalReply');
      }
      return Object.freeze({observation: Object.freeze({useCid,
        statusCode: result.ok ? 200 : 409,
        body: Buffer.from(JSON.stringify(result))})});
    },
    async reconcile(prepared: PreparedWrite, signal?: AbortSignal) {
      const owned = own(prepared);
      return reconcileOperation(owned.payload.operation, signal, owned.beforeBodyAllocation, owned.bodyReceived);
    },
    // Recovery needs the original sealed operation, not live input, a new
    // writer preparation or recreated payload. Caller owns evidence authority.
    reconcileOperation,
    async inspect(prepared: PreparedWrite, signal?: AbortSignal) {
      const owned = own(prepared);
      const payload = {operation: owned.payload.operation};
      preflight('inspect', payload);
      return invoke('inspect', payload, signal, undefined, owned.beforeBodyAllocation, owned.bodyReceived);
    },
    async cleanup(prepared: PreparedWrite, signal?: AbortSignal) {
      const owned = own(prepared);
      if (!owned.attempted || !owned.stopped) fail('TableWriterNotStopped');
      // The Catalog checks original-operation publication and fences commit in
      // the same transaction before deleting only this operation's staged files.
      return invoke('cleanup', {operation: owned.payload.operation}, signal, undefined, owned.beforeBodyAllocation, owned.bodyReceived);
    },
    async read(receipt: unknown, mapping: unknown, signal?: AbortSignal,
      beforeBodyAllocation?: BeforeBodyAllocation, bodyReceived?: BodyReceived, bodySnapshot?: BodySnapshot) {
      const payload = snapshot({receipt, mapping});
      preflight('read', payload);
      return invoke('read', payload, signal, undefined, beforeBodyAllocation, bodyReceived, bodySnapshot);
    },
    async resolveGeneration(selector: unknown, signal?: AbortSignal,
      beforeBodyAllocation?: BeforeBodyAllocation, bodyReceived?: BodyReceived, bodySnapshot?: BodySnapshot) {
      const payload = {selector: bridge.checkReadSelector(selector)};
      preflight('resolve_generation', payload);
      return invoke('resolve_generation', payload, signal, undefined, beforeBodyAllocation, bodyReceived, bodySnapshot);
    },
    status(prepared: PreparedWrite) {
      const owned = own(prepared);
      return Object.freeze({attempted: owned.attempted, stopped: owned.stopped});
    },
  });
  return bridge;
}
