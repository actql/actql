import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {prepareInstalledEffectManagedPlan} from './installed-effect-plan.mjs';
import type {createInstalledRowEffectCaptureValues} from './installed-row-effect-capture-values.mjs';

type MappingKind = 'create' | 'update' | 'upsert' | 'delete';
type Mapping = Readonly<{
  resource: string; target: string; mappingCid: string; mappingRef: string; primaryIdentity: unknown;
  approval?: string;
  rules: readonly Readonly<{effect_kind: string; permissions?: readonly string[]}>[];
}>;
type Command = Readonly<{resource: string; commandCid: string; commandRef: string; target: string; permissions: readonly string[]}>;
type RowMember = Readonly<{stageIndex?: number; effectId: string; memberIndex: number; resource: string}> & (
  Readonly<{kind: MappingKind; mapping: Mapping}> | Readonly<{kind: 'command'; command: Command}>
);
type Member = RowMember & Readonly<{stageIndex: number}>;
type Owner = Readonly<{
  installed: readonly Mapping[]; installedCommands: readonly Command[];
  connection: string; configuredMaxMembers?: number;
}>;
type Route<SelectedOwner> = Readonly<{descriptor: Readonly<{effectId?: string; kind?: string; target?: string;
  mappingRef?: string; mappingCid?: string}>; owner: SelectedOwner}>;
type EffectUnit = Readonly<{effectIds: readonly string[]; stageIndex: number; programId: string; stageId: string}>;
type ManagedPlan = Parameters<typeof prepareInstalledEffectManagedPlan<Member>>[0];
type Runtime = ManagedPlan['moon'] & Readonly<{
  clientProgramEffectCompilationPlanWire(compilation: unknown): string;
  clientProgramEffectMemberDescriptor(prepared: unknown, stageIndex: number, effectId: string, maxWork: number): unknown;
}>;
type MemberControls<SelectedOwner extends Owner> = Readonly<{
  moon: Runtime; limits: {planWork: number; maxMembers: number};
  owners: readonly SelectedOwner[]; singular?: SelectedOwner; routes?: readonly Route<SelectedOwner>[];
  installedEffectKinds(owner: SelectedOwner): readonly string[];
  retainMember<Original extends Member>(owner: SelectedOwner, member: Original): Readonly<Original>;
  ownerOf(member: RowMember): SelectedOwner;
  assertPrepared(facts: Readonly<{moon: Runtime; prepared: unknown; compilation: unknown}>): void;
  installedRowEffectUnit(moon: Runtime, compilation: unknown): EffectUnit;
  recipeOf: ManagedPlan['recipeFor'];
  fail(code: string): never;
}>;
type RequestFacts = Readonly<{value?: unknown; target?: unknown}>;
type RequestRow = Readonly<{value?: unknown; selector?: unknown; proposalWire?: string}>;
type PreparedRequest = Readonly<{request?: unknown; requestCid?: string}>;
type CreateRow = Readonly<{identity: unknown}>;
type ContentBorrower = ReturnType<ReturnType<typeof createInstalledRowEffectCaptureValues>['commandContentBorrower']>;
type RequestContext = Readonly<{
  member: RowMember; value: unknown; selector: unknown; current: unknown;
  runOriginal?: unknown; createRowIdentity?: unknown; proposalWire?: string; content?: unknown;
}>;
type RequestControls = Readonly<{
  ownerOf(member: RowMember): Readonly<{owned: Readonly<{
    requestFacts(request: unknown): unknown;
    prepareRequest(context: RequestContext): PreparedRequest | null | undefined;
  }> }>;
  cidPattern: RegExp;
  targeted(kind: RowMember['kind']): boolean;
  sameEffectValue(kind: RowMember['kind'], left: unknown, right: unknown): boolean;
  sameValue(left: unknown, right: unknown): boolean;
  resourceFields(member: RowMember): Readonly<{runOriginal?: object}>;
  commandContentRow(contentOf: ContentBorrower, index: number): unknown;
  fail(code: string): never;
}>;

