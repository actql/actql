import {checked} from '../host-common/runtime-result.mjs';
import {issueCompletedEffectfulComputationEvidence} from '../host-common/completed-run-publication.mjs';
import {verifyPinnedEffectPlan} from './effect-plan-verify.mjs';
import {prepareInstalledEffectRequestChild} from './installed-effect-plan.mjs';
import {prepareInstalledRowCaptureChild} from './installed-row-capture-cleanup.mjs';
import {prepareInstalledRowEffectCaptureInputs} from './installed-row-effect-capture-inputs.mjs';
import {createInstalledRowEffectCaptureRows} from './installed-row-effect-capture-rows.mjs';
import {approvedValue} from './installed-row-effect-commit.mjs';
import {canonicalJson} from './local-account-config.mjs';

import type {effectApplicationControl} from '../host-common/effect-application-control.mjs';
import type {createInstalledRowEffectCapability, createInstalledRowEffectTargetAuthorization} from './installed-row-effect-authorization.mjs';
import type {createInstalledRowEffectCaptureValues} from './installed-row-effect-capture-values.mjs';
import type {createInstalledRowEffectClaims} from './installed-row-effect-claims.mjs';
import type {createInstalledRowEffectPhysicalRoute} from './installed-row-effect-physical-route.mjs';
import type {createInstalledRowEffectReadOperations} from './installed-row-effect-physical-read.mjs';
import type {createInstalledRowEffectFootprint, createInstalledRowEffectPreview,
  createInstalledRowEffectPreviewContext} from './installed-row-effect-preview.mjs';
import type {createInstalledRowEffectMembers, createInstalledRowEffectRequests} from './installed-row-effect-members.mjs';
import type {preparePinnedEffectSourceSet, preparePinnedEffectSourceHoldings,
  retainPinnedEffectDependencyPayloads} from './effect-input-export.mjs';

type Requests = ReturnType<typeof createInstalledRowEffectRequests>;
type RequestMember = Parameters<Requests['requestEntry']>[0];
type MappingMember = Extract<RequestMember, {kind: Exclude<RequestMember['kind'], 'command'>}>;
type RowMember = Extract<RequestMember, {kind: 'command'}> | MappingMember;
type Member = RowMember & Readonly<{stageIndex: number}>;
type RowOptions = Parameters<typeof createInstalledRowEffectCaptureRows<Member>>[0];
type Values = ReturnType<typeof createInstalledRowEffectCaptureValues>;
type Effect = Pick<ReturnType<typeof effectApplicationControl>, 'admitPreviewIdentity' | 'dispatchKeyCid'>;
type EffectCapture = Parameters<typeof issueCompletedEffectfulComputationEvidence>[0];
type VerifyPlan = Parameters<typeof verifyPinnedEffectPlan>[0];
type Claims = ReturnType<typeof createInstalledRowEffectClaims<Member>>;
type ClaimInput = Parameters<Claims['claimsOf']>[0];
type Route = ReturnType<typeof createInstalledRowEffectPhysicalRoute<Member>>;
type RouteInput = Parameters<Route>[0];
type Context = ReturnType<typeof createInstalledRowEffectPreviewContext<Member, never>>;
type Preview = ReturnType<typeof createInstalledRowEffectPreview<Member>>;
type PreviewInput = Parameters<Preview>[0];
type Ledger = RouteInput['ledger'];
type ReadOperations = ReturnType<typeof createInstalledRowEffectReadOperations<Member>>;
type BaseCapture = Parameters<typeof prepareInstalledRowEffectCaptureInputs>[0];
type SourceInputs = Parameters<typeof preparePinnedEffectSourceSet>[0];
type SourceHolding = Parameters<typeof preparePinnedEffectSourceHoldings>[0];
type DependencyRetention = Parameters<typeof retainPinnedEffectDependencyPayloads>[0];
type Entry = ReturnType<Requests['requestEntry']> & ClaimInput['entries'][number][number];
type Entries = readonly (readonly Entry[])[];
type Limits = ReturnType<BaseCapture['runLimits']> & PreviewInput['limits'] & Readonly<{maxFrontierWork: number}>;
type Control = BaseCapture['control'] & EffectCapture['control'] & PreviewInput['control'] &
  Parameters<Values['commandContentBorrower']>[0]['control'] & SourceHolding['control'] & DependencyRetention['control'];
