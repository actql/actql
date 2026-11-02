// Table-specific physical projection of the existing installed row Source.
// The caller installs the same current authorization/Site as other Sources;
// this adapter issues no grant, runs no task scheduler and owns no capture.
import {createHash} from 'node:crypto';
import {checkpointApprovalFacts} from '../host-common/checkpoint-approval.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {createInstalledRowSource, rowSourceCheckEnvironment} from './installed-row-source.mjs';

const fail = code => { throw Object.assign(new Error(code), {code}); };
const text = value => typeof value === 'string' && value.length > 0;
const keys = (value, names) => value && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join(',') === [...names].sort().join(',');
const identifier = value => /^sha256:[0-9a-f]{64}$/u.test(value ?? '');
const dataCid = value => `sha256:${createHash('sha256')
  .update(canonicalJson(value, {dataKeys: true})).digest('hex')}`;
const closedReply = (value, resultKeys) => {
  if (value?.ok === false && keys(value, ['ok', 'code']) && text(value.code)) fail(value.code);
  if (!keys(value, ['ok', 'result']) || value.ok !== true ||
      resultKeys !== undefined && !keys(value.result, resultKeys)) fail('InvalidTableReadReply');
  return value.result;
};

// No external credential is needed for local Catalog I/O. This Site only
// admits decisions issued by the installed gate or the existing Checkpoint
// owner for this exact physical binding. It is not an approval/Run owner.
export function installedTableReadSite({connection, authorization, principalId, targets, ownAuthorization = false}) {
  let closed = false;
  const approvals = new WeakMap();
  const ensureOpen = () => { if (closed) fail('InstalledTableSiteClosed'); };
  return Object.freeze({connection,
    admitCheckpointReadApproval(decision) {
      ensureOpen();
      const facts = checkpointApprovalFacts(decision);
      const binding = facts?.physicalBinding;
      const target = targets().find(target => target.resource === decision?.tuple?.resource);
      if (!facts || !target || decision.action !== 'dispatch' || decision.basis !== 'resumed_approval' ||
          decision.boundary !== 'acquisition' || facts.principalId !== principalId ||
          facts.readTuple?.connection !== connection || facts.readTuple?.operation !== 'read' ||
          facts.readTuple?.resource !== target.resource || decision.tuple?.connection !== connection ||
          decision.tuple?.operation !== 'read' ||
          !keys(binding, ['version', 'catalog_cid', 'selector', 'selector_cid', 'resource', 'fields']) ||
          binding.version !== target.version || binding.catalog_cid !== target.catalog_cid ||
          binding.selector_cid !== target.selector_cid || canonicalJson(binding.selector, {dataKeys: true}) !== canonicalJson(target.selector, {dataKeys: true}) ||
          binding.resource !== target.resource || !Array.isArray(binding.fields) ||
          binding.fields.length === 0 ||
          new Set(binding.fields).size !== binding.fields.length ||
          binding.fields.some(field => !target.fields.includes(field))) fail('TableSourceReadApprovalNotAdmitted');
      approvals.set(decision, target.resource);
      return decision;
    },
    issueReadGrant({operation, decision, resource, runInvocationCid, dispatchRequestCid, maxUses}) {
      ensureOpen();
      if (operation !== 'table.read' || !identifier(runInvocationCid) || !identifier(dispatchRequestCid) ||
          !Number.isSafeInteger(maxUses) || maxUses < 1 ||
          !targets().some(target => target.resource === resource) ||
          decision?.action !== 'dispatch' || decision.boundary !== 'acquisition' ||
          decision.tuple?.connection !== connection || decision.tuple?.resource !== resource ||
          decision.tuple?.operation !== 'read' ||
          (approvals.get(decision) !== resource &&
            (!authorization.issued(decision) || decision.contextCid !== authorization.context.contextCid))) {
        fail('TableSourceReadGrantNotAuthorized');
      }
      return Object.freeze({runInvocationCid, dispatchRequestCid});
    },
    referenceCurrent() {return !closed;},
    close() {
      if (ownAuthorization && authorization.close() !== true) fail('InstalledSourceAuthorizationCleanupPending');
      closed = true;
    },
  });
}

