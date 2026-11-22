import {invokeDeclaredRowUpdate} from '../host-common/owned-invocation-context.mjs';
import {captureClaimedEffectResponse} from './effect-physical-dispatch.mjs';

import type {ControlWork, prepareInstalledEffectControlConstruction} from './installed-effect-plan.mjs';
import type {InstalledEffectPlanRecipe} from './installed-effect-recipe.mjs';
import type {openEffectLedger} from './effect-ledger.mjs';
import type {EffectDispatchClaim} from './effect-physical-dispatch.mjs';
import type {createInstalledRowEffectApproval, createInstalledRowEffectCommit} from './installed-row-effect-commit.mjs';
import type {createInstalledRowEffectCapability, createInstalledRowEffectReadDecision,
  createInstalledRowEffectTargetAuthorization} from './installed-row-effect-authorization.mjs';
import type {createInstalledRowEffectPhysicalOperation, createInstalledRowEffectReadOperations} from './installed-row-effect-physical-read.mjs';

type Awaitable<Value> = Value | PromiseLike<Value>;
type Current = () => undefined;
type MemberRef = Readonly<{resource: string; memberIndex: number}> & (
  Readonly<{kind: 'command'; command: object}>
  | Readonly<{kind: 'create' | 'update' | 'upsert' | 'delete'; mapping: Readonly<{approval?: string}>}>);
type Entry = Readonly<{request: unknown; requestCid: string; value?: unknown; target: unknown}>;
type PreviewRow = Readonly<{
  row_preview_cid: string; before: Readonly<{state: string}>;
  target_row_identity?: unknown; intended_changes?: Readonly<{value?: unknown}>; after?: Readonly<{value?: unknown}>;
}>;
type ObservedPreflight = Readonly<{observedRows: readonly string[]}>;
type ClaimField = keyof EffectDispatchClaim;
type Ledger = ReturnType<typeof openEffectLedger>;
type RefusedClaim = Extract<ReturnType<Ledger['claimDispatch']>, {claimed: false}>;
type UpdateSlot = Parameters<typeof invokeDeclaredRowUpdate>[3] & Readonly<{operationIndex: number}>;
type UpdateDeclaration = Parameters<typeof invokeDeclaredRowUpdate>[0];
type CredentialInvocation = Parameters<typeof invokeDeclaredRowUpdate>[1];
type ReadAuthorization<Member extends MemberRef> = ReturnType<typeof createInstalledRowEffectTargetAuthorization<Member>>;
type TargetRead<Member extends MemberRef> = Awaited<ReturnType<ReadAuthorization<Member>>>;
type ReadPorts<Member extends MemberRef> = ReturnType<typeof createInstalledRowEffectReadOperations<Member>>;
type CommitPorts<Member extends MemberRef> = ReturnType<typeof createInstalledRowEffectCommit<Member>>;
type CapabilityPorts<Member extends MemberRef> = ReturnType<typeof createInstalledRowEffectCapability<Member>>;
type Grant = Readonly<Record<string, unknown> & {then?: never}>;
type GrantFacts = Readonly<{
  operation: string; decision: unknown; resource: string; runInvocationCid: string; dispatchRequestCid: string;
}>;
type Site = Readonly<{
  credential?: unknown; callResource?: unknown;
  issueReadGrant(facts: GrantFacts & Readonly<{maxUses: number}>): Grant;
  issueEffectGrant(facts: GrantFacts & Readonly<{subjectCid: string}>): Grant;
}>;
type Hook = Readonly<{resource: string; operation: string; receiver: object; request: (...args: never[]) => unknown}>;
type GrantControl = ControlWork & Partial<Pick<ReturnType<typeof prepareInstalledEffectControlConstruction>, 'grant'>>;
type Physical = Readonly<{observation?: Readonly<{useCid?: unknown; statusCode?: unknown; body?: unknown}>; headers?: unknown}>;
type Projection = Readonly<{kind?: string; providerEvidence?: unknown; outcome?: Readonly<{state?: string}>}>;
type Driver = Readonly<{
  writeOperation?(member: unknown): unknown;
  operation?: unknown;
  recheckRequests?(facts: object): Awaitable<unknown>;
  send(facts: object): Awaitable<Physical>;
}> & Partial<UpdateDeclaration>;
type Owner = Readonly<{
  installed: readonly object[]; installedCommands: readonly object[]; owned: Driver; site: Site;
  beforeSendCheck?: Hook; responseConfirmation?: Hook; updateWriteSlot?: UpdateSlot;
}>;
type PhysicalOperation<Member extends MemberRef> = (
  facts: Parameters<ReturnType<typeof createInstalledRowEffectPhysicalOperation<Member>>>[0],
) => unknown;
type RouteInput<Member extends MemberRef> = Readonly<{
  members: readonly Member[]; entries: readonly (readonly Entry[])[] | undefined;
  previewRows: readonly (readonly PreviewRow[])[] | undefined; runInvocationCid: string; dispatches: readonly string[];
  subjectCid: string; applyPreview: unknown; ledger: Ledger;
  targetReads?: Parameters<ReadAuthorization<Member>>[0]['targetReads']; assertCurrent?: Current;
  dispatchIndexes: readonly (readonly number[])[]; physicalOperations?: PhysicalOperation<Member>;
  controlConstruction?: GrantControl; operationPhase?: string;
}>;
type ConfirmationInput = Readonly<{
  memberIndex: number; rowIndex: number; projected: Projection | undefined; current: unknown; signal?: AbortSignal;
}>;
type DispatchBinding<Member extends MemberRef> = Readonly<{
  members: readonly Readonly<{claims: readonly EffectDispatchClaim[]}>[];
  subjectCid: string; signal?: AbortSignal; decisions: Parameters<CommitPorts<Member>['commitDecisions']>[0];
}>;
type DispatchInput = Readonly<{memberIndex: number; rowIndex: number; claim: EffectDispatchClaim; currentPreflight: object}>;
type RouteControls<Member extends MemberRef> = Readonly<{
  recipeOf(member: Member): InstalledEffectPlanRecipe | undefined;
  ownerOf(member: Member): Owner;
  fail(code: string, cause?: unknown): never;
  guarded(kind: Member['kind']): boolean;
  decideTargetRead: ReadAuthorization<Member>;
  resourceFields(member: Member): Readonly<{runOriginal?: object}>;
  readDecision: ReturnType<typeof createInstalledRowEffectReadDecision<Member>>;
  requireApproval: ReturnType<typeof createInstalledRowEffectApproval>;
  installedEffectWriteOperation(owned: Driver, member: Member, updateWriteSlot: UpdateSlot | undefined): unknown;
  projectOwnedResponse(member: Member, facts: object, controlConstruction: GrantControl | undefined): Projection | undefined;
}> & ReadPorts<Member> & CommitPorts<Member> & CapabilityPorts<Member>;

