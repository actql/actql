import {createHash} from 'node:crypto';
import {installedEffectDependencyOriginal} from '../host-common/installed-effect-dependency-original.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {checkedEffectPreparation} from '../host-common/effect-preparation-result.mjs';
import {advanceEffectCommandKey, type EffectCommandKeyCleanupFailure} from './effect-command-key.mjs';
import {exportPinnedResult} from './effect-source-stream.mjs';

import type {retainCompletedEffectDependencyPayloads} from '../host-common/completed-run-publication.mjs';
import type {openLocalPublicationStore} from '../store-local/publication-store.mjs';

type Awaitable<Value> = Value | PromiseLike<Value>;
type Retention = Parameters<typeof retainCompletedEffectDependencyPayloads>[0];
type LocalArtifact = Retention['dependencies'][number]['artifact'];
type Contract = Retention['runDefinition'];
type Limits = Parameters<Retention['control']['admit']>[2];
type Body = Readonly<{kind: string; wire: string; cid?: string}>;
type Wire = Readonly<{identity: string; wire: string}>;
type Stream = Parameters<typeof exportPinnedResult<Contract | undefined>>[0];
type ProposalBounds = Readonly<Pick<Limits, 'maxNodes' | 'maxDepth'> &
  {maxFields: number; maxWork: number; maxBytes: number; maxUtf16Units: number}>;
type Store = Pick<Awaited<ReturnType<typeof openLocalPublicationStore>>, 'createPreparedObjectWriter' | 'storeAuthorityCid'>;
type Writer = ReturnType<Store['createPreparedObjectWriter']>;
type Sealed = Awaited<ReturnType<Writer['seal']>>;
type CleanupHandle = Readonly<{status(): Readonly<{pending: boolean}>; retry(): Awaitable<unknown>}>;
type Custody = Readonly<{
  store: Store; checkedOwner: unknown; inputs: unknown; memberIndex: number | undefined;
  localInvocationToken: unknown; unitIndex: number | undefined; tableInput: boolean; contractLimits: Limits;
}>;
type Context = Readonly<{
  admission: unknown; runDefinition: Contract; runInvocation: Contract; observation: unknown;
}>;
type Evidence = Context & Readonly<{
  retentionDependencies?: readonly Body[]; resultDataPolicy?: Body;
  acquisitionDependencies?: readonly Body[]; acquiredCatalogBodies?: readonly Body[];
  acquiredEvidence?: Readonly<{catalogBodies?: readonly Body[]}>;
}>;
type DependentLocal = Readonly<{
  resultIndex?: number; tableInput?: boolean; sourceFree?: false;
  dependencyConstruction?: Retention['dependencyConstruction']; dependencyText: {remaining: number};
  dependency: Readonly<{bodies: readonly Body[]; catalogBodies?: readonly Body[]}>;
  staticBodies: readonly Body[]; originalArtifact?: LocalArtifact;
}>;
type Local = DependentLocal | Readonly<{
  resultIndex: number; sourceFree: true; tableInput?: false; originalArtifact?: undefined;
}>;
type ManifestSet = Map<number | undefined, {invocation: unknown; artifacts: LocalArtifact[]; manifest?: Wire}>;
type Runtime = Stream['moon'] & Readonly<{
  clientProgramEffectInputsShareView(inputs: unknown, left: number, right: number): boolean;
  clientProgramEffectLocalResultMatchesMember(inputs: unknown, result: number, member: number): boolean;
  clientProgramEffectLocalResultStage(result: unknown): number;
  clientProgramEffectLocalResultName(result: unknown): string;
  clientProgramEffectTableInputStage(input: unknown): number;
  clientProgramEffectInputStage(input: unknown): number;
  clientProgramIssueCapturedEffectTableInputLocalDefinition(owner: unknown, inputs: unknown, member: number,
    bytes: number, nodes: number, depth: number): unknown;
  clientProgramIssueCapturedEffectInputLocalResultDefinition(owner: unknown, inputs: unknown, member: number,
    bytes: number, nodes: number, depth: number): unknown;
  clientProgramIssueLocalEffectResultDefinition(owner: unknown, stage: number, name: string,
    bytes: number, nodes: number, depth: number): unknown;
  clientProgramLocalEffectTableDefinitionCid(definition: unknown): string;
  clientProgramLocalEffectTableDefinitionJson(definition: unknown): string;
  clientProgramLocalEffectResultDefinitionCid(definition: unknown): string;
  clientProgramLocalEffectResultDefinitionJson(definition: unknown): string;
  clientProgramIssueCapturedEffectInputLocalInvocation(owner: unknown, inputs: unknown, member: number,
    bytes: number, nodes: number, depth: number): unknown;
  clientProgramLocalEffectInvocationCid(invocation: unknown): string;
  clientProgramLocalEffectInvocationJson(invocation: unknown): string;
  clientProgramEffectProposalBegin(inputs: unknown, member: number, fields: number, work: number): unknown;
  clientProgramEffectProposalBeginWithTarget(inputs: unknown, member: number, fields: number,
    work: number, target: unknown): unknown;
  clientProgramEffectProposalBeginWithKey(inputs: unknown, member: number, fields: number, work: number, key: unknown): unknown;
  clientProgramEffectProposalBeginWithTargetAndKey(inputs: unknown, member: number, fields: number,
    work: number, target: unknown, key: unknown): unknown;
  clientProgramEffectProposalRow(plan: unknown, row: unknown, index: number, fields: number, work: number,
    bytes: number, nodes: number, depth: number): unknown;
  clientProgramEffectProposalFinish(plan: unknown, rows: number): unknown;
  clientProgramEffectProposalCancel(plan: unknown): void;
  clientProgramStartEffectCommandKeyWorkspace(workspace: unknown): unknown;
  clientProgramEffectCommandKeyWorkspaceSynchronousEnd(workspace: unknown): void;
  clientProgramEffectCommandKeyAdvance?(key: unknown, quantum: number): unknown;
  clientProgramEffectInputExportSchemaWire(receipt: unknown): string;
  clientProgramInstalledEffectDependencyTextRetain(parent: unknown, prepared: unknown, request: unknown,
    plan: unknown, text: string): unknown;
}>;
type IssueSourceArtifact = (input: unknown, receipt: unknown, invocation: Contract, retention: Contract,
  bindingCid: string, authorityCid: string, limits: Limits) => Contract;
