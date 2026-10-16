// Projections of the existing prepared/Run and installed row owners. These
// bytes live in their existing request and Checkpoint custody; they never
// resolve aliases, issue permissions or establish another recovery authority.
import {checked} from '../host-common/runtime-result.mjs';
import {installedEffectFor} from './installed-effect-inventory.mjs';
import {installedRowEffectOwnerBinding, installedRowEffectUpdateObservations} from
  './installed-row-effect.mjs';
import {refusedEffectPreparation} from '../host-common/effect-preparation-result.mjs';

import {installationsShape, updateTargetPreparedOriginalShape, updateTargetRunOriginalShape,
  runUpdateSelectionCid, originalUpdateTargetSelectionsCid as updateTargetSelectionsCid, retainUpdateTargetSelection,
  assertUpdateTargetSelectionCurrent, updateTargetSelectionMatchesRun,
  updateTargetOriginalDataEqual}
  from './update-target-original-shape.mjs';
const fail = () => { throw refusedEffectPreparation(Object.assign(
  new Error('InstalledEffectOriginalSelectionChanged'), {code: 'InstalledEffectOriginalSelectionChanged'})); };

export function installUpdateTargetOriginals({moon, control, installedEffect, limits,
  features = [false, true, true, true, true, false, false]}) {
  const compilations = new WeakMap();
  const same = (left, right) => updateTargetOriginalDataEqual(moon, left, right);
  const selectionsOf = prepared => retainUpdateTargetSelection(moon, prepared);
  const descriptors = selections => selections.map(value => ({kind: 'update',
    effectId: value.effect_id, target: value.target_ref,
    mappingRef: value.mapping_ref, mappingCid: value.mapping_cid}));
  const current = selections => {
    if (selections === undefined) return undefined;
    const originals = new Map();
    const observations = new Map();
    for (const descriptor of descriptors(selections)) {
      const owner = installedEffectFor(installedEffect, [descriptor]);
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
  const restoreRun = (original, runDefinition, identity) => {
    if (!updateTargetRunOriginalShape(original, undefined, moon)) fail();
    const expectedSelectionCid = runUpdateSelectionCid(runDefinition, moon);
    if (expectedSelectionCid === undefined) fail();
    const restored = checked(moon.clientProgramAdmitEffectRunMaterials(original.materialsWire,
      runDefinition.identity, ...features, identity ?? null));
    const prepared = moon.clientProgramEffectRunMaterialsPrepared(restored);
    const compilation = moon.clientProgramEffectRunMaterialsCompilation(restored);
    const allowed = moon.clientProgramEffectRunMaterialsAllowed(restored);
    const definition = moon.clientProgramEffectRunMaterialsDefinition(restored);
    // Retain the existing whole Run/material binding admission as well as the
    // nominal selection/preparation projection. No replacement Run is issued.
    checked(moon.clientProgramEffectRunMaterialsTargetSelections(restored));
    const selections = selectionsOf(prepared);
    if (selections === undefined || updateTargetSelectionsCid(selections, moon) !== expectedSelectionCid ||
        !updateTargetSelectionMatchesRun(selections, prepared, definition)) fail();
    const bound = bind(selections, original.installations);
    compilations.set(prepared, compilation);
    return Object.freeze({prepared, compilation, allowed, definition, ...bound});
  };
  return Object.freeze({selectionsOf, capturePrepared, restorePrepared, restoreRun,
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
      const restored = restoreRun(original, runDefinition, identity);
      if (!same(capturePrepared(prepared, compilation),
        capturePrepared(restored.prepared, restored.compilation))) fail();
      return {updateTargetSelections: restored.updateTargetSelections,
        assertUpdateSelectionCurrent: restored.assertUpdateSelectionCurrent};
    },
  });
}
