import {types as nodeTypes} from 'node:util';
import {withDeclaredUpdateTargetReads} from '../host-common/owned-invocation-context.mjs';
import {prepareInstalledEffectOwnedPhysicalChild} from './installed-effect-owned-operation.mjs';
import {prepareInstalledEffectOwnedRequestChild, selectInstalledEffectCredentialOperation} from './installed-effect-plan.mjs';
import type {ControlWork, prepareInstalledEffectControlConstruction, prepareInstalledEffectCredentialChild} from './installed-effect-plan.mjs';
import type {InstalledEffectPlanRecipe} from './installed-effect-recipe.mjs';
import type {prepareInstalledRowCaptureChild} from './installed-row-capture-cleanup.mjs';
import type {installedRowCredentialOperationSite} from './installed-row-source.mjs';
import type {createInstalledRowEffectDriverControls} from './installed-row-effect-driver.mjs';
import type {createInstalledRowEffectReadDecision} from './installed-row-effect-authorization.mjs';

type CredentialOptions = Parameters<typeof prepareInstalledEffectCredentialChild<unknown>>[0];
type OwnedPhysicalOptions = Parameters<typeof prepareInstalledEffectOwnedPhysicalChild<unknown>>[0];
type OwnedRequestOptions = Parameters<typeof prepareInstalledEffectOwnedRequestChild<unknown>>[0];
type Invocation = Parameters<CredentialOptions['invoke']>[0];
type InvocationInput = Parameters<Invocation['callResource']>[0];
type Run = CredentialOptions['run'] & OwnedPhysicalOptions['run'] & OwnedRequestOptions['run'];
type RetainedChildren = Parameters<typeof prepareInstalledRowCaptureChild<unknown>>[0]['children'];
type GrantControl = ControlWork & Partial<Pick<ReturnType<typeof prepareInstalledEffectControlConstruction>, 'grant'>>;
type DeclaredTargetOptions = Parameters<typeof withDeclaredUpdateTargetReads>[0];
type SynchronousResource = ReturnType<typeof createInstalledRowEffectDriverControls>['requireSynchronousEffectResource'];