type IssueLocalArtifact = (owner: unknown, inputs: unknown, member: number, importing: unknown, definition: unknown,
  invocation: unknown, receipt: unknown, retention: Contract, context: Context, limits: Limits) => LocalArtifact;
type Control = Readonly<{
  originalEffectUnitArtifactDefinition(artifact: LocalArtifact): unknown;
  reuseOriginalEffectUnitArtifact(owner: unknown, inputs: unknown, artifact: LocalArtifact, importing: unknown,
    receipt: unknown): LocalArtifact;
  issueEffectSourceArtifactFromExport: IssueSourceArtifact;
  issueEffectTableSourceArtifactFromExport: IssueSourceArtifact;
  issueSourceFreeLocalEffectResultArtifact: IssueLocalArtifact;
  issueSourceFreeLocalEffectTableArtifact: IssueLocalArtifact;
  issueSourceFreeExportedLocalEffectResultArtifact(owner: unknown, inputs: unknown, importing: unknown,
    definition: unknown, invocation: unknown, receipt: unknown, retention: Contract, context: Context, limits: Limits): LocalArtifact;
  issueDependentLocalEffectResultArtifact(owner: unknown, inputs: unknown, importing: unknown, dependency: DependentLocal['dependency'],
    definition: unknown, receipt: unknown, retention: Contract, context: Context, limits: Limits): LocalArtifact;
  issueDependentLocalEffectTableArtifact(owner: unknown, inputs: unknown, member: number, importing: unknown,
    dependency: DependentLocal['dependency'], definition: unknown, receipt: unknown, retention: Contract,
    context: Context, limits: Limits): LocalArtifact;
  issueLocalEffectResultManifest(owner: unknown, invocation: unknown, artifacts: readonly LocalArtifact[], limits: Limits): Wire;
}>;
type PayloadOptions = Pick<Stream, 'execution' | 'inputs' | 'limits' | 'memberIndex' | 'signal' | 'commandWorkspace'> &
  Readonly<{
    moon: Runtime; store: Store; control: Control; checkedOwner: unknown; maxBytes: number; sourceBindingCid: string;
    invocation: Contract; retention: Contract; contractLimits: Limits; localEvidenceContext: Evidence;
    proposalMemberIndexes?: readonly number[]; proposalLimits?: ProposalBounds; publishedTarget?: unknown;
    onProposalRow?(member: number, index: number, projection: Readonly<{selectorWire: string; changesWire: string}>): Awaitable<unknown>;
    onOriginalArtifact?(artifact: LocalArtifact, member: number): unknown;
    onCommandKey?(member: number, key: unknown): unknown;
  }>;

