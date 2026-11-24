import {runtimeTupleFromFields} from '../host-common/compiler-binding.generated.mjs';

import type {SynchronousRuntimeData} from '../host-common/runtime-result.mjs';
import type {releasePreparedResults} from '../host-common/completed-run-publication.mjs';
import type {ControlWork, prepareInstalledEffectRequestChild} from './installed-effect-plan.mjs';
import type {InstalledEffectPlanRecipe} from './installed-effect-recipe.mjs';
import type {RecoveryInput, createInstalledRowEffectRecoveryEntries} from './installed-row-effect-claims.mjs';

type MappingKind = 'create' | 'update' | 'upsert' | 'delete';
type SavedEffect = Readonly<{effect_id: string; target: string}> & (
  Readonly<{effect_kind: 'command'; resolved_command_contract_cid: string; contract: string;
    mapping?: undefined; resolved_mapping_contract_cid?: undefined}> |
  Readonly<{effect_kind: MappingKind; resolved_mapping_contract_cid: string; mapping: string}>);
type SavedPreview = Readonly<{effects: readonly SavedEffect[]}>;
type SavedContinuation = Readonly<{members: readonly Readonly<{
  effect_id: string; command_cid?: string; mapping_cid?: string; installation?: unknown;
}>[]}>;
type Mapping = Readonly<{mappingCid: string; mappingRef: string; target: string; resource: string}>;
type Command = Readonly<{commandCid: string; commandRef: string; target: string; resource: string}>;
type Installation<M extends Mapping, C extends Command> = Readonly<{
  installed: readonly M[]; installedCommands: readonly C[];
}>;
type RecoveredMember<M extends Mapping, C extends Command> =
  Readonly<{effectId: string; memberIndex: number; resource: string}> & (
    Readonly<{kind: MappingKind; mapping: M}> | Readonly<{kind: 'command'; command: C}>);
type MemberControls<M extends Mapping, C extends Command, Owner extends Installation<M, C>> = Readonly<{
  singular?: Owner;
  selectOwner(descriptor: unknown): Owner;
  sameValue(left: unknown, right: unknown): boolean;
  installationFacts(owner: Owner): unknown;
  selectionChanged(): never;
  installedEffectKinds(owner: Owner): readonly string[];
  retainMember<Original extends RecoveredMember<M, C>>(owner: Owner, member: Original): Readonly<Original>;
  fail(code: string): never;
}>;

type RecoveryMember = Readonly<{
  kind: MappingKind | 'command'; resource: string; effectId: string; memberIndex: number;
  mapping?: unknown; command?: unknown;
}>;
type RecoveryMethods = ReturnType<typeof createInstalledRowEffectRecoveryEntries>;
type RecoveryResult = ReturnType<RecoveryMethods['recoveredEntries']>;
type RecoveryChild = ReturnType<typeof prepareInstalledEffectRequestChild<RecoveryResult>>;
type PrepareRecovery = () => RecoveryResult;
type GrowRecoveryInput = (metadata: unknown) => undefined;
type ChildRun = Parameters<typeof prepareInstalledEffectRequestChild<RecoveryResult>>[0]['run'];
type PreparedEntry = Parameters<typeof releasePreparedResults>[0][number];
type ConnectorRecovery = RecoveryInput<RecoveryMember>['durable']['connectorRecovery'];
type InputExtent = (previewWire: string, recovery: ConnectorRecovery, memberIndex: number,
  metadata?: unknown) => SynchronousRuntimeData;

type RecoveryBacking<Member> = {
  body: RecoveryInput<Member>['body'] | undefined;
  previewWire: string;
  members: readonly Member[] | undefined;
  connectorRecovery: ConnectorRecovery;
  result: RecoveryResult | undefined;
  children: RecoveryChild[];
  borrowers: number;
  retiring: boolean;
  draining: boolean;
  failed: boolean;
  failure: unknown;
  retire(): boolean;
};
type ManagedRun<Member> = ChildRun & {
  controlConstruction?: ControlWork;
  recoveredRequestInput?: RecoveryBacking<Member>;
};
type BackingFacts<Member> = RecoveryInput<Member> & Readonly<{
  managedEffect?: ManagedRun<Member>;
  requestChildren: PreparedEntry[];
  retireRequestAliases: () => boolean;
  assertCurrent?: () => SynchronousRuntimeData;
  signal?: AbortSignal;
}>;
type BackingControls<Member extends RecoveryMember> = Readonly<{
  moon: ChildRun['runtime'];
  recipeOf(member: Member): InstalledEffectPlanRecipe | undefined;
  ownerOf(member: Member): Readonly<{owned: Readonly<{requestCid(request: unknown): string}>}>;
  sameValue(left: unknown, right: unknown): boolean;
  prepareInstalledEffectRequestChild: typeof prepareInstalledEffectRequestChild;
  recoveredEntries(facts: RecoveryInput<Member>): RecoveryResult;
  validateRecoveredEntries(facts: RecoveryInput<Member>, entries: RecoveryResult['entries']): void;
  fail(code: string): never;
}>;

