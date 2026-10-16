// Projections of the existing prepared/Run and installed row owners. These
// bytes live in their existing request and Checkpoint custody; they never
// resolve aliases, issue permissions or establish another recovery authority.
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson as valueJson} from '../../packages/sdk/host-port.mjs';
import {installedEffectFor} from './installed-effect-inventory.mjs';
import {installedRowEffectOwnerBinding, validateInstalledUpdateOwnerSelections} from
  './installed-row-effect.mjs';
import {refusedEffectPreparation} from '../host-common/effect-preparation-result.mjs';

import {installationsShape, updateTargetPreparedOriginalShape, updateTargetRunOriginalShape,
  runUpdateSelectionCid, updateTargetSelectionsCid}
  from './update-target-original-shape.mjs';
const wire = value => typeof value === 'string' && value.length > 0 &&
  Buffer.byteLength(value) <= 1024 * 1024;
const fail = () => { throw refusedEffectPreparation(Object.assign(
  new Error('InstalledEffectOriginalSelectionChanged'), {code: 'InstalledEffectOriginalSelectionChanged'})); };
const same = (a, b) => valueJson(a, {dataKeys: true}) === valueJson(b, {dataKeys: true});

export function installUpdateTargetOriginals({moon, control, installedEffect, limits,
  features = [false, true, true, true, true, false, false]}) {
  const compilations = new WeakMap();
  const readSelections = value => {
    if (value === undefined) return undefined;
    if (!wire(value)) fail();
    let result;
    try { result = JSON.parse(value); } catch { fail(); }
    if (!Array.isArray(result) || result.length === 0 || result.length > 1024 ||
        valueJson(result, {dataKeys: true}) !== value) fail();
    return result;
  };
  const selectionsOf = prepared =>
    readSelections(moon.clientProgramEffectTargetSelections(prepared));
  const descriptors = selections => selections.map(value => ({kind: 'update',
    effectId: value.effect_id, target: value.target_ref,
    mappingRef: value.mapping_ref, mappingCid: value.mapping_cid}));
  const current = selections => {
    if (selections === undefined) return undefined;
    const originals = new Map();
    for (const [index, descriptor] of descriptors(selections).entries()) {
      const owner = installedEffectFor(installedEffect, [descriptor]);
      validateInstalledUpdateOwnerSelections(owner, [selections[index]]);
      const original = installedRowEffectOwnerBinding(owner);
      if (original === undefined || original.cid !== selections[index].installation_owner_cid) fail();
      originals.set(original.cid, original);
    }
    return [...originals.values()].sort((a, b) => a.cid.localeCompare(b.cid));
  };
  const bind = (selections, installations) => {
    if (selections === undefined || !installationsShape(installations)) fail();
    installations = Object.freeze(installations.map(value => Object.freeze({...value})));
    const assertUpdateSelectionCurrent = () => {
      if (!same(current(selections), installations)) fail();
    };
    assertUpdateSelectionCurrent();
    return Object.freeze({updateTargetSelections: Object.freeze(selections.map(Object.freeze)),
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
    if (!updateTargetPreparedOriginalShape(original)) fail();
    return Object.freeze(original);
  };
  const restorePrepared = original => {
    if (!updateTargetPreparedOriginalShape(original)) fail();
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
    if (!updateTargetRunOriginalShape(original)) fail();
    const expectedSelectionCid = runUpdateSelectionCid(runDefinition);
    if (expectedSelectionCid === undefined) fail();
    const restored = checked(moon.clientProgramAdmitEffectRunMaterials(original.materialsWire,
      runDefinition.identity, ...features, identity ?? null));
    const prepared = moon.clientProgramEffectRunMaterialsPrepared(restored);
    const compilation = moon.clientProgramEffectRunMaterialsCompilation(restored);
    const allowed = moon.clientProgramEffectRunMaterialsAllowed(restored);
    const definition = moon.clientProgramEffectRunMaterialsDefinition(restored);
    const selections = readSelections(checked(moon.clientProgramEffectRunMaterialsTargetSelections(restored)));
    if (updateTargetSelectionsCid(selections) !== expectedSelectionCid) fail();
    const bound = bind(selections, original.installations);
    if (!same(selectionsOf(prepared), selections)) fail();
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
      if (runUpdateSelectionCid({wire: moon.strategyPublicationContractJson(definition)}) !==
          updateTargetSelectionsCid(selections)) fail();
      const original = {materialsWire: checked(moon.clientProgramIssuePreparedEffectRunMaterials(
        allowed, definition, identity ?? null)), installations: Object.freeze(current(selections))};
      if (!updateTargetRunOriginalShape(original)) fail();
      return Object.freeze(original);
    },
    validateRun({prepared, compilation, evidence, runDefinition, identity}) {
      const selections = selectionsOf(prepared);
      const original = evidence.updateTargetRunOriginal;
      const expectedSelectionCid = runUpdateSelectionCid(runDefinition);
      if (selections === undefined && original === undefined && expectedSelectionCid === undefined) return {};
      if (selections === undefined || original === undefined ||
          expectedSelectionCid !== updateTargetSelectionsCid(selections) ||
          !updateTargetRunOriginalShape(original, evidence)) fail();
      const restored = restoreRun(original, runDefinition, identity);
      if (!same(capturePrepared(prepared, compilation),
        capturePrepared(restored.prepared, restored.compilation))) fail();
      return {updateTargetSelections: restored.updateTargetSelections,
        assertUpdateSelectionCurrent: restored.assertUpdateSelectionCurrent};
    },
  });
}