type Runtime = BaseCapture['moon'] & RowOptions['moon'] & VerifyPlan['moon'] & Readonly<{
  strategyPublicationContractIdentity(value: unknown): string;
  clientProgramEffectInputAt(inputs: unknown, index: number): unknown;
  clientProgramEffectInputStage(input: unknown): number;
  clientProgramEffectPreviewInputLimits(maxWireBytes: number, maxNodes: number, maxDepth: number,
    maxWork: number, maxFields: number, maxKeyBytes: number, maxKeyNodes: number, maxKeyDepth: number,
    members: number, rows: number, maxGroupingWork: number, maxKeyWork: number): unknown;
  clientProgramBindEffectPreviewInputs(host: unknown, inputs: unknown, invocation: unknown,
    stage: number, wire: string, authoringCid: string, limits: unknown): unknown;
  clientProgramEffectApplySubjectCid(previewInputs: unknown): string | undefined;
}>;
type SourceSet = Awaited<ReturnType<typeof preparePinnedEffectSourceSet>>;
type CaptureOptions = Parameters<typeof prepareInstalledRowEffectCaptureInputs<Member, BaseCapture['plan']['outputLimits'],
  SourceSet, Limits>>[0];
type StageOwner = Omit<ReturnType<BaseCapture['ownerOf']>, 'owned' | 'profile'> & Readonly<{
  profile: Readonly<{source: string; unit: string}>;
  updateWriteSlot?: unknown;
  authorization?: unknown;
  owned: RowOptions['owned'] & Readonly<{
    finalizeRequest?(options: Readonly<{request: unknown; requestTag: string}>):
      ReturnType<RowOptions['owned']['prepareRequest']>;
    assertRequestFinalized?(request: unknown, requestTag: string): unknown;
  }>;
}>;
type EffectIntent = Pick<EffectCapture, 'runDefinition' | 'invocation' | 'admission' | 'observation' |
  'normalizationJournal' | 'receiptEvidence' | 'captureEvidence' | 'contractLimits'> & Readonly<{
  outputLimits: BaseCapture['plan']['outputLimits'];
  effectInputRetention: SourceInputs['retention'];
  runDefinition: EffectCapture['runDefinition'] & Readonly<{identity: string}>;
  sourceFreeInvocationOriginal?: unknown; localEvidenceContext: SourceInputs['localEvidenceContext'];
  request: unknown; attempt: unknown; now?: unknown;
}>;
type PreflightEffect = Parameters<Context['basePreflight']>[0]['effects'][number];
type BodyRow = NonNullable<RouteInput['previewRows']>[number][number] & PreflightEffect['changes'][number];
type BodyEffect = Omit<ClaimInput['body']['effects'][number] & PreflightEffect, 'changes'> &
  Readonly<{changes: readonly BodyRow[]}>;
