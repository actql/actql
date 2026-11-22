import {checked} from '../host-common/runtime-result.mjs';
import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import type {ControlWork, prepareInstalledEffectControlConstruction} from './installed-effect-plan.mjs';
import type {InstalledEffectPlanRecipe} from './installed-effect-recipe.mjs';

type MemberRef = Readonly<{kind: string; resource: string}>;
type Entry = Readonly<{request: unknown; requestCid?: string}>;
type CapabilityBinding = Readonly<{
  connector_registration?: unknown; connector_revision?: unknown; runtime_bundle_cid?: unknown;
}>;
type IssuedCapability = Readonly<{identity?: string; route?: string; binding?: unknown}>;
type CapabilityFacts<Member> = Readonly<{
  member: Member; entries: readonly Entry[]; current: unknown; runInvocationCid: string; dispatchRequestCid: string;
}>;
type CapabilityDriver<Member> = Readonly<{
  capabilityRequestCid?(request: unknown): string;
  issueCapability?(facts: CapabilityFacts<Member>): SynchronousRuntimeData;
  writeOperation?(member: Member): unknown;
  operation?: unknown;
}>;
type CapabilityOwner<Member> = Readonly<{
  connectorRegistration: string; connectorRevision: string; runtimeBundleCid: string;
  bindingCid: string; connection: string; owned: CapabilityDriver<Member>; updateWriteSlot?: unknown;
}>;
type CapabilityControls<Member> = Readonly<{
  moon: Readonly<{
    clientProgramEffectApplyCapabilityFromCodes(evidenceCid: string, routeCode: number, atomicityCode: number,
      failureCode: number, rowErrorIdentity: boolean, requestOrderPreserved: boolean,
      idempotencyCode: number, reconciliationCode: number): unknown;
  }>;
  ownerOf(member: Member): CapabilityOwner<Member>;
  cid(value: unknown): string; cidPattern: RegExp;
  CAPABILITY_VERSION: string;
  contractCidOf(member: Member): string;
  installedEffectWriteOperation(driver: CapabilityDriver<Member>, member: Member, updateWriteSlot: unknown): unknown;
  fail(code: string): never;
}>;
type ReadTuple = Readonly<{connection: string; resource: string; operation: string}>;
type Decision = Readonly<{action?: unknown}>;
type ReadContext = Readonly<{subjectCid: string; signal?: AbortSignal}>;
type ReadDecision = Decision | undefined | PromiseLike<Decision | undefined>;
type ReadOwner = Readonly<{
  connection: string;
  authorization: Readonly<{authorize(kind: 'acquisition', tuple: ReadTuple, context: ReadContext): ReadDecision}>;
}>;
type ReadGrant = Readonly<Record<string, unknown> & {then?: never}>;
type TargetGrantFacts = Readonly<{
  operation: string; decision: unknown; resource: string; runInvocationCid: string; dispatchRequestCid: string; maxUses: number;
}>;
type TargetOwner<Member> = ReadOwner & Readonly<{
  owned: Readonly<{
    targetRead: Readonly<{operation: string}>;
    admitTargetReadApproval?(facts: Readonly<{member: Member; decision: Decision}>): unknown;
  }>;
  site: Readonly<{issueReadGrant(facts: TargetGrantFacts): ReadGrant}>;
}>;
type GrantControl = ControlWork & Partial<Pick<ReturnType<typeof prepareInstalledEffectControlConstruction>, 'grant'>>;
type TargetOptions<Member> = Readonly<{
  member: Member; runInvocationCid: string; dispatchRequestCid: string; subjectCid: string;
  signal?: AbortSignal; assertCurrent?: () => void; controlConstruction?: GrantControl;
  targetReads?: Readonly<{authorize(tuple: ReadTuple, context: ReadContext): ReadDecision}>;
}>;
type TargetControls<Member> = Readonly<{
  ownerOf(member: Member): TargetOwner<Member>;
  targetPlanOf(member: Member, owner: TargetOwner<Member>): Readonly<{targetReadOperation: string}> | undefined;
  recipeOf(member: Member): InstalledEffectPlanRecipe | undefined;
  fail(code: string): never;
}>;