type MemberRef = Readonly<{resource: string}>;
type PhysicalMember = MemberRef & Readonly<{memberIndex: number}>;
type StageMember = MemberRef & Readonly<{kind: string}>;
type Current = () => undefined;
type GrantView = Readonly<{grant?: unknown; useId?: string}>;
type Grant = Readonly<Record<string, unknown> & {then?: never}>;
type Site = Readonly<{credential?: unknown; callResource?: unknown}>;
type PhysicalFacts<Member> = Readonly<{
  member: Member;
  rowIndex: number;
  phase: string;
  operation: string;
  site?: Site;
  originalAuthorization?: unknown;
  useId?: string;
  resource?: string;
  purpose?: CredentialOptions['purpose'];
  invoke?: CredentialOptions['invoke'] | OwnedPhysicalOptions['invoke'];
  runInvocationCid?: string;
  dispatchRequestCid?: string;
  assertCurrent?: Current;
  signal?: AbortSignal;
  maxResponseBytes?: number;
  constructChild?: OwnedRequestOptions['constructChild'];
  credentialSlot?: string;
  responsePreparation?: CredentialOptions['responsePreparation'];
}>;
type OperationInput<Member> = PhysicalFacts<Member> & Readonly<{
  managedEffect?: Run;
  requestChildren?: RetainedChildren;
  retireRequestAliases?: () => boolean;
}>;
type PhysicalOperations<Member> = (facts: PhysicalFacts<Member>) => unknown;
type RecipeOf<Member> = (member: Member) => InstalledEffectPlanRecipe | undefined;
type PhysicalControls<Member> = Readonly<{
  moon: Readonly<{clientProgramInstalledEffectManagedPlanCaptureChildren?(plan: unknown): number}>;
  recipeOf: RecipeOf<Member>;
  fail(code: string): never;
  installedRowCredentialOperationSite: typeof installedRowCredentialOperationSite;
  prepareInstalledRowCaptureChild: typeof prepareInstalledRowCaptureChild;
  prepareInstalledEffectCredentialChild: typeof prepareInstalledEffectCredentialChild;
}>;
type ReadChildInput = GrantView & Readonly<{maxResponseBytes: number; operations?: unknown}>;
type ManagedReadInput<Member> = Readonly<{
  member: Member;
  phase: string;
  physicalOperations?: PhysicalOperations<Member>;
  runInvocationCid: string;
  dispatchRequestCid: string;
  assertCurrent?: Current;
  signal?: AbortSignal;
  originalTargetAuthorization?(authorization: GrantView | undefined, rowIndex: number): GrantView | undefined;
  accountTargetRead?: boolean;
}>;
type ReadChildControls<Member> = Readonly<{
  ownerOf(member: Member): Readonly<{site: Site}>;
  recipeOf: RecipeOf<Member>;
  requireSynchronousEffectResource: SynchronousResource;
  fail(code: string): never;
}>;
type ReadFacts = Readonly<{runInvocationCid: string; signal?: AbortSignal; assertCurrent?: Current}>;
type ReadOperationsFacts<Member> = ReadFacts & Readonly<{
  dispatchRequestCid: string;
  member: Member;
  physicalOperations?: PhysicalOperations<Member>;
  operationPhase: string;
}>;
type DescribeInput<Member> = ReadOperationsFacts<Member> & Readonly<{
  maxRows?: number; label: string; approval?: unknown; controlConstruction?: GrantControl;
}>;
type CheckInput<Member> = ReadFacts & Readonly<{
  members: readonly Member[];
  entries: readonly (readonly {request: unknown}[])[];
  dispatches: readonly string[];
  subjectOf(member: Member): string;
  physicalOperations?: PhysicalOperations<Member>;
  controlConstruction?: GrantControl;
  operationPhase?: string;
}>;
type ObserveInput<Member> = ReadOperationsFacts<Member> & Readonly<{
  entries: readonly {target: unknown}[];
  current: unknown;
  read: Readonly<{
    approval?: unknown;
    authorizationForRow: DeclaredTargetOptions['authorizationForRow'];
    consumeOriginal?: ManagedReadInput<Member>['originalTargetAuthorization'];
  }>;
}>;
type ObservedRow = Readonly<{identity?: unknown; state?: unknown; versionCid?: string; before?: unknown}>;
type ReadGrantFacts = Readonly<{
  operation: string; decision: unknown; resource: string; runInvocationCid: string; dispatchRequestCid: string; maxUses: number;
}>;
type CheckedSite = Site & Readonly<{issueReadGrant(facts: ReadGrantFacts): Grant}>;
type ReadOwner = Readonly<{
  owned: Readonly<{
    describe?(facts: object): unknown;
    check?: Readonly<{resource: string; operation: string}>;
    checkRequest?(facts: object): unknown;
    observeTargets?(facts: object): unknown;
    targetRead?: Readonly<{operation: string}>;
  }>;
  site: CheckedSite;
  updateWriteSlot?: unknown;
}>;
type ReadOperationsControls<Member extends StageMember> = Readonly<{
  ownerOf(member: Member): ReadOwner;
  recipeOf: RecipeOf<Member>;
  managedReadChild: ReturnType<typeof createInstalledRowEffectReadChild<Member>>;
  resourceFields(member: Member): Readonly<{runOriginal?: object}>;
  readDecision: ReturnType<typeof createInstalledRowEffectReadDecision<Member>>;
  sameValue(left: unknown, right: unknown): boolean;
  cidPattern: RegExp;
  fail(code: string): never;
}>;

