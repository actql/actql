import {canonicalJson} from './local-account-config.mjs';

import type {effectApplicationControl} from '../host-common/effect-application-control.mjs';
import type {localContractLimits as defaultContractLimits} from './local-publication-limits.mjs';
import type {recoverProjectedEffectResponse} from './effect-response-recovery.mjs';
import type {EffectDispatchClaim} from './effect-physical-dispatch.mjs';
import type {openEffectLedger} from './effect-ledger.mjs';
import type {prepareInstalledEffectControlConstruction} from './installed-effect-plan.mjs';
import type {createInstalledRowEffectRecoveryBacking, createInstalledRowEffectRecoveredMembers} from './installed-row-effect-recovery-backing.mjs';
import type {createInstalledRowEffectClaims} from './installed-row-effect-claims.mjs';
import type {createInstalledRowEffectPreviewContext} from './installed-row-effect-preview.mjs';
import type {createInstalledRowEffectRunControls} from './installed-row-effect-run-controls.mjs';
import type {createInstalledRowEffectCommit} from './installed-row-effect-commit.mjs';
import type {createInstalledRowEffectPhysicalRoute} from './installed-row-effect-physical-route.mjs';
import type {createInstalledRowEffectCapability} from './installed-row-effect-authorization.mjs';
import type {createInstalledRowEffectPhysicalOperation} from './installed-row-effect-physical-read.mjs';

type Ledger = ReturnType<typeof openEffectLedger>;
type Effect = ReturnType<typeof effectApplicationControl>;
type Construction = ReturnType<typeof prepareInstalledEffectControlConstruction>;
type CloseOwner = Readonly<{close(): Promise<boolean>; cleanup(): Promise<boolean>; cleanupPending(): boolean}>;
type RouteOptions<Member extends MemberRef> = Parameters<ReturnType<typeof createInstalledRowEffectPhysicalRoute<Member>>>[0];
type Route<Member extends MemberRef> = ReturnType<ReturnType<typeof createInstalledRowEffectPhysicalRoute<Member>>>;
type MemberRef = RouteOptionsOfAnyMember['members'][number] & Readonly<{effectId: string}>;
type RouteOptionsOfAnyMember = Parameters<ReturnType<typeof createInstalledRowEffectPhysicalRoute>>[0];
type ReadProjection = Parameters<Route<MemberRef>['confirmResponse']>[0]['projected'];
type StoredObservation = Pick<NonNullable<ReturnType<Ledger['readClaimedResponse']>>,
  'credentialUseCid' | 'statusCode' | 'responseBytes'>;
type RecoveryPort<Member extends MemberRef> = ReturnType<typeof createInstalledRowEffectRecoveryBacking<Member>>;
type BackingInput<Member extends MemberRef> = Parameters<RecoveryPort<Member>>[0];
type PhysicalFacts<Member extends MemberRef> = Parameters<NonNullable<RouteOptions<Member>['physicalOperations']>>[0];
type CredentialPort<Member extends MemberRef> = ReturnType<typeof createInstalledRowEffectPhysicalOperation<Member>>;
type Prepared<Member extends MemberRef> = ReturnType<RecoveryPort<Member>>;
type RecoveredEntries<Member extends MemberRef> = Prepared<Member> & Readonly<{entries: NonNullable<RouteOptions<Member>['entries']>}>;
type NativeRun = NonNullable<BackingInput<MemberRef>['managedEffect']>;
type CredentialRun = NonNullable<Parameters<CredentialPort<MemberRef>>[0]['managedEffect']>;
type ManagedRun<Member extends MemberRef> = NonNullable<BackingInput<Member>['managedEffect']> &
  NonNullable<Parameters<CredentialPort<Member>>[0]['managedEffect']> & Readonly<{
    runtime: Runtime;
    controlConstruction: Construction;
    definitionOriginal: Readonly<{definition: unknown; allowed: unknown}>;
  }>;
