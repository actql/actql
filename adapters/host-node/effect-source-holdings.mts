import {createHash} from 'node:crypto';
import type {issueCompletedEffectfulComputationEvidence} from '../host-common/completed-run-publication.mjs';
import type {openLocalPublicationStore} from '../store-local/publication-store.mjs';

type Awaitable<Value> = Value | PromiseLike<Value>;
type Capture = Parameters<typeof issueCompletedEffectfulComputationEvidence>[0];
type Holding = Capture['effectSourceHoldings'][number];
type Contract = Capture['runDefinition'];
type Limits = Capture['contractLimits'];
type Preview = Capture['preview'];
type Source = Holding['source'];
type Record = Holding['record'];
type Wire = Readonly<{identity: string; wire: string}>;
type Physical = Readonly<{cid: string; bytes: number}>;
type Prepared = Parameters<Capture['store']['commitPhysicalHolding']>[1][number];
type Store = Pick<Capture['store'], 'storeAuthorityCid' | 'commitPhysicalHolding'> & Readonly<{
  sharePhysicalHolding?(from: string, record: Record): Awaitable<unknown>;
}>;
type SetStore = Store & Pick<Capture['store'], 'retainEffectCaptureCustody'>;
type ReadStore = Pick<Awaited<ReturnType<typeof openLocalPublicationStore>>, 'consumePhysicalHolding'>;
type RecoveredStore = ReadStore & Pick<Capture['store'], 'storeAuthorityCid' | 'inspectPhysicalHolding'>;
type Payload = Readonly<{
  summary: Readonly<{artifact?: Contract; logicalCid: string; rowCount: number}>;
  schema?: Holding['schema'];
  localResultDefinition: Wire; localInvocation: Wire; localResultArtifact: Wire; localManifest: Wire;
  physical: Physical; prepared: Prepared;
}>;
type SourceSet = Readonly<{
  payloads: readonly Payload[];
  members: readonly Readonly<{memberIndex: number; payload: Payload}>[];
}>;
type PayloadOwner = Readonly<{
  store: unknown; checkedOwner: unknown; inputs: unknown; localInvocationToken: unknown;
  tableInput: boolean; contractLimits: Limits;
}>;
type SetOwner = Readonly<{store: unknown; control: unknown; runDefinition: Contract; contractLimits: Limits}>;
type CustodyPorts = Readonly<{
  preparedEffectSourceOwners: Pick<WeakMap<object, PayloadOwner>, 'get'>;
  preparedEffectSourceSets: Pick<WeakMap<object, SetOwner>, 'get'>;
  adoptedEffectSourceDependencies: Pick<WeakSet<object>, 'has'>;
}>;
type AdmitControl = Readonly<{
  admitCapturedEffectSourceArtifact(preview: Preview, member: number, invocation: Contract,
    artifact: Contract, authorityCid: string): Source;
  admitCapturedEffectSourceFromTableInput(preview: Preview, member: number, invocation: Contract,
    artifact: Contract, result: Wire, authorityCid: string, limits: Limits): Source;
  admitCapturedEffectSourceFromResult(preview: Preview, member: number, invocation: Contract,
    artifact: Contract, result: Wire, authorityCid: string, limits: Limits): Source;
  capturedEffectSourceHoldingCid(source: Source): string;
  localEffectSourceMatches(owner: unknown, inputs: unknown, member: number, manifest: Wire,
    localInvocation: unknown, result: Wire, source: Source): boolean;
  admitLocalEffectSourceEvidence(owner: unknown, inputs: unknown, member: number, manifest: Wire,
    localInvocation: unknown, result: Wire, source: Source, limits: Limits): Holding['localEvidence'];
}>;
type HoldingEntry = Readonly<{memberIndex: number; artifact: Contract; result?: Wire}>;
type SetControl = AdmitControl & Readonly<{
  capturedEffectSourceRecoveryInventoryValid(preview: Preview, sources: readonly HoldingEntry[]): boolean;
  capturedEffectSourceInventoryFromArtifactsValid(preview: Preview, sources: readonly HoldingEntry[], limits: Limits): boolean;
}>;
type HoldingOptions = Readonly<{
  payload: Payload; store: Store; control: AdmitControl; preview: Preview; invocation: Contract;
  memberIndex: number; resultArtifact?: Wire; shareFromHoldingCid?: string;
}>;
type HoldingsOptions = Readonly<{
  sources: SourceSet; store: SetStore; control: SetControl; preview: Preview;
  invocation: Contract; resultArtifacts?: readonly Wire[];
}>;
type LiveRead = Readonly<{
  holding: Readonly<{holdingCid: string}>; store: ReadStore;
  control: Readonly<{tableInputMatchesSource(tableInput: object, artifact: Wire, identity: object): boolean}>;
  tableInput: object; identity: object; maxBytes: number; signal?: AbortSignal;
}>;
type RecoveredRead<PreviewView extends object> = Readonly<{
  store: RecoveredStore; source: Source; artifact: Wire; tablePreview: PreviewView;
  control: Pick<Capture['control'], 'capturedEffectSourceArtifactCid' | 'capturedEffectSourceStoreAuthorityCid' |
    'capturedEffectSourceHoldingCid'> & Readonly<{recoveredTablePreviewMatchesSource(preview: PreviewView, source: Source): boolean}>;
  maxBytes: number; signal?: AbortSignal; assertAvailable(): void;
}>;
type ReadOptions = Readonly<{
  store: ReadStore; holdingCid: string; physicalCid: string; physicalBytes: number;
  logicalCid: string; rowCount: number; maxBytes: number; signal?: AbortSignal;
}>;
// The recovered typed view must retain this exact source token. Captured
// computation custody is confirmed by its existing owner before calling here.
export async function readRecoveredEffectTableInput<PreviewView extends object>({store, control, source,
  artifact, tablePreview, maxBytes, signal, assertAvailable}: RecoveredRead<PreviewView>) {
  if (control.recoveredTablePreviewMatchesSource(tablePreview, source) !== true ||
      control.capturedEffectSourceArtifactCid(source) !== artifact.identity ||
      control.capturedEffectSourceStoreAuthorityCid(source) !== store.storeAuthorityCid ||
      !Number.isSafeInteger(maxBytes) || maxBytes < 1 ||
      typeof assertAvailable !== 'function') {
    throw new TypeError('ForeignRecoveredTableSource');
  }
  const holdingCid = control.capturedEffectSourceHoldingCid(source);
  const holding = await store.inspectPhysicalHolding(holdingCid);
  if (holding?.namespace !== 'effect-source' || holding.manifest_cid !== artifact.identity ||
      holding.objects?.length !== 1 || holding.objects[0].byte_count > maxBytes) {
    throw new TypeError('UnavailableRecoveredTableSource');
  }
  assertAvailable();
  const body = JSON.parse(artifact.wire) as Readonly<{logical_result_cid: string; actual_row_count: number}>;
  return readRetainedTableRows({store, holdingCid,
    physicalCid: holding.objects[0].cid, physicalBytes: holding.objects[0].byte_count,
    logicalCid: body.logical_result_cid, rowCount: body.actual_row_count, maxBytes, signal});
}