export function createInstalledRowEffectPhysicalOperation<Member extends PhysicalMember>({
  moon, recipeOf, fail, installedRowCredentialOperationSite, prepareInstalledRowCaptureChild, prepareInstalledEffectCredentialChild,
}: PhysicalControls<Member>) {
  const reject: PhysicalControls<Member>['fail'] = fail;
  // This is the same capture retainer and original Run/Plan, including its
  // failed child prefix. The implementation recipe selects a DISTINCT native
  // occurrence for each phase; equal operation names do not share a slot.
  const prepareCredentialOperation = async ({member, rowIndex, phase, operation,
    site, originalAuthorization, useId, resource, purpose, invoke,
    managedEffect, requestChildren, retireRequestAliases, runInvocationCid,
    dispatchRequestCid, assertCurrent, signal, maxResponseBytes, constructChild, credentialSlot, responsePreparation}: OperationInput<Member>) => {
    const recipe = recipeOf(member);
    const ownedRead = recipe?.ownedReadOperations?.find(entry => entry.phase === phase);
    if (ownedRead !== undefined) {
      if (credentialSlot !== undefined || recipe!.rowOperations[ownedRead.operationIndex].operation !== operation ||
          managedEffect?.runtime !== moon || !Array.isArray(requestChildren) ||
          typeof retireRequestAliases !== 'function' || typeof constructChild !== 'function') {
        reject('InstalledEffectPhysicalPlanUnavailable');
      }
      return prepareInstalledRowCaptureChild({children: requestChildren,
        create: () => prepareInstalledEffectOwnedRequestChild({run: managedEffect,
          memberIndex: member.memberIndex, rowIndex, operationIndex: ownedRead.operationIndex, operation,
          constructChild, requestsRetired: retireRequestAliases}), assertCurrent, signal});
    }
    if (recipe?.physicalWrite !== undefined) {
      const selected = recipe.physicalWrite;
      if (credentialSlot !== undefined || phase !== 'write' || recipe.rowOperations[selected.operationIndex].operation !== operation ||
          managedEffect?.runtime !== moon || !Array.isArray(requestChildren) ||
          typeof retireRequestAliases !== 'function') reject('InstalledEffectPhysicalPlanUnavailable');
      return prepareInstalledRowCaptureChild({children: requestChildren,
        create: () => prepareInstalledEffectOwnedPhysicalChild({run: managedEffect,
          memberIndex: member.memberIndex, rowIndex, operationIndex: selected.operationIndex, operation,
          transferBytes: selected.transferBytes, invoke, requestsRetired: retireRequestAliases} as OwnedPhysicalOptions),
        assertCurrent, signal});
    }
    const selected = selectInstalledEffectCredentialOperation(recipe, phase, credentialSlot);
    const perRow = selected?.perRow ?? true;
    const operations = perRow ? recipe?.rowOperations : recipe?.memberOperations;
    const responseBytes = maxResponseBytes ?? selected?.maxResponseBytes;
    if (selected === undefined || operations![selected.operationIndex]?.operation !== operation ||
        selected.resource !== undefined && (resource !== selected.resource || purpose !== 'read') ||
        !Number.isSafeInteger(responseBytes) || responseBytes! < 1 || responseBytes! > selected.maxResponseBytes ||
        managedEffect?.runtime !== moon || !Array.isArray(requestChildren) ||
        typeof retireRequestAliases !== 'function' || typeof assertCurrent !== 'function') {
      reject('InstalledEffectPhysicalPlanUnavailable');
    }
    const readChildren = moon.clientProgramInstalledEffectManagedPlanCaptureChildren;
    if (typeof readChildren !== 'function') reject('InstalledEffectOperationRuntimeUnavailable');
    const maxChildren = Reflect.apply(readChildren, moon, [managedEffect.operationPlan]);
    if (!Number.isSafeInteger(maxChildren) || maxChildren < 1 || requestChildren.length >= maxChildren) {
      reject('InstalledEffectPhysicalChildLimit');
    }
    // Lookup recognizes only the original credential returned by this Site.
    // Its issuer receives the untouched authorization, never the useId copy.
    const originalSite = installedRowCredentialOperationSite(site!.credential);
    return prepareInstalledRowCaptureChild({children: requestChildren,
      create: () => prepareInstalledEffectCredentialChild({run: managedEffect,
        memberIndex: member.memberIndex, rowIndex,
        operationIndex: selected.operationIndex, operation, perRow, originalSite,
        originalAuthorization, useId, resource, purpose, runInvocationCid, dispatchRequestCid,
        maxRequestBytes: selected.maxRequestBytes, maxResponseBytes: responseBytes,
        responseExtent: selected.responseExtent, responsePreparation,
        discardResponseProjection: selected.discardResponseProjection === true,
        assertCurrent, observeCurrent: async () => {assertCurrent();},
        requestsRetired: retireRequestAliases, invoke} as CredentialOptions), assertCurrent, signal});
  };

  return prepareCredentialOperation;
}