// The normal Table reader uses the existing provider-reader contract. Its
// process, RowRun, Site and Request are originals; it owns no replacement
// reservation, grant, attempt, receipt or physical cleanup implementation.
function createInstalledTableSourceReader({moon, initialCapacity, readPages, frameLimits}) {
  const bodyCapacity = moon.clientProgramInstalledTableSourceBodyCapacity;
  const serializationCapacity = moon.clientProgramInstalledTableSourceSerializationCapacity;
  const chargeBody = moon.clientProgramRowSourceChargeResponseBody;
  if ([bodyCapacity,serializationCapacity,chargeBody].some(value=>typeof value !== 'function') ||
      initialCapacity === undefined || typeof readPages !== 'function' || !Object.isFrozen(frameLimits)) {
    fail('InstalledTableSourceReaderUnavailable');
  }
  let closing = false;
  const readers = new Set();
  const factory = Object.freeze({capacity:initialCapacity,
    prepare(options, retainPreparation, reserveResponseCapacity) {
      if (this !== factory || closing || retainPreparation !== undefined ||
          typeof reserveResponseCapacity !== 'function' || readers.size === Number.MAX_SAFE_INTEGER) {
        fail('InstalledTableSourceReaderUnavailable');
      }
      // The SAME caller supplied these methods after its RowRun/cleanup bind.
      let run = options.rowRun?.run, consume = options.consumeObservation;
      if (run === undefined || typeof consume !== 'function') fail('InstalledTableSourceResponseUnavailable');
      let stop = new AbortController();
      let signal = options.signal === undefined ? stop.signal : AbortSignal.any([options.signal,stop.signal]);
      let selected = options, capacity = initialCapacity, ticket, bodyBytes = 0;
      let phase = 'ready', pending = false, stopped = false, retired = false, cleanup;
      let handle;
      const check = () => {
        if (closing || retired || stopped || !pending) fail('InstalledTableSourceReaderClosed');
        signal.throwIfAborted();
      };
      const consumePrevious = () => {
        if (ticket !== undefined) {Reflect.apply(consume,selected,[ticket]);ticket=undefined;}
      };
      const grow = next => {
        check();reserveResponseCapacity(next,'announced-body');check();capacity=next;
      };
      const beforeBodyAllocation = length => {
        check();consumePrevious();
        grow(checked(Reflect.apply(bodyCapacity,moon,[capacity,length,frameLimits.maxDepth])));
      };
      const bodyReceived = body => {
        check();if(ticket!==undefined)fail('InstalledTableSourceResponsePending');
        ticket=checked(Reflect.apply(chargeBody,moon,[run,body]));bodyBytes=body.byteLength;
      };
      const preparePayload = () => {
        check();consumePrevious();
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
            const physical={signal,beforeBodyAllocation,bodyReceived,preparePayload,prepareOutput,
              finalCharge() {if(ticket===undefined)fail('InstalledTableSourceResponseUnavailable');const value=ticket;ticket=undefined;return value;}};
            const result=await readPages(selected,physical);
            phase='complete';return result;
          }catch(cause){cleanup=cause?.cleanupHandle;phase='failed';throw cause;}
          finally{pending=false;if(stopped)retire();}
        },
        requestStop(reason) {
          if(this!==handle)fail('ForeignInstalledTableSourceReader');
          if(retired)return;stopped=true;stop.abort(reason);retire();
        },
        async retry() {
          if(this!==handle||!stopped)fail('InstalledTableSourceReaderStopRequired');
          if(cleanup!==undefined)await cleanup.retry();retire();
        },
        observe() {
          if(this!==handle)fail('ForeignInstalledTableSourceReader');
          return Object.freeze({phase,readPending:pending,stopRequested:stopped,cleanupConfirmed:retire()});
        },
      });
      readers.add(handle);return handle;
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
  declaration: originalDeclaration, declared: originalDeclared, environment: originalEnvironment, publicationBindingCid}) {
  if (!moon || !text(baseEnvironmentWire) || !text(connectorId) ||
      !text(connectorRegistration) || !text(connectorRevision) ||
      !text(site?.connection) || typeof site?.issueReadGrant !== 'function' ||
      typeof authorization?.authorize !== 'function' ||
      !['checkReadSelector', 'resolveGeneration', 'read'].every(key => typeof bridge?.[key] === 'function') ||
      !Array.isArray(targets) || targets.length < 1 || targets.length > 64) {
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
    connectorId, connectorRegistration, connectorRevision, specification, undefined));
  const declared = originalDeclared ?? JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment = originalEnvironment ?? rowSourceCheckEnvironment(baseEnvironmentWire, declared);
  const byResource = new Map(installed.map(target => [target.resource, target]));
  const physicalTarget = (resource, fields) => {
    const target = byResource.get(resource);
    if (!target || fields.some(field => !declared.views.find(view =>
      view.resource === resource).fields.includes(field))) fail('InstalledTableReadTargetMismatch');
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
  const readPages = async (options, physical) => {
    const {resource, columns, authorizationFor, chargePage, consumePageWire} = options;
    const signal = physical?.signal ?? options.signal;
    const target = byResource.get(resource);
    const view = declared.views.find(view => view.resource === resource);
    if (!target || columns.some(column => !view.fields.includes(column))) fail('InstalledTableReadTargetMismatch');
    signal?.throwIfAborted();
    await Reflect.apply(authorizationFor, options, [0]);
    const frozen = closedReply(await bridge.resolveGeneration(target.selector, signal, physical?.beforeBodyAllocation, physical?.bodyReceived),
      ['receipt', 'mapping', 'schema_wire']);
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
      physical?.beforeBodyAllocation, physical?.bodyReceived));
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
  let providerReader;
  if(sourceInitialization!==undefined){
    if(typeof bindReader!=='function')fail('InstalledTableSourceReaderUnavailable');
    providerReader=createInstalledTableSourceReader({moon,initialCapacity:readerCapacity,readPages,frameLimits:bridge.frameLimits});
    bindReader(providerReader);
  }
  return createInstalledRowSource({moon, declaration, declared, environment, sourceInitialization,
    environmentWire: environment.wire, connectorId, connectorRegistration,
    connectorRevision, site, authorization, readOperation: 'table.read',
    physicalTarget, ...(providerReader===undefined?{readPages}:{providerReader}), bindingCid, publicationBindingCid, limits,
    tableReadTargets: Object.freeze(installed.map(target => physicalTarget(target.resource,
      declared.views.find(view => view.resource === target.resource).fields)))});
}