export function createInstalledRowEffectMembers<SelectedOwner extends Owner>({
  moon, limits, owners, singular, routes, installedEffectKinds, retainMember, ownerOf,
  assertPrepared, installedRowEffectUnit, recipeOf, fail,
}: MemberControls<SelectedOwner>) {
  const reject: MemberControls<SelectedOwner>['fail'] = fail;
  const selectOwner = (descriptor: unknown) => {
    if (singular !== undefined) return singular;
    const route = routes!.find(value => value.descriptor.effectId === runtimeField(descriptor, 1));
    const expected = route?.descriptor;
    if (expected === undefined || expected.kind !== runtimeField(descriptor, 2) ||
        expected.target !== runtimeField(descriptor, 3) || expected.mappingRef !== runtimeField(descriptor, 4) ||
        expected.mappingCid !== runtimeField(descriptor, 5)) reject('InstalledEffectProgramMismatch');
    return route!.owner;
  };
  const scopes = (members: readonly RowMember[]) => Object.freeze(members.map(member =>
    Object.freeze({connection: ownerOf(member).connection, resource: member.resource})));
  const permissionsOf = (member: Member) => {
    if (member.kind === 'command') return [...member.command.permissions];
    const rule = member.mapping.rules.find(item =>
      item.effect_kind === member.kind);
    if (!Array.isArray(rule?.permissions)) {
      reject('InstalledRowEffectMappingNotInstalled');
    }
    return [...rule.permissions];
  };

  // One member of the Effect Unit: its Program descriptor, the installed
  // Mapping the Program resolved and the kind that Mapping was checked for.
  // Refused before any I/O when the Mapping is not installed or its kind is
  // not one this driver writes.
  const resolveMember = (prepared: unknown, {stageIndex, effectId}: {stageIndex: number; effectId: string}): Member => {
    const descriptor = checked(moon.clientProgramEffectMemberDescriptor(
      prepared, stageIndex, effectId, limits.planWork));
    const owner = selectOwner(descriptor);
    const {installed, installedCommands} = owner;
    if (runtimeField(descriptor, 2) === 'command') {
      const command = installedCommands.find(candidate =>
        candidate.commandCid === runtimeField(descriptor, 5) &&
        candidate.commandRef === runtimeField(descriptor, 4) && candidate.target === runtimeField(descriptor, 3));
      if (command === undefined || !installedEffectKinds(owner).includes('command') ||
          runtimeField(descriptor, 6) === undefined) reject('InstalledRowEffectCommandNotInstalled');
      return retainMember(owner, {stageIndex, effectId: runtimeField(descriptor, 1) as string,
        memberIndex: runtimeField(descriptor, 0) as number, kind: 'command', command,
        resource: command.resource});
    }
    const mapping = installed.find(candidate =>
      candidate.mappingCid === runtimeField(descriptor, 5) &&
      candidate.mappingRef === runtimeField(descriptor, 4));
    if (mapping === undefined || !installedEffectKinds(owner).includes(runtimeField(descriptor, 2) as string) ||
        runtimeField(descriptor, 6) === undefined) {
      reject('InstalledRowEffectMappingNotInstalled');
    }
    const member = retainMember(owner, {stageIndex, effectId: runtimeField(descriptor, 1) as string,
      memberIndex: runtimeField(descriptor, 0) as number, kind: runtimeField(descriptor, 2) as MappingKind, mapping,
      resource: mapping.resource});
    permissionsOf(member);
    return member;
  };
  const membersOf = (prepared: unknown, unit: EffectUnit, maxMembers = limits.maxMembers) => {
    const effectIds = unit.effectIds;
    if (effectIds.length > maxMembers ||
        new Set(effectIds).size !== effectIds.length) {
      reject('InstalledRowEffectUnitUnsupported');
    }
    const members = effectIds.map(effectId => resolveMember(prepared,
      {stageIndex: unit.stageIndex, effectId}));
    members.sort((a, b) => a.memberIndex - b.memberIndex);
    if (members.some((member, index) => member.memberIndex !== index)) {
      reject('InstalledRowEffectUnitUnsupported');
    }
    return Object.freeze(members);
  };
  const prepareManagedPlan = (facts: ManagedPlan['facts'] & {compilation: unknown}, inputs: ManagedPlan['inputs']) => {
    assertPrepared({moon, prepared: facts?.prepared, compilation: facts?.compilation});
    const unit = installedRowEffectUnit(moon, facts.compilation);
    // The original Request Effect construction borrow funds wrappers for the
    // checked inventory before this entry. Explicit installer policy still
    // narrows it; the member count grants no row work or physical sends.
    const maxMembers = owners.reduce((bound, owner) => owner.configuredMaxMembers === undefined
      ? bound : Math.min(bound, owner.configuredMaxMembers), unit.effectIds.length);
    const members = membersOf(facts.prepared, unit, maxMembers);
    return prepareInstalledEffectManagedPlan({moon, facts, inputs, unit, members,
      recipeFor: recipeOf});
  };

  return {selectOwner, scopes, permissionsOf, membersOf, prepareManagedPlan};
}

export function createInstalledRowEffectRequests({
  ownerOf, cidPattern, targeted, sameEffectValue, sameValue, resourceFields, commandContentRow, fail,
}: RequestControls) {
  const reject: RequestControls['fail'] = fail;
  // One row's request with the facts the common owner holds it to: the
  // value it writes and, for an update, the target it selects.
  const entryOf = (member: RowMember, request: unknown, requestCid: string | undefined) => {
    const {owned} = ownerOf(member);
    const facts = owned.requestFacts(request) as RequestFacts | null | undefined;
    if (!request || !cidPattern.test(requestCid ?? '') ||
        facts === null || typeof facts !== 'object' ||
        (member.kind === 'delete' ? facts.value !== undefined :
          facts.value === null || typeof facts.value !== 'object') ||
        targeted(member.kind) === (facts.target === undefined)) {
      reject('InvalidInstalledRowEffectRequest');
    }
    return Object.freeze({request, requestCid, value: facts.value,
      target: facts.target});
  };

  // The exact request of every row of a member, from its mapped values and
  // selectors. A request that writes another value, or selects another
  // target, than the Program's row is refused.
  const requestEntry = (member: RowMember, row: RequestRow, prepared: PreparedRequest | null | undefined) => {
    const entry = entryOf(member, prepared?.request, prepared?.requestCid);
    if (!sameEffectValue(member.kind, entry.value, row.value) ||
        (targeted(member.kind) && !sameValue(entry.target, row.selector))) {
      reject('ForeignInstalledRowEffectRequest');
    }
    return entry;
  };
  const requestsOf = (member: RowMember, rows: readonly RequestRow[], current: unknown,
    contentOf: ContentBorrower | undefined, createRows: readonly CreateRow[] | undefined) => Object.freeze(rows.map((row, index) => {
    const {owned} = ownerOf(member);
    return requestEntry(member, row, owned.prepareRequest({member, value: row.value,
      selector: row.selector, current, ...resourceFields(member),
      ...(member.kind === 'create' ? {createRowIdentity: createRows![index].identity,
        ...(row.proposalWire === undefined ? {} : {proposalWire: row.proposalWire})} : {}),
      ...(contentOf === undefined ? {} : {content: commandContentRow(contentOf, index)})}));
  }));

  return {entryOf, requestEntry, requestsOf};
}
