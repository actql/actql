// Table-specific physical projection of the existing installed row Source.
// The caller installs the same current authorization/Site as other Sources;
// this adapter issues no grant, runs no task scheduler and owns no capture.
import {createHash} from 'node:crypto';
import {types as nodeTypes} from 'node:util';
import {checkpointApprovalFacts} from '../host-common/checkpoint-approval.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {createInstalledRowSource, rowSourceCheckEnvironment} from './installed-row-source.mjs';
import type {createIcebergPhysicalBridge} from '../connectors/local/host/iceberg-process.mjs';
import type {FrameLimits} from './process-frames.mjs';

type Runtime = Readonly<{
  clientProgramInstalledTableSourceBodyCapacity(capacity: unknown, bytes: number, maxDepth: number): unknown;
  clientProgramInstalledTableSourceSerializationCapacity(capacity: unknown, bytes: number): unknown;
  clientProgramInstalledTableSourceCompletedCapacity(capacity: unknown, nodes: number, fields: number,
    objects: number, arrays: number, utf16Units: number): unknown;
  clientProgramRowSourceChargeResponseBody(run: unknown, body: Buffer): unknown;
  clientProgramRowSourceRestoreRelationDeclaration(connectorId: string, registration: string, revision: string,
    views: string, expectedCatalogCid: undefined): unknown;
  clientProgramRowSourceDeclarationJson(declaration: unknown): string;
}>;
type Bridge = Pick<ReturnType<typeof createIcebergPhysicalBridge>,
  'checkReadSelector' | 'resolveGeneration' | 'read' | 'frameLimits'>;
type Selector = ReturnType<Bridge['checkReadSelector']>;
type BodyGeometry = Parameters<NonNullable<Parameters<Bridge['read']>[5]>>[0];
type PhysicalTarget = Readonly<{version: string; catalog_cid: string; selector: Selector;
  selector_cid: string; resource: string; fields: readonly string[]}>;
type ReadTuple = Readonly<{connection?: unknown; operation?: unknown; resource?: unknown}>;
type Decision = Readonly<{action?: unknown; basis?: unknown; boundary?: unknown;
  tuple?: ReadTuple; contextCid?: unknown}>;
type Authorization = Readonly<{issued(decision: Decision): unknown; context: Readonly<{contextCid: unknown}>;
  close?: unknown}>;
type ReadSiteInput = {connection: string; authorization: Authorization | undefined; principalId: string | undefined;
  targets: (() => readonly PhysicalTarget[]) | undefined; ownAuthorization?: boolean};
type GrantInput = Readonly<{operation: string; decision: Decision | undefined; resource: string;
  runInvocationCid: string; dispatchRequestCid: string; maxUses: number}>;
type ReadOptions = Readonly<{resource: string; columns: readonly string[]; signal?: AbortSignal;
  rowRun?: Readonly<{run: unknown}>;
  authorizationFor(index: number): Promise<unknown>; chargePage(bytes: Buffer): unknown;
  consumePageWire(wire: string, options: Readonly<{charge: unknown}>): unknown;
  consumeObservation?: (ticket: unknown) => unknown}>;
type PhysicalRead = Readonly<{signal: AbortSignal; beforeBodyAllocation(length: number): undefined;
  bodyReceived(body: Buffer): undefined; bodySnapshot(geometry: BodyGeometry): undefined;
  preparePayload(): void; prepareOutput(): void; finalCharge(): unknown}>;
type ReaderPhase = 'preparing' | 'ready' | 'reading' | 'complete' | 'failed';
type Cleanup = Readonly<{status(): Readonly<{pending: boolean}>; retry(): unknown}>;
type Reader = Readonly<{read(): Promise<void>; requestStop(reason?: unknown): void;
  retry(): Promise<boolean> | undefined;
  observe(): Readonly<{phase: ReaderPhase; readPending: boolean; stopRequested: boolean;
    cleanupConfirmed: boolean}>; retire(): boolean}>;