export function createInstalledRowEffectCapability<Member extends MemberRef>({
  moon, ownerOf, cid, cidPattern, CAPABILITY_VERSION, contractCidOf, installedEffectWriteOperation, fail,
}: CapabilityControls<Member>) {
  const reject: CapabilityControls<Member>['fail'] = fail;
  // The common sealed capability of an installation whose driver issues
  // none: its runtime, connection and Mapping, and the exact requests.
  const commonCapability = (member: Member, entries: readonly Entry[]) => {
    const {connectorRegistration, connectorRevision, runtimeBundleCid, bindingCid, connection, owned,
      updateWriteSlot} = ownerOf(member);
    return Object.freeze({
    identity: cid({
      version: CAPABILITY_VERSION,
      connector_registration: connectorRegistration,
      connector_revision: connectorRevision,
      runtime_bundle_cid: runtimeBundleCid, binding_cid: bindingCid,
      connection, resource: member.resource,
      ...(member.kind === 'command'
        ? {command_cid: contractCidOf(member)} : {mapping_cid: contractCidOf(member)}),
      operation: installedEffectWriteOperation(owned, member, updateWriteSlot),
      route: 'single_serial', idempotency: 'unavailable',
      request_cids: entries.map(entry => owned.capabilityRequestCid === undefined
        ? entry.requestCid : owned.capabilityRequestCid(entry.request))}),
    route: 'single_serial'});
  };

  // Admit a member's capability. A provider-issued capability (its formal
  // issuer having checked its own evidence) is admitted only when its
  // binding names this installation's registration, revision and the
  // runtime the Host itself runs, and its route is the one this factory
  // drives: one serial row per request, no provider idempotency, an
  // uncertain send reconciled. The admission does not establish the
  // provider evidence's authenticity, and nothing it binds is claimed to be
  // inside the provider's identity.
  const admitCapability = (member: Member, entries: readonly Entry[], current: unknown, runInvocationCid: string,
    dispatchRequestCid: string, controlConstruction?: ControlWork) => {
    const {owned, connectorRegistration, connectorRevision, runtimeBundleCid} = ownerOf(member);
    if (owned.issueCapability === undefined) {
      return commonCapability(member, entries);
    }
    const facts = {member, entries, current, runInvocationCid, dispatchRequestCid};
    const issued = (controlConstruction === undefined ? owned.issueCapability(facts)
      : controlConstruction(owned, owned.issueCapability, [facts])) as IssuedCapability | null | undefined;
    const binding = issued?.binding as CapabilityBinding | undefined;
    if (!cidPattern.test(issued?.identity ?? '') ||
        issued!.route !== 'single_serial' ||
        binding === null || typeof binding !== 'object' ||
        binding.connector_registration !== connectorRegistration ||
        binding.connector_revision !== connectorRevision ||
        binding.runtime_bundle_cid !== runtimeBundleCid) {
      reject('InstalledRowEffectCapabilityNotAdmitted');
    }
    return Object.freeze({identity: issued!.identity!, route: issued!.route});
  };
  const routeOf = (capability: {identity: string}) => checked(
    moon.clientProgramEffectApplyCapabilityFromCodes(capability.identity, 0,
      0, 0, true, true, 2, 1));

  return {admitCapability, routeOf};
}

export function createInstalledRowEffectReadDecision<Member>({ownerOf}: Readonly<{ownerOf(member: Member): ReadOwner}>) {
  // A current read decision of `resource` for `subjectCid`; a held or denied
  // read reads nothing.
  const readDecision = async (member: Member, resource: string, subjectCid: string,
    signal?: AbortSignal, assertCurrent?: () => void) => {
    const {authorization, connection} = ownerOf(member);
    assertCurrent?.();
    const decision = await authorization.authorize('acquisition', {
      connection, resource, operation: 'read'}, {subjectCid, signal});
    assertCurrent?.();
    if (decision?.action !== 'dispatch') {
      throw Object.assign(new Error('InstalledRowEffectCheckNotAuthorized'),
        {code: 'InstalledRowEffectCheckNotAuthorized',
          action: decision?.action});
    }
    return decision;
  };
  return readDecision;
}

export function createInstalledRowEffectTargetAuthorization<Member extends MemberRef>({
  ownerOf, targetPlanOf, recipeOf, fail,
}: TargetControls<Member>) {
  const reject: TargetControls<Member>['fail'] = fail;
  // A current read decision of an update member's targets for `subjectCid`:
  // on the installation's gate, or through the Host's resumed target-read
  // Checkpoint (`targetReads`), whose approval the driver admits for exactly
  // this member. A held or denied read reads nothing.
  const decideTargetRead = async ({member, runInvocationCid,
    dispatchRequestCid, subjectCid, signal, targetReads, assertCurrent, controlConstruction}: TargetOptions<Member>) => {
    const owner = ownerOf(member), {connection, authorization, owned, site} = owner;
    const operation = targetPlanOf(member, owner)?.targetReadOperation ?? owned.targetRead.operation;
    const tuple = {connection, resource: member.resource, operation: 'read'};
    assertCurrent?.();
    const decision = targetReads === undefined
      ? await authorization.authorize('acquisition', tuple, {subjectCid, signal})
      : await targetReads.authorize(tuple, {subjectCid, signal});
    assertCurrent?.();
    if (decision?.action !== 'dispatch') {
      throw Object.assign(new Error('InstalledRowEffectCheckNotAuthorized'),
        {code: 'InstalledRowEffectCheckNotAuthorized',
          action: decision?.action});
    }
    let approval: unknown;
    if (targetReads !== undefined) {
      if (typeof owned.admitTargetReadApproval !== 'function') {
        reject('InstalledRowEffectTargetReadApprovalNotAdmitted');
      }
      approval = owned.admitTargetReadApproval({member, decision});
    }
    let use = 0;
    const originals = recipeOf(member)?.credentialOperations?.some(entry =>
      ['capture-target', 'apply-target', 'resume-target'].includes(entry.phase)) ? new Map<unknown, {grant: ReadGrant; rowIndex: number}>() : undefined;
    return Object.freeze({approval,
      ...(originals === undefined ? {} : {consumeOriginal(authorization: unknown, rowIndex: number) {
        const original = originals.get(authorization);
        if (original === undefined || original.rowIndex !== rowIndex) reject('ForeignInstalledEffectReadChild');
        originals.delete(authorization);
        return original.grant;
      }}),
      authorizationForRow: async (rowIndex: number) => {
        assertCurrent?.();
        const grantFacts = {operation, decision: approval ?? decision,
          resource: member.resource, runInvocationCid, dispatchRequestCid, maxUses: 1};
        const grant = controlConstruction === undefined ? site.issueReadGrant(grantFacts)
          : (controlConstruction.grant ?? controlConstruction)(site, site.issueReadGrant, [grantFacts]);
        const authorization = {...grant, useId: `${dispatchRequestCid}-check-${subjectCid}-${rowIndex}-${use++}`};
        originals?.set(authorization, {grant, rowIndex});
        return authorization;
      }});
  };

  return decideTargetRead;
}
