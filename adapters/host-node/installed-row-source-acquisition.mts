import {randomUUID} from 'node:crypto';
import {types as nodeTypes} from 'node:util';

import {AcquisitionOpenError, acquisitionFailure} from '../host-common/acquisition-outcome.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {bindClientSourceOperationRowRun} from './client-source-operation.mjs';
import {rowListingCallbacks} from './installed-row-listing.mjs';
import {rejectInstalledRowSource as fail} from './installed-row-source-mapping.mjs';

import type {startInstalledRowRun as startRowRun} from './installed-row-run.mjs';
import type {createInstalledRowSourceKeyedRead} from './installed-row-source-keyed-read.mjs';
import type {createInstalledRowSourcePreparation} from './installed-row-source-preparation.mjs';
import type {createInstalledRowSourceReadAuthority} from './installed-row-source-read-authority.mjs';

type RowRun = ReturnType<typeof startRowRun>;
type RowRunOptions = Parameters<typeof startRowRun>[0];
type MutableCapacity = {-readonly [Key in keyof NonNullable<RowRunOptions['capacity']>]: NonNullable<RowRunOptions['capacity']>[Key]};
type AcquisitionState = Parameters<RowRun['closeAfterFailure']>[0] & {started: boolean; closeFailed: boolean};
type TransportRecovery = NonNullable<Parameters<RowRun['closeAfterFailure']>[1]>;
type PreparePorts = Parameters<typeof createInstalledRowSourcePreparation>[0];
type Prepare = ReturnType<typeof createInstalledRowSourcePreparation>['prepare'];
type Prepared = Parameters<ReadAuthority['currentRead']>[0];
type Owner = NonNullable<ReturnType<PreparePorts['preparations']['get']>>;
type SourceAccess = PreparePorts['sourceAccess'];
type PrepareOptions = Parameters<Prepare>[0];
type ContractInputs = Pick<PrepareOptions, 'registry' | 'values' | 'fragment' | 'ordered'>;
type OpenOptions = Pick<PrepareOptions, 'preparedProgram' | 'preparedEffect' | 'sourceAccess' | 'occurrence'> & Readonly<{
  signal?: AbortSignal;
  retainedRelationOutput?: boolean;
  ledger?: unknown;
  originalOperationScope?: object;
}> & (
  Readonly<{preparedSource: Prepared}> & Partial<ContractInputs> |
  Readonly<{preparedSource?: undefined}> & ContractInputs
);
type ReadAuthority = ReturnType<typeof createInstalledRowSourceReadAuthority>;
type Site = Parameters<typeof createInstalledRowSourceKeyedRead>[0]['site'];
type Grant = ReturnType<Site['issueReadGrant']>;
type Authorization = Grant & {useId: string};
type ScopedGrant = Readonly<{grant: Grant; verifyCurrent(): ReturnType<ReadAuthority['currentRead']>}>;
type ReadChildOccurrence = {operation: string; uses: number; grant?: Grant};
type SequenceEntry = Readonly<{operation: string; resource?: string; maxUses: number}>;
type Sequence = Readonly<{operation: string; maxUses: number; children: readonly SequenceEntry[]}>;
type ReaderDemand = Readonly<{transferUnitBytes?: bigint; sequence?: Sequence;
  sequences?: Readonly<Record<string, Sequence | undefined>>}> & (
  Readonly<{nested: true; responses: number; queryPages: number; propertyPages: number; propertyOccurrences: number}> |
  Readonly<{nested?: false; responses: number}>
);
type PageLimits = Readonly<{maxNodes: number; maxDepth: number}>;
type ReadLimits = Readonly<{maxPageBytes: number; maxPageRows: number; maxCaptureRows: number; maxPages: number}>;
type Identity = Readonly<{runInvocationCid: string; dispatchRequestCid: string}>;
type PrepareRead = (input: Readonly<{
  prepared: Prepared;
  acquisition: unknown;
  wholeInput?: boolean;
  decision: Awaited<ReturnType<ReadAuthority['currentRead']>>;
  granted: Parameters<Site['issueReadGrant']>[0]['decision'];
  resource: string;
  nonce: string;
  runInvocationCid: string;
  dispatchRequestCid: string;
  signal?: AbortSignal;
}>) => unknown;
type RowFrame = Parameters<typeof bindClientSourceOperationRowRun>[4];
type PageCharge = Readonly<{charge?: unknown}>;
type ReadPagesInput = Readonly<{
  resource: string;
  columns: readonly string[];
  requestWire: string;
  preparedRead: unknown;
  operation: string;
  signal?: AbortSignal;
  verifyRead: () => ReturnType<ReadAuthority['currentRead']>;
  rowRun: RowFrame & Readonly<{inputKind?: 'whole-input'; originalRead?: unknown}>;
  withOriginalJob?: ReturnType<typeof bindClientSourceOperationRowRun>;
  listing?: ReturnType<typeof rowListingCallbacks>;
  originalAuthorization?: Grant;
  authorizationFor?(index: number): Promise<Authorization>;
  authorizeReadChild?(operation: string, index: number, occurrence: unknown,
    supplied?: unknown, signal?: AbortSignal): Promise<unknown>;
  chargePage(body: Uint8Array): unknown;
  consumeObservation?: (charge: unknown) => unknown;
  consumeProjectedPage(page: unknown, options?: PageCharge): unknown;
  consumeValues?(columns: unknown, rows: unknown, options?: PageCharge): unknown;
  consumePageWire(wire: unknown, options?: PageCharge): unknown;
  consumePage(rows: unknown, options?: PageCharge): unknown;
}>;
type RowRuntime = RowRunOptions['moon'] & Parameters<typeof bindClientSourceOperationRowRun>[1] &
  Parameters<typeof rowListingCallbacks>[0]['moon'] & Readonly<{
  clientProgramWholeSourceTarget(acquisition: unknown): readonly string[];
  clientProgramRowSourceColumns(acquisition: unknown): readonly string[];
  clientProgramRowSourceIsListing(acquisition: unknown): boolean;
  clientProgramWholeSourceIsListing(acquisition: unknown): boolean;
  clientProgramWholeSourceRequestWire(acquisition: unknown): unknown;
  clientProgramRowSourceRequestWire(acquisition: unknown): unknown;
  clientProgramRowSourceBegin(run: unknown, maxPageBytes: number, maxPageRows: number,
    maxCaptureRows: number, issuer: unknown): unknown;
  clientProgramRowSourceBeginWithPageLimits(run: unknown, maxPageBytes: number, maxNodes: number,
    maxDepth: number, maxPageRows: number, maxCaptureRows: number, issuer: unknown): unknown;
  clientProgramRowSourceListingComplete(run: unknown): boolean;
  clientProgramRowSourceChargePage(run: unknown, body: Uint8Array): unknown;
  clientProgramRowSourceConsumeObservationCharge(run: unknown, charge: unknown): unknown;
  clientProgramRowSourceAcceptChargedProjectedPage(run: unknown, charge: unknown, page: unknown): unknown;
  clientProgramRowSourceAcceptChargedValues(run: unknown, charge: unknown, columns: unknown, rows: unknown): unknown;
  clientProgramRowSourceAcceptPage(run: unknown, bytes: Uint8Array): unknown;
  clientProgramRowSourceAcceptChargedPage(run: unknown, charge: unknown, bytes: Uint8Array): unknown;
}>;