type ReaderFactory = Readonly<{capacity: unknown;
  prepare(options: ReadOptions, retainPreparation: (reader: Reader) => void,
    reserveResponseCapacity: (capacity: unknown, phase?: 'announced-body' | 'completed-body') => void): Reader;
  retire(): boolean}>;
type SourceInputs = Readonly<{moon: Runtime; baseEnvironmentWire: string; connectorId: string;
  connectorRegistration: string; connectorRevision: string;
  site: Readonly<{connection: string; issueReadGrant(input: GrantInput): unknown; close(): unknown}>;
  authorization: Readonly<{authorize: (...args: never[]) => unknown}>; bridge: Bridge;
  targets: readonly Readonly<{resource: string; selector: unknown; schemaWire: string}>[];
  limits: Readonly<{maxPages: number; maxPageBytes: number; maxPageRows: number; maxCaptureRows: number}>;
  sourceInitialization?: object; readerCapacity?: unknown; bindReader?: (reader: ReaderFactory) => void;
  declaration?: unknown; declared?: unknown; environment?: Readonly<{wire: string}>;
  publicationBindingCid?: string}>;
type Declaration = Parameters<typeof rowSourceCheckEnvironment>[1] & Readonly<{
  catalog_cid: string; views: readonly Readonly<{source_ref: string; resource: string; fields: readonly string[]}>[];
}>;
type FrozenGeneration = Readonly<{schema_wire: unknown; receipt: Readonly<{catalog_identity_cid: unknown;
  table_uuid: unknown; schema_cid: unknown; storage_mapping_cid: unknown; generation_cid: unknown;
  row_count: unknown}>; mapping: Readonly<{schema_cid: unknown; mapping_cid: unknown}>}>;
type SourceAdapter = Readonly<{close(): unknown; tableReadTargets: readonly PhysicalTarget[]}>;


const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;
const keys = (value: unknown, names: readonly string[]): value is Record<string, unknown> => (value && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join(',') === [...names].sort().join(',')) as boolean;
const identifier = (value: unknown) => /^sha256:[0-9a-f]{64}$/u.test((value ?? '') as string);
const dataCid = (value: unknown) => `sha256:${createHash('sha256')
  .update(canonicalJson(value, {dataKeys: true})).digest('hex')}`;
const closedReply = (value: unknown, resultKeys?: readonly string[]) => {
  if ((value as {ok?: unknown} | undefined)?.ok === false && keys(value, ['ok', 'code']) && text(value.code)) fail(value.code);
  if (!keys(value, ['ok', 'result']) || value.ok !== true ||
      resultKeys !== undefined && !keys(value.result, resultKeys)) fail('InvalidTableReadReply');
  return value.result;
};