export function createInstalledRowEffectPhysicalRoute<Member extends MemberRef>({
  recipeOf, ownerOf, fail, guarded, decideTargetRead, describeMember, resourceFields, checkRows,
  observeRows, admitCapability, routeOf, readDecision, commitDecisions, requireApproval, scopeKey,
  admitRow, installedEffectWriteOperation, projectOwnedResponse, settle,
}: RouteControls<Member>) {
  const reject: RouteControls<Member>['fail'] = fail;
  // Current use and physical dispatch over one set of members. `entries`
  // and `previewRows` are each member's rows in the approved Preview's order.
  const physicalRoute = ({members, entries, previewRows, runInvocationCid,
    dispatches, subjectCid, applyPreview, ledger, targetReads, assertCurrent,
    dispatchIndexes, physicalOperations, controlConstruction, operationPhase = 'apply'}: RouteInput<Member>) => {
    // A saved route cannot borrow the fresh capture's parent merely from its
    // recipe or CID. The recovery owner must supply its actual retainer first.
    if (typeof physicalOperations !== 'function' && members.some(member =>
      (recipeOf(member)?.credentialOperations !== undefined ||
        recipeOf(member)?.physicalWrite !== undefined))) {
      reject('InstalledEffectPhysicalPlanUnavailable');
    }
    // Once the durable claim exists, selection drift does not establish an
    // unsent outcome. Preserve the claim and any retained response for recovery.
    const assertClaimedCurrent: Current = () => {
      try { assertCurrent?.(); }
      catch (error) { reject('InstalledRowEffectSelectionChangedAfterClaim', error); }
    };
    // Every apply carries its exact returned refresh into dispatch. A later
    // refresh may finish before this one is sent; equal capability DATA does
    // not substitute that later Catalog for this original current observation.
    let currentsByPreflight = new WeakMap<object, readonly unknown[]>();
    let hasRefreshed = false, closing = false, active = 0;
    const requireOpen = () => { if (closing) reject('InstalledRowEffectRouteRetired'); };
    const retire = () => {
      closing = true;
      if (active !== 0) return false;
      // SAME route/closure inventory. A fulfilled prepare did not sever these
      // aliases, and an active refresh/send still owns its original locals.
      currentsByPreflight = new WeakMap<object, readonly unknown[]>();
      entries = undefined;
      previewRows = undefined;
      return true;
    };
    const current = async <Preflight extends ObservedPreflight>({signal, preflight}:
      Readonly<{signal?: AbortSignal; preflight: Preflight}>) => {
      requireOpen();
      active++;
      try {
        assertCurrent?.();
        if (preflight === null || typeof preflight !== 'object') {
          reject('InvalidInstalledRowEffectRoute');
        }
        for (const member of members) {
          const {installed, installedCommands} = ownerOf(member);
          const available = member.kind === 'command'
            ? installedCommands.includes(member.command) : installed.includes(member.mapping);
          if (!available) {
            reject('InstalledRowEffectMappingNotInstalled');
          }
        }
        // Every read is decided before this refresh's provider I/O.
        const reads: (TargetRead<Member> | undefined)[] = [];
        for (const [index, member] of members.entries()) {
          reads.push(!guarded(member.kind) ? undefined :
            await decideTargetRead({member, runInvocationCid,
              dispatchRequestCid: dispatches[index], subjectCid, signal,
              targetReads, assertCurrent, controlConstruction}));
          assertCurrent?.();
        }
        const fresh: unknown[] = [];
        for (const [index, member] of members.entries()) {
          const {owned} = ownerOf(member);
          assertCurrent?.();
          const description = await describeMember({member, maxRows: entries![index].length, runInvocationCid,
            dispatchRequestCid: dispatches[index], label: `apply-${index}`,
            approval: reads[index]?.approval, signal, assertCurrent, physicalOperations, operationPhase, controlConstruction});
          assertCurrent?.();
          await owned.recheckRequests?.({member, entries: entries![index],
            current: description, controlConstruction, ...resourceFields(member)});
          assertCurrent?.();
          fresh.push(description);
        }
        await checkRows({members, entries: entries!, runInvocationCid, dispatches,
          subjectOf: () => subjectCid, signal, assertCurrent, physicalOperations, controlConstruction, operationPhase});
        assertCurrent?.();
        const currentVersions = new Map<string, string | undefined>();
        for (const [index, member] of members.entries()) {
          if (!guarded(member.kind)) continue;
          const observed = await observeRows({member, entries: entries![index],
            current: fresh[index], read: reads[index]!, signal, assertCurrent, physicalOperations, operationPhase,
            runInvocationCid, dispatchRequestCid: dispatches[index]});
          assertCurrent?.();
          for (const [rowIndex, row] of observed.entries()) {
            const original = previewRows![index][rowIndex];
            if ((row.state === 'absent') !== (original.before.state === 'absent')) {
              // A fresh read cannot switch a sealed creation into an update, or
              // a sealed update into creation. Nothing has been claimed/sent.
              reject('InstalledRowEffectTargetPresenceChanged');
            }
            if (row.state !== 'absent') currentVersions.set(original.row_preview_cid, row.versionCid);
          }
        }
        const capabilities = members.map((member, index) => admitCapability(
          member, entries![index], fresh[index], runInvocationCid,
          dispatches[index], controlConstruction));
        signal?.throwIfAborted();
        assertCurrent?.();
        if (currentVersions.size !== preflight.observedRows.length) reject('ForeignInstalledRowEffectObservation');
        const refreshed = Object.freeze({...preflight,
          guardVersions: Object.freeze(preflight.observedRows.map(row => {
            if (!currentVersions.has(row)) reject('ForeignInstalledRowEffectObservation');
            return currentVersions.get(row);
          })),
          capabilities: Object.freeze(capabilities.map(value => value.identity)),
          routes: Object.freeze(capabilities.map(routeOf))});
        currentsByPreflight.set(refreshed, Object.freeze(fresh));
        hasRefreshed = true;
        return refreshed;
      } finally { active--; }
    };
    const confirmResponse = async ({memberIndex, rowIndex, projected, current: description, signal}: ConfirmationInput) => {
      const member = members[memberIndex];
      if (member === undefined) reject('InvalidInstalledRowEffectConfirmation');
      const {site, responseConfirmation} = ownerOf(member);
      if (responseConfirmation === undefined || projected?.kind !== 'provider-response' ||
          projected.providerEvidence === undefined) return projected;
      requireOpen();
      active++;
      try {
        const sourceIndex = dispatchIndexes[memberIndex]?.[rowIndex];
        const entry = entries![memberIndex]?.[sourceIndex!];
        if (entry === undefined || !['apply', 'resume'].includes(operationPhase) ||
            typeof physicalOperations !== 'function') reject('InstalledEffectConfirmationPlanUnavailable');
        signal?.throwIfAborted();
        assertClaimedCurrent();
        // Effect approval/current cannot stand in for this separately scoped
        // read. Keep the original request/dispatch and already captured reply.
        const decision = await readDecision(member, responseConfirmation.resource,
          subjectCid, signal, assertClaimedCurrent);
        assertClaimedCurrent();
        const facts = {operation: responseConfirmation.operation, decision,
          resource: responseConfirmation.resource, runInvocationCid,
          dispatchRequestCid: dispatches[memberIndex], maxUses: 1};
        const originalAuthorization = controlConstruction === undefined ? site.issueReadGrant(facts)
          : (controlConstruction.grant ?? controlConstruction)(site, site.issueReadGrant, [facts]);
        assertClaimedCurrent();
        const confirmed = await physicalOperations({member, rowIndex: sourceIndex!,
          phase: `${operationPhase}-confirm`, operation: responseConfirmation.operation,
          site, originalAuthorization,
          useId: `${dispatches[memberIndex]}-${operationPhase}-confirm-${subjectCid}-${rowIndex}`,
          resource: responseConfirmation.resource, purpose: 'read', runInvocationCid,
          dispatchRequestCid: dispatches[memberIndex], assertCurrent: assertClaimedCurrent, signal,
          invoke: (context: unknown) => Reflect.apply(responseConfirmation.request, responseConfirmation.receiver,
            [{member, request: entry.request, current: description, ...context as object,
              providerEvidence: projected.providerEvidence, signal, controlConstruction}])});
        assertClaimedCurrent();
        signal?.throwIfAborted();
        return confirmed === undefined ? projected : confirmed as Projection;
      } finally {active--;}
    };
    const bindDispatch = ({members: claims, subjectCid: activeSubject, signal,
      decisions}: DispatchBinding<Member>) => {
      requireOpen();
      assertCurrent?.();
      if (activeSubject !== subjectCid || !hasRefreshed) {
        reject('InvalidInstalledRowEffectRoute');
      }
      const commits = commitDecisions(decisions, subjectCid, members);
      return async ({memberIndex, rowIndex, claim, currentPreflight}: DispatchInput) => {
        requireOpen();
        active++;
        try {
          assertCurrent?.();
          const now = currentsByPreflight.get(currentPreflight);
          if (now === undefined) reject('InvalidInstalledRowEffectRoute');
          const member = members[memberIndex];
          const sourceIndex = dispatchIndexes[memberIndex]?.[rowIndex];
          const entry = entries![memberIndex]?.[sourceIndex!];
          const expected = claims[memberIndex]?.claims[rowIndex];
          if (member === undefined || entry === undefined || !claim ||
              !expected || (['scope', 'locator', 'key', 'basis',
                'intentFingerprintCid', 'canonicalRequestCid'] as ClaimField[]).some(field =>
                expected[field] === undefined ||
                expected[field] !== claim[field])) {
            reject('InvalidInstalledRowEffectDispatch');
          }
          const {owned, site, beforeSendCheck, updateWriteSlot} = ownerOf(member);
          const managedPlanRecipe = recipeOf(member);
          signal?.throwIfAborted();
          requireApproval(member, commits.get(scopeKey(member)));
          const ownedClaim = admitRow({applyPreview, memberIndex, rowIndex,
            claim, member, entry,
            previewRow: previewRows![memberIndex][sourceIndex!]});
          await owned.recheckRequests?.({member, entries: [entry],
            current: now[memberIndex], controlConstruction, ...resourceFields(member)});
          assertCurrent?.();
          const grantFacts = {operation: installedEffectWriteOperation(owned, member, updateWriteSlot) as string,
            decision: commits.get(scopeKey(member)), resource: member.resource,
            runInvocationCid, dispatchRequestCid: dispatches[memberIndex], subjectCid};
          const grantConstructor = managedPlanRecipe?.grantConstruction;
          const grant = controlConstruction === undefined ? site.issueEffectGrant(grantFacts)
            : grantConstructor !== undefined && grantConstructor.receiver === site &&
                grantConstructor.method === site.issueEffectGrant
              ? controlConstruction(site, grantConstructor.method as Site['issueEffectGrant'], [grantFacts], grantConstructor.capacity)
              : (controlConstruction.grant ?? controlConstruction)(site, site.issueEffectGrant, [grantFacts]);
          const captured = await captureClaimedEffectResponse<Physical, ReturnType<Ledger['recordResponse']>['response'], never>({ledger,
            claim: ownedClaim, requestCid: entry.requestCid,
            execute: () => {
              assertClaimedCurrent();
              const useId = `${dispatches[memberIndex]}-write-${subjectCid}-${rowIndex}`;
              if (managedPlanRecipe?.physicalWrite !== undefined) {
                if (typeof physicalOperations !== 'function') reject('InstalledEffectPhysicalPlanUnavailable');
                return physicalOperations({member, rowIndex: sourceIndex!, phase: 'write',
                  operation: installedEffectWriteOperation(owned, member, updateWriteSlot) as string, assertCurrent: assertClaimedCurrent, signal,
                  invoke: (physicalOperation: unknown) => owned.send({member, request: entry.request, current: now[memberIndex],
                    authorization: {...grant, useId}, credential: site.credential, signal, physicalOperation,
                    ...resourceFields(member)})}) as Awaitable<Physical>;
              }
              if (managedPlanRecipe?.credentialOperations !== undefined) {
                if (typeof physicalOperations !== 'function') reject('InstalledEffectPhysicalPlanUnavailable');
                const send = () => physicalOperations({member, rowIndex: sourceIndex!, phase: 'write',
                  operation: installedEffectWriteOperation(owned, member, updateWriteSlot) as string, site, originalAuthorization: grant, useId,
                  resource: member.resource, purpose: 'effect', runInvocationCid,
                  dispatchRequestCid: dispatches[memberIndex], assertCurrent: assertClaimedCurrent, signal,
                  invoke: ({authorization, credential, callResource}: CredentialInvocation) => {
                    const invocation = {member, request: entry.request, current: now[memberIndex],
                      authorization, credential, callResource, signal, ...resourceFields(member)};
                    return updateWriteSlot === undefined ? owned.send(invocation)
                      : invokeDeclaredRowUpdate(owned as UpdateDeclaration, invocation,
                        managedPlanRecipe.rowOperations[updateWriteSlot.operationIndex].operation, updateWriteSlot);
                  }}) as Awaitable<Physical>;
                if (beforeSendCheck === undefined) return send();
                return (async () => {
                  // The SAME durable dispatch already owns this possible send.
                  // A fresh acquisition decision is still required for Form
                  // access; effect commit cannot stand in for a read grant.
                  const decision = await readDecision(member, beforeSendCheck.resource,
                    subjectCid, signal, assertClaimedCurrent);
                  assertClaimedCurrent();
                  const checkGrantFacts = {operation: beforeSendCheck.operation,
                    decision, resource: beforeSendCheck.resource, runInvocationCid,
                    dispatchRequestCid: dispatches[memberIndex], maxUses: 1};
                  const originalAuthorization = controlConstruction === undefined ? site.issueReadGrant(checkGrantFacts)
                    : (controlConstruction.grant ?? controlConstruction)(site, site.issueReadGrant, [checkGrantFacts]);
                  await physicalOperations({member, rowIndex: sourceIndex!, phase: 'write-check',
                    operation: beforeSendCheck.operation, site, originalAuthorization,
                    useId: `${dispatches[memberIndex]}-write-check-${subjectCid}-${rowIndex}`,
                    resource: beforeSendCheck.resource, purpose: 'read', runInvocationCid,
                    dispatchRequestCid: dispatches[memberIndex], assertCurrent: assertClaimedCurrent, signal,
                    invoke: (context: unknown) => Reflect.apply(beforeSendCheck.request, beforeSendCheck.receiver,
                      [{member, request: entry.request, ...context as object, signal, controlConstruction}])});
                  assertClaimedCurrent();
                  return send();
                })();
              }
              return owned.send({member, request: entry.request, current: now[memberIndex],
                authorization: {...grant, useId}, credential: site.credential,
                callResource: site.callResource, signal, ...resourceFields(member)});
            }});
          assertClaimedCurrent();
          if (!captured.claimed) {
            return Object.freeze({claimed: false,
              ownership: Object.freeze({action: (captured.ownership as RefusedClaim).action})});
          }
          const projectionFacts = {member, memberIndex, rowIndex,
            preview: applyPreview, request: entry.request, current: now[memberIndex],
            observation: captured.physical.observation, headers: captured.physical.headers};
          let projected = projectOwnedResponse(member, projectionFacts, controlConstruction);
          if (ownerOf(member).responseConfirmation !== undefined && projected?.kind === 'provider-response' &&
              projected.providerEvidence !== undefined) {
            projected = await confirmResponse({memberIndex, rowIndex, projected,
              current: now[memberIndex], signal});
          }
          const settled = settle({ledger, claim: ownedClaim, applyPreview,
            memberIndex, rowIndex, projected});
          return Object.freeze({claimed: true, physical: projected,
            ...(settled ?? {})});
        } finally { active--; }
      };
    };
    return {current, bindDispatch, confirmResponse, assertClaimedCurrent, retire};
  };

  return physicalRoute;
}