type Selection = Parameters<ReturnType<typeof createInstalledRowEffectRunControls>['selectionFence']>[3];
type KeyLimits = Readonly<{maxBytes: number; maxNodes: number; maxDepth: number}>;
type PreviewLimits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type Limits = Readonly<{
  maxMembers: number; maxRows: number; maxWork: number; maxRowsPerMember: number; maxFields: number;
  maxFrontierWork: number; key: KeyLimits; preview: PreviewLimits;
}>;
type SavedBodyProjection = Parameters<ReturnType<typeof createInstalledRowEffectRecoveredMembers>>[0];
type PreflightProjection<Member> = ReturnType<typeof createInstalledRowEffectPreviewContext<Member & MemberRef, unknown>>;
type SavedEffect<Member extends MemberRef> = SavedBodyProjection['effects'][number] &
  Parameters<PreflightProjection<Member>['basePreflight']>[0]['effects'][number] &
  BackingInput<Member>['body']['effects'][number] & Readonly<{changes: NonNullable<RouteOptions<Member>['previewRows']>[number]}>;
type SavedBody<Member extends MemberRef> = Readonly<{
  effects: readonly SavedEffect<Member>[]; invocation_cid: string; run_identity_cid: string;
  authoring_context: Readonly<{authoring_context_cid: string}>;
}>;
type SavedMember = Parameters<ReturnType<typeof createInstalledRowEffectRecoveredMembers>>[1]['members'][number] &
  Readonly<{dispatch_request_cid: string}>;
type SavedProvider = Readonly<Record<string, unknown>> & Readonly<{
  version: string; stage_index?: number; program_id: string; stage_id: string; members: readonly SavedMember[];
  request: unknown; attempt?: Readonly<{externalIdempotencyKey?: unknown}>;
}>;
type Continuation = SavedProvider & Readonly<{provider?: SavedProvider}>;
type Durable = BackingInput<MemberRef>['durable'] & Readonly<{
  computation: unknown; preview: unknown; storedResults: unknown; invocation: unknown;
}>;
type Submitted = Readonly<{intent: unknown; assertCurrent(): unknown}>;
type Recovered = Readonly<{
  requestIdentity: unknown; requestScope: unknown; computation: Durable; runDefinition?: Readonly<{identity: unknown}>;
  originalSubmittedIntent?: Submitted; materials?: unknown;
}>;
type Keys = readonly (readonly unknown[])[];
type RecoveryControl = Parameters<Construction['retainRecoveredInputs']>[0] & Readonly<{
  effectComputationPreviewWire(preview: unknown): string;
  effectComputationPreviewLedgerIdentity(preview: unknown): unknown;
  effectComputationPreviewSemanticCid(preview: unknown): string;
  recoverInstalledEffectPreviewKeys(value: unknown, prepared: unknown, request: unknown, plan: unknown, allowed: unknown,
    definition: unknown, invocation: unknown, preview: unknown, scope: unknown, maxMembers: number, maxRows: number,
    maxWork: number, maxKeyBytes: number, maxKeyNodes: number, maxKeyDepth: number, construction: Construction): Keys;
  restoreRequestedEffectStop(submitted: Submitted, identity: unknown, materials: unknown, invocation: unknown,
    preview: unknown, limits: unknown): unknown;
}>;
type Runtime = (NativeRun & CredentialRun)['runtime'] & Readonly<{
  clientRequestRelation?(request: unknown, identity: unknown): number;
  strategyPublicationContractIdentity?(definition: unknown): string;
  clientSubmittedIntentRequestsCommitStop(intent: unknown): boolean;
  clientProgramEffectPreviewInputLimits(...limits: number[]): unknown;
}>;
type Facts<Member extends MemberRef> = Readonly<{
  moon: Runtime; control: RecoveryControl; store: unknown; recovered: Recovered; continuation: Continuation;
  signal?: AbortSignal; retainRecoveryOwner?(owner: CloseOwner): void;
  targetReads?: RouteOptions<Member>['targetReads']; managedEffect?: ManagedRun<Member>; updateTargetSelections?: Selection;
  contentRun?: unknown; principalId?: string;
}>;
type ContentChild = Readonly<{
  prepare(): unknown; release(): unknown; status(): Readonly<{pending: boolean}>;
}>;
type RecoveryRequestChild = BackingInput<MemberRef>['requestChildren'][number] &
  {prepared: Readonly<{retry(): unknown; release(): unknown; status(): Readonly<{pending: boolean}>}>; recoveryReleaseAttempted?: boolean};