export function createInstalledRowEffectRecoveredMembers<M extends Mapping, C extends Command, Owner extends Installation<M, C>>({
  singular, selectOwner, sameValue, installationFacts, selectionChanged, installedEffectKinds, retainMember, fail,
}: MemberControls<M, C, Owner>) {
  const reject: MemberControls<M, C, Owner>['fail'] = fail;
  // The members of a recovered capture, from its exact saved Preview and
  // continuation. The installation must still hold each Mapping.
  const recoveredMembers = (body: SavedPreview, provider: SavedContinuation, selected: boolean, maxMembers: number) => {
    if (body.effects.length > maxMembers || body.effects.length !== provider.members.length) {
      reject('InstalledEffectContinuationMismatch');
    }
    return Object.freeze(body.effects.map((member, index) => {
      const saved = provider.members[index];
      const owner = selectOwner(runtimeTupleFromFields({1: member.effect_id, 2: member.effect_kind, 3: member.target, 4: member.mapping, 5: member.resolved_mapping_contract_cid}));
      const {installed, installedCommands} = owner;
      // Initial composed-profile restriction: recovery requires every retained
      // installation identity, not merely equivalent Mappings/capabilities. A
      // republished revision or binding therefore refuses here even when the
      // historical singular row profile could admit that replacement.
      if ((singular === undefined || selected) &&
          !sameValue(saved?.installation, installationFacts(owner))) {
        if (selected) selectionChanged();
        reject('InstalledRowEffectInstallationChanged');
      }
      if (member.effect_kind === 'command') {
        const command = installedCommands.find(candidate =>
          candidate.commandCid === member.resolved_command_contract_cid &&
          candidate.commandRef === member.contract && candidate.target === member.target);
        if (saved?.effect_id !== member.effect_id ||
            saved.command_cid !== member.resolved_command_contract_cid ||
            Object.hasOwn(saved, 'mapping_cid')) reject('InstalledEffectContinuationMismatch');
        if (command === undefined || !installedEffectKinds(owner).includes('command')) {
          reject('InstalledRowEffectCommandNotInstalled');
        }
        return retainMember(owner, {effectId: member.effect_id, memberIndex: index,
          kind: 'command', command, resource: command.resource});
      }
      const mapping = installed.find(candidate =>
        candidate.mappingCid === member.resolved_mapping_contract_cid &&
        (!selected || (candidate.mappingRef === member.mapping &&
          candidate.target === member.target)));
      if (saved?.effect_id !== member.effect_id ||
          saved.mapping_cid !== member.resolved_mapping_contract_cid) {
        reject('InstalledEffectContinuationMismatch');
      }
      if (mapping === undefined || !installedEffectKinds(owner).includes(member.effect_kind)) {
        if (selected) selectionChanged();
        reject('InstalledRowEffectMappingNotInstalled');
      }
      return retainMember(owner, {effectId: member.effect_id, memberIndex: index,
        kind: member.effect_kind, mapping, resource: mapping.resource});
    }));
  };

  return recoveredMembers;
}