export function createInstalledRowEffectReadChild<Member extends MemberRef>({
  ownerOf, recipeOf, requireSynchronousEffectResource, fail,
}: ReadChildControls<Member>) {
  const reject: ReadChildControls<Member>['fail'] = fail;
  const managedReadChild = ({member, phase, physicalOperations, runInvocationCid,
    dispatchRequestCid, assertCurrent, signal, originalTargetAuthorization, accountTargetRead}: ManagedReadInput<Member>) => {
    const recipe = recipeOf(member);
    const ownedRead = recipe?.ownedReadOperations?.find(entry => entry.phase === phase);
    if (ownedRead !== undefined) {
      if (typeof physicalOperations !== 'function') reject('InstalledEffectPhysicalPlanUnavailable');
      return Object.freeze({owned(constructChild: OwnedRequestOptions['constructChild'], rowIndex: number) {
        if (typeof constructChild !== 'function' || !Number.isSafeInteger(rowIndex) || rowIndex < 0) {
          reject('ForeignInstalledEffectReadChild');
        }
        return physicalOperations({member, rowIndex, phase,
          operation: recipe!.rowOperations[ownedRead.operationIndex].operation,
          constructChild, assertCurrent, signal});
      }});
    }
    if (!recipe?.credentialOperations?.some(entry => entry.phase === phase)) return undefined;
    if (typeof physicalOperations !== 'function') reject('InstalledEffectPhysicalPlanUnavailable');
    const {site} = ownerOf(member);
    return (authorization: GrantView | undefined, input: ReadChildInput, rowIndex = 0,
      slot?: string, project?: (response: unknown) => unknown, prepareOperations?: () => unknown) => {
      if (project !== undefined && (typeof project !== 'function' || nodeTypes.isProxy(project) ||
          nodeTypes.isAsyncFunction(project))) reject('ForeignInstalledEffectReadChild');
      const selected = selectInstalledEffectCredentialOperation(recipe, phase, slot);
      if (selected === undefined ||
          prepareOperations !== undefined && (typeof prepareOperations !== 'function' ||
            selected.maxTargetBytes === undefined || slot !== 'target')) reject('ForeignInstalledEffectReadChild');
      const operation = (selected.perRow === false ? recipe.memberOperations : recipe.rowOperations)
        [selected.operationIndex].operation;
      // Only a target occurrence consumes this same row's retained approval
      // grant. Metadata slots require their OWN Account read authorization;
      // that original is validated again by the existing Credential child.
      const originalAuthorization = selected.resource === undefined && selected.perRow !== false &&
          originalTargetAuthorization !== undefined
        ? originalTargetAuthorization(authorization, rowIndex) : authorization;
      if (input?.grant !== originalAuthorization?.grant || input.useId === undefined ||
          !Number.isSafeInteger(input.maxResponseBytes) || input.maxResponseBytes < 1 ||
          input.maxResponseBytes > selected.maxResponseBytes) reject('ForeignInstalledEffectReadChild');
      let responsePreparation: CredentialOptions['responsePreparation'];
      if(project!==undefined){
        if(typeof project!=='function'||nodeTypes.isProxy(project))reject('InvalidInstalledEffectReadProjector');
        const field=Object.getOwnPropertyDescriptor(project,'responsePreparation');
        if(field!==undefined&&!Object.hasOwn(field,'value'))reject('InvalidInstalledEffectReadProjector');
        responsePreparation=field?.value;
      }
      // The standard declaration consumes its own ordinary Account-issued
      // read grant when there was no Checkpoint target-read delegation.
      // The physical child still requires the exact original Site purpose.
      const ordinaryRead = selected.perRow === false || selected.resource !== undefined ||
        (accountTargetRead === true && prepareOperations !== undefined);
      return physicalOperations({member, rowIndex, phase, operation, site, originalAuthorization,
        responsePreparation,
        useId: input.useId, resource: selected.resource ?? member.resource,
        purpose: ordinaryRead ? 'read' : 'target-read',
        credentialSlot: slot,
        runInvocationCid, dispatchRequestCid, assertCurrent, signal,
        maxResponseBytes: input.maxResponseBytes,
        invoke: async ({authorization, credential, callResource}: Invocation) => {
          const operations = prepareOperations === undefined ? input.operations : prepareOperations();
          const response = await callResource({...input, operations,
            ...credential, ...authorization, maxRequestBytes: selected.maxRequestBytes} as InvocationInput);
          // Native decoding must finish INSIDE the original physical child.
          // Its response workspace cannot shrink while projection is pending.
          return project === undefined ? response : requireSynchronousEffectResource(project(response));
        }});
    };
  };
  return managedReadChild;
}

