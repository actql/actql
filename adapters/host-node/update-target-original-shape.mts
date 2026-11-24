// Physical conversion only. The existing MoonBit selection Owner defines
// fields, constraints, canonical identities and original-material matching.
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {encodeUpdateTargetData, encodeUpdateTargetOriginalData} from './update-target-data.generated.mjs';

export type UpdateTargetRuntime = Readonly<{
  clientProgramEffectTargetSelectionOriginal(prepared: unknown): readonly unknown[];
  clientProgramEffectTargetSelectionMatchesPrepared(original: unknown, prepared: unknown): boolean;
  clientProgramEffectTargetSelectionWire(original: unknown): string;
  clientProgramEffectTargetSelectionCurrent(original: unknown, prepared: unknown, observations: string): boolean;
  clientProgramEffectTargetSelectionCurrentData?(original: unknown, prepared: unknown,
    installations: readonly unknown[], observations: string): boolean;
  clientProgramEffectTargetSelectionMatchesRun(original: unknown, prepared: unknown, definition: unknown): boolean;
  clientProgramEffectTargetSelectionMembersCurrent(original: unknown, prepared: unknown, members: string): boolean;
  clientProgramIssueEffectTargetInstallation(facts: string): unknown;
  clientProgramIssueEffectTargetInstallationData(facts: readonly string[]): unknown;
  clientProgramEffectTargetOriginalDataEqual(left: string, right: string): boolean;
  clientProgramEffectTargetInstallationsShape(wire: string): boolean;
  clientProgramEffectTargetPreparedOriginalShape(wire: string): boolean;
  clientProgramEffectTargetRunOriginalShape(wire: string, evidence: readonly string[]): boolean;
  clientProgramEffectTargetRunSelectionCid(wire: string): unknown;
  clientProgramEffectTargetSelectionCid(original: unknown): string;
  clientProgramEffectTargetSelectionDataCid(wire: string): unknown;
}>;
type SelectionRuntime = Pick<UpdateTargetRuntime,
  'clientProgramEffectTargetSelectionOriginal' | 'clientProgramEffectTargetSelectionMatchesPrepared' |
  'clientProgramEffectTargetSelectionWire' | 'clientProgramEffectTargetSelectionCurrent' |
  'clientProgramEffectTargetSelectionCurrentData' | 'clientProgramEffectTargetSelectionMatchesRun' |
  'clientProgramEffectTargetSelectionMembersCurrent' | 'clientProgramEffectTargetSelectionCid'>;
type DataCidRuntime = Pick<UpdateTargetRuntime, 'clientProgramEffectTargetSelectionDataCid'>;
type SelectionBinding = Readonly<{moon: SelectionRuntime; original: unknown; prepared: unknown}>;
type SelectionEntry = Readonly<{
  stage_index: number; effect_id: string; target_ref: string; mapping_ref: string; mapping_cid: string;
  check_environment_cid: string; installation_binding_cid: string; installation_owner_cid: string;
}>;
type RunEvidence = Readonly<{prepared: string; authorization: string}>;

// Conversion aliases borrow Common's opaque original. Copying every DATA
// property cannot copy this association; Common still checks the original on
// every use. This is not another selection issuer or semantic registry.
const selectionOriginals = new WeakMap<object, SelectionBinding>();
const invalid: () => never = () => { throw new TypeError('InvalidEffectTargetSelections'); };

export function retainUpdateTargetSelection(moon: SelectionRuntime, prepared: unknown) {
  const originals = moon.clientProgramEffectTargetSelectionOriginal(prepared);
  if (originals.length === 0) return undefined;
  if (originals.length !== 1) invalid();
  const original = originals[0];
  if (!moon.clientProgramEffectTargetSelectionMatchesPrepared(original, prepared)) invalid();
  const entries = JSON.parse(moon.clientProgramEffectTargetSelectionWire(original)) as SelectionEntry[];
  for (const entry of entries) Object.freeze(entry);
  // This is a conversion alias, not a new issuer. Every semantic operation
  // checks the original opaque value with its original prepared Owner again.
  selectionOriginals.set(entries, Object.freeze({moon, original, prepared}));
  return Object.freeze(entries);
}

export function assertUpdateTargetSelectionCurrent(selections: unknown, observations: unknown, prepared?: unknown) {
  const binding = selectionOriginals.get(selections as object);
  if (binding === undefined || !binding.moon.clientProgramEffectTargetSelectionCurrent(
    binding.original, prepared ?? binding.prepared, encodeUpdateTargetData(observations))) invalid();
}

export function assertUpdateTargetSelectionCurrentData(selections: unknown, observations: unknown,
  installations: readonly unknown[], prepared?: unknown) {
  const binding = selectionOriginals.get(selections as object);
  if (binding === undefined || typeof binding.moon.clientProgramEffectTargetSelectionCurrentData !== 'function' ||
      binding.moon.clientProgramEffectTargetSelectionCurrentData(binding.original,
        prepared ?? binding.prepared, installations, encodeUpdateTargetData(observations)) !== true) invalid();
}