export function createInstalledRowSourceAcquisition({prepare, preparations, originalReader, captureCapacity, currentRead,
  site, moon, directReadIdentity, cidPattern, cid, prepareRead, maxTransferBytes, limits, readerDemand,
  listingReportCapacity, startInstalledRowRun, preparingSourceReads, closeSourceRead, operationBindings,
  grantBeforeBegin, pageLimits, managedPageLimits, referenceIssuer, text, readPages, sourceAccess}: {
  prepare: Prepare;
  preparations: Pick<PreparePorts['preparations'], 'get'>;
  originalReader?: Readonly<{capacity: unknown; prepare: unknown; receiver: unknown}>;
  captureCapacity(owner: Owner): unknown;
  currentRead: ReadAuthority['currentRead'];
  site: Site;
  moon: RowRuntime;
  directReadIdentity?: Readonly<{attempt(prepared: Prepared, nonce: string): Identity; useId(nonce: string, index: number): string}>;
  cidPattern: RegExp;
  cid(value: unknown): string;
  prepareRead?: PrepareRead;
  maxTransferBytes: bigint;
  limits: ReadLimits;
  readerDemand?: ReaderDemand;
  listingReportCapacity?: unknown;
  startInstalledRowRun: typeof startRowRun;
  preparingSourceReads: Pick<PreparePorts['preparingSourceReads'], 'delete'>;
  closeSourceRead?: (originalRead: unknown) => unknown;
  operationBindings: ReadonlyMap<string, string>;
  grantBeforeBegin: boolean;
  pageLimits?: PageLimits;
  managedPageLimits?: PageLimits;
  referenceIssuer: unknown;
  text(value: unknown): value is string;
  readPages?: (input: ReadPagesInput) => unknown;
  sourceAccess: SourceAccess;
}) {
  async function open(options: OpenOptions) {
    const state: AcquisitionState = {started: false, closeFailed: false, recovery: undefined};
    try {
      return await acquire(state, options);
    } catch (error) {
      if (state.closeFailed && error instanceof AcquisitionOpenError &&
          error.recovery === undefined) {
        throw new AcquisitionOpenError(error, 'unknown', state.recovery);
      }
      throw acquisitionFailure(error, state.closeFailed ? 'unknown'
        : !state.started ? 'not_started' : 'stopped', state.recovery);
    }
  }

  // A keyed consumer first borrows this original capture prefix. Its enclosing
  // task is not complete until the checked JOIN's other inputs are acquired.
  // This exposes no replacement Program, raw rows or fabricated task result.
  async function openCapture(options: OpenOptions) {
    const state: AcquisitionState = {started: false, closeFailed: false, recovery: undefined};
    try {
      return await acquire(state, options, true);
    } catch (error) {
      if (state.closeFailed && error instanceof AcquisitionOpenError &&
          error.recovery === undefined) {
        throw new AcquisitionOpenError(error, 'unknown', state.recovery);
      }
      throw acquisitionFailure(error, state.closeFailed ? 'unknown'
        : !state.started ? 'not_started' : 'stopped', state.recovery);
    }
  }

  async function acquire(state: AcquisitionState, {preparedProgram, preparedEffect, registry,
    values, fragment, ordered, sourceAccess: access = sourceAccess, signal,
    preparedSource, retainedRelationOutput = false,
    occurrence = {stage: 0, input: 0, task: 0}, ledger,
    originalOperationScope}: OpenOptions, captureOnly = false) {
    const prepared: Prepared = preparedSource ?? await prepare({preparedProgram,
      preparedEffect, registry, values, fragment, ordered,
      sourceAccess: access, occurrence} as PrepareOptions);
    const owner = preparations.get(prepared);
    if (owner === undefined || owner.retainedOnly === true ||
        owner.checkedOwner !== (preparedEffect ?? preparedProgram) ||
        owner.effectful !== (preparedEffect !== undefined) ||
        owner.access !== access ||
        owner.occurrence.stage !== occurrence.stage ||
        owner.occurrence.input !== occurrence.input ||
        owner.occurrence.task !== occurrence.task) {
      fail('InstalledSourcePreparationMismatch');
    }
    if (originalReader !== undefined) {
      if (ledger === undefined) fail('InstalledProviderSourceLedgerRequired');
      captureCapacity(owner);
    }
    const decision = await currentRead(prepared, access, signal);
    const granted = decision.basis === 'resumed_approval'
      ? site.admitCheckpointReadApproval!(decision) : decision;
    const acquisition = owner.acquisition;
    const columns = owner.wholeInput ? moon.clientProgramWholeSourceTarget(acquisition).slice(1)
      : [...moon.clientProgramRowSourceColumns(acquisition)];
    const nonce = randomUUID();
    const identity = directReadIdentity === undefined ? undefined
      : directReadIdentity.attempt(prepared, nonce);
    if (directReadIdentity !== undefined &&
        (identity === null || typeof identity !== 'object' ||
          Object.getPrototypeOf(identity) !== Object.prototype ||
          !Object.isFrozen(identity) ||
          Object.keys(identity).sort().join('\0') !==
            ['dispatchRequestCid', 'runInvocationCid'].join('\0') ||
          !cidPattern.test(identity.runInvocationCid) ||
          !cidPattern.test(identity.dispatchRequestCid))) {
      fail('InvalidInstalledSourceReadIdentity');
    }
    const runInvocationCid = identity?.runInvocationCid ??
      cid({version: 'actql-row-source-acquisition/0.1',
        ...(owner.wholeInput ? {sourceInput: prepared.checkedSource.sourceInput}
          : {requirementCid: prepared.checkedSource.requirementCid}), nonce});
    const dispatchRequestCid = identity?.dispatchRequestCid ?? cid({
      version: 'actql-row-source-acquisition-dispatch/0.1', runInvocationCid});
    let preparedRead;
    if (prepareRead !== undefined && originalReader === undefined) {
      // A provider's original bounded metadata observation precedes the row
      // attempt. Mark the physical start before awaiting that same operation;
      // a lost response is never reclassified as an unstarted acquisition.
      state.started = true;
      preparedRead = await prepareRead(Object.freeze({prepared, acquisition,
        decision, granted, resource: owner.resource, nonce, runInvocationCid,
        dispatchRequestCid, signal}));
    }
    const capacity: MutableCapacity = {transferBytes: maxTransferBytes,
      executionBytes: BigInt(limits.maxPageBytes),
      ...(readerDemand?.transferUnitBytes === undefined ? {} : {transferUnitBytes:readerDemand.transferUnitBytes})};
    if (originalReader !== undefined) capacity.provider = originalReader.capacity;
    if (!owner.wholeInput && listingReportCapacity !== undefined &&
        moon.clientProgramRowSourceIsListing(acquisition)) {
      // Extra report/control backing is admitted by Core before page I/O and
      // retained through original capture/evidence/cleanup, not settled by
      // this JS caller when capture returns. Ordinary rows have no new field.
      capacity.listingReport = listingReportCapacity;
    }
    const session = startInstalledRowRun({moon, acquisition, nonce, ledger, capacity,
      originalRead: owner.originalRead, wholeInput: owner.wholeInput});
    preparingSourceReads.delete(owner.originalRead);
    const {run} = session;
    let externalClosed = closeSourceRead === undefined || owner.managedRun === undefined;
    let externalCloseAttempted = false;
    let nativeReadPending = false;
    const closeOriginal = async () => {
      if (externalClosed) return;
      externalCloseAttempted = true;
      const observed = await closeSourceRead!(owner.originalRead);
      const pending = observed !== null && typeof observed === 'object'
        ? Object.getOwnPropertyDescriptor(observed, 'pending') : undefined;
      if (!pending || !Object.hasOwn(pending, 'value') || pending.value !== false) {
        fail('InstalledSourceCleanupPending');
      }
      externalClosed = true;
    };
    const complete = async () => {
      const verifyRead = () => currentRead(prepared, access, signal);
      // The completed Direct prefix owns its own logical input and Source
      // observation even when later keyed inputs are still unacquired. Reuse
      // the existing capture tuple issuer, never label it as JOIN completion.
      return await session.complete({owner, prepared, registry,
        values, fragment, ordered, retainedRelationOutput, signal,
        currentRead: verifyRead, captureOnly});
    };
    try {
      if (prepareRead !== undefined && originalReader !== undefined) {
        // A managed Reader's original facts are prepared only after its SAME
        // accounted Run starts. Its native protocol owns every physical child;
        // the original session catches and retires a failed preparation too.
        preparedRead = await prepareRead(Object.freeze({prepared, acquisition,
          wholeInput: owner.wholeInput,
          decision, granted, resource: owner.resource, nonce, runInvocationCid,
          dispatchRequestCid, signal}));
      }
      // Encode only after the existing RowRun's accounted reservation. The
      // common owner includes this wire while its completion records overlap.
      // The driver decodes its declared typed Request (including existing wire
      // markers for JSON scalars), not a replacement selector.
      const requestWire = checked(owner.wholeInput ? moon.clientProgramWholeSourceRequestWire(acquisition)
        : moon.clientProgramRowSourceRequestWire(acquisition)) as string;
      const operation = operationBindings.get(owner.resource)!;
      const issueGrant = () => site.issueReadGrant({operation,
        decision: granted, resource: owner.resource, runInvocationCid,
        dispatchRequestCid, maxUses: (readerDemand?.sequences?.[owner.resource] ?? readerDemand?.sequence)?.maxUses ?? limits.maxPages});
      // Preserve a selected driver's original grant/attempt order. The
      // ordinary JSON/listing path keeps its existing post-begin issuance.
      // A local original read has no credential to issue. A managed provider
      // read adds Resource custody only: it still needs the same Site grant
      // and current Account decision, never permission from its Run identity.
      const credentialRead = owner.originalRead === undefined ||
        owner.managedRun !== undefined && originalReader !== undefined;
      let grant = credentialRead && grantBeforeBegin ? issueGrant() : undefined;
      const readChildGrants = new Map<string, Grant | ScopedGrant>(), readChildUses = new Map<string, number>();
      const readChildOriginals = new WeakMap<object, true | ReadChildOccurrence>();
      let readChildIndex = 0, rootReadUses = 0, propertyOccurrences = 0;
      const beginPageLimits = owner.wholeInput ? managedPageLimits ?? pageLimits : pageLimits;
      checked(beginPageLimits === undefined
        ? moon.clientProgramRowSourceBegin(run, limits.maxPageBytes,
          limits.maxPageRows, limits.maxCaptureRows, referenceIssuer)
        : moon.clientProgramRowSourceBeginWithPageLimits(run, limits.maxPageBytes,
          beginPageLimits.maxNodes, beginPageLimits.maxDepth, limits.maxPageRows,
          limits.maxCaptureRows, referenceIssuer));
      const isListing = owner.wholeInput
        ? moon.clientProgramWholeSourceIsListing(acquisition)
        : moon.clientProgramRowSourceIsListing(acquisition);
      // paths=[] is already typed and complete. Do not issue a read grant or
      // enter a Site driver merely to manufacture an empty transport result.
      if (isListing && moon.clientProgramRowSourceListingComplete(run)) {
        await closeOriginal();
        return await complete();
      }
      if (credentialRead && !grantBeforeBegin) grant = issueGrant();
      state.started = true;
      const rowRun = Object.freeze({acquisition, run, requestId: nonce,
        runInvocationCid, dispatchRequestCid,
        ...(owner.wholeInput ? {inputKind: 'whole-input' as const} : {}),
        ...(owner.originalRead === undefined ? {} : {originalRead: owner.originalRead})});
      const withOriginalJob = originalOperationScope === undefined ? undefined
        : bindClientSourceOperationRowRun(originalOperationScope, moon,
          preparedProgram, prepared, rowRun);
      const readerOptions: ReadPagesInput = {resource: owner.resource, columns, requestWire, preparedRead,
        operation, signal,
        verifyRead: () => currentRead(prepared, access, signal),
        // Same-runtime opaque borrowing for trusted installed adapters only.
        // The original Host keeps finish/capture/close and physical capacity.
        rowRun,
        ...(withOriginalJob === undefined ? {} : {withOriginalJob}),
        ...(isListing ? {listing: rowListingCallbacks({moon, run, signal,
          currentRead: () => currentRead(prepared, access, signal)})} : {}),
        // The current read decision is taken again before every request.
        ...(credentialRead ? {originalAuthorization: grant, authorizationFor: async index => {
          if (index > 0) await currentRead(prepared, access, signal);
          const useId = directReadIdentity === undefined ? `${nonce}-read-${index}`
            : directReadIdentity.useId(nonce, index);
          if (!text(useId)) fail('InvalidInstalledSourceReadIdentity');
          return {...grant!, useId};
        }, authorizeReadChild: async (childOperation,index,occurrence,supplied,childSignal = signal) => {
          if (readerDemand?.sequence !== undefined || readerDemand?.sequences !== undefined) {
            const sequence = readerDemand.sequences?.[owner.resource] ?? readerDemand.sequence;
            if (sequence === undefined || operation !== sequence.operation || !Number.isSafeInteger(index) || index !== readChildIndex ||
                index >= readerDemand.responses || occurrence === null || typeof occurrence !== 'object' ||
                nodeTypes.isProxy(occurrence) || readChildOriginals.has(occurrence)) fail('InvalidInstalledSourceReadChild');
            let selected;
            if (childOperation === sequence.operation) {
              if (rootReadUses >= sequence.maxUses) fail('InstalledSourceQueryUseLimit');
              rootReadUses++;
            } else {
              selected = sequence.children.find(entry => entry.operation === childOperation);
              if (selected === undefined) fail('InvalidInstalledSourceReadChild');
              const used = readChildUses.get(childOperation) ?? 0;
              if (used >= selected.maxUses) fail('InstalledSourceReadChildUseLimit');
              readChildUses.set(childOperation,used+1);
            }
            readChildIndex++;
            // Spend the original occurrence before any reentrant current or
            // Site callback. Failure cannot restore a consumed request/use.
            readChildOriginals.set(occurrence,true);
            const decision = await currentRead(prepared,access,signal);
            if (supplied !== undefined) return supplied;
            if (selected?.resource !== undefined && selected.resource !== owner.resource) {
              // This child shares the original request/target, not the parent
              // Resource's permission. The already declared Resource gets its
              // own current Account decision and original Site-issued grant.
              let original = readChildGrants.get(childOperation) as ScopedGrant | undefined;
              if (original === undefined) {
                const verifyCurrent = async () => {
                  childSignal?.throwIfAborted();
                  const childDecision = await access.authorization.authorize('acquisition',
                    {connection: prepared.readTuple.connection, resource: selected!.resource!, operation: 'read'},
                    {subjectCid: cid({binding: prepared.physicalBinding, operation: childOperation}), signal: childSignal});
                  childSignal?.throwIfAborted();
                  if (childDecision?.action !== 'dispatch') {
                    throw Object.assign(new Error('ExecutionAuthorizationDenied'),
                      {code: 'ExecutionAuthorizationDenied', decision: childDecision});
                  }
                  return childDecision;
                };
                const childDecision = await verifyCurrent();
                const childGrant = site.issueReadGrant({operation: childOperation, decision: childDecision,
                  resource: selected.resource, runInvocationCid, dispatchRequestCid, maxUses: selected.maxUses});
                original = Object.freeze({grant: childGrant, verifyCurrent});
                readChildGrants.set(childOperation, original);
              } else await original.verifyCurrent();
              const useId = directReadIdentity === undefined ? `${nonce}-read-${index}`
                : directReadIdentity.useId(nonce,index);
              if (!text(useId)) fail('InvalidInstalledSourceReadIdentity');
              return Object.freeze({originalAuthorization: original.grant,
                authorization: Object.freeze({...original.grant, useId}), verifyCurrent: original.verifyCurrent});
            }
            const childGranted = owner.originalRead === undefined && decision.basis === 'resumed_approval'
              ? site.admitCheckpointReadApproval!(decision) : decision;
            let original = childOperation === operation ? grant : readChildGrants.get(childOperation) as Grant | undefined;
            if (original === undefined) {
              original = site.issueReadGrant({operation:childOperation,decision:childGranted,
                resource:owner.resource,runInvocationCid,dispatchRequestCid,maxUses:sequence.children.find(entry => entry.operation === childOperation)!.maxUses});
              readChildGrants.set(childOperation,original);
            }
            const useId = directReadIdentity === undefined ? `${nonce}-read-${index}`
              : directReadIdentity.useId(nonce,index);
            if (!text(useId)) fail('InvalidInstalledSourceReadIdentity');
            return Object.freeze({originalAuthorization:original,authorization:Object.freeze({...original,useId})});
          }
          if (readerDemand?.nested === true) {
            if (!text(childOperation) || !Number.isSafeInteger(index) || index !== readChildIndex ||
                index >= readerDemand.responses) fail('InvalidInstalledSourceReadChild');
            let entry;
            if (childOperation === operation) {
              if (rootReadUses >= readerDemand.queryPages) fail('InstalledSourceQueryUseLimit');
              rootReadUses++;
            } else {
              if (occurrence === null || typeof occurrence !== 'object' || nodeTypes.isProxy(occurrence)) {
                fail('InstalledSourceReadChildOriginalUnavailable');
              }
              entry = readChildOriginals.get(occurrence) as ReadChildOccurrence | undefined;
              if (entry === undefined) {
                if (propertyOccurrences >= readerDemand.propertyOccurrences) fail('InstalledSourcePropertyOccurrenceLimit');
                propertyOccurrences++;
                // A weak occurrence key never turns the completed native
                // query/property graph into a retained all-pages history.
                entry = {operation: childOperation, uses: 0, grant: undefined};
                readChildOriginals.set(occurrence, entry);
              }
              if (entry.operation !== childOperation || entry.uses >= readerDemand.propertyPages) {
                fail('InstalledSourcePropertyUseLimit');
              }
              entry.uses++;
            }
            readChildIndex++;
            const decision = await currentRead(prepared, access, signal);
            if (supplied !== undefined) return supplied;
            const childGranted = owner.originalRead === undefined && decision.basis === 'resumed_approval'
              ? site.admitCheckpointReadApproval!(decision) : decision;
            if (entry !== undefined && entry.grant === undefined) {
              entry.grant = site.issueReadGrant({operation: childOperation, decision: childGranted,
                resource: owner.resource, runInvocationCid, dispatchRequestCid, maxUses: readerDemand.propertyPages});
            }
            const selected = entry === undefined ? grant : entry.grant;
            const useId = directReadIdentity === undefined ? `${nonce}-read-${index}`
              : directReadIdentity.useId(nonce,index);
            if (!text(useId)) fail('InvalidInstalledSourceReadIdentity');
            return Object.freeze({originalAuthorization: selected,
              authorization: Object.freeze({...selected,useId})});
          }
          if (!text(childOperation) || !Number.isSafeInteger(index) || index !== readChildIndex || index >= limits.maxPages) {
            fail('InvalidInstalledSourceReadChild');
          }
          // Spend this original ordinal before an external current callback.
          // A failed or reentrant call cannot reuse it to issue another child.
          readChildIndex++;
          await currentRead(prepared, access, signal);
          if (supplied !== undefined) return supplied;
          let original = childOperation === operation ? grant : readChildGrants.get(childOperation) as Grant | undefined;
          if (original === undefined) {
            original = site.issueReadGrant({operation:childOperation,decision:granted,
              resource:owner.resource,runInvocationCid,dispatchRequestCid,maxUses:limits.maxPages});
            readChildGrants.set(childOperation,original);
          }
          const useId = directReadIdentity === undefined ? `${nonce}-read-${index}`
            : directReadIdentity.useId(nonce,index);
          if (!text(useId)) fail('InvalidInstalledSourceReadIdentity');
          return Object.freeze({originalAuthorization:original,
            authorization:Object.freeze({...original,useId})});
        }} : {}),
        chargePage: body => checked(moon.clientProgramRowSourceChargePage(
          run, body)),
        consumeObservation: ledger === undefined ? undefined : function consumeObservation(charge) {
          return checked(moon.clientProgramRowSourceConsumeObservationCharge(run, charge));
        },
        consumeProjectedPage: (page, {charge} = {}) => {
          // The same compiled RowRun checks opaque page provenance and the
          // original response ticket before full schema/retention admission.
          // Foreign pages never fall back to serialization or another parse.
          if (charge === undefined) fail('InvalidInstalledSourcePageCharge');
          return checked(moon.clientProgramRowSourceAcceptChargedProjectedPage(run, charge, page));
        },
        ...(originalReader === undefined ? {} : {consumeValues: (columns, rows, {charge} = {}) => {
          if (charge === undefined) fail('InvalidInstalledSourcePageCharge');
          return checked(moon.clientProgramRowSourceAcceptChargedValues(run, charge, columns, rows));
        }}),
        consumePageWire: (wire, {charge} = {}) => {
          if (typeof wire !== 'string') fail('InvalidInstalledSourcePageWire');
          const bytes = Buffer.from(wire, 'utf8');
          return checked(charge === undefined
            ? moon.clientProgramRowSourceAcceptPage(run, bytes)
            : moon.clientProgramRowSourceAcceptChargedPage(run, charge, bytes));
        },
        consumePage: (rows, {charge} = {}) => {
          const bytes = Buffer.from(JSON.stringify(rows), 'utf8');
          return checked(charge === undefined
            ? moon.clientProgramRowSourceAcceptPage(run, bytes)
            : moon.clientProgramRowSourceAcceptChargedPage(run, charge, bytes));
        }};
      if (originalReader === undefined) {
        nativeReadPending = true;
        await readPages!(readerOptions);
        nativeReadPending = false;
      }
      else await session.readProvider({prepare: originalReader.prepare,
        receiver: originalReader.receiver, options: Object.freeze(readerOptions)});
      await closeOriginal();
      return await complete();
    } catch (error) {
      if (nativeReadPending && !externalClosed && closeSourceRead !== undefined && owner.managedRun !== undefined &&
          error instanceof AcquisitionOpenError && error.outcome === 'unknown') {
        // The native adapter already attempted cleanup. Preserve its original
        // recovery instead of immediately asking another helper to close it.
        // An absent owner cannot be replaced by a different close's success.
        const original = (error.recovery as TransportRecovery | undefined) ?? Object.freeze({
          async cleanup() {return false;}, cleanupPending: () => true,
        });
        session.closeAfterFailure(state, original);
        throw new AcquisitionOpenError(error, 'unknown', state.recovery);
      }
      if (!externalClosed && !externalCloseAttempted) {
        try {await closeOriginal();} catch { /* Same cleanup remains pending. */ }
      }
      if (!externalClosed) {
        // The original external child still owns its backing. Do not close
        // the Core RowRun or release that capacity ahead of its actual ACK.
        const recovery = Object.freeze({close() {}, async cleanup() {
          try {await closeOriginal();} catch {return false;}
          return true;
        }, cleanupPending: () => !externalClosed});
        session.closeAfterFailure(state, recovery);
        throw new AcquisitionOpenError(error, 'unknown', state.recovery);
      }
      session.closeAfterFailure(state);
      throw error;
    }
  }

  return {open, openCapture};
}