export function createInstalledRowEffectReadOperations<Member extends StageMember>({
  ownerOf, recipeOf, managedReadChild, resourceFields, readDecision, sameValue, cidPattern, fail,
}: ReadOperationsControls<Member>) {
  const reject: ReadOperationsControls<Member>['fail'] = fail;
  const describeMember = async ({member, maxRows, physicalOperations, operationPhase, runInvocationCid,
    dispatchRequestCid, label, approval, signal, assertCurrent, controlConstruction}: DescribeInput<Member>) => {
    const {owned} = ownerOf(member);
    if (owned.describe === undefined) return undefined;
    const readChild = managedReadChild({member, phase: `${operationPhase}-describe`,
      physicalOperations, runInvocationCid, dispatchRequestCid, assertCurrent, signal});
    return owned.describe({member, maxRows, runInvocationCid, dispatchRequestCid, label, approval, signal, controlConstruction,
      ...(readChild === undefined ? {} : {readChild}), ...resourceFields(member)});
  };

  // Every create row's provider check, under a current read decision.
  const checkRows = async ({members, entries, runInvocationCid, dispatches,
    subjectOf, signal, assertCurrent, physicalOperations, controlConstruction, operationPhase = 'capture'}: CheckInput<Member>) => {
    assertCurrent?.();
    for (const [index, member] of members.entries()) {
      const {owned, site} = ownerOf(member);
      const managedPlanRecipe = recipeOf(member);
      if (member.kind !== 'create' || owned.check === undefined) continue;
      if (managedPlanRecipe?.credentialOperations !== undefined && typeof physicalOperations !== 'function') {
        reject('InstalledEffectPhysicalPlanUnavailable');
      }
      const subjectCid = subjectOf(member);
      const decision = await readDecision(member, owned.check.resource, subjectCid,
        signal, assertCurrent);
      for (const [rowIndex, entry] of entries[index].entries()) {
        signal?.throwIfAborted();
        assertCurrent?.();
        const grantFacts = {operation: owned.check.operation,
          decision, resource: owned.check.resource, runInvocationCid,
          dispatchRequestCid: dispatches[index], maxUses: 1};
        const grant = controlConstruction === undefined ? site.issueReadGrant(grantFacts)
          : (controlConstruction.grant ?? controlConstruction)(site, site.issueReadGrant, [grantFacts]);
        const useId = `${dispatches[index]}-check-${subjectCid}-${rowIndex}`;
        if (managedPlanRecipe?.credentialOperations !== undefined) {
          await physicalOperations!({member, rowIndex, phase: `${operationPhase}-check`,
            operation: owned.check.operation, site, originalAuthorization: grant, useId,
            resource: owned.check.resource, purpose: 'read',
            runInvocationCid, dispatchRequestCid: dispatches[index], assertCurrent, signal,
            invoke: ({authorization, credential, callResource}: Invocation) =>
              owned.checkRequest!({member, request: entry.request, authorization, credential, callResource, signal, controlConstruction})});
        } else {
          await owned.checkRequest!({member, request: entry.request,
            authorization: {...grant, useId},
            credential: site.credential, callResource: site.callResource, signal, controlConstruction});
        }
        assertCurrent?.();
      }
    }
  };

  // The observed target of every update row under its read decision. Each
  // observation must be of exactly the target the row's request selects.
  const observeRows = async ({member, entries, current, read, signal, assertCurrent,
    physicalOperations, operationPhase, runInvocationCid, dispatchRequestCid}: ObserveInput<Member>) => {
    const {owned, updateWriteSlot} = ownerOf(member);
    assertCurrent?.();
    const phase = `${operationPhase}-target`;
    const readChild = managedReadChild({member, phase,
      physicalOperations, runInvocationCid, dispatchRequestCid, assertCurrent, signal,
      originalTargetAuthorization: read.consumeOriginal, accountTargetRead: read.approval === undefined});
    const observe = (targetEntry: object) => owned.observeTargets!({member, entries, current,
      ...targetEntry, signal,
      ...(readChild === undefined ? {} : typeof readChild === 'function' ? {
        readChild
      } : {ownedReadChild: readChild.owned}),
      ...resourceFields(member)});
    let observed: unknown;
    if (updateWriteSlot === undefined) {
      observed = await observe({authorizationForRow: read.authorizationForRow});
    } else {
      const recipe = recipeOf(member);
      const slot = selectInstalledEffectCredentialOperation(recipe, phase, 'target');
      const operation = owned.targetRead!.operation;
      if (slot === undefined || slot.perRow === false || slot.resource !== undefined ||
          recipe!.rowOperations[slot.operationIndex]?.operation !== operation) {
        reject('InstalledEffectPhysicalPlanUnavailable');
      }
      observed = await withDeclaredUpdateTargetReads({readChild,
        authorizationForRow: read.authorizationForRow, slot, operation, rowCount: entries.length,
        assertCurrent, signal} as DeclaredTargetOptions, readTarget => observe({readTarget}));
    }
    assertCurrent?.();
    if (!Array.isArray(observed) || observed.length !== entries.length) {
      reject('ForeignInstalledRowEffectObservation');
    }
    return Object.freeze(observed.map((row: ObservedRow | null | undefined, index: number) => {
      const {identity, state, versionCid, before} = row ?? {};
      if (!sameValue(identity, entries[index].target)) reject('ForeignInstalledRowEffectObservation');
      if (state === 'absent') {
        if (member.kind !== 'upsert' || versionCid !== undefined || before !== undefined) {
          reject('ForeignInstalledRowEffectObservation');
        }
        return Object.freeze({identity, state: 'absent'});
      }
      if ((state !== undefined && state !== 'present') || !cidPattern.test(versionCid ?? '') ||
          before === null || typeof before !== 'object') reject('ForeignInstalledRowEffectObservation');
      return Object.freeze({identity, state: 'present', versionCid, before});
    }));
  };

  return {describeMember, checkRows, observeRows};
}