export function updateTargetSelectionMatchesRun(selections: unknown, prepared: unknown, definition: unknown) {
  const binding = selectionOriginals.get(selections as object);
  return binding !== undefined && binding.prepared === prepared &&
    binding.moon.clientProgramEffectTargetSelectionMatchesRun(
      binding.original, prepared, definition);
}

export function assertUpdateTargetSelectionMembersCurrent(selections: unknown, members: unknown, prepared?: unknown) {
  const binding = selectionOriginals.get(selections as object);
  if (binding === undefined || !binding.moon.clientProgramEffectTargetSelectionMembersCurrent(
    binding.original, prepared ?? binding.prepared, encodeUpdateTargetData(members))) invalid();
}

export function issueUpdateTargetInstallation(moon: Pick<UpdateTargetRuntime, 'clientProgramIssueEffectTargetInstallation'>, facts: unknown) {
  const original = checked(moon.clientProgramIssueEffectTargetInstallation(encodeUpdateTargetData(facts)));
  return Object.freeze({cid: runtimeField(original, 0) as string, wire: runtimeField(original, 1) as string});
}

// Physical scalar slots of the existing Core installation port. All field
// constraints, NFC, canonical order/digest and virtual wire bounds stay there.
export function issueUpdateTargetInstallationData(moon: Pick<UpdateTargetRuntime, 'clientProgramIssueEffectTargetInstallationData'>, values: readonly string[]) {
  const original = checked(moon.clientProgramIssueEffectTargetInstallationData(values));
  return {installation: Object.freeze({cid: runtimeField(original, 0) as string, wire: runtimeField(original, 1) as string}),
    data: runtimeField(original, 2)};
}

export function updateTargetOriginalDataEqual(moon: Pick<UpdateTargetRuntime, 'clientProgramEffectTargetOriginalDataEqual'>, left: unknown, right: unknown) {
  try {
    return moon.clientProgramEffectTargetOriginalDataEqual(
      encodeUpdateTargetOriginalData(left), encodeUpdateTargetOriginalData(right));
  } catch { return false; }
}

export function installationsShape(values: unknown, moon: Pick<UpdateTargetRuntime, 'clientProgramEffectTargetInstallationsShape'>) {
  try { return moon.clientProgramEffectTargetInstallationsShape(encodeUpdateTargetData(values)); }
  catch { return false; }
}

export function updateTargetPreparedOriginalShape(value: unknown, moon: Pick<UpdateTargetRuntime, 'clientProgramEffectTargetPreparedOriginalShape'>) {
  try { return moon.clientProgramEffectTargetPreparedOriginalShape(encodeUpdateTargetOriginalData(value)); }
  catch { return false; }
}

export function updateTargetRunOriginalShape(value: unknown, evidence: RunEvidence | undefined,
  moon: Pick<UpdateTargetRuntime, 'clientProgramEffectTargetRunOriginalShape'>) {
  try {
    return moon.clientProgramEffectTargetRunOriginalShape(encodeUpdateTargetOriginalData(value),
      evidence === undefined ? [] : [evidence.prepared, evidence.authorization]);
  } catch { return false; }
}

export function runUpdateSelectionCid(runDefinition: Readonly<{wire: string}>,
  moon: Pick<UpdateTargetRuntime, 'clientProgramEffectTargetRunSelectionCid'>) {
  return (checked(moon.clientProgramEffectTargetRunSelectionCid(runDefinition.wire)) as readonly string[])[0] as string | undefined;
}

export function updateTargetSelectionsCid(selections: unknown, moon?: DataCidRuntime) {
  const binding = selectionOriginals.get(selections as object);
  if (binding !== undefined) {
    if (moon !== undefined && moon !== (binding.moon as object) ||
        !binding.moon.clientProgramEffectTargetSelectionMatchesPrepared(binding.original, binding.prepared)) invalid();
    return binding.moon.clientProgramEffectTargetSelectionCid(binding.original);
  }
  // Compatibility DATA projection is not nominal selection admission.
  if (moon === undefined) invalid();
  return checked(moon.clientProgramEffectTargetSelectionDataCid(encodeUpdateTargetData(selections))) as string;
}

// Original-custody callers require the retained opaque borrow. The separate
// compatibility DATA digest above never authenticates a copied selection.
export function originalUpdateTargetSelectionsCid(selections: unknown, moon?: object) {
  if (!selectionOriginals.has(selections as object)) invalid();
  return updateTargetSelectionsCid(selections, moon as DataCidRuntime | undefined);
}

// Private trusted installation for the existing request journal. It exposes
// only the same Owner's bounded DATA check, never a restoration/send issuer.
export function createUpdateTargetOriginalShapeControl(moon: Pick<UpdateTargetRuntime, 'clientProgramEffectTargetRunOriginalShape'>) {
  return Object.freeze({run: (value: unknown, evidence?: RunEvidence) => updateTargetRunOriginalShape(value, evidence, moon)});
}