// No external credential is needed for local Catalog I/O. This Site only
// admits decisions issued by the installed gate or the existing Checkpoint
// owner for this exact physical binding. It is not an approval/Run owner.
export function installedTableReadSite({connection, authorization, principalId, targets, ownAuthorization = false}: ReadSiteInput) {
  let authorizationClose: (() => unknown) | undefined, closeFlight: Promise<unknown> | undefined;
  if (ownAuthorization) {
    if (!authorization || typeof authorization !== 'object' || nodeTypes.isProxy(authorization)) {
      fail('InvalidInstalledTableAuthorization');
    }
    const close = Object.getOwnPropertyDescriptor(authorization, 'close');
    if (!close || !Object.hasOwn(close, 'value') || typeof close.value !== 'function' ||
        nodeTypes.isProxy(close.value) || nodeTypes.isAsyncFunction(close.value)) {
      fail('InvalidInstalledTableAuthorization');
    }
    authorizationClose = close.value;
  }
  let closed = false, retiring = false, cleanupRunning = false;
  let approvals: WeakMap<Decision, string> | undefined = new WeakMap();
  const ensureOpen = () => { if (closed || retiring) fail('InstalledTableSiteClosed'); };
  return Object.freeze({connection,
    admitCheckpointReadApproval<Original extends Decision>(decision: Original) {
      ensureOpen();
      const facts = checkpointApprovalFacts(decision);
      const binding = facts?.physicalBinding;
      const selectedTargets = targets!();
      ensureOpen();
      const target = selectedTargets.find(target => target.resource === decision?.tuple?.resource);
      if (!facts || !target || decision.action !== 'dispatch' || decision.basis !== 'resumed_approval' ||
          decision.boundary !== 'acquisition' || facts.principalId !== principalId ||
          (facts.readTuple as ReadTuple | undefined)?.connection !== connection || (facts.readTuple as ReadTuple | undefined)?.operation !== 'read' ||
          (facts.readTuple as ReadTuple | undefined)?.resource !== target.resource || decision.tuple?.connection !== connection ||
          decision.tuple?.operation !== 'read' ||
          !keys(binding, ['version', 'catalog_cid', 'selector', 'selector_cid', 'resource', 'fields']) ||
          binding.version !== target.version || binding.catalog_cid !== target.catalog_cid ||
          binding.selector_cid !== target.selector_cid || canonicalJson(binding.selector, {dataKeys: true}) !== canonicalJson(target.selector, {dataKeys: true}) ||
          binding.resource !== target.resource || !Array.isArray(binding.fields) ||
          binding.fields.length === 0 ||
          new Set(binding.fields).size !== binding.fields.length ||
          binding.fields.some(field => !target.fields.includes(field))) fail('TableSourceReadApprovalNotAdmitted');
      ensureOpen();
      approvals!.set(decision, target.resource);
      return decision;
    },
    issueReadGrant({operation, decision, resource, runInvocationCid, dispatchRequestCid, maxUses}: GrantInput) {
      ensureOpen();
      const selectedTargets = targets!();
      ensureOpen();
      if (operation !== 'table.read' || !identifier(runInvocationCid) || !identifier(dispatchRequestCid) ||
          !Number.isSafeInteger(maxUses) || maxUses < 1 ||
          !selectedTargets.some(target => target.resource === resource) ||
          decision?.action !== 'dispatch' || decision.boundary !== 'acquisition' ||
          decision.tuple?.connection !== connection || decision.tuple?.resource !== resource ||
          decision.tuple?.operation !== 'read') {
        fail('TableSourceReadGrantNotAuthorized');
      }
      ensureOpen();
      if (approvals!.get(decision) !== resource) {
        const issued = authorization!.issued(decision);
        ensureOpen();
        if (!issued || decision.contextCid !== authorization!.context.contextCid) {
          fail('TableSourceReadGrantNotAuthorized');
        }
      }
      ensureOpen();
      return Object.freeze({runInvocationCid, dispatchRequestCid});
    },
    referenceCurrent() {return !closed && !retiring;},
    close() {
      if (closed) return;
      retiring = true;
      if (cleanupRunning || closeFlight !== undefined) fail('InstalledSourceAuthorizationCleanupPending');
      cleanupRunning = true;
      try {
        if (ownAuthorization) {
          const completed = Reflect.apply(authorizationClose!, authorization, []);
          if (completed !== true) {
            if (nodeTypes.isPromise(completed)) {
              // Retain one entered original until settlement. Settlement only
              // permits cleanup retry; it is never this scope's close ACK.
              closeFlight = completed;
              Promise.prototype.then.call(completed,
                () => {closeFlight = undefined;}, () => {closeFlight = undefined;});
            }
            fail('InstalledSourceAuthorizationCleanupPending');
          }
        }
        closed = true;
        authorization = authorizationClose = targets = approvals = principalId = undefined;
      } finally { cleanupRunning = false; }
    },
  });
}