type Body = Readonly<{run_identity_cid: string; authoring_context: unknown; effects: readonly BodyEffect[]}>;
type StageInputs = Readonly<{
  control: Control; store: BaseCapture['store'] & EffectCapture['store'] & SourceHolding['store'];
  execution: EffectCapture['execution'] & VerifyPlan['execution'] & SourceInputs['execution'];
  checkedHost: unknown; prepared: unknown; identity: unknown; plan: EffectIntent;
  previewContext: Omit<PreviewInput['context'], 'storeAuthorityCid'>;
  unit: Parameters<Context['continuationOf']>[1] & ClaimInput['unit'];
  members: readonly Member[]; runInvocationCid: string; dispatches: readonly string[];
  requestScope: unknown; storedResults: EffectCapture['storedResults']; signal?: AbortSignal;
  targetReads?: RouteInput['targetReads']; contentOwner?: unknown;
  managedEffect?: NonNullable<BaseCapture['managedEffect']> & NonNullable<PreviewInput['managedEffect']>;
  updateTargetSelections?: unknown;
  own(sourceSet: SourceSet): void; ownInputs: BaseCapture['ownInputs'];
  ownChildren: BaseCapture['ownChildren']; assertCurrent?: RowOptions['assertCurrent'];
}>;
type StageControls = Readonly<{
  moon: Runtime; fail(code: string): never; ownerOf(member: Member): StageOwner;
  runLimits(managed: StageInputs['managedEffect']): Limits;
  prepareCredentialOperation: CaptureOptions['prepareCredentialOperation'];
  recipeOf: BaseCapture['recipeOf']; singular?: StageOwner;
  cid: BaseCapture['cid']; exportLimits: BaseCapture['exportLimits'];
  preparePinnedEffectSourceSet: typeof preparePinnedEffectSourceSet;
  guarded: RowOptions['guarded']; targeted: RowOptions['targeted']; checkSubject(runInvocationCid: string, member: Member): string;
  decideTargetRead: ReturnType<typeof createInstalledRowEffectTargetAuthorization<Member>>;
  resourceFields: RowOptions['resourceFields']; sameEffectValue(kind: Member['kind'], left: unknown, right: unknown): boolean;
  sameValue(left: unknown, right: unknown): boolean;
  retainPinnedEffectDependencyPayloads: typeof retainPinnedEffectDependencyPayloads;
  preparePinnedEffectSourceHoldings: typeof preparePinnedEffectSourceHoldings;
  effect: Effect; openLedger(identity: unknown, construction: RowOptions['controlConstruction']): Ledger;
  physicalRoute: Route; authorPreview: Preview; footprintOf: ReturnType<typeof createInstalledRowEffectFootprint<Member>>;
  scopes: ReturnType<typeof createInstalledRowEffectMembers>['scopes'];
}> & ReadOperations & Pick<Requests, 'requestEntry' | 'requestsOf'> & Values & Pick<Context, 'basePreflight' | 'continuationOf'> & Claims &
  Pick<ReturnType<typeof createInstalledRowEffectCapability<Member>>, 'admitCapability'>;

type Computation = Awaited<ReturnType<typeof issueCompletedEffectfulComputationEvidence>>;
type CaptureClaims = ReturnType<Claims['claimsOf']>;
type ApplyPreview = ReturnType<Effect['admitPreviewIdentity']>;
type Scopes = ReturnType<StageControls['scopes']>;
type OpenRoute = ReturnType<Route>;
type CaptureResult = Readonly<{
  preview: EffectCapture['preview']; computation: Computation; storedResults: StageInputs['storedResults'];
  apply: Readonly<{
    moon: Runtime; capturedInputs: unknown;
    preflight: ReturnType<Context['basePreflight']> & Readonly<{proofs: readonly unknown[]}>;
    ledger: Ledger; members: CaptureClaims; maxFrontierWork: number;
    refreshPreflight: OpenRoute['current']; bindDispatch: OpenRoute['bindDispatch'];
    authorization: Readonly<{gate: StageOwner['authorization']; scopes: Scopes}>;
  }>;
  receipt: Readonly<{
    ledger: Ledger; preview: ApplyPreview; commonMoon: Runtime; publicationPreview: EffectCapture['preview'];
    authorizeEvidenceRead(): Promise<boolean>;
    members: readonly Readonly<{rowOwners: readonly Readonly<{claim: CaptureClaims[number]['claims'][number]}>[]; replayed: boolean}>[];
    limits: EffectIntent['contractLimits'];
  }>;
  publication: Pick<StageInputs, 'execution' | 'store' | 'storedResults' | 'control'> &
    Pick<EffectIntent, 'request' | 'attempt' | 'contractLimits' | 'now'> &
    Readonly<{computation: Computation; preview: EffectCapture['preview']; ledger: Ledger}>;
  scopes: Scopes; continuationWire: ReturnType<Context['continuationOf']>;
  releaseInputs(): Promise<void>; dispose(): Promise<void>;
}>;

