import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import type {ControlWork} from './installed-effect-plan.mjs';
import type {createInstalledRowEffectDriverControls} from './installed-row-effect-driver.mjs';
import type {assertUpdateTargetSelectionMembersCurrent, retainUpdateTargetSelection} from './update-target-original-shape.mjs';

type DriverControls = ReturnType<typeof createInstalledRowEffectDriverControls>;
type TargetSelections = ReturnType<typeof retainUpdateTargetSelection>;
type ManagedShape = (plan: unknown) => readonly [number, number, number];
type ManagedRun = Readonly<{
  runtime: object; closed?: boolean; operationPlan: unknown; controlConstruction?: ControlWork;
}>;
type StageLimits = Readonly<{maxRows: number; maxMembers: number}>;
type Mapping = Readonly<{target: string; mappingRef: string; mappingCid: string}>;
type StoreMapping = Mapping & Readonly<{
  storeCommand: Readonly<{command_ref: string; command_contract_cid: string}>;
}>;
type StageMember = Readonly<{stageIndex?: number; effectId: string}> & (
  Readonly<{kind: 'create' | 'update' | 'upsert' | 'delete'; mapping: Mapping}> |
  Readonly<{kind: 'command'; command: Readonly<{commandRef: string; commandCid: string}>}>
);
type StageOwner = Readonly<{
  configuredMaxRows?: number; configuredMaxMembers?: number;
  resources?: ReturnType<DriverControls['captureEffectResources']>;
  storeMappings: readonly StoreMapping[];
}>;
type CurrentFacts = Readonly<{
  prepared: unknown;
  assertContinuationCurrent?: () => unknown;
  assertUpdateSelectionCurrent?: () => unknown;
}>;
type LimitControls<Limits> = Readonly<{
  moon: object; readManagedShape?: ManagedShape; limits: Limits;
  owners: readonly Pick<StageOwner, 'configuredMaxRows' | 'configuredMaxMembers'>[];
  fail(code: string): never;
}>;
type RunControls = Readonly<{
  owners: readonly StageOwner[];
  ownerOf(member: StageMember): StageOwner;
  fail(code: string): never;
  selectionChanged(cause?: unknown): never;
  requireSynchronousEffectResource: DriverControls['requireSynchronousEffectResource'];
  validateOwnerSelections(owners: readonly StageOwner[], selections: TargetSelections, prepared: unknown): TargetSelections;
  assertUpdateTargetSelectionMembersCurrent: typeof assertUpdateTargetSelectionMembersCurrent;
}>;

export function createInstalledRowEffectRunLimits<Limits extends StageLimits>({
  moon, readManagedShape, limits, owners, fail,
}: LimitControls<Limits>) {
  const reject: LimitControls<Limits>['fail'] = fail;
  const runLimits = (managed: ManagedRun | undefined) => {
    if (managed === undefined) return {...limits, maxRowsPerMember: limits.maxRows};
    if (managed.runtime !== moon || managed.closed || typeof managed.controlConstruction !== 'function' ||
        typeof readManagedShape !== 'function') reject('ForeignInstalledEffectManagedRun');
    // This SAME adopted Plan supplies a rejection ceiling, not authority or
    // already funded rows. retainInputs/retainRecoveredInputs still debit the
    // actual inventory before any row-dependent constructor or provider call.
    const shape = managed.controlConstruction(moon, readManagedShape, [managed.operationPlan]);
    const rows = runtimeField(shape, 0) as number, members = runtimeField(shape, 1) as number;
    if (!Number.isSafeInteger(rows) || rows < 0 || !Number.isSafeInteger(members) || members < 1 ||
        rows > 2147483647 || members > 2147483647) reject('InvalidInstalledEffectManagedShape');
    // Core preview/ledger counters are Int. Saturate only this conservative
    // stage ceiling; an overlarge product must not refuse a small valid stage.
    const total = Math.min(2147483647, rows * members);
    const maxRows = owners.reduce((bound, owner) => owner.configuredMaxRows === undefined
      ? bound : Math.min(bound, owner.configuredMaxRows), total);
    const maxMembers = owners.reduce((bound, owner) => owner.configuredMaxMembers === undefined
      ? bound : Math.min(bound, owner.configuredMaxMembers), members);
    return Object.freeze({...limits, maxMembers, maxRows, maxRowsPerMember: Math.min(rows, maxRows)});
  };
  return runLimits;
}