export function createPinnedEffectSourcePayloads(preparedEffectSourceOwners: Pick<WeakMap<object, Custody>, 'set'>) {
  /**
   * Prepare bounded bytes from the exact checked input. The returned Store
   * owner must be committed to an independent holding or explicitly released.
   * Neither sealing bytes nor this summary claims a completed Captured Run.
   */
  async function preparePinnedEffectSourcePayload(options: PayloadOptions) {
    return preparePinnedEffectSourcePayloadOwned(options);
  }

  async function preparePinnedEffectSourcePayloadOwned({
    moon, checkedOwner, execution, inputs, memberIndex, limits, store, maxBytes,
    control, invocation, retention, sourceBindingCid, contractLimits, signal,
    localEvidenceContext,
    onProposalRow, proposalMemberIndexes, proposalLimits, onOriginalArtifact,
    commandWorkspace, onCommandKey, publishedTarget,
  }: PayloadOptions, manifestSet?: ManifestSet, local?: Local) {
    if (typeof store?.createPreparedObjectWriter !== 'function' ||
        typeof store.storeAuthorityCid !== 'string' ||
        typeof moon?.clientProgramIssueCapturedEffectInputLocalResultDefinition !==
          'function' ||
        typeof moon?.clientProgramIssueCapturedEffectInputLocalInvocation !==
          'function' ||
        checkedOwner === undefined ||
        !['maxWireBytes', 'maxNodes', 'maxDepth'].every(key =>
          Number.isSafeInteger(contractLimits?.[key as keyof Limits]) &&
          contractLimits[key as keyof Limits] > 0) ||
        typeof control?.issueEffectSourceArtifactFromExport !== 'function' ||
        typeof control?.issueSourceFreeLocalEffectResultArtifact !== 'function' ||
        typeof control?.issueLocalEffectResultManifest !== 'function' ||
        typeof sourceBindingCid !== 'string' ||
        !['admission', 'runDefinition', 'runInvocation', 'observation'].every(
          key => localEvidenceContext?.[key as keyof Context] !== undefined) ||
        (proposalMemberIndexes !== undefined &&
          (onProposalRow === undefined ||
            !Array.isArray(proposalMemberIndexes) ||
            proposalMemberIndexes.length === 0 ||
            new Set(proposalMemberIndexes).size !==
              proposalMemberIndexes.length ||
            proposalMemberIndexes.some(index =>
              !Number.isSafeInteger(index) || index < 0))) ||
        (onProposalRow !== undefined &&
          (typeof onProposalRow !== 'function' ||
            !['maxFields', 'maxWork', 'maxBytes', 'maxNodes', 'maxDepth',
              'maxUtf16Units'].every(key =>
              Number.isSafeInteger(proposalLimits?.[key as keyof ProposalBounds]) &&
              proposalLimits![key as keyof ProposalBounds] >= 0) ||
            proposalLimits!.maxBytes === 0 ||
            proposalLimits!.maxNodes === 0 ||
            proposalLimits!.maxDepth === 0)) ||
        (onOriginalArtifact !== undefined && typeof onOriginalArtifact !== 'function') ||
        (onCommandKey !== undefined && typeof onCommandKey !== 'function') ||
        !Number.isSafeInteger(maxBytes) || maxBytes < 0) {
      throw new TypeError('InvalidEffectSourceStore');
    }
    const proposalBounds = onProposalRow === undefined ? undefined :
      Object.freeze({maxFields: proposalLimits!.maxFields,
        maxWork: proposalLimits!.maxWork, maxBytes: proposalLimits!.maxBytes,
        maxNodes: proposalLimits!.maxNodes, maxDepth: proposalLimits!.maxDepth,
        maxUtf16Units: proposalLimits!.maxUtf16Units});
    const proposalMembers = onProposalRow === undefined ? undefined :
      Object.freeze([...(proposalMemberIndexes ?? [memberIndex!])]);
    if (proposalMembers?.some(index =>
      moon.clientProgramEffectInputsShareView(inputs, memberIndex!, index) !==
        true)) {
      throw new TypeError('ForeignEffectProposalSource');
    }
    if (commandWorkspace !== undefined &&
        (proposalMembers?.length !== 1 || proposalMembers[0] !== memberIndex ||
          local?.tableInput === true ||
          (local !== undefined && moon.clientProgramEffectLocalResultMatchesMember(
            inputs, local.resultIndex!, memberIndex!) !== true))) {
      throw new TypeError('ForeignEffectCommandWorkspaceRoute');
    }
    if (publishedTarget !== undefined &&
        (proposalMembers?.length !== 1 || proposalMembers[0] !== memberIndex ||
          local?.tableInput === true)) {
      throw new TypeError('ForeignEffectPublishedTargetRoute');
    }
    signal?.throwIfAborted();
    const selectedResult = local === undefined || local.tableInput ? undefined :
      moon.clientProgramEffectLocalResultAt(inputs, local.resultIndex!);
    const tableInput = local === undefined || local.tableInput
      ? moon.clientProgramEffectTableInputAt?.(inputs, memberIndex!) : undefined;
    const table = tableInput !== undefined;
    if (table && (onProposalRow !== undefined ||
        typeof control.issueSourceFreeLocalEffectTableArtifact !== 'function' ||
        typeof control.issueEffectTableSourceArtifactFromExport !== 'function')) {
      throw new TypeError('InvalidPrivateTableSourceExport');
    }
    const localDefinition = local?.originalArtifact !== undefined
      ? control.originalEffectUnitArtifactDefinition(local.originalArtifact)
      : checked(local === undefined || table
      ? table ? moon.clientProgramIssueCapturedEffectTableInputLocalDefinition(
        checkedOwner, inputs, memberIndex!,
        contractLimits.maxWireBytes, contractLimits.maxNodes, contractLimits.maxDepth)
      : moon.clientProgramIssueCapturedEffectInputLocalResultDefinition(
        checkedOwner, inputs, memberIndex!,
        contractLimits.maxWireBytes, contractLimits.maxNodes,
        contractLimits.maxDepth)
      : moon.clientProgramIssueLocalEffectResultDefinition(checkedOwner,
        moon.clientProgramEffectLocalResultStage(selectedResult),
        moon.clientProgramEffectLocalResultName(selectedResult),
        contractLimits.maxWireBytes, contractLimits.maxNodes,
        contractLimits.maxDepth));
    const localResultDefinition = Object.freeze({
      identity: table ? moon.clientProgramLocalEffectTableDefinitionCid(localDefinition)
        : moon.clientProgramLocalEffectResultDefinitionCid(localDefinition),
      wire: table ? moon.clientProgramLocalEffectTableDefinitionJson(localDefinition)
        : moon.clientProgramLocalEffectResultDefinitionJson(localDefinition),
    });
    const unitIndex = local !== undefined && !table
      ? moon.clientProgramEffectLocalResultStage(selectedResult)
      : manifestSet === undefined ? undefined :
      table ? moon.clientProgramEffectTableInputStage(tableInput)
        : moon.clientProgramEffectInputStage(
          moon.clientProgramEffectInputAt(inputs, memberIndex!));
    const localInvocationToken = manifestSet?.get(unitIndex)?.invocation ?? checked(
      moon.clientProgramIssueCapturedEffectInputLocalInvocation(
        checkedOwner, inputs, memberIndex!,
        contractLimits.maxWireBytes, contractLimits.maxNodes,
        contractLimits.maxDepth));
    if (manifestSet !== undefined && !manifestSet.has(unitIndex)) {
      manifestSet.set(unitIndex, {invocation: localInvocationToken, artifacts: []});
    }
    const localInvocation = Object.freeze({
      identity: moon.clientProgramLocalEffectInvocationCid(
        localInvocationToken),
      wire: moon.clientProgramLocalEffectInvocationJson(
        localInvocationToken),
    });
    const localContext = Object.freeze({
      admission: localEvidenceContext.admission,
      runDefinition: localEvidenceContext.runDefinition,
      runInvocation: localEvidenceContext.runInvocation,
      observation: localEvidenceContext.observation,
    });
    const proposalPlans: unknown[] = [];
    try {
      for (const index of commandWorkspace === undefined ? proposalMembers ?? [] : []) {
        proposalPlans.push(checked(publishedTarget === undefined
          ? moon.clientProgramEffectProposalBegin(
            inputs, index, proposalBounds!.maxFields, proposalBounds!.maxWork)
          : moon.clientProgramEffectProposalBeginWithTarget(
            inputs, index, proposalBounds!.maxFields, proposalBounds!.maxWork, publishedTarget)));
      }
    } catch (error) {
      for (const plan of proposalPlans) {
        moon.clientProgramEffectProposalCancel(plan);
      }
      throw error;
    }
    let writer: Writer;
    try {
      writer = store.createPreparedObjectWriter(maxBytes);
    } catch (error) {
      for (const plan of proposalPlans) {
        moon.clientProgramEffectProposalCancel(plan);
      }
      throw error;
    }
    let sealed: Sealed | undefined;
    let localResultArtifact: LocalArtifact | undefined;
    let byteCount = 0;
    const digest = createHash('sha256');
    const dependent = local !== undefined && local.sourceFree !== true;
    const relationChunks = dependent ? [] as string[] : undefined;
    let schemaBody: Body | undefined;
    let sourceSchema: Readonly<{cid: string; wire: string}> | undefined;
    const retainText = (text: string) => {
      if ((local as DependentLocal).dependencyConstruction !== undefined) {
        const original=installedEffectDependencyOriginal((local as DependentLocal).dependencyConstruction,moon);
        checked(moon.clientProgramInstalledEffectDependencyTextRetain(original.parent,
          original.prepared,original.request,original.plan,text));
        original.current();
      } else {
        const bytes = Buffer.byteLength(text, 'utf8');
        if (bytes > (local as DependentLocal).dependencyText.remaining) throw new RangeError('EffectDependencyBodyByteLimit');
        (local as DependentLocal).dependencyText.remaining -= bytes;
      }
      return text;
    };
    try {
      if (dependent) retainText('{"sort":"relation","value":}');
      const summary = await exportPinnedResult<Contract | undefined>({
        moon, execution, inputs, memberIndex, limits, signal,
        commandWorkspace,
        ...(commandWorkspace === undefined ? {} : {
          async prepareProposal() {
            let key;
            try {
              key = checked(moon.clientProgramStartEffectCommandKeyWorkspace(commandWorkspace));
            } finally {
              moon.clientProgramEffectCommandKeyWorkspaceSynchronousEnd(commandWorkspace);
            }
            await advanceEffectCommandKey(moon, key, signal, 256);
            if (onCommandKey !== undefined && onCommandKey(memberIndex!, key) !== undefined) {
              throw new TypeError('InvalidEffectCommandKeyProjection');
            }
            proposalPlans.push(checked(publishedTarget === undefined
              ? moon.clientProgramEffectProposalBeginWithKey(
                inputs, memberIndex!, proposalBounds!.maxFields, proposalBounds!.maxWork, key)
              : moon.clientProgramEffectProposalBeginWithTargetAndKey(
                inputs, memberIndex!, proposalBounds!.maxFields, proposalBounds!.maxWork, publishedTarget, key)));
          },
        }),
        localResultIndex: table ? undefined : local?.resultIndex,
        ...(onProposalRow === undefined ? {} : {
          canonicalRowLimits: {maxNodes: proposalBounds!.maxNodes,
            maxDepth: proposalBounds!.maxDepth,
            maxUtf16Units: proposalBounds!.maxUtf16Units},
          onCanonicalRow: async (index, row) => {
            for (const [planIndex, proposalMemberIndex] of
              proposalMembers!.entries()) {
              // This pure common projection examines an already captured row.
              // Its refusal is not an uncertain provider dispatch or Store I/O.
              const projected = checkedEffectPreparation(moon.clientProgramEffectProposalRow(
                proposalPlans[planIndex], row, index,
                proposalBounds!.maxFields, proposalBounds!.maxWork,
                proposalBounds!.maxBytes, proposalBounds!.maxNodes,
                proposalBounds!.maxDepth));
              await onProposalRow(proposalMemberIndex, index,
                Object.freeze({selectorWire: runtimeField(projected, 0) as string,
                  changesWire: runtimeField(projected, 1) as string}));
            }
          },
        }),
        onReceipt: (input, receipt, importing) => {
          // Retain the original exported schema even when this private Effect
          // input is not a dependent or publicly named Result.
          sourceSchema = Object.freeze({
            cid: moon.clientProgramEffectInputExportSchemaCid(receipt),
            wire: moon.clientProgramEffectInputExportSchemaWire(receipt),
          });
          if (dependent) {
            schemaBody = Object.freeze({kind: 'relation_schema',
              cid: sourceSchema.cid, wire: retainText(sourceSchema.wire),
            });
          }
          localResultArtifact = local?.originalArtifact !== undefined
            ? control.reuseOriginalEffectUnitArtifact(checkedOwner, inputs, local.originalArtifact, importing, receipt)
            : table && dependent
            ? control.issueDependentLocalEffectTableArtifact(checkedOwner,
              inputs, memberIndex!, importing, local!.dependency, localDefinition,
              receipt, retention, localContext, contractLimits)
            : local === undefined
            ? table ? control.issueSourceFreeLocalEffectTableArtifact(
              checkedOwner, inputs, memberIndex!, importing, localDefinition,
              localInvocationToken, receipt, retention, localContext, contractLimits)
            : control.issueSourceFreeLocalEffectResultArtifact(
            checkedOwner, inputs, memberIndex!, importing, localDefinition,
            localInvocationToken, receipt, retention, localContext,
            contractLimits)
            : local.sourceFree ? control.issueSourceFreeExportedLocalEffectResultArtifact(
              checkedOwner, inputs, importing, localDefinition, localInvocationToken,
              receipt, retention, localContext, contractLimits)
            : control.issueDependentLocalEffectResultArtifact(checkedOwner,
              inputs, importing, local.dependency, localDefinition, receipt,
              retention, localContext, contractLimits);
          if (onOriginalArtifact !== undefined && proposalMembers !== undefined) {
            for (const originalMember of proposalMembers) {
              // The same original export still owns its reference backing here.
              // The capture must retain the Artifact before a fallible adoption;
              // normal export finally remains responsible for the old receipt.
              if (onOriginalArtifact(localResultArtifact, originalMember) !== undefined) {
                throw new TypeError('InvalidEffectOriginalArtifactProjection');
              }
            }
          }
          if (local !== undefined && !table) {
            if (memberIndex === undefined) return undefined;
            if (!moon.clientProgramEffectLocalResultMatchesMember(
              inputs, local.resultIndex!, memberIndex!)) {
              throw new TypeError('ForeignEffectMemberExport');
            }
            input = moon.clientProgramEffectInputAt(inputs, memberIndex!);
          }
          return (table ? control.issueEffectTableSourceArtifactFromExport
            : control.issueEffectSourceArtifactFromExport)(
            input, receipt, invocation, retention, sourceBindingCid,
            store.storeAuthorityCid, contractLimits);
        },
        async onChunk(chunk) {
          if (typeof chunk !== 'string') {
            throw new TypeError('InvalidEffectSourceChunk');
          }
          const bytes = Buffer.byteLength(chunk, 'utf8');
          if (bytes > maxBytes - byteCount) {
            throw new RangeError('EffectSourceByteLimit');
          }
          if (relationChunks !== undefined) {
            relationChunks.push(retainText(chunk));
          }
          await writer.append(chunk);
          digest.update(chunk, 'utf8');
          byteCount += bytes;
        },
      });
      for (const plan of proposalPlans) {
        checked(moon.clientProgramEffectProposalFinish(plan,
          summary.rowCount));
      }
      const localManifest = manifestSet === undefined
        ? control.issueLocalEffectResultManifest(checkedOwner,
          localInvocationToken, [localResultArtifact!], contractLimits)
        : undefined;
      const physicalCid = `sha256:${digest.digest('hex')}`;
      sealed = await writer.seal(physicalCid);
      if (sealed.cid !== physicalCid || sealed.bytes !== byteCount) {
        throw new Error('EffectSourcePhysicalIdentityMismatch');
      }
      const payload = Object.freeze({
        summary, schema: sourceSchema,
        localResultDefinition,
        localInvocation,
        localResultArtifact: localResultArtifact!,
        localManifest,
        ...(!dependent ? {} : {dependencyBodies: Object.freeze([
          ...local.dependency.bodies,
          ...(local.dependency.catalogBodies ?? []),
          ...local.staticBodies,
          ...localEvidenceContext.retentionDependencies!,
          ...(localEvidenceContext.resultDataPolicy === undefined ? [] :
            [localEvidenceContext.resultDataPolicy]),
          ...(localEvidenceContext.acquisitionDependencies ?? []),
          ...(localEvidenceContext.acquiredCatalogBodies
            ?? localEvidenceContext.acquiredEvidence?.catalogBodies ?? []),
          schemaBody!,
          Object.freeze({kind: 'relation_value', cid: summary.logicalCid,
            wire: '{"sort":"relation","value":' + relationChunks!.join('') + '}'}),
        ])}),
        physical: Object.freeze({cid: sealed.cid, bytes: sealed.bytes}),
        prepared: sealed.prepared,
      });
      preparedEffectSourceOwners.set(payload, Object.freeze({
        store, checkedOwner, inputs, memberIndex, localInvocationToken, unitIndex,
        tableInput: table,
        contractLimits: Object.freeze({...contractLimits}),
      }));
      // Preserve every independently issued original for its member's custody.
      // Common deduplicates only the canonical named entry after checking the
      // exact live Result origin; it still retains each physical witness.
      manifestSet?.get(unitIndex)!.artifacts.push(localResultArtifact!);
      return payload;
    } catch (failure) {
      const pendingOwners: CleanupHandle[] = [];
      if ((failure as Partial<EffectCommandKeyCleanupFailure> | undefined)?.cleanupPending === true &&
          (failure as Partial<EffectCommandKeyCleanupFailure>).cleanupHandle !== undefined) {
        pendingOwners.push((failure as EffectCommandKeyCleanupFailure).cleanupHandle);
      }
      let cleanupError;
      try {
        if (sealed === undefined) await writer.cancel();
        else await sealed.prepared.release();
      } catch (error) {
        cleanupError = error;
        pendingOwners.push(Object.freeze({
          status: () => Object.freeze({pending: sealed === undefined
            ? writer.status().reservationHeld === true ||
              writer.status().custodyPending === true
            : sealed.prepared.status().pending === true}),
          retry: sealed === undefined
            ? () => writer.cancel() : () => sealed!.prepared.retry(),
        }));
      }
      if (pendingOwners.some(owner => owner.status().pending === true)) {
        const error = new Error('EffectSourceCleanupPending', {cause: failure}) as EffectCommandKeyCleanupFailure;
        error.cleanupPending = true;
        error.cleanupError = cleanupError;
        error.cleanupHandle = Object.freeze({
          status: () => Object.freeze({pending: pendingOwners.some(
            owner => owner.status().pending === true)}),
          async retry() {
            const errors = [];
            for (const owner of pendingOwners) {
              if (owner.status().pending !== true) continue;
              try { await owner.retry(); }
              catch (reason) { errors.push(reason); }
            }
            return Object.freeze({
              pending: pendingOwners.some(owner =>
                owner.status().pending === true),
              errors: Object.freeze(errors),
            });
          },
        });
        throw error;
      }
      throw failure;
    } finally {
      for (const plan of proposalPlans) {
        moon.clientProgramEffectProposalCancel(plan);
      }
    }
  }
  return {preparePinnedEffectSourcePayload, preparePinnedEffectSourcePayloadOwned};
}
