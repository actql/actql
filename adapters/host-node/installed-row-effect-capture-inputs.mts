import {checked} from '../host-common/runtime-result.mjs';
import {installedEffectDependencyOriginal} from '../host-common/installed-effect-dependency-original.mjs';
import {retireEffectCommandKeyWorkspace} from './effect-command-key.mjs';
import {releaseInstalledRowCapture, retainInstalledRowCaptureChild} from './installed-row-capture-cleanup.mjs';
import {prepareInstalledEffectCaptureChild, prepareInstalledEffectRequestChild} from './installed-effect-plan.mjs';

import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import type {prepareInstalledEffectControlConstruction} from './installed-effect-plan.mjs';
import type {InstalledEffectPlanRecipe} from './installed-effect-recipe.mjs';
import type {createInstalledRowEffectPhysicalOperation} from './installed-row-effect-physical-read.mjs';

type MemberRef = Readonly<{kind: string; memberIndex: number; resource: string}>;
type Operation<Member extends MemberRef> = Parameters<ReturnType<typeof createInstalledRowEffectPhysicalOperation<Member>>>[0];
type PhysicalRun = NonNullable<Operation<MemberRef>['managedEffect']>;
type NativeRun = Parameters<typeof prepareInstalledEffectRequestChild<undefined>>[0]['run'];
type Construction = ReturnType<typeof prepareInstalledEffectControlConstruction>;
type Runtime = (PhysicalRun & NativeRun)['runtime'] & Readonly<{
  clientProgramPinEffectSources(host: unknown, maxPinnedResults: number): unknown;
  clientProgramInstalledEffectDependencySourcesPin(parent: unknown, prepared: unknown, identity: unknown,
    plan: unknown, host: unknown, maxPinnedResults: number): unknown;
  clientProgramReleaseEffectInputs(inputs: unknown): unknown;
  clientProgramCloseEffectCommandKeyWorkspace(workspace: unknown): unknown;
  clientProgramEffectInputExportLimits(...args: number[]): unknown;
  clientProgramPlanEffectCommandKeyWorkspace?(host: unknown, inputs: unknown, index: number, limits: unknown, work: number): unknown;
  clientProgramEffectPublishedStoreBinding?(inputs: unknown, memberIndex: number, maxWork: number): unknown;
  clientProgramBindEffectCommandTarget?(inputs: unknown, memberIndex: number, pair: unknown, reference: unknown, maxWork: number): unknown;
}>;
type Run = PhysicalRun & NativeRun & Readonly<{runtime: Runtime; controlConstruction?: Construction}>;
type ReleaseOptions = Parameters<typeof releaseInstalledRowCapture>[0];
type RequestChildren = NonNullable<ReleaseOptions['children']>[number][];
type ContentBorrower = Readonly<{release(): void}>;
type SourceSet = Readonly<{payloads: NonNullable<ReleaseOptions['payloads']>}>;
type Current = () => SynchronousRuntimeData;
type Proposal = Readonly<{changesWire: string; selectorWire?: string; proposalWire?: string}>;
type Entry = Readonly<{request: unknown; requestCid: string; value?: unknown; target: unknown}>;
type RecoveryEntry = Readonly<{kind?: string; observationCid?: string; wire?: string; then?: never}>;
type CapturedRow = Readonly<{entry: Entry; identity?: unknown; state?: string; versionCid?: string; before?: unknown}>;
type CaptureRows = readonly CapturedRow[] | (() => Promise<RecoveryEntry | undefined>);
type Child = ReturnType<typeof prepareInstalledEffectCaptureChild<RecoveryEntry | undefined>>;
type Constructor = (options: Parameters<typeof prepareInstalledEffectCaptureChild<RecoveryEntry | undefined>>[0]) => Child;
type RetainedCapture = ReturnType<typeof retainInstalledRowCaptureChild<RecoveryEntry | undefined>>;
type InputExtent = (proposals: readonly Proposal[]) => SynchronousRuntimeData;
type Limits = Readonly<{
  maxPinnedResults: number; maxRows: number; maxRowsPerMember: number; maxFields: number; maxWork: number;
  body: Readonly<{maxBytes: number; maxNodes: number; maxDepth: number}>;
}>;
type Control = ReleaseOptions['control'] & Readonly<{
  bindCheckedInstalledEffectSourceFreeInvocation(parent: unknown, prepared: unknown, identity: unknown, plan: unknown,
    host: unknown, admission: unknown, definition: unknown, invocation: unknown): unknown;
  prepareEffectCommandContentArtifact(prepared: unknown, inputs: unknown, memberIndex: number, artifact: unknown, limits: Limits): unknown;
  releaseEffectCommandContentArtifact(artifact: unknown, maxWork: number): boolean;
}>;
type Plan<Output> = Readonly<{
  outputLimits: Output; admission?: unknown; runDefinition: unknown; invocation: unknown;
  sourceFreeInvocationOriginal?: unknown; effectInputRetention: unknown; contractLimits: unknown; localEvidenceContext?: unknown;
}>;
type Owner<Member> = Readonly<{
  owned: Readonly<{recoveryEntry?(facts: Readonly<{member: Member; current: unknown; entries: readonly Entry[]}>): RecoveryEntry | undefined}>;
  profile: Readonly<{source: string}>;
  issueOriginalCollectionReference?(pair: unknown, maxWork: number): unknown;
}>;
type Store = Readonly<{storeAuthorityCid: string}>;
type ExportInputs = Readonly<{
  moon: Runtime; dependencyConstruction?: Construction;
  commandWorkspaces?: readonly unknown[]; publishedTargets?: readonly unknown[];
  onCommandKey(memberIndex: number, key: unknown): void;
  checkedOwner: unknown; execution: unknown; inputs: unknown; maxMembers: number; maxGroupingWork: number;
  limits: unknown; store: Store; maxBytes: number; control: Control;
  invocation: unknown; retention: unknown; memberSourceBindings?: readonly Readonly<{memberIndex: number; sourceBindingCid: string}>[];
  sourceBindingCid?: string; contractLimits: unknown; localEvidenceContext?: unknown;
  proposalLimits: Readonly<{maxFields: number; maxWork: number; maxBytes: number; maxNodes: number; maxDepth: number; maxUtf16Units: number}>;
  onOriginalArtifact(artifact: unknown, memberIndex: number): void;
  onProposalRow(memberIndex: number, rowIndex: number, proposal: Proposal): void;
  signal?: AbortSignal;
}>;
type Options<Member extends MemberRef, Output extends {maxWireBytes: number}, Sources extends SourceSet, RunLimits extends Limits> = Readonly<{
  moon: Runtime; control: Control; store: Store; execution: unknown; checkedHost: unknown;
  prepared: unknown; identity: unknown; plan: Plan<Output>; members: readonly Member[];
  runInvocationCid: string; signal?: AbortSignal; managedEffect?: Run; assertCurrent?: Current;
  ownInputs(release: () => Promise<void>, finish: () => void): void;
  ownChildren(children: RequestChildren): void;
  runLimits(run: Run | undefined): RunLimits;
  prepareCredentialOperation: ReturnType<typeof createInstalledRowEffectPhysicalOperation<Member>>;
  ownerOf(member: Member): Owner<Member>; recipeOf(member: Member): InstalledEffectPlanRecipe | undefined;
  singular?: Owner<Member>;
  cid(value: unknown): string;
  exportLimits(output: Output): readonly number[];
  preparePinnedEffectSourceSet(options: ExportInputs): Promise<Sources>;
  readSourceSet(): Sources | undefined;
  readEntries(): readonly (readonly Entry[])[] | undefined;
  retireRoute(): boolean;
  fail(code: string, cause?: unknown): never;
}>;

