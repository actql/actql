// Projections of the existing prepared/Run and installed row owners. These
// bytes live in their existing request and Checkpoint custody; they never
// resolve aliases, issue permissions or establish another recovery authority.
import {checked} from '../host-common/runtime-result.mjs';
import {installedRowEffectOwnerBinding, installedRowEffectUpdateObservations,
  installedRowEffectDescriptors} from
  './installed-row-effect.mjs';
import {refusedEffectPreparation} from '../host-common/effect-preparation-result.mjs';

import {installationsShape, updateTargetPreparedOriginalShape, updateTargetRunOriginalShape,
  runUpdateSelectionCid, originalUpdateTargetSelectionsCid as updateTargetSelectionsCid, retainUpdateTargetSelection,
  assertUpdateTargetSelectionCurrent, assertUpdateTargetSelectionMembersCurrent, updateTargetSelectionMatchesRun,
  updateTargetOriginalDataEqual}
  from './update-target-original-shape.mjs';
const fail = () => { throw refusedEffectPreparation(Object.assign(
  new Error('InstalledEffectOriginalSelectionChanged'), {code: 'InstalledEffectOriginalSelectionChanged'})); };

export function installUpdateTargetOriginals({moon, control, installedEffect, limits,
  features = [false, true, true, true, true, false, false]}) {
  const compilations = new WeakMap();
  const admitWithCompilation = Object.getOwnPropertyDescriptor(moon,
    'clientProgramAdmitEffectRunMaterialsWithCompilation')?.value;
  const same = (left, right) => updateTargetOriginalDataEqual(moon, left, right);
  const selectionsOf = prepared => retainUpdateTargetSelection(moon, prepared);
  const current = selections => {
    if (selections === undefined) return undefined;
    const originals = new Map();
    const observations = new Map();
    for (const selection of selections) {
      // The opaque Common selection already fixes its installed Owner. Look
      // up that actual private owner, then let Common check its original
      // UPDATE/DELETE/STORE purpose and Mapping against current observations.
      // Reconstructing every selection as an UPDATE loses STORE's Command.
      const matches = (installedEffect?.effects ?? [installedEffect]).filter(owner =>
        installedRowEffectOwnerBinding(owner)?.cid === selection.installation_owner_cid);
      if (matches.length !== 1) fail();
      const owner = matches[0];
      const original = installedRowEffectOwnerBinding(owner);
      if (original === undefined) fail();
      originals.set(original.cid, original);
      for (const observation of installedRowEffectUpdateObservations(owner)) {
        observations.set(observation.installation.cid, observation);
      }
    }
    assertUpdateTargetSelectionCurrent(selections, [...observations.values()]);
    return [...originals.values()].sort((a, b) => a.cid.localeCompare(b.cid));
  };
  const bind = (selections, installations) => {
    if (selections === undefined || !installationsShape(installations, moon)) fail();
    installations = Object.freeze(installations.map(value => Object.freeze({...value})));
    const assertUpdateSelectionCurrent = () => {
      if (!same(current(selections), installations)) fail();
    };
    assertUpdateSelectionCurrent();
    return Object.freeze({updateTargetSelections: selections,
      assertUpdateSelectionCurrent});
  };
  const capturePrepared = (prepared, compilation) => {
    const selections = selectionsOf(prepared);
    if (selections === undefined) return undefined;
    const installations = current(selections);
    const compiled = control.admit('compiled_plan',
      moon.clientProgramEffectCompilationCompiledPlanWire(compilation), limits);
    const original = {preparedWire: checked(moon.clientProgramIssueEffectPreparedOriginal(compilation)),
      compiledPlanCid: compiled.identity, installations: Object.freeze(installations)};
    if (!updateTargetPreparedOriginalShape(original, moon)) fail();
    return Object.freeze(original);
  };
  const restorePrepared = original => {
    if (!updateTargetPreparedOriginalShape(original, moon)) fail();
    const restored = checked(moon.clientProgramAdmitEffectPreparedOriginal(
      original.preparedWire, original.compiledPlanCid, ...features));
    const prepared = moon.clientProgramEffectPreparedOriginalPrepared(restored);
    const compilation = moon.clientProgramEffectPreparedOriginalCompilation(restored);
    const bound = bind(selectionsOf(prepared), original.installations);
    if (!same(capturePrepared(prepared, compilation), original)) fail();
    compilations.set(prepared, compilation);
    return Object.freeze({prepared, compilation, ...bound});
  };
  const restoreEffectMaterials = (wire, runDefinition, identity, originalCompilation) => {
    if (originalCompilation !== undefined &&
        (typeof admitWithCompilation !== 'function' || identity === undefined)) fail();
    // The caller already retains/funds this nominal compiler. Bind saved full
    // materials to it instead of parsing/checking/compiling the Program again.
    // A wire-only cold caller keeps the existing restoration route until its
    // SAME Request owner supplies the actual compiler, never a data flag.
    const restored = checked(originalCompilation === undefined
      ? moon.clientProgramAdmitEffectRunMaterials(wire, runDefinition.identity, ...features, identity ?? null)
      : Reflect.apply(admitWithCompilation, moon,
        [wire, runDefinition.identity, originalCompilation, identity, ...features]));
    const prepared = moon.clientProgramEffectRunMaterialsPrepared(restored);
    const compilation = moon.clientProgramEffectRunMaterialsCompilation(restored);
    const allowed = moon.clientProgramEffectRunMaterialsAllowed(restored);
    const definition = moon.clientProgramEffectRunMaterialsDefinition(restored);
    return Object.freeze({materials: restored, prepared, compilation, allowed, definition});
  };
  const restoreRun = (original, runDefinition, identity, originalCompilation) => {
    if (!updateTargetRunOriginalShape(original, undefined, moon)) fail();
    const expectedSelectionCid = runUpdateSelectionCid(runDefinition, moon);
    if (expectedSelectionCid === undefined) fail();
    const restored = restoreEffectMaterials(original.materialsWire, runDefinition, identity, originalCompilation);
    const {prepared, compilation, definition} = restored;
    // Retain the existing whole Run/material binding admission as well as the
    // nominal selection/preparation projection. No replacement Run is issued.
    checked(moon.clientProgramEffectRunMaterialsTargetSelections(restored.materials));
    const selections = selectionsOf(prepared);
    if (selections === undefined || updateTargetSelectionsCid(selections, moon) !== expectedSelectionCid ||
        !updateTargetSelectionMatchesRun(selections, prepared, definition)) fail();
    const bound = bind(selections, original.installations);
    compilations.set(prepared, compilation);
    return Object.freeze({...restored, ...bound});
  };
  return Object.freeze({selectionsOf, capturePrepared, restorePrepared, restoreRun,
    restoreEffectMaterials,
    validateRecoveredSelectionMembers({prepared, compilation, selections, preview, stageIndex}) {
      current(selections);
      const descriptors = installedRowEffectDescriptors(moon, prepared, compilation);
      const members = preview.effects.flatMap(member => {
        if (member.effect_kind === 'update' || member.effect_kind === 'delete') {
          return [{stage_index: stageIndex, effect_id: member.effect_id,
            target_ref: member.target, mapping_ref: member.mapping,
            mapping_cid: member.resolved_mapping_contract_cid}];
        }
        const selected = selections?.filter(value => value.effect_id === member.effect_id) ?? [];
        if (selected.length === 0) return [];
        const actual = descriptors.filter(value => value.effectId === member.effect_id);
        if (selected.length !== 1 || actual.length !== 1 || member.effect_kind !== 'command' ||
            actual[0].kind !== 'command' || member.target !== actual[0].target ||
            member.contract !== actual[0].commandRef ||
            member.resolved_command_contract_cid !== actual[0].commandCid) fail();
        // Common's same-prepared selection has already established STORE,
        // not a generic Command. Bind the saved Command member to that exact
        // Mapping selection without relabeling either one as UPDATE.
        const selection = selected[0];
        return [{stage_index: stageIndex, effect_id: member.effect_id,
          target_ref: selection.target_ref, mapping_ref: selection.mapping_ref,
          mapping_cid: selection.mapping_cid}];
      });
      assertUpdateTargetSelectionMembersCurrent(selections, members, prepared);
    },
    captureEffectMaterials({allowed, definition, identity}) {
      return checked(moon.clientProgramIssuePreparedEffectRunMaterials(
        allowed, definition, identity ?? null));
    },
    compilationFor: prepared => compilations.get(prepared),
    validatePrepared(prepared) {
      const selections = selectionsOf(prepared);
      current(selections);
      return selections;
    },
    captureRun({prepared, allowed, definition, identity}) {
      const selections = selectionsOf(prepared);
      if (selections === undefined) return undefined;
      if (!updateTargetSelectionMatchesRun(selections, prepared, definition)) fail();
      const original = {materialsWire: checked(moon.clientProgramIssuePreparedEffectRunMaterials(
        allowed, definition, identity ?? null)), installations: Object.freeze(current(selections))};
      if (!updateTargetRunOriginalShape(original, undefined, moon)) fail();
      return Object.freeze(original);
    },
    validateRun({prepared, compilation, evidence, runDefinition, identity}) {
      const selections = selectionsOf(prepared);
      const original = evidence.updateTargetRunOriginal;
      const expectedSelectionCid = runUpdateSelectionCid(runDefinition, moon);
      if (selections === undefined && original === undefined && expectedSelectionCid === undefined) return {};
      if (selections === undefined || original === undefined ||
          expectedSelectionCid !== updateTargetSelectionsCid(selections, moon) ||
          !updateTargetRunOriginalShape(original, evidence, moon)) fail();
      const restored = restoreRun(original, runDefinition, identity, compilation);
      if (!same(capturePrepared(prepared, compilation),
        capturePrepared(restored.prepared, restored.compilation))) fail();
      // The restored pair authenticates the saved material. Execution keeps
      // this caller's preparation, so retain its own nominal selection too.
      return bind(selections, original.installations);
    },
  });
}