type Owner = Readonly<{
  authorization?: unknown;
  profile?: Readonly<{continuation: string; continuationBinding: string}>;
  continuationBinding?: unknown;
  responseConfirmation?: unknown;
  owned: Readonly<{finalizeRequest?: unknown; prepareRecoveredContentChild?(facts: object): ContentChild}>;
}>;
type ReconcileFacts = Readonly<{
  members: readonly Readonly<{claims: readonly EffectDispatchClaim[]}>[]; preview: unknown; signal?: AbortSignal;
}>;
type RecoveryOptions<Member extends MemberRef, Installation extends Owner> = Readonly<{
  moon: Runtime; localContractLimits: typeof defaultContractLimits; ROUTING_VERSION: string;
  singular?: Installation & Readonly<{profile: NonNullable<Owner['profile']>}>;
  owners: readonly Installation[];
  ownerOf(member: Member): Installation;
  text(value: unknown): value is string;
  selectionChanged(): never;
  runLimits(managed: ManagedRun<Member> | undefined): Limits;
  recoveredMembers(body: SavedBody<Member>, provider: SavedProvider, selected: boolean, maxMembers: number): readonly Member[];
  bindRunResources(facts: Facts<Member>, members: readonly Member[]): void;
  selectionFence(facts: Facts<Member>, members: readonly Member[], stageIndex: number | undefined,
    selections?: Selection): RouteOptions<Member>['assertCurrent'];
  memberDispatch(runInvocationCid: string, member: Member): string;
  effect: Pick<Effect, 'recoveredPreviewKeys' | 'admitPreviewIdentity' | 'dispatchKeyCid'>;
  openLedger(identity: unknown, construction: Construction | undefined): Ledger;
  prepareCredentialOperation: CredentialPort<Member>;
  prepareRecoveredEntries: RecoveryPort<Member>;
  admitCapability: ReturnType<typeof createInstalledRowEffectCapability<Member>>['admitCapability'];
  orderedSourceIndexes: ReturnType<typeof createInstalledRowEffectClaims>['orderedSourceIndexes'];
  physicalRoute: ReturnType<typeof createInstalledRowEffectPhysicalRoute<Member>>;
  admitRow: ReturnType<typeof createInstalledRowEffectCommit<Member>>['admitRow'];
  projectOwnedResponse(member: Member, facts: object, construction: Construction | undefined): ReadProjection;
  recoverProjectedEffectResponse: typeof recoverProjectedEffectResponse;
  settle: ReturnType<typeof createInstalledRowEffectCommit<Member>>['settle'];
  basePreflight: PreflightProjection<Member>['basePreflight'];
  scopes(members: readonly Member[]): unknown;
  resourceFields(member: Member): Readonly<{runOriginal?: object}>;
  fail(code: string, cause?: unknown): never;
}>;