// The normal Table reader uses the existing provider-reader contract. Its
// process, RowRun, Site and Request are originals; it owns no replacement
// reservation, grant, attempt, receipt or physical cleanup implementation.
function createInstalledTableSourceReader({moon, initialCapacity, readPages, frameLimits}: Readonly<{
  moon: Runtime; initialCapacity: unknown;
  readPages(options: ReadOptions, physical: PhysicalRead): Promise<void>; frameLimits: FrameLimits;
}>): ReaderFactory {
  const bodyCapacity = moon.clientProgramInstalledTableSourceBodyCapacity;
  const serializationCapacity = moon.clientProgramInstalledTableSourceSerializationCapacity;
  const completedCapacity = moon.clientProgramInstalledTableSourceCompletedCapacity;
  const chargeBody = moon.clientProgramRowSourceChargeResponseBody;
  if ([bodyCapacity,serializationCapacity,completedCapacity,chargeBody].some(value=>typeof value !== 'function') ||
      initialCapacity === undefined || typeof readPages !== 'function' || !Object.isFrozen(frameLimits)) {
    fail('InstalledTableSourceReaderUnavailable');
  }
  let closing = false;
  const readers = new Set<Reader>();
  const factory: ReaderFactory = Object.freeze({capacity:initialCapacity,
    prepare(options: ReadOptions, retainPreparation: (reader: Reader) => void,
      reserveResponseCapacity: (capacity: unknown, phase?: 'announced-body' | 'completed-body') => void) {
      if (this !== factory || closing || typeof retainPreparation !== 'function' ||
          typeof reserveResponseCapacity !== 'function' || readers.size === Number.MAX_SAFE_INTEGER) {
        fail('InstalledTableSourceReaderUnavailable');
      }
      // Retain this SAME record before any option getter or signal constructor.
      // A failed preparation then uses the Host's existing original retry.
      let run: unknown, consume: ReadOptions['consumeObservation'];
      let stop: AbortController | undefined, signal: AbortSignal | undefined;
      let selected: ReadOptions | undefined = options, capacity: unknown = initialCapacity;
      let ticket: unknown, bodyBytes = 0;
      let nodes = 0, fields = 0, objects = 0, arrays = 0, utf16Units = 0;
      let phase: ReaderPhase = 'preparing', pending = false, stopped = false, retired = false;
      let cleanup: Cleanup | undefined;
      let handle: Reader;
      const check = () => {
        if (closing || retired || stopped || !pending) fail('InstalledTableSourceReaderClosed');
        signal!.throwIfAborted();
      };
      const consumePrevious = () => {
        if (ticket !== undefined) {Reflect.apply(consume!,selected,[ticket]);ticket=undefined;}
      };
      const grow = (next: unknown) => {
        check();reserveResponseCapacity(next,'announced-body');check();capacity=next;
      };
      const beforeBodyAllocation = (length: number): undefined => {
        check();consumePrevious();
        grow(checked(Reflect.apply(bodyCapacity,moon,[capacity,length,frameLimits.maxDepth])));
      };
      const bodyReceived = (body: Buffer): undefined => {
        check();if(ticket!==undefined)fail('InstalledTableSourceResponsePending');
        ticket=checked(Reflect.apply(chargeBody,moon,[run,body]));
        // Resource/current may synchronously stop this SAME reader. Keep the
        // observed ticket, but never decode after that original callback.
        check();bodyBytes=body.byteLength;
      };
      const bodySnapshot = (geometry: BodyGeometry): undefined => {
        check();
        if (!Number.isSafeInteger(geometry.nodes) || geometry.nodes < 0 ||
            !Number.isSafeInteger(geometry.fields) || geometry.fields < 0 ||
            !Number.isSafeInteger(geometry.objects) || geometry.objects < 0 ||
            !Number.isSafeInteger(geometry.arrays) || geometry.arrays < 0 ||
            !Number.isSafeInteger(geometry.utf16Units) || geometry.utf16Units < 0) {
          fail('InvalidTableReplyGeometry');
        }
        nodes += geometry.nodes; fields += geometry.fields; objects += geometry.objects;
        arrays += geometry.arrays; utf16Units += geometry.utf16Units;
        if (nodes > 2147483647 || fields > 2147483647 || objects > 2147483647 ||
            arrays > 2147483647 || utf16Units > 2147483647) fail('InvalidTableReplyGeometry');
      };
      const completeBodies = () => {
        // Both bridge calls return only after their ORIGINAL process close.
        // The same snapshot traversal measured every returned native tree;
        // old Buffers, decoded text and parser/encoder scratch no longer escape.
        const next = checked(Reflect.apply(completedCapacity, moon,
          [initialCapacity, nodes, fields, objects, arrays, utf16Units]));
        reserveResponseCapacity(next, 'completed-body'); check(); capacity = next;
      };
      const preparePayload = () => {
        check();consumePrevious();completeBodies();
        // Actual metadata payload snapshot, full envelope preflight and send
        // encoding are separate constructors. Keep their original full peaks
        // alongside the received prefix; no earlier body is assumed retired.
        for(let index=0;index<3;index++)grow(checked(Reflect.apply(bodyCapacity,moon,
          [capacity,bodyBytes,frameLimits.maxDepth])));
        grow(checked(Reflect.apply(serializationCapacity,moon,[capacity,bodyBytes])));
      };
      const prepareOutput = () => {
        check();
        if(ticket===undefined)fail('InstalledTableSourceResponseUnavailable');
        // This is the final received response: preserve its unconsumed
        // original ticket and use the EXISTING charged constructor entrance.
        completeBodies();
        const next=checked(Reflect.apply(serializationCapacity,moon,[capacity,bodyBytes]));
        reserveResponseCapacity(next);check();capacity=next;
      };
      // Retirement follows the existing process Owner's observation, never a
      // settled read, a stop request or an exception code. The SAME unresolved
      // cleanup handle remains reachable on this original reader.
      const retire = () => {
        if(retired)return true;
        if(!stopped||pending||cleanup!==undefined&&cleanup.status().pending!==false)return false;
        selected=capacity=ticket=cleanup=run=consume=signal=stop=undefined;
        retired=true;readers.delete(handle);return true;
      };
      handle=Object.freeze({
        async read() {
          if(this!==handle||phase!=='ready'||stopped||closing)fail('InstalledTableSourceReaderAlreadyStarted');
          phase='reading';pending=true;
          try {
            const physical={signal:signal!,beforeBodyAllocation,bodyReceived,bodySnapshot,preparePayload,prepareOutput,
              finalCharge() {if(ticket===undefined)fail('InstalledTableSourceResponseUnavailable');const value=ticket;ticket=undefined;return value;}};
            const result=await readPages(selected!,physical);
            phase='complete';return result;
          }catch(cause){cleanup=(cause as {cleanupHandle?: Cleanup} | undefined)?.cleanupHandle;phase='failed';throw cause;}
          finally{pending=false;if(stopped)retire();}
        },
        requestStop(reason?: unknown) {
          if(this!==handle)fail('ForeignInstalledTableSourceReader');
          if(retired)return;stopped=true;stop?.abort(reason);retire();
        },
        retry() {
          if(this!==handle||!stopped)fail('InstalledTableSourceReaderStopRequired');
          if(retired)return;
          if(cleanup===undefined){retire();return;}
          // Only the entered original cleanup task may keep a Promise live.
          // A spent reader cannot create fresh pending work on every retry.
          return Promise.resolve(cleanup.retry()).then(retire);
        },
        observe() {
          if(this!==handle)fail('ForeignInstalledTableSourceReader');
          return Object.freeze({phase,readPending:pending,stopRequested:stopped,cleanupConfirmed:retire()});
        },
        retire() {
          if(this!==handle)fail('ForeignInstalledTableSourceReader');
          if(!stopped){stopped=true;stop?.abort();}
          return retire();
        },
      });
      readers.add(handle);
      retainPreparation(handle);
      if(closing||stopped||retired)fail('InstalledTableSourceReaderClosed');
      // The SAME caller supplied these methods after its RowRun/cleanup bind.
      run=options.rowRun?.run;
      // A getter may retire this SAME early record. Do not retain its returned
      // alias or enter the next constructor after that original retirement.
      if(closing||stopped||retired){run=undefined;fail('InstalledTableSourceReaderClosed');}
      consume=options.consumeObservation;
      if(closing||stopped||retired){run=consume=undefined;fail('InstalledTableSourceReaderClosed');}
      if(run===undefined||typeof consume!=='function')fail('InstalledTableSourceResponseUnavailable');
      stop=new AbortController();
      if(closing||stopped||retired){run=consume=stop=undefined;fail('InstalledTableSourceReaderClosed');}
      const originalSignal=options.signal;
      if(closing||stopped||retired)fail('InstalledTableSourceReaderClosed');
      signal=originalSignal===undefined?stop.signal:AbortSignal.any([originalSignal,stop.signal]);
      if(closing||stopped||retired){run=consume=stop=signal=undefined;fail('InstalledTableSourceReaderClosed');}
      phase='ready';return handle;
    },
    retire() {
      if(this!==factory)fail('ForeignInstalledTableSourceReader');closing=true;
      for(const reader of readers)reader.requestStop();
      return readers.size===0;
    },
  });
  return factory;
}