export function prepareInstalledRowEffectCaptureInputs<Member extends MemberRef, Output extends {maxWireBytes: number},
  Sources extends SourceSet, RunLimits extends Limits>({
  moon, control, store, execution, checkedHost, prepared, identity, plan, members, runInvocationCid, signal,
  managedEffect, assertCurrent, ownInputs, ownChildren, runLimits, prepareCredentialOperation, ownerOf, recipeOf,
  singular, cid, exportLimits, preparePinnedEffectSourceSet, readSourceSet, readEntries, retireRoute, fail,
}: Options<Member, Output, Sources, RunLimits>) {
  const reject: Options<Member, Output, Sources, RunLimits>['fail'] = fail;
  assertCurrent?.();
  const limits = runLimits(managedEffect);
  const controlConstruction = managedEffect?.controlConstruction;
  if (managedEffect !== undefined && typeof controlConstruction !== 'function') reject('InstalledEffectControlRuntimeUnavailable');
  const dependencyOriginal = managedEffect === undefined ? undefined
    : installedEffectDependencyOriginal(controlConstruction,moon);
  if(dependencyOriginal!==undefined&&(dependencyOriginal.parent!==managedEffect!.value||
      dependencyOriginal.prepared!==prepared||dependencyOriginal.request!==identity||
      dependencyOriginal.plan!==managedEffect!.operationPlan))reject('ForeignInstalledEffectManagedRun');
  if (dependencyOriginal !== undefined && plan.sourceFreeInvocationOriginal !== undefined) {
    control.bindCheckedInstalledEffectSourceFreeInvocation(dependencyOriginal.parent,
      prepared, identity, dependencyOriginal.plan, checkedHost, plan.admission,
      plan.runDefinition, plan.sourceFreeInvocationOriginal);
    dependencyOriginal.current();
  }
  const inputs = dependencyOriginal === undefined
    ? checked(moon.clientProgramPinEffectSources(checkedHost, limits.maxPinnedResults))
    : checked(moon.clientProgramInstalledEffectDependencySourcesPin(dependencyOriginal.parent,
      prepared,identity,dependencyOriginal.plan,checkedHost,limits.maxPinnedResults));
  dependencyOriginal?.current();
  const commandWorkspaces: unknown[] = [];
  const commandKeys: unknown[] = [];
  const contentBorrowers: ContentBorrower[] = [];
  const contentArtifacts: unknown[] = [];
  const requestChildren: RequestChildren = [];
  const memberCaptures: RetainedCapture[] = [];
  const proposals: Proposal[][] = [], currents: unknown[] = [], rowsOf: CaptureRows[] = [], observations: unknown[] = [];
  let captureOpen = true;
  const retireRequestAliases = () => {
    if (captureOpen || !retireRoute()) return false;
    currents.length = 0;
    rowsOf.length = 0;
    observations.length = 0;
    proposals.length = 0;
    memberCaptures.length = 0;
    return true;
  };
  const physicalOperations = (facts: Operation<Member>) => {
    if (managedEffect?.runtime !== moon || managedEffect.prepared !== prepared ||
        managedEffect.request !== identity) reject('ForeignInstalledEffectManagedRun');
    return prepareCredentialOperation({...facts, managedEffect, requestChildren, retireRequestAliases});
  };
  ownChildren(requestChildren);
  const childrenPending = () => requestChildren.some(value =>
    typeof value?.prepared?.status !== 'function' ||
    value.prepared.status()?.pending !== false);
  const releaseInputPins = async () => {
    if (!retireRequestAliases()) reject('InstalledRowEffectRequestCleanupPending');
    for (const borrower of contentBorrowers) borrower.release();
    contentBorrowers.length = 0;
    let retired = true;
    for (const artifact of contentArtifacts) {
      // Scrub every original inventory, but do not return the parent pin
      // merely because one bounded cleanup quantum was exhausted.
      if (!control.releaseEffectCommandContentArtifact(artifact, limits.maxWork)) retired = false;
    }
    if (!retired) reject('InstalledRowEffectContentCleanupPending');
    contentArtifacts.length = 0;
    // The original parent retains phase/key aliases until request children,
    // content borrowers and artifacts have actually retired. Export finally
    // closes only the temporary import, never this byte borrower.
    for (const workspace of commandWorkspaces) {
      if (workspace === undefined) continue;
      await retireEffectCommandKeyWorkspace(() => checked(
        moon.clientProgramCloseEffectCommandKeyWorkspace(workspace)) as boolean);
    }
    commandWorkspaces.length = 0;
    commandKeys.length = 0;
    moon.clientProgramReleaseEffectInputs(inputs);
  };
  const releaseInputs = async () => {
    if (!retireRequestAliases()) reject('InstalledRowEffectRequestCleanupPending');
    // Direct successful-route disposal still drains its original children
    // and Sources. Failure cleanup already owns that same inventory below;
    // its input-pin callback must not create a second nested cleanup pass.
    if (requestChildren.length) {
      const marker = Object.freeze(new Error('InstalledRowEffectRequestCleanup'));
      try { await releaseInstalledRowCapture({children: requestChildren,
        payloads: readSourceSet()?.payloads ?? [], control}, marker); }
      catch (error) { if (error !== marker) throw error; }
    }
    await releaseInputPins();
  };
  ownInputs(releaseInputPins, () => { captureOpen = false; });
  if (managedEffect !== undefined) {
    if (typeof controlConstruction!.retainInputs !== 'function') reject('InstalledEffectOperationRuntimeUnavailable');
    controlConstruction!.retainInputs(inputs);
  }
  memberCaptures.length = members.length;
  // Reserve each original member's capture body before export can append
  // proposal rows, parse their values or issue canonical CREATE inventory.
  // These SAME arrays and children survive through ordinary route retirement.
  for (const member of members) {
    const recipe = recipeOf(member);
    if (recipe === undefined) { proposals.push([]); continue; }
    if (managedEffect?.runtime !== moon || managedEffect.prepared !== prepared ||
        managedEffect.request !== identity) reject('ForeignInstalledEffectManagedRun');
    const selected = recipe.captureConstruction;
    if (selected === undefined) reject('InstalledEffectCaptureConstructionUnavailable');
    const operation = recipe.memberOperations[selected.operationIndex]?.operation;
    const {owned} = ownerOf(member);
    const recoveryEntry = owned.recoveryEntry;
    let original: Child | undefined;
    const retained = retainInstalledRowCaptureChild({children: requestChildren,
      create: () => {
        const observed = selected.inputExtent !== undefined;
        if (observed && recipe.requestConstruction?.inputExtent === undefined) reject('InstalledEffectCaptureConstructionUnavailable');
        original = ((observed ? prepareInstalledEffectCaptureChild : prepareInstalledEffectRequestChild) as Constructor)({run: managedEffect,
          memberIndex: member.memberIndex, perRow: false, rowIndex: 0,
          operationIndex: selected.operationIndex, operation: operation!,
          ...(observed ? {inputExtent: () => controlConstruction!(undefined, selected.inputExtent as InputExtent,
            [proposals[member.memberIndex]])} : {}),
          construct: observed ? () => {
            const construct = rowsOf[member.memberIndex];
            if (typeof construct !== 'function') reject('InstalledEffectCaptureConstructionUnavailable');
            return construct();
          } : () => recoveryEntry === undefined ? undefined :
            Reflect.apply(recoveryEntry, owned, [{member, current: currents[member.memberIndex],
              entries: readEntries()![member.memberIndex]}]), requestsRetired: retireRequestAliases});
        return original;
      }, assertCurrent, signal});
    // Retain before this cheap original-record fence can fail. The actual
    // constructor is deferred; its original reservation already owns input.
    original!.checkOriginal();
    proposals.push([]);
    memberCaptures[member.memberIndex] = retained;
  }
  let proposalCount = 0;
  const sourceLimits = moon.clientProgramEffectInputExportLimits(
    ...exportLimits(plan.outputLimits));
  if (typeof moon.clientProgramPlanEffectCommandKeyWorkspace === 'function') {
    for (let index = 0; index < members.length; index++) {
      // This is the original Local Effect Host, not the prepared computation
      // (`checkedOwner`) or a Host re-created from the same CID.
      commandWorkspaces.push(checked(moon.clientProgramPlanEffectCommandKeyWorkspace(
        checkedHost, inputs, index, sourceLimits, limits.maxWork)));
    }
  }
  let publishedTargets: readonly unknown[] | undefined;
  if (typeof moon.clientProgramEffectPublishedStoreBinding === 'function') {
    let selected = false;
    const targets = members.map(member => {
      const pair = checked(moon.clientProgramEffectPublishedStoreBinding!(
        inputs, member.memberIndex, limits.maxWork));
      if (pair === undefined) return undefined;
      const owner = ownerOf(member);
      if (member.kind !== 'command' ||
          typeof owner.issueOriginalCollectionReference !== 'function' ||
          typeof moon.clientProgramBindEffectCommandTarget !== 'function') {
        reject('InstalledEffectPublishedTargetUnavailable');
      }
      assertCurrent?.();
      const reference = owner.issueOriginalCollectionReference(pair, limits.maxWork);
      assertCurrent?.();
      const target = checked(moon.clientProgramBindEffectCommandTarget(
        inputs, member.memberIndex, pair, reference, limits.maxWork));
      selected = true;
      return target;
    });
    if (selected) publishedTargets = Object.freeze(targets);
  } else if (members.some(member =>
    typeof ownerOf(member).issueOriginalCollectionReference === 'function')) {
    reject('InstalledEffectPublishedTargetUnavailable');
  }
  const sourceExport = preparePinnedEffectSourceSet({moon,
    dependencyConstruction: controlConstruction,
    ...(commandWorkspaces.length ? {commandWorkspaces: Object.freeze([...commandWorkspaces])} : {}),
    ...(publishedTargets === undefined ? {} : {publishedTargets}),
    onCommandKey(memberIndex, key) { commandKeys[memberIndex] = key; },
    checkedOwner: prepared, execution, inputs,
    maxMembers: members.length,
    // Membership, distinct keyed/target groups and dependency imports share
    // the existing finite Host structural-work ceiling. Result/member counts
    // bound inventory size, not the work of its cross-product comparisons.
    maxGroupingWork: limits.maxWork,
    limits: sourceLimits,
    store, maxBytes: plan.outputLimits.maxWireBytes, control,
    invocation: plan.invocation, retention: plan.effectInputRetention,
    ...(singular === undefined ? {memberSourceBindings: Object.freeze(members.map((member, memberIndex) =>
      Object.freeze({memberIndex, sourceBindingCid: cid({version: ownerOf(member).profile.source,
        run_invocation_cid: runInvocationCid, store_authority_cid: store.storeAuthorityCid})})))} : {
      sourceBindingCid: cid({version: singular.profile.source,
        run_invocation_cid: runInvocationCid, store_authority_cid: store.storeAuthorityCid})}),
    contractLimits: plan.contractLimits,
    localEvidenceContext: plan.localEvidenceContext,
    proposalLimits: {maxFields: limits.maxFields, maxWork: limits.maxWork,
      maxBytes: limits.body.maxBytes, maxNodes: limits.body.maxNodes,
      maxDepth: limits.body.maxDepth,
      maxUtf16Units: limits.body.maxBytes},
    onOriginalArtifact(artifact, memberIndex) {
      if (members[memberIndex]?.kind !== 'command') return;
      if (!contentArtifacts.includes(artifact)) contentArtifacts.push(artifact);
      // Retain before a Common/source callback can fail after the move.
      control.prepareEffectCommandContentArtifact(prepared, inputs,
        memberIndex, artifact, limits);
    },
    onProposalRow(memberIndex, rowIndex, proposal) {
      if (rowIndex !== proposals[memberIndex]?.length ||
          rowIndex >= limits.maxRowsPerMember || proposalCount >= limits.maxRows) {
        reject('InstalledRowEffectRowLimit');
      }
      proposalCount++;
      proposals[memberIndex].push(proposal);
    },
    signal});

  return {limits, controlConstruction, inputs, commandKeys, contentBorrowers, requestChildren, memberCaptures,
    proposals, currents, rowsOf, observations, publishedTargets, physicalOperations, retireRequestAliases,
    childrenPending, releaseInputs, sourceExport};
}