export function createInstalledRowEffectRecoveryBacking<Member extends RecoveryMember>({
  moon, recipeOf, ownerOf, sameValue, prepareInstalledEffectRequestChild, recoveredEntries, validateRecoveredEntries, fail,
}: BackingControls<Member>) {
  const reject: BackingControls<Member>['fail'] = fail;
  // Every original member's native recovery constructor is backed BEFORE
  // the first provider rebuild. Nest only our frozen synchronous native body
  // constructors: all original workspaces coexist while the whole-Set vendor
  // recovery runs once. Cleanup stays in the SAME already-retained ledger
  // owner's requestChildren; no physical occurrence or grant is reconstructed.
  const prepareRecoveredEntries = ({managedEffect, requestChildren, retireRequestAliases,
    assertCurrent, signal, ...facts}: BackingFacts<Member>) => {
    if (managedEffect === undefined) return recoveredEntries(facts);
    if (managedEffect.runtime !== moon || managedEffect.closed) reject('ForeignInstalledEffectManagedRun');
    const controlConstruction = managedEffect.controlConstruction;
    if (typeof controlConstruction !== 'function') reject('InstalledEffectControlRuntimeUnavailable');
    let input = managedEffect.recoveredRequestInput;
    if (input === undefined) {
      // This input remains on the SAME Plan's original constructor backing.
      // The transient recovery stage borrows it; closing that stage is not
      // retirement of a still-needed hot-reconciliation request body.
      input = controlConstruction(undefined, (): RecoveryBacking<Member> => ({
        body: facts.body, previewWire: facts.previewWire, members: facts.members,
        connectorRecovery: facts.durable.connectorRecovery, result: undefined,
        children: [], borrowers: 0, retiring: false, draining: false, failed: false, failure: undefined,
        retire() {
          if (this.borrowers !== 0 || this.draining) return false;
          this.draining = true;
          try {
            this.retiring = true;
            this.result = this.body = this.members = this.connectorRecovery = undefined;
            for (const child of this.children) {
              if (child.status().pending && child.release() !== true) return false;
            }
            this.children.length = 0;
            this.failure = undefined;
            return true;
          } finally {this.draining = false;}
        },
      }), []);
      managedEffect.recoveredRequestInput = input;
      try {
        const calls: PrepareRecovery[] = [], growers = new Map<number, GrowRecoveryInput>(), members = facts.members;
        const reserveRecoveryInput = (memberIndex: number, metadata: unknown) => {
          const grow = growers.get(memberIndex);
          if (typeof grow !== 'function') reject('InstalledEffectRecoveryConstructionUnavailable');
          grow(metadata);
        };
        for (const [index, member] of members.entries()) {
          const recipe = recipeOf(member), selected = recipe?.recoveryConstruction;
          const operation = selected === undefined ? undefined : recipe!.memberOperations[selected.operationIndex]?.operation;
          if (operation === undefined || selected!.operationIndex === recipe!.captureConstruction?.operationIndex) {
            reject('InstalledEffectRecoveryConstructionUnavailable');
          }
          const original = prepareInstalledEffectRequestChild({run: managedEffect,
            memberIndex: member.memberIndex, perRow: false, rowIndex: 0,
            operationIndex: selected!.operationIndex, operation,
            ...(selected!.inputExtent === undefined ? {} : {inputExtent: () =>
              controlConstruction(undefined, selected!.inputExtent as InputExtent,
                [facts.previewWire, facts.durable.connectorRecovery, member.memberIndex])}),
            construct: grow => {
              if (selected!.inputExtent !== undefined) growers.set(member.memberIndex, metadata =>
                grow(controlConstruction(undefined, selected!.inputExtent as InputExtent,
                  [facts.previewWire, facts.durable.connectorRecovery, member.memberIndex, metadata])));
              try {
                return index + 1 === members.length
                  ? recoveredEntries({...facts, reserveRecoveryInput}) : calls[index + 1]();
              } finally {growers.delete(member.memberIndex);}
            },
            requestsRetired: () => input!.retiring && input!.borrowers === 0 && input!.result === undefined});
          // The raw selected constructor is synchronous. Retain before any
          // subsequent fence/failure; only final control retirement releases it.
          input.children.push(original);
          original.checkOriginal();
          const prepare = original.prepare;
          calls.push(() => Reflect.apply(prepare, original, []) as RecoveryResult);
        }
        signal?.throwIfAborted();assertCurrent?.();
        input.result = calls[0]();
        signal?.throwIfAborted();assertCurrent?.();
      } catch (cause) {input.failed = true;input.failure = cause;throw cause;}
    } else {
      if (input.retiring) reject('InstalledEffectRecoveryInputRetired');
      if (input.failed) throw input.failure;
      if (input.result === undefined) reject('InstalledEffectRecoveryInputPending');
      // Actual admitted Preview and original installed member owners remain
      // mandatory. A matching request CID, copied graph or new installation
      // cannot substitute for the original input or its physical backing.
      controlConstruction(undefined, () => {
        if (input!.body !== facts.body || input!.previewWire !== facts.previewWire ||
            input!.members!.length !== facts.members.length ||
            !sameValue(input!.connectorRecovery, facts.durable.connectorRecovery) ||
            input!.members!.some((member, index) => ownerOf(member) !== ownerOf(facts.members[index]) ||
              member.kind !== facts.members[index].kind || member.memberIndex !== facts.members[index].memberIndex ||
              member.effectId !== facts.members[index].effectId || member.mapping !== facts.members[index].mapping ||
              member.command !== facts.members[index].command)) reject('ForeignInstalledRowEffectRequest');
        for (const child of input!.children) {
          if (child.status().pending !== true) reject('InstalledEffectRecoveryInputRetired');
          child.checkOriginal();
        }
        facts.members.forEach((member, index) => {
          for (const entry of input!.result!.entries[index]) {
            if (entry.requestCid !== ownerOf(member).owned.requestCid(entry.request)) {
              reject('ForeignInstalledRowEffectRequest');
            }
          }
        });
        validateRecoveredEntries(facts, input!.result!.entries);
      }, []);
    }
    signal?.throwIfAborted();assertCurrent?.();
    if (input.borrowers !== 0) reject('InstalledEffectRecoveryInputBorrowed');
    let returned = false, borrowed: RecoveryBacking<Member> | undefined = input,
      retireAliases: (() => boolean) | undefined = retireRequestAliases;
    const release = () => {
      if (returned) return;
      if (retireAliases!() !== true) return false;
      returned = true;
      borrowed!.borrowers--;
      borrowed = retireAliases = undefined;
    };
    // Keep the original borrow in the existing stage cleanup bag before its
    // value escapes. Only its actual alias/route retirement returns the borrow.
    input.borrowers++;
    requestChildren.push({prepared: Object.freeze({release, retry: release,
      status: () => Object.freeze({pending: !returned})})});
    return input.result!;
  };

  return prepareRecoveredEntries;
}