// Installation binds saved schema and Table UUID/name. It never reads provider
// metadata during Check or uses observed rows to issue a declaration. A new
// acquisition resolves one immutable generation under current read authority.
export async function createInstalledTableSource({moon, baseEnvironmentWire,
  connectorId, connectorRegistration, connectorRevision,
  site, authorization, bridge, targets, limits, sourceInitialization, readerCapacity, bindReader,
  declaration: originalDeclaration, declared: originalDeclared, environment: originalEnvironment, publicationBindingCid}: SourceInputs): Promise<SourceAdapter> {
  if (!moon || !text(baseEnvironmentWire) || !text(connectorId) ||
      !text(connectorRegistration) || !text(connectorRevision) ||
      !text(site?.connection) || typeof site?.issueReadGrant !== 'function' ||
      typeof authorization?.authorize !== 'function' ||
      !['checkReadSelector', 'resolveGeneration', 'read'].every(key => typeof bridge?.[key as keyof Bridge] === 'function') ||
      !Array.isArray(targets) || targets.length < 1) {
    fail('InvalidInstalledTableSource');
  }
  const installed = targets.map(target => {
    if (!keys(target, ['resource', 'selector', 'schemaWire']) ||
        !text(target.resource) || typeof target.schemaWire !== 'string') fail('InvalidInstalledTableReadTarget');
    return Object.freeze({resource: target.resource,
      selector: bridge.checkReadSelector(target.selector), schemaWire: target.schemaWire});
  });
  if (new Set(installed.map(target => target.resource)).size !== installed.length) {
    fail('DuplicateInstalledTableReadTarget');
  }
  const specification = originalDeclaration === undefined ? JSON.stringify({views: installed.map(target => ({
    resource: target.resource, resource_kind: 'table',
    schema_wire: target.schemaWire, schema_cid: target.selector.schema_cid,
  }))}) : undefined;
  const declaration = originalDeclaration ?? checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    connectorId, connectorRegistration, connectorRevision, specification!, undefined));
  const declared = (originalDeclared ?? JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration))) as Declaration;
  const environment = originalEnvironment ?? rowSourceCheckEnvironment(baseEnvironmentWire, declared) as Readonly<{wire: string}>;
  const byResource = new Map(installed.map(target => [target.resource, target]));
  const physicalTarget = (resource: string, fields: readonly string[]) => {
    const target = byResource.get(resource);
    if (!target || fields.some(field => !declared.views.find(view =>
      view.resource === resource)!.fields.includes(field))) fail('InstalledTableReadTargetMismatch');
    return Object.freeze({version: 'actql-installed-table-read-target/0.1',
      catalog_cid: declared.catalog_cid, selector: target.selector,
      // Bind exact namespace/name bytes even when a containing configuration
      // owner normalizes descriptive strings. This is not an operation key.
      selector_cid: dataCid(target.selector),
      resource, fields: Object.freeze([...fields])});
  };
  // These are installed configuration identities, not Table content, operation
  // identity or an inference about whether an uncertain commit succeeded.
  const bindingCid = dataCid({version: 'actql-installed-table-read-binding/0.1',
    connection: site.connection, connectorId, connectorRegistration,
    connectorRevision, catalogCid: declared.catalog_cid,
    targets: installed.map(({resource, selector}) => ({resource, selector}))});
  const readPages = async (options: ReadOptions, physical?: PhysicalRead) => {
    const {resource, columns, authorizationFor, chargePage, consumePageWire} = options;
    const signal = physical?.signal ?? options.signal;
    const target = byResource.get(resource);
    const view = declared.views.find(view => view.resource === resource);
    if (!target || columns.some(column => !view!.fields.includes(column))) fail('InstalledTableReadTargetMismatch');
    signal?.throwIfAborted();
    await Reflect.apply(authorizationFor, options, [0]);
    const frozen = closedReply(await bridge.resolveGeneration(target.selector, signal, physical?.beforeBodyAllocation, physical?.bodyReceived, physical?.bodySnapshot),
      ['receipt', 'mapping', 'schema_wire']) as FrozenGeneration;
    signal?.throwIfAborted();
    // The physical owner verified its immutable metadata and publication record.
    // Bind their exact logical material to the common-issued installed schema;
    // never default or reconstruct primitive contracts from this response.
    if (frozen.schema_wire !== target.schemaWire ||
        frozen.receipt?.catalog_identity_cid !== target.selector.catalog_identity_cid ||
        frozen.receipt?.table_uuid !== target.selector.table_uuid ||
        frozen.receipt?.schema_cid !== target.selector.schema_cid ||
        frozen.mapping?.schema_cid !== target.selector.schema_cid ||
        frozen.mapping?.mapping_cid !== frozen.receipt?.storage_mapping_cid ||
        !identifier(frozen.receipt?.generation_cid)) fail('InstalledTableReadGenerationMismatch');
    // Re-evaluation after the metadata await and after the data await uses the
    // existing acquisition gate. It does not renew original Effect authority.
    await Reflect.apply(authorizationFor, options, [1]);
    signal?.throwIfAborted();
    physical?.preparePayload();
    const rows = closedReply(await bridge.read(frozen.receipt, frozen.mapping, signal,
      physical?.beforeBodyAllocation, physical?.bodyReceived, physical?.bodySnapshot));
    if (!Array.isArray(rows) || rows.length !== frozen.receipt.row_count) fail('InvalidTableReadReply');
    await Reflect.apply(authorizationFor, options, [2]);
    signal?.throwIfAborted();
    // Keep original objects: omitted fields remain omitted. The existing common
    // checked-input owner validates and captures the rows, including empty input.
    physical?.prepareOutput();
    const pageWire = JSON.stringify(rows);
    const charge = physical === undefined ? Reflect.apply(chargePage, options, [Buffer.from(pageWire, 'utf8')]) : physical.finalCharge();
    Reflect.apply(consumePageWire, options, [pageWire, {charge}]);
  };
  let providerReader: ReaderFactory | undefined;
  if(sourceInitialization!==undefined){
    if(typeof bindReader!=='function')fail('InstalledTableSourceReaderUnavailable');
    providerReader=createInstalledTableSourceReader({moon,initialCapacity:readerCapacity,readPages,frameLimits:bridge.frameLimits});
    bindReader(providerReader);
  }
  // Table supplies the existing Table Site alongside the shared runtime and
  // responds through its own reader. Forward those originals as one input.
  return createInstalledRowSource({moon, declaration, declared, environment, sourceInitialization,
    environmentWire: environment.wire, connectorId, connectorRegistration,
    connectorRevision, site, authorization, readOperation: 'table.read',
    physicalTarget, ...(providerReader===undefined?{readPages}:{providerReader}), bindingCid, publicationBindingCid, limits,
    tableReadTargets: Object.freeze(installed.map(target => physicalTarget(target.resource,
      declared.views.find(view => view.resource === target.resource)!.fields)))} as unknown as
      Parameters<typeof createInstalledRowSource>[0]) as Promise<SourceAdapter>;
}