export function createInstalledRowEffectRunControls({
  owners, ownerOf, fail, selectionChanged,
  requireSynchronousEffectResource, validateOwnerSelections, assertUpdateTargetSelectionMembersCurrent,
}: RunControls) {
  const reject: RunControls['fail'] = fail;
  const refuseSelection: RunControls['selectionChanged'] = selectionChanged;

  const runResources = new WeakMap<StageMember, object>();
  const bindRunResources = (facts: unknown, members: readonly StageMember[]) => {
    const originals = new Map<StageOwner, object>();
    for (const member of members) {
      const owner = ownerOf(member);
      if (owner.resources === undefined) continue;
      if (!originals.has(owner)) {
        const original = requireSynchronousEffectResource(owner.resources.bindRunOriginal(facts));
        if (original === null || typeof original !== 'object') {
          reject('InstalledEffectResourcesUnavailable');
        }
        originals.set(owner, original);
      }
      runResources.set(member, originals.get(owner)!);
    }
  };
  const resourceFields = (member: StageMember) => {
    if (ownerOf(member).resources === undefined) return {};
    const runOriginal = runResources.get(member);
    if (runOriginal === undefined) reject('InstalledEffectResourcesUnavailable');
    return {runOriginal};
  };
  const selectionFence = (facts: CurrentFacts, members: readonly StageMember[], stageIndex: number,
    updateTargetSelections?: TargetSelections) => {
    const selections = validateOwnerSelections(owners, updateTargetSelections, facts.prepared);
    const resourceOwners = [...new Map(members.flatMap(member => {
      const owner = ownerOf(member);
      return owner.resources === undefined ? [] : [[owner, resourceFields(member).runOriginal] as const];
    })).entries()];
    const liveAssertion = selections === undefined
      ? facts.assertContinuationCurrent : facts.assertUpdateSelectionCurrent;
    if (selections === undefined && resourceOwners.length === 0 && liveAssertion === undefined) return undefined;
    if (selections !== undefined && typeof liveAssertion !== 'function') refuseSelection();
    const selectedMembers = members.flatMap(member => {
      const stage = member.stageIndex ?? stageIndex;
      if (member.kind === 'update' || member.kind === 'delete') {
        return [{stage_index: stage, effect_id: member.effectId,
          target_ref: member.mapping.target, mapping_ref: member.mapping.mappingRef,
          mapping_cid: member.mapping.mappingCid}];
      }
      const selected = selections?.filter(value => value.stage_index === stage &&
        value.effect_id === member.effectId) ?? [];
      if (selected.length === 0) return [];
      // STORE remains a checked Command occurrence with its original Mapping
      // selection. Bind both to this same installed owner; a generic Command
      // or a matching selection tuple alone cannot supply STORE purpose.
      if (selected.length !== 1 || member.kind !== 'command') refuseSelection();
      const mappings = ownerOf(member).storeMappings.filter(mapping =>
        mapping.target === selected[0].target_ref &&
        mapping.mappingRef === selected[0].mapping_ref &&
        mapping.mappingCid === selected[0].mapping_cid &&
        mapping.storeCommand.command_ref === member.command.commandRef &&
        mapping.storeCommand.command_contract_cid === member.command.commandCid);
      if (mappings.length !== 1) refuseSelection();
      return [{stage_index: stage, effect_id: member.effectId,
        target_ref: mappings[0].target, mapping_ref: mappings[0].mappingRef,
        mapping_cid: mappings[0].mappingCid}];
    });
    const assertCurrent = () => {
      for (const [owner, original] of resourceOwners) {
        if (requireSynchronousEffectResource(owner.resources!.assertCurrent(original)) !== undefined) {
          reject('InstalledEffectResourcesUnavailable');
        }
      }
      if (selections !== undefined) {
        validateOwnerSelections(owners, selections, facts.prepared);
        try {
          assertUpdateTargetSelectionMembersCurrent(selections, selectedMembers, facts.prepared);
        } catch (cause) { refuseSelection(cause); }
      }
      if (liveAssertion === undefined) return;
      const result = Reflect.apply(liveAssertion, facts, []);
      // A live-owner assertion must finish before the physical operation.
      if (typeof (result as {then?: unknown} | null | undefined)?.then === 'function') {
        void Promise.resolve(result).catch(() => {});
        refuseSelection();
      }
    };
    assertCurrent();
    return assertCurrent;
  };

  return {bindRunResources, resourceFields, selectionFence};
}