// Live and recovered inputs share the same Store read and exact-byte checks;
// this helper is not another physical read or cleanup owner.
async function readRetainedTableRows({store, holdingCid, physicalCid, physicalBytes,
  logicalCid, rowCount, maxBytes, signal}: ReadOptions): Promise<readonly unknown[]> {
  signal?.throwIfAborted();
  const chunks: Buffer[] = [];
  let bytes = 0;
  const read = await store.consumePhysicalHolding(holdingCid, 0,
    chunk => {
      signal?.throwIfAborted();
      bytes += chunk.byteLength;
      if (bytes > maxBytes) throw new RangeError('TableSourceByteLimit');
      chunks.push(Buffer.from(chunk));
    });
  const body = Buffer.concat(chunks, bytes);
  // Store verifies the physical digest. Independently retain the logical
  // Relation binding without normalization or defaults for absent columns.
  const logical = createHash('sha256').update('{"sort":"relation","value":')
    .update(body).update('}').digest('hex');
  if (read.cid !== physicalCid || read.bytes !== physicalBytes ||
      `sha256:${logical}` !== logicalCid) {
    throw new TypeError('ForeignTableSourceBytes');
  }
  const rows: unknown = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(body));
  if (!Array.isArray(rows) || rows.length !== rowCount) {
    throw new TypeError('InvalidTableSourceRows');
  }
  return rows;
}