export function createInstalledRowEffectRecovery<Member extends MemberRef, Installation extends Owner>({
  moon, localContractLimits, ROUTING_VERSION, singular, owners, ownerOf, text, selectionChanged, runLimits,
  recoveredMembers, bindRunResources, selectionFence, memberDispatch, effect, openLedger, prepareCredentialOperation,
  prepareRecoveredEntries, admitCapability, orderedSourceIndexes, physicalRoute, admitRow, projectOwnedResponse,
  recoverProjectedEffectResponse, settle, basePreflight, scopes, resourceFields, fail,
}: RecoveryOptions<Member, Installation>) {
  const reject: RecoveryOptions<Member, Installation>['fail'] = fail;

  function prepareRecovered(facts: Facts<Member>) {
    const {moon: runMoon, control, store, recovered, continuation, signal,
      retainRecoveryOwner, targetReads, managedEffect} = facts ?? {};
    if (runMoon !== moon || !recovered?.computation || !continuation) {
      reject('InvalidInstalledEffectRecovery');
    }
    signal?.throwIfAborted();
    const contractLimits = localContractLimits;
    const provider = continuation.provider ?? continuation;
    // The legacy singular continuation records, but does not compare, its binding:
    // a republished installation resumes only if every Mapping remains and
    // it issues/adopts the Preview's capability (both checked below). The
    // initial composed profile additionally checks exact installation facts
    // in recoveredMembers. Selected updates require the exact retained owner
    // and stage even for a singular installation.
    if (provider?.version !== (singular?.profile.continuation ?? ROUTING_VERSION) ||
        (singular !== undefined && !text(provider[singular.profile.continuationBinding])) ||
        !Array.isArray(provider.members) || !text(provider.program_id) ||
        !text(provider.stage_id)) {
      reject('InstalledEffectContinuationMismatch');
    }
    const updateTargetSelections = facts.updateTargetSelections;
    const selected = updateTargetSelections !== undefined;
    if (!selected && Object.hasOwn(provider, 'stage_index')) selectionChanged();
    if (selected && (!Number.isSafeInteger(provider.stage_index) ||
        provider.stage_index! < 0 || (singular !== undefined &&
        provider[singular.profile.continuationBinding] !== singular.continuationBinding))) {
      selectionChanged();
    }
    const {requestIdentity, requestScope, computation: durable} = recovered;
    const {computation, preview, storedResults} = durable;
    const previewWire = control.effectComputationPreviewWire(preview);
    const body = (managedEffect === undefined ? JSON.parse(previewWire)
      : managedEffect.controlConstruction.parsePreview(previewWire, true)) as SavedBody<Member>;
    const limits = runLimits(managedEffect);
    const members = recoveredMembers(body, provider, selected, limits.maxMembers);
    bindRunResources(facts, members);
    const assertCurrent = selectionFence(facts, members, provider.stage_index, updateTargetSelections);
    const runInvocationCid = body.invocation_cid;
    const dispatches = members.map(member =>
      memberDispatch(runInvocationCid, member));
    if (dispatches.some((dispatch, index) =>
      dispatch !== provider.members[index].dispatch_request_cid)) {
      reject('InstalledEffectContinuationMismatch');
    }
    const controlConstruction = managedEffect?.controlConstruction;
    if (managedEffect !== undefined && typeof controlConstruction !== 'function') reject('InstalledEffectControlRuntimeUnavailable');
    const managedPrepared = managedEffect?.prepared, managedRequest = managedEffect?.request;
    if (managedEffect !== undefined) {
      if (typeof retainRecoveryOwner !== 'function') reject('InstalledEffectRecoveryCustodyRequired');
      if (managedEffect.runtime !== moon || managedEffect.closed || managedPrepared === undefined ||
          typeof moon.clientRequestRelation !== 'function' ||
          moon.clientRequestRelation(managedRequest, requestIdentity) !== 1 ||
          managedEffect.definitionOriginal?.definition === undefined || recovered.runDefinition === undefined ||
          typeof moon.strategyPublicationContractIdentity !== 'function' ||
          moon.strategyPublicationContractIdentity(managedEffect.definitionOriginal.definition) !== recovered.runDefinition.identity) {
        reject('ForeignInstalledEffectManagedRun');
      }
      if (Object.hasOwn(managedEffect, 'failure')) throw managedEffect.failure;
      // The original admitted Preview, compiled Run and Request supply the
      // cold row inventory before recovered member request construction.
      // The existing synchronous control frame owns current/reentry/failure.
      controlConstruction!.retainRecoveredInputs(control,
        managedEffect.definitionOriginal.allowed, managedEffect.definitionOriginal.definition,
        durable.invocation, preview);
    }
    const admitted = control.effectComputationPreviewLedgerIdentity(preview);
    const keys = (managedEffect === undefined
      ? effect.recoveredPreviewKeys(admitted, requestScope,
        members.length, limits.maxRows, limits.maxWork, limits.key.maxBytes,
        limits.key.maxNodes, limits.key.maxDepth)
      : control.recoverInstalledEffectPreviewKeys(managedEffect.value, managedEffect.prepared,
        managedEffect.request, managedEffect.operationPlan, managedEffect.definitionOriginal.allowed,
        managedEffect.definitionOriginal.definition, durable.invocation, preview, requestScope,
        members.length, limits.maxRows, limits.maxWork, limits.key.maxBytes,
        limits.key.maxNodes, limits.key.maxDepth, controlConstruction!)) as Keys;
    let recoveredRows = 0, recoveredMemberRows = 0;
    for (const member of body.effects) {
      if (!Array.isArray(member.changes)) reject('InstalledEffectContinuationMismatch');
      recoveredRows += member.changes.length;
      recoveredMemberRows = Math.max(recoveredMemberRows, member.changes.length);
      if (member.changes.length > limits.maxRowsPerMember || recoveredRows > limits.maxRows) {
        reject('InstalledRowEffectRowLimit');
      }
    }
    // Run limits remain rejection ceilings. Ledger recovery consumes this
    // verified whole cohort; each native member constructor consumes only the
    // widest actual member. Neither receiver inherits the Run's policy size.
    const applyPreview = effect.admitPreviewIdentity(previewWire,
      body.run_identity_cid, body.authoring_context.authoring_context_cid,
      requestScope, keys, limits.preview.maxWireBytes,
      limits.preview.maxNodes, limits.preview.maxDepth);
    const submitted = recovered.originalSubmittedIntent;
    submitted?.assertCurrent();
    const requestedStop = submitted === undefined ||
      !moon.clientSubmittedIntentRequestsCommitStop(submitted.intent)
      ? undefined : control.restoreRequestedEffectStop(
      submitted, requestIdentity, recovered.materials, durable.invocation, preview,
      moon.clientProgramEffectPreviewInputLimits(
        limits.preview.maxWireBytes, limits.preview.maxNodes,
        limits.preview.maxDepth, limits.maxWork, limits.maxFields,
        limits.preview.maxWireBytes, limits.preview.maxNodes,
        limits.preview.maxDepth, members.length, limits.maxRows,
        limits.maxWork, limits.maxWork));
    const assertRequestedStopCurrent = () => {
      submitted?.assertCurrent();
      assertCurrent?.();
    };
    const ledger = openLedger(requestIdentity, controlConstruction);
    // The handle is released exactly once: it is marked released only after
    // its close succeeds, so a failed close stays this owner's pending
    // cleanup and a retry by the same owner closes it.
    let closed = false, closing = false, opening = true, reconciling = 0, cleanupFlight: Promise<boolean> | undefined;
    let entries: NonNullable<RouteOptions<Member>['entries']> | undefined, currents: readonly unknown[] | undefined,
      route: Route<Member> | undefined;
    const recoveryChildren: ContentChild[] = [], requestChildren: RecoveryRequestChild[] = [];
    const recoveryPending = () => recoveryChildren.some(child => child.status().pending !== false);
    const requestsPending = () => requestChildren.some(child => child.prepared.status().pending !== false);
    const retireRequestAliases = () => {
      if (opening || reconciling !== 0 || route !== undefined && !route.retire()) return false;
      entries = currents = undefined;
      return true;
    };
    const physicalOperations = managedEffect === undefined ? undefined : (operation: PhysicalFacts<Member>) => {
      if (closing || closed) reject('InstalledRowEffectRouteRetired');
      if (managedEffect.runtime !== moon || managedEffect.prepared !== managedPrepared ||
          managedEffect.request !== managedRequest || managedEffect.closed) reject('ForeignInstalledEffectManagedRun');
      if (Object.hasOwn(managedEffect, 'failure')) throw managedEffect.failure;
      const observeCurrent = operation.assertCurrent;
      return prepareCredentialOperation({...operation, managedEffect, requestChildren, retireRequestAliases,
        assertCurrent() {
          if (closing || closed) reject('InstalledRowEffectRouteRetired');
          observeCurrent!();
          if (closing || closed) reject('InstalledRowEffectRouteRetired');
        }});
    };
    const releaseLedger = () => {
      if (closed) return;
      ledger.close();
      closed = true;
    };
    const closeRecovery = () => {
      closing = true;
      if (closed) return Promise.resolve(true);
      if (opening) return Promise.resolve(false);
      // A child may await this Owner reentrantly. Report pending rather than
      // making that child await the flight which is itself awaiting the child.
      if (cleanupFlight !== undefined) return Promise.resolve(false);
      // Keep this same Owner/flight before any child method can reenter it.
      const flight = Promise.resolve().then(async () => {
        if (!retireRequestAliases()) return false;
        // The recovered Content child owns the original physical writer.
        // Let it acknowledge close before the operation token checks that
        // same writer; neither pending child may release the parent Ledger.
        for (const child of recoveryChildren) await child.release();
        for (const child of requestChildren) {
          const retry = child.recoveryReleaseAttempted === true;
          child.recoveryReleaseAttempted = true;
          await (retry ? child.prepared.retry() : child.prepared.release());
        }
        if (requestsPending() || recoveryPending()) return false;
        releaseLedger();
        return true;
      }).finally(() => {if (cleanupFlight === flight) cleanupFlight = undefined;});
      cleanupFlight = flight;
      return flight;
    };
    const ledgerOwner = Object.freeze({close: closeRecovery, cleanup: closeRecovery,
      cleanupPending: () => !closed || recoveryPending() || requestsPending()});
    if (retainRecoveryOwner !== undefined) {
      try { retainRecoveryOwner(ledgerOwner); }
      catch (error) { releaseLedger(); throw error; }
    }
    try {
      const recorded = ledger.recoverClaimFacts({preview: admitted,
        scope: requestScope, programId: provider.program_id,
        nodeId: provider.stage_id, maxRows: recoveredRows,
        maxWork: limits.maxWork}, keys);
      assertCurrent?.();
      ({entries, currents} = prepareRecoveredEntries({members, body, durable, maxRows: recoveredMemberRows,
        recorded, previewWire, runInvocationCid, dispatches,
        requestTags: keys.map((rows, index) => ownerOf(members[index]).owned.finalizeRequest === undefined
          ? undefined : rows.map(key => effect.dispatchKeyCid(key))), controlConstruction,
        managedEffect, requestChildren, retireRequestAliases, assertCurrent, signal}) as RecoveredEntries<Member>);
      assertCurrent?.();
      const finish = () => {
        if (closing) reject('InstalledRowEffectRouteRetired');
        // The installation as loaded now must issue and admit the same
        // capability the Preview carries, for the same requests, before any
        // provider I/O.
        members.forEach((member, index) => {
          let capability;
          try {
            capability = admitCapability(member, entries![index],
              currents![index], runInvocationCid, dispatches[index], controlConstruction);
          } catch (error) {
            reject('InstalledRowEffectInstallationChanged', error);
          }
          if (capability.identity !==
              body.effects[index].capability_evidence_cid) {
            reject('InstalledRowEffectInstallationChanged');
          }
        });
        const previewRows = body.effects.map(member => member.changes);
        const dispatchIndexes = body.effects.map(orderedSourceIndexes);
        if (closing) reject('InstalledRowEffectRouteRetired');
        route = physicalRoute({members, entries, previewRows, dispatchIndexes,
          runInvocationCid, dispatches,
          subjectCid: control.effectComputationPreviewSemanticCid(preview),
          applyPreview, ledger, targetReads, assertCurrent, physicalOperations, controlConstruction, operationPhase: 'resume'});
        const reconcileStoredResponses = async ({members: claims,
          preview: ledgerPreview, signal: recoverySignal = signal}: ReconcileFacts) => {
          if (closing || closed) reject('InstalledRowEffectRouteRetired');
          reconciling++;
          const assertRecoveredCurrent = () => {
            if (closing || closed) reject('InstalledRowEffectRouteRetired');
            route!.assertClaimedCurrent();
            if (closing || closed) reject('InstalledRowEffectRouteRetired');
          };
          try {
            assertRecoveredCurrent();
            for (const [memberIndex, member] of claims.entries()) {
              for (const [rowIndex, claim] of member.claims.entries()) {
                assertRecoveredCurrent();
                if (ledger.readClaimedResponse(claim) === undefined) continue;
                const sourceIndex = dispatchIndexes[memberIndex][rowIndex];
                const entry = entries![memberIndex][sourceIndex];
                const ownedClaim = admitRow({applyPreview: ledgerPreview,
                  memberIndex, rowIndex, claim, member: members[memberIndex],
                  entry, previewRow: previewRows[memberIndex][sourceIndex]});
                let retainedOutcome = false;
                const recovery = await recoverProjectedEffectResponse<StoredObservation, ReadProjection>({ledger,
                  claims: ownedClaim, commonMoon: moon,
                  expectedRequestCid: entry.requestCid,
                  authorizeEvidenceRead: async () => true,
                  projectStored: stored => {
                    assertRecoveredCurrent();
                    const {responseConfirmation} = ownerOf(members[memberIndex]);
                    // Presence alone is not a terminal fact. Reuse the
                    // existing complete receipt/current/history admission and
                    // original CAS continuation, never another provider read
                    // to replace an already recorded outcome or lost COMMIT.
                    if (responseConfirmation !== undefined && ledger.readClaimedOutcome(ownedClaim) !== undefined) {
                      ledger.commitAdmittedRowOutcome({claim: ownedClaim, preview: ledgerPreview,
                        memberIndex, previewRowIndex: rowIndex});
                      retainedOutcome = true;
                      return undefined;
                    }
                    const projectionFacts = {member: members[memberIndex], memberIndex, rowIndex,
                      preview: ledgerPreview, request: entry.request, current: currents![memberIndex],
                      observation: Object.freeze({useCid: stored.credentialUseCid,
                        statusCode: stored.statusCode, body: stored.responseBytes}), headers: undefined};
                    return projectOwnedResponse(members[memberIndex], projectionFacts, controlConstruction);
                  }});
                assertRecoveredCurrent();
                if (retainedOutcome) continue;
                let projected = recovery.recovered;
                if (ownerOf(members[memberIndex]).responseConfirmation !== undefined && projected?.kind === 'provider-response' &&
                    projected.providerEvidence !== undefined) {
                  projected = await route!.confirmResponse({memberIndex, rowIndex, projected,
                    current: currents![memberIndex], signal: recoverySignal});
                  assertRecoveredCurrent();
                }
                settle({ledger, claim: ownedClaim, applyPreview: ledgerPreview,
                  memberIndex, rowIndex, projected});
              }
            }
          } finally {reconciling--;}
        };
        return Object.freeze({preview, computation, storedResults,
          ...(requestedStop === undefined ? {} : {requestedStop, assertRequestedStopCurrent}),
          apply: {moon, store, publicationControl: control, computation,
            preview, ledger, requestScope, programId: provider.program_id,
            nodeId: provider.stage_id, maxRows: recoveredRows,
            maxFrontierWork: limits.maxFrontierWork,
            maxRecoveryWork: limits.maxWork,
            keyLimits: {...limits.key, maxWork: limits.maxWork},
            reconcileStoredResponses,
            refreshPreflight: ({signal: refreshSignal}: Readonly<{signal?: AbortSignal}> = {}) => route!.current({
              signal: refreshSignal, preflight: basePreflight({
                effects: body.effects, members, requestScope, limits})}),
            bindDispatch: route.bindDispatch,
            authorization: {gate: singular?.authorization, scopes: scopes(members)}},
          receipt: {ledger, preview: applyPreview, commonMoon: moon,
            publicationPreview: preview,
            authorizeEvidenceRead: async () => true,
            members: recorded.members.map(member => ({rowOwners:
              member.claims.map(claim => ({claim})), replayed: true})),
            limits: contractLimits},
          publication: {execution: null, store, storedResults, control,
            computation, preview, ledger, request: provider.request,
            attempt: {...provider.attempt, externalIdempotencyKey:
              provider.attempt?.externalIdempotencyKey}, contractLimits,
            now: () => new Date().toISOString()},
          scopes: scopes(members),
          continuationWire: canonicalJson(provider),
          cleanupOwner: ledgerOwner,
          dispose: closeRecovery});
      };
      for (const owner of owners) {
        if (owner.owned.prepareRecoveredContentChild === undefined) continue;
        if (typeof retainRecoveryOwner !== 'function') {
          reject('InstalledEffectRecoveryCustodyRequired');
        }
        const memberIndexes = Object.freeze(members.flatMap((member, index) =>
          ownerOf(member) === owner ? [index] : []));
        if (memberIndexes.length === 0) continue;
        const child = owner.owned.prepareRecoveredContentChild({
          recovered, members, entries, memberIndexes, control, store, signal,
          contentRun: facts.contentRun, principalId: facts.principalId,
          assertCurrent, limits, ...resourceFields(members[memberIndexes[0]]),
          managedContext: managedEffect});
        if (typeof child?.prepare !== 'function' || typeof child.release !== 'function' ||
            typeof child.status !== 'function') {
          reject('InvalidInstalledEffectRecoveryChild');
        }
        // The same already-retained ledger owner keeps every child before
        // current callbacks or the first awaited physical Store confirmation.
        recoveryChildren.push(child);
        assertCurrent?.();
      }
      if (recoveryChildren.length === 0) {
        const stage = finish();
        opening = false;
        return stage;
      }
      return (async () => {
        try {
          for (const child of recoveryChildren) {
            await child.prepare();
            signal?.throwIfAborted();
            assertCurrent?.();
          }
          return finish();
        } finally {opening = false;}
      })();
    } catch (error) {
      opening = false;
      if (retainRecoveryOwner === undefined) releaseLedger();
      throw error;
    }
  }

  return prepareRecovered;
}
