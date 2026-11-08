// Physical conversion only. The existing MoonBit selection Owner defines
// fields, constraints, canonical identities and original-material matching.
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {encodeUpdateTargetData, encodeUpdateTargetOriginalData} from './update-target-data.generated.mjs';

// Conversion aliases borrow Common's opaque original. Copying every DATA
// property cannot copy this association; Common still checks the original on
// every use. This is not another selection issuer or semantic registry.
const selectionOriginals = new WeakMap();
const invalid = () => { throw new TypeError('InvalidEffectTargetSelections'); };

export function retainUpdateTargetSelection(moon, prepared) {
  const originals = moon.clientProgramEffectTargetSelectionOriginal(prepared);
  if (originals.length === 0) return undefined;
  if (originals.length !== 1) invalid();
  const original = originals[0];
  if (!moon.clientProgramEffectTargetSelectionMatchesPrepared(original, prepared)) invalid();
  const entries = JSON.parse(moon.clientProgramEffectTargetSelectionWire(original));
  for (const entry of entries) Object.freeze(entry);
  // This is a conversion alias, not a new issuer. Every semantic operation
  // checks the original opaque value with its original prepared Owner again.
  selectionOriginals.set(entries, Object.freeze({moon, original, prepared}));
  return Object.freeze(entries);
}

export function assertUpdateTargetSelectionCurrent(selections, observations, prepared) {
  const binding = selectionOriginals.get(selections);
  if (binding === undefined || !binding.moon.clientProgramEffectTargetSelectionCurrent(
    binding.original, prepared ?? binding.prepared, encodeUpdateTargetData(observations))) invalid();
}

export function updateTargetSelectionMatchesRun(selections, prepared, definition) {
  const binding = selectionOriginals.get(selections);
  return binding !== undefined && binding.prepared === prepared &&
    binding.moon.clientProgramEffectTargetSelectionMatchesRun(
      binding.original, prepared, definition);
}

export function assertUpdateTargetSelectionMembersCurrent(selections, members, prepared) {
  const binding = selectionOriginals.get(selections);
  if (binding === undefined || !binding.moon.clientProgramEffectTargetSelectionMembersCurrent(
    binding.original, prepared ?? binding.prepared, encodeUpdateTargetData(members))) invalid();
}

export function issueUpdateTargetInstallation(moon, facts) {
  const original = checked(moon.clientProgramIssueEffectTargetInstallation(encodeUpdateTargetData(facts)));
  return Object.freeze({cid: runtimeField(original, 0), wire: runtimeField(original, 1)});
}

export function updateTargetOriginalDataEqual(moon, left, right) {
  try {
    return moon.clientProgramEffectTargetOriginalDataEqual(
      encodeUpdateTargetOriginalData(left), encodeUpdateTargetOriginalData(right));
  } catch { return false; }
}

export function installationsShape(values, moon) {
  try { return moon.clientProgramEffectTargetInstallationsShape(encodeUpdateTargetData(values)); }
  catch { return false; }
}

export function updateTargetPreparedOriginalShape(value, moon) {
  try { return moon.clientProgramEffectTargetPreparedOriginalShape(encodeUpdateTargetOriginalData(value)); }
  catch { return false; }
}

export function updateTargetRunOriginalShape(value, evidence, moon) {
  try {
    return moon.clientProgramEffectTargetRunOriginalShape(encodeUpdateTargetOriginalData(value),
      evidence === undefined ? [] : [evidence.prepared, evidence.authorization]);
  } catch { return false; }
}

export function runUpdateSelectionCid(runDefinition, moon) {
  return checked(moon.clientProgramEffectTargetRunSelectionCid(runDefinition.wire))[0];
}

export function updateTargetSelectionsCid(selections, moon) {
  const binding = selectionOriginals.get(selections);
  if (binding !== undefined) {
    if (moon !== undefined && moon !== binding.moon ||
        !binding.moon.clientProgramEffectTargetSelectionMatchesPrepared(binding.original, binding.prepared)) invalid();
    return binding.moon.clientProgramEffectTargetSelectionCid(binding.original);
  }
  // Compatibility DATA projection is not nominal selection admission.
  if (moon === undefined) invalid();
  return checked(moon.clientProgramEffectTargetSelectionDataCid(encodeUpdateTargetData(selections)));
}

// Original-custody callers require the retained opaque borrow. The separate
// compatibility DATA digest above never authenticates a copied selection.
export function originalUpdateTargetSelectionsCid(selections, moon) {
  if (!selectionOriginals.has(selections)) invalid();
  return updateTargetSelectionsCid(selections, moon);
}

// Private trusted installation for the existing request journal. It exposes
// only the same Owner's bounded DATA check, never a restoration/send issuer.
export function createUpdateTargetOriginalShapeControl(moon) {
  return Object.freeze({run: (value, evidence) => updateTargetRunOriginalShape(value, evidence, moon)});
}