export function createInstalledRowEffectCaptureStage({
  moon, fail, ownerOf, runLimits, prepareCredentialOperation, recipeOf, singular, cid, exportLimits,
  preparePinnedEffectSourceSet, guarded, targeted, checkSubject, decideTargetRead, describeMember,
  commandContentBorrower, resourceFields, prepareInstalledCreateRows, commandContentRow, requestEntry, requestsOf,
  observeRows, checkRows, admitCapability, footprintOf, retainPinnedEffectDependencyPayloads, authorPreview,
  sameEffectValue, sameValue, effect, preparePinnedEffectSourceHoldings, openLedger, claimsOf, physicalRoute,
  orderedSourceIndexes, basePreflight, scopes, continuationOf,
}: StageControls) {
  async function captureStage({control, store, execution, checkedHost,
    prepared, identity, plan, previewContext, unit, members,
    runInvocationCid, dispatches, requestScope, storedResults, signal,
    targetReads, contentOwner, managedEffect, updateTargetSelections, own, ownInputs, ownChildren, assertCurrent}: StageInputs): Promise<CaptureResult> {
    let sourceSet: SourceSet | undefined;
    let createOriginals: ReturnType<Preview['memberOriginal']>[] | undefined;
    let entries: Entries | undefined;
    let route: ReturnType<Route> | undefined;
    const {limits, controlConstruction, inputs, commandKeys, contentBorrowers, requestChildren, memberCaptures,
      proposals, currents, rowsOf, observations, publishedTargets, physicalOperations, retireRequestAliases,
      childrenPending, releaseInputs, sourceExport} = prepareInstalledRowEffectCaptureInputs({
      moon, control, store, execution, checkedHost, prepared, identity, plan, members, runInvocationCid, signal,
      managedEffect, assertCurrent, ownInputs, ownChildren, runLimits, prepareCredentialOperation, ownerOf, recipeOf,
      singular, cid, exportLimits, preparePinnedEffectSourceSet, fail,
      readSourceSet: () => sourceSet,
      readEntries: () => entries,
      retireRoute() {
        if (route !== undefined && !route.retire()) return false;
        entries = undefined;
        createOriginals = undefined;
        return true;
      },
    });
    sourceSet = await sourceExport;
    own(sourceSet);
    assertCurrent?.();
    // Reads of each update member's targets are decided before any provider
    // I/O: a held or denied read authors no Preview.
    const reads: (Awaited<ReturnType<StageControls['decideTargetRead']>> | undefined)[] = [];
    for (const [index, member] of members.entries()) {
      reads.push(!guarded(member.kind) ? undefined :
        await decideTargetRead({member, runInvocationCid,
          dispatchRequestCid: dispatches[index],
          subjectCid: checkSubject(runInvocationCid, member), signal,
          targetReads, assertCurrent, controlConstruction}));
      assertCurrent?.();
    }
    for (const [index, member] of members.entries()) {
      const {owned, updateWriteSlot} = ownerOf(member);
      assertCurrent?.();
      if (proposals[index].length === 0) fail('InstalledRowEffectEmptyMember');
      const description = await describeMember({member, maxRows: proposals[index].length, runInvocationCid,
        dispatchRequestCid: dispatches[index], label: `preview-${index}`,
        approval: reads[index]?.approval, signal, assertCurrent, physicalOperations, operationPhase: 'capture', controlConstruction});
      assertCurrent?.();
      currents.push(description);
      const contentOf = member.kind !== 'command' ? undefined : commandContentBorrower({
        control, prepared, inputs, memberIndex: member.memberIndex,
        artifact: sourceSet.members[index].payload.localResultArtifact,
        limits, assertCurrent});
      if (contentOf !== undefined) contentBorrowers.push(contentOf);
      const recipe = recipeOf(member);
      let fileCreateIdentity: RowOptions['fileCreateIdentity'];
      if (member.kind === 'create' && recipe?.requestConstruction !== undefined && recipe.physicalWrite !== undefined) {
        // The same source and Effect originals fix the allocated storage key
        // and are later sealed by the Preview.
        const original = authorPreview.memberOriginal({control, prepared, inputs, member,
          payload: sourceSet.members[index].payload, runInvocation: previewContext.runInvocation,
          storeAuthorityCid: store.storeAuthorityCid, limits});
        (createOriginals ??= [])[index] = original;
        fileCreateIdentity = Object.freeze({
          runDefinitionCid: moon.strategyPublicationContractIdentity(previewContext.runDefinition),
          sourceBindingCid: original.sourceBindingCid, effectIdentityCid: original.identity.identity,
        });
      }
      const {constructRows, recoverObservedRows} = createInstalledRowEffectCaptureRows({
        member, index, owned, updateWriteSlot, description, contentOf, moon, proposals, limits, recipeOf,
        managedEffect, prepared, identity, reads, controlConstruction, runInvocationCid, dispatches, signal,
        assertCurrent, contentOwner, fileCreateIdentity, resourceFields, physicalOperations, guarded, targeted, requestChildren,
        rowsOf, observations, prepareInstalledCreateRows, commandContentRow, requestEntry, requestsOf,
        observeRows, retireRequestAliases, fail,
      });
      const observedCapture = recipe?.captureConstruction?.inputExtent !== undefined;
      if (observedCapture) {
        // The proposal Strings are borrowed from the completed original Read.
        // Its same constructor now funds every native map/parse/request below
        // BEFORE entry and joins the actual asynchronous task before completion.
        rowsOf[index] = recoverObservedRows;
        observations[index] = await memberCaptures[index].prepare();
      } else await constructRows();
    }
    entries = Object.freeze(rowsOf.map(rows =>
      Object.freeze((rows as readonly {entry: Entry}[]).map(row => row.entry))));
    // Every create row passes the provider check before a Preview.
    await checkRows({members, entries, runInvocationCid, dispatches,
      subjectOf: member => checkSubject(runInvocationCid, member), signal, assertCurrent,
      physicalOperations, controlConstruction, operationPhase: 'capture'});
    assertCurrent?.();
    const capabilities = members.map((member, index) => admitCapability(
      member, entries![index], currents[index], runInvocationCid,
      dispatches[index], controlConstruction));
    const footprints = members.map((member, index) =>
      footprintOf(member, entries![index], controlConstruction));
    if (sourceSet.dependencies !== undefined) {
      retainPinnedEffectDependencyPayloads({sources: sourceSet, execution,
        store, storedResults, control, runDefinition: plan.runDefinition});
    }
    const payloads = sourceSet.members.map(member => member.payload);
    const preview = authorPreview({control, prepared, inputs, limits, managedEffect,
      context: {runDefinition: previewContext.runDefinition,
        runInvocation: previewContext.runInvocation,
        compiledPlan: previewContext.compiledPlan,
        storeAuthorityCid: store.storeAuthorityCid},
      requestScope, members, rowsOf: rowsOf as PreviewInput['rowsOf'], capabilities, footprints, payloads, createOriginals});
    const body = (managedEffect === undefined ? JSON.parse(preview.wire)
      : managedEffect.controlConstruction.parsePreview(preview.wire)) as Body;
    // The admitted Preview must state exactly the rows its requests write.
    body.effects.forEach((member, index) => {
      if (member.changes.length !== entries![index].length ||
          member.changes.some((change, row) =>
            !sameEffectValue(members[index].kind, approvedValue(members[index].kind, change), entries![index][row].value) ||
            (targeted(members[index].kind) && !sameValue(
              change.target_row_identity, entries![index][row].target)))) {
        fail('InstalledRowEffectPreviewOrderMismatch');
      }
    });
    const authoringContext = control.admitRunEvidence('authoring_context',
      canonicalJson(body.authoring_context), plan.contractLimits);
    const admittedPreview = control.admitEffectComputationPreview(
      preview.wire, plan.runDefinition, authoringContext,
      plan.contractLimits);
    let applyPreview: ReturnType<Effect['admitPreviewIdentity']> | undefined;
    if (members.some(member => ownerOf(member).owned.finalizeRequest !== undefined)) {
      applyPreview = effect.admitPreviewIdentity(preview.wire,
        body.run_identity_cid, preview.authoringCid, requestScope,
        preview.keys, limits.preview.maxWireBytes, limits.preview.maxNodes,
        limits.preview.maxDepth);
      const finalized: Entries[number][] = [];
      for (const [memberIndex, member] of members.entries()) {
        const {owned} = ownerOf(member);
        const recipe = recipeOf(member);
        if (owned.finalizeRequest === undefined) {finalized.push(entries[memberIndex]); continue;}
        const constructor = recipe?.requestFinalization;
        const operationIndex = constructor?.operationIndex;
        if (managedEffect?.runtime !== moon || managedEffect.prepared !== prepared ||
            managedEffect.request !== identity || !Number.isSafeInteger(operationIndex) ||
            operationIndex! < 0 || operationIndex! >= recipe!.rowOperations.length ||
            operationIndex === recipe!.requestConstruction?.operationIndex) {
          fail('InstalledEffectRequestFinalizationPlanUnavailable');
        }
        const rows = [];
        for (const [rowIndex, original] of entries[memberIndex].entries()) {
          const requestTag = effect.dispatchKeyCid(preview.keys[memberIndex][rowIndex]);
          const preparedRequest = await prepareInstalledRowCaptureChild({children: requestChildren,
            create: () => prepareInstalledEffectRequestChild({run: managedEffect!,
              memberIndex: member.memberIndex, rowIndex, operationIndex: operationIndex!,
              operation: recipe!.rowOperations[operationIndex!].operation!,
              construct: () => owned.finalizeRequest!({request: original.request, requestTag}),
              requestsRetired: retireRequestAliases}), assertCurrent, signal});
          const entry = requestEntry(member, {value: original.value, selector: original.target}, preparedRequest) as Entry;
          owned.assertRequestFinalized!(entry.request, requestTag);
          rows.push(entry);
        }
        finalized.push(Object.freeze(rows));
      }
      entries = Object.freeze(finalized);
    }
    const holdings = await preparePinnedEffectSourceHoldings({
      sources: sourceSet, store, control, preview: admittedPreview,
      invocation: plan.invocation,
      resultArtifacts: payloads.map(payload => payload.localResultArtifact)}).commit();
    assertCurrent?.();
    const previewInputs = checked(moon.clientProgramBindEffectPreviewInputs(
      checkedHost, inputs, previewContext.runInvocation,
      moon.clientProgramEffectInputStage(
        moon.clientProgramEffectInputAt(inputs, 0)), preview.wire,
      preview.authoringCid, moon.clientProgramEffectPreviewInputLimits(
        limits.preview.maxWireBytes, limits.preview.maxNodes,
        limits.preview.maxDepth, limits.maxWork, limits.maxFields,
        limits.preview.maxWireBytes, limits.preview.maxNodes,
        limits.preview.maxDepth, members.length, limits.maxRows,
        limits.maxWork, limits.maxWork)));
    // Every non-create member is verified against its pinned input. Command
    // proofs bind exact target/input but are not Mapping Plan documents.
    const plans = [];
    for (const member of members) {
      if (member.kind === 'create') continue;
      const chunks: string[] = [];
      const verified = await verifyPinnedEffectPlan({moon, execution,
        previewInputs, previewIndex: member.memberIndex,
        inputKey: commandKeys[member.memberIndex],
        publishedTarget: publishedTargets?.[member.memberIndex],
        limits: moon.clientProgramEffectInputExportLimits(
          ...exportLimits(plan.outputLimits)),
        planLimits: {maxFields: limits.maxFields, maxWork: limits.planWork,
          maxBytes: limits.preview.maxWireBytes,
          maxNodes: limits.preview.maxNodes,
          maxDepth: limits.preview.maxDepth,
          maxUtf16Units: limits.preview.maxWireBytes},
        onChunk: chunk => { chunks.push(chunk); }, signal});
      assertCurrent?.();
      plans.push({name: member.effectId,
        ...(member.kind === 'command' ? {} : {wire: chunks.join('')}),
        proof: verified.proof});
    }
    const connectorRecovery = [];
    for (const [index, member] of members.entries()) {
      const {owned} = ownerOf(member);
      const retained = memberCaptures[index];
      const observedCapture = recipeOf(member)?.captureConstruction?.inputExtent !== undefined;
      const entry = (observedCapture ? observations[index] : retained === undefined
        ? owned.recoveryEntry?.({member, current: currents[index], entries: entries[index]})
        : await retained.prepare()) as Omit<EffectCapture['connectorRecovery'][number], 'memberIndex'> | undefined;
      if (owned.recoveryEntry !== undefined) connectorRecovery.push({memberIndex: index,
        kind: entry?.kind, observationCid: entry?.observationCid, wire: entry?.wire});
    }
    const computation = await issueCompletedEffectfulComputationEvidence({
      execution, store, storedResults, control, admission: plan.admission,
      runDefinition: plan.runDefinition, invocation: plan.invocation,
      observation: plan.observation,
      normalizationJournal: plan.normalizationJournal, authoringContext,
      receiptEvidence: plan.receiptEvidence,
      captureEvidence: plan.captureEvidence, preview: admittedPreview,
      plans: plans.filter(item => item.wire !== undefined)
        .map(({name, wire}) => ({name, wire: wire!})),
      effectSourceHoldings: holdings, connectorRecovery,
      contractLimits: plan.contractLimits, signal});
    assertCurrent?.();
    for (const payload of sourceSet.payloads) {
      if (!childrenPending() && payload.prepared!.status().pending) await payload.prepared!.release();
      assertCurrent?.();
    }
    const ledger = openLedger(identity, controlConstruction);
    try {
      applyPreview ??= effect.admitPreviewIdentity(preview.wire,
        body.run_identity_cid, preview.authoringCid, requestScope,
        preview.keys, limits.preview.maxWireBytes, limits.preview.maxNodes,
        limits.preview.maxDepth);
      const claims = claimsOf({body, keys: preview.keys, entries,
        requestScope, unit, dispatches,
        members, unitCids: members.map(member => cid({version: ownerOf(member).profile.unit,
          run_definition_cid: plan.runDefinition.identity, stage_index: member.stageIndex})),
        retentionId: plan.effectInputRetention.identity});
      route = physicalRoute({members, entries,
        previewRows: body.effects.map(member => member.changes),
        dispatchIndexes: body.effects.map(orderedSourceIndexes),
        runInvocationCid, dispatches,
        subjectCid: moon.clientProgramEffectApplySubjectCid(previewInputs)!,
        applyPreview, ledger, targetReads, assertCurrent, physicalOperations, controlConstruction});
      const preflight = {proofs: plans.map(item => item.proof),
        ...basePreflight({effects: body.effects, members, requestScope, limits,
          keys: preview.keys})};
      return Object.freeze({preview: admittedPreview, computation,
        storedResults,
        apply: {moon, capturedInputs: previewInputs, preflight, ledger,
          members: claims, maxFrontierWork: limits.maxFrontierWork,
          refreshPreflight: route.current, bindDispatch: route.bindDispatch,
          authorization: {gate: singular?.authorization, scopes: scopes(members)}},
        receipt: {ledger, preview: applyPreview, commonMoon: moon,
          publicationPreview: admittedPreview,
          authorizeEvidenceRead: async () => true,
          members: claims.map(member => ({rowOwners: member.claims.map(
            claim => ({claim})), replayed: false})),
          limits: plan.contractLimits},
        publication: {execution, store, storedResults, control, computation,
          preview: admittedPreview, ledger, request: plan.request,
          attempt: plan.attempt, contractLimits: plan.contractLimits,
          now: plan.now},
        scopes: scopes(members),
        continuationWire: continuationOf(plan, unit, members, dispatches,
          updateTargetSelections !== undefined),
        releaseInputs,
        dispose: async () => { await releaseInputs(); ledger.close(); }});
    } catch (error) {
      ledger.close();
      throw error;
    }
  }

  return captureStage;
}