export function createPinnedEffectSourceHoldings({
  preparedEffectSourceOwners, preparedEffectSourceSets, adoptedEffectSourceDependencies,
}: CustodyPorts) {
  const pinnedEffectSourceHoldings = new WeakMap<object, Readonly<{payload: Payload; store: unknown; control: unknown}>>();

  // Admission creates no physical holding and performs no Store I/O.
  function admitPinnedEffectSourceHolding({
    payload, store, control, preview, memberIndex, invocation, resultArtifact,
  }: HoldingOptions) {
    const owner = preparedEffectSourceOwners.get(payload);
    if (owner?.store !== store ||
        typeof store?.commitPhysicalHolding !== 'function' ||
        typeof control?.admitCapturedEffectSourceArtifact !== 'function' ||
        typeof control?.capturedEffectSourceHoldingCid !== 'function' ||
        typeof control?.localEffectSourceMatches !== 'function' ||
        payload.summary.artifact === undefined) {
      throw new TypeError('InvalidEffectSourceHoldingOwner');
    }
    if (resultArtifact !== undefined && resultArtifact !== payload.localResultArtifact) {
      throw new TypeError('ForeignEffectSourceResultArtifact');
    }
    const source = resultArtifact === undefined ? control.admitCapturedEffectSourceArtifact(
      preview, memberIndex, invocation, payload.summary.artifact, store.storeAuthorityCid) :
      (owner.tableInput ? control.admitCapturedEffectSourceFromTableInput
        : control.admitCapturedEffectSourceFromResult)(preview, memberIndex, invocation,
        payload.summary.artifact, resultArtifact, store.storeAuthorityCid, owner.contractLimits);
    if (control.localEffectSourceMatches(
      owner.checkedOwner, owner.inputs, memberIndex, payload.localManifest,
      owner.localInvocationToken, payload.localResultArtifact, source) !== true) {
      throw new TypeError('ForeignLocalEffectSource');
    }
    const localEvidence = control.admitLocalEffectSourceEvidence(
      owner.checkedOwner, owner.inputs, memberIndex, payload.localManifest,
      owner.localInvocationToken, payload.localResultArtifact, source,
      owner.contractLimits);
    const holdingCid = control.capturedEffectSourceHoldingCid(source);
    const record: Record = Object.freeze({
      version: 'actql-local-physical-holding/0.1',
      namespace: 'effect-source', holding_cid: holdingCid,
      manifest_cid: payload.summary.artifact.identity,
      objects: Object.freeze([Object.freeze({
        cid: payload.physical.cid, byte_count: payload.physical.bytes,
      })]),
    });
    const holding = Object.freeze({source, memberIndex,
      artifact: payload.summary.artifact, schema: payload.schema,
      localResultDefinition: payload.localResultDefinition,
      localInvocation: payload.localInvocation,
      localResultArtifact: payload.localResultArtifact,
      localManifest: payload.localManifest,
      localEvidence,
      holdingCid, record});
    pinnedEffectSourceHoldings.set(holding, Object.freeze({payload, store, control}));
    return holding;
  }

  // Read only the exact source occurrence admitted and durably retained above.
  // The existing physical-holding read owner excludes retirement while bytes are
  // consumed; a prepared object path or a matching content CID is not custody.
  async function readPinnedEffectTableInput({holding, store, control,
    tableInput, identity, maxBytes, signal}: LiveRead) {
    const owner = pinnedEffectSourceHoldings.get(holding);
    if (owner?.store !== store || owner?.control !== control ||
        !Number.isSafeInteger(maxBytes) || maxBytes < 1 ||
        owner.payload.physical.bytes > maxBytes ||
        control.tableInputMatchesSource(tableInput,
          owner.payload.localResultArtifact, identity) !== true) {
      throw new TypeError('ForeignTableSourceHolding');
    }
    return readRetainedTableRows({store, holdingCid: holding.holdingCid,
      physicalCid: owner.payload.physical.cid, physicalBytes: owner.payload.physical.bytes,
      logicalCid: owner.payload.summary.logicalCid, rowCount: owner.payload.summary.rowCount,
      maxBytes, signal});
  }

  /**
   * Reconcile one exact physical holding without re-exporting the source. A
   * failed commit leaves the prepared owner with the caller for same-record
   * retry or explicit cleanup; it never authorizes another Compute attempt.
   */
  async function commitPinnedEffectSourceHolding(options: HoldingOptions) {
    const holding = admitPinnedEffectSourceHolding(options);
    const {store, payload, shareFromHoldingCid} = options;
    if (shareFromHoldingCid === undefined) {
      await store.commitPhysicalHolding(holding.record, [payload.prepared]);
    } else {
      if (typeof store.sharePhysicalHolding !== 'function' ||
          typeof shareFromHoldingCid !== 'string') {
        throw new TypeError('InvalidEffectSourceHoldingShare');
      }
      await store.sharePhysicalHolding(shareFromHoldingCid, holding.record);
    }
    return holding;
  }

  // Admit the entire inventory before the first durable write. Return exact
  // responsibility records synchronously so a failed or lost commit reply
  // cannot hide an already-created holding from the caller. There is no
  // cross-member transaction: Store reconciliation uses the same records.
  function preparePinnedEffectSourceHoldings({
    sources, store, control, preview, invocation, resultArtifacts,
  }: HoldingsOptions) {
    const owner = preparedEffectSourceSets.get(sources);
    if (owner?.store !== store || owner?.control !== control ||
        typeof store?.commitPhysicalHolding !== 'function' ||
        typeof store?.sharePhysicalHolding !== 'function' ||
        typeof control?.capturedEffectSourceRecoveryInventoryValid !==
          'function') {
      throw new TypeError('InvalidEffectSourceSetOwner');
    }
    const commit = store.commitPhysicalHolding.bind(store);
    const share = store.sharePhysicalHolding.bind(store);
    const memberPayloads = new Set(sources.members.map(member => member.payload));
    if (sources.payloads.some(payload => !memberPayloads.has(payload)) &&
        !adoptedEffectSourceDependencies.has(sources)) {
      // This entry point commits member holdings only. It must not claim a
      // durable capture while upstream payload custody is still merely prepared.
      throw new TypeError('IncompleteEffectDependencyHoldings');
    }
    const firstByPayload = new Map<Payload, string>();
    if (resultArtifacts !== undefined && (!Array.isArray(resultArtifacts) ||
        resultArtifacts.length !== sources.members.length)) {
      throw new TypeError('IncompleteEffectSourceResults');
    }
    const entries = sources.members.map(({memberIndex, payload}) => {
      const holding = admitPinnedEffectSourceHolding({payload, store, control,
        preview, memberIndex, invocation, resultArtifact: resultArtifacts?.[memberIndex]});
      const first = firstByPayload.get(payload);
      if (first === undefined) firstByPayload.set(payload, holding.holdingCid);
      return Object.freeze({holding, payload, first});
    });
    const holdings = Object.freeze(entries.map(entry => entry.holding));
    const inventory = holdings.map(({memberIndex, artifact}) => ({memberIndex, artifact,
      ...(resultArtifacts === undefined ? {} : {result: resultArtifacts[memberIndex]})}));
    const valid = resultArtifacts === undefined ?
      control.capturedEffectSourceRecoveryInventoryValid(preview, inventory) :
      control.capturedEffectSourceInventoryFromArtifactsValid(preview, inventory, owner.contractLimits);
    if (valid !== true) {
      throw new TypeError('IncompleteEffectSourceHoldings');
    }
    let flight: Promise<typeof holdings> | undefined;
    return Object.freeze({holdings,
      // Single-flight is physical I/O ownership, not an Effect retry decision.
      // A later call revalidates/re-syncs the Store's exact durable records.
      commit() {
        if (flight !== undefined) return flight;
        flight = (async () => {
          await store.retainEffectCaptureCustody(owner.runDefinition,
            holdings.map(holding => holding.record));
          for (const {holding, payload, first} of entries) {
            if (first === undefined) {
              await commit(holding.record, [payload.prepared]);
            } else {
              await share(first, holding.record);
            }
          }
          return holdings;
        })().finally(() => { flight = undefined; });
        return flight;
      },
    });
  }

  return {commitPinnedEffectSourceHolding, preparePinnedEffectSourceHoldings, readPinnedEffectTableInput};
}
