// Trusted installation evidence for the existing acquisition planner. This
// module neither chooses a winner nor grants provider access. Estimates are
// assertions scoped to exact input conditions, never measured resource limits.
import {checked} from '../../../host-common/runtime-result.mjs';

const names = Object.freeze(['nativeQuery', 'broadQuery']);
const sourceKeys = Object.freeze(['database', 'schema', 'sourceRef', 'table']);
const quantityKeys = Object.freeze(['moneyUnits', 'retainedBytes', 'transferBytes']);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const keys = (value, expected) => object(value) &&
  Object.keys(value).sort().join('\0') === [...expected].sort().join('\0');
const quantity = value => value === null || Number.isSafeInteger(value) && value >= 0 && !Object.is(value, -0);
const fail = () => { throw new TypeError('InvalidInstalledAcquisitionPlanning'); };

export function freezeAcquisitionDiagnostic(value) {
  if (object(value) || Array.isArray(value)) {
    for (const child of Object.values(value)) freezeAcquisitionDiagnostic(child);
    Object.freeze(value);
  }
  return value;
}

export function checkDuckDBAcquisitionPlanning(value) {
  if (!object(value)) fail();
  if (value.policy === 'priority') {
    if (!keys(value, ['policy', 'priority']) || !Array.isArray(value.priority) ||
        value.priority.length !== 2 || new Set(value.priority).size !== 2 ||
        value.priority.some(name => !names.includes(name))) fail();
  } else if (value.policy === 'estimatedLatency') {
    if (!keys(value, ['policy', 'candidates']) || !object(value.candidates) ||
        Object.keys(value.candidates).some(name => !names.includes(name))) fail();
    for (const [name, estimate] of Object.entries(value.candidates)) {
      if (!keys(estimate, ['inputConditions', 'unit', 'basis', 'estimates', 'quantities']) ||
          !keys(estimate.inputConditions, ['requirementCid', 'source']) ||
          !/^sha256:[0-9a-f]{64}$/u.test(estimate.inputConditions.requirementCid) ||
          !keys(estimate.inputConditions.source, sourceKeys) ||
          !Object.values(estimate.inputConditions.source).every(value =>
            typeof value === 'string' && value.length > 0 && value.length <= 4096) ||
          estimate.unit !== 'milliseconds' || typeof estimate.basis !== 'string' ||
          estimate.basis.trim().length === 0 || estimate.basis.length > 1024 ||
          !Array.isArray(estimate.estimates) || estimate.estimates.length > 11 ||
          !keys(estimate.quantities, quantityKeys) ||
          !Object.values(estimate.quantities).every(quantity)) fail();
      for (const line of estimate.estimates) {
        if (!keys(line, ['workSlots', 'milliseconds']) || !Array.isArray(line.workSlots) ||
            line.workSlots.length > 11 || !quantity(line.milliseconds) ||
            line.workSlots.some(slot => !Number.isInteger(slot) || slot < 0 ||
              slot >= (name === 'nativeQuery' ? 11 : 8))) fail();
      }
    }
  } else fail();
  // Installation owns this snapshot; later caller mutation cannot revise it.
  return freezeAcquisitionDiagnostic(structuredClone(value));
}

// Called only after the current read gate and mandatory physical limits pass.
// The common owner validates work coverage, compares the actual candidates,
// and retains the selected payload. The source tuple uses exact strings;
// canonical text normalization cannot make different physical files equal.
export function selectInstalledDuckDBAcquisition({moon, requirement, schema,
  table, contracts, source, planning}) {
  const policy = planning === undefined
    ? {policy: 'estimatedLatency', candidates: {}}
    : checkDuckDBAcquisitionPlanning(planning);
  const requirementCid = moon.clientProgramQueryRequirementCid(requirement);
  const missingEvidence = [];
  const admitted = {};
  const unknown = () => checked(moon.clientProgramDuckDBAcquisitionEstimate(
    [], [], [undefined, undefined, undefined]));
  const estimates = names.map(name => {
    if (policy.policy === 'priority') return unknown();
    const evidence = policy.candidates[name];
    if (evidence === undefined) {
      missingEvidence.push(`${name}.evidence`);
      return unknown();
    }
    const missing = [];
    if (evidence.inputConditions.requirementCid !== requirementCid) {
      missing.push(`${name}.inputConditions.requirementCid`);
    }
    for (const key of sourceKeys) {
      if (evidence.inputConditions.source[key] !== source[key]) {
        missing.push(`${name}.inputConditions.source.${key}`);
      }
    }
    if (missing.length !== 0) {
      missingEvidence.push(...missing);
      return unknown();
    }
    admitted[name] = evidence;
    const optional = value => value === null ? undefined : BigInt(value);
    return checked(moon.clientProgramDuckDBAcquisitionEstimate(
      evidence.estimates.map(line => line.workSlots),
      evidence.estimates.map(line => optional(line.milliseconds)),
      ['transferBytes', 'retainedBytes', 'moneyUnits'].map(key => optional(evidence.quantities[key]))));
  });
  const selected = checked(moon.clientProgramSelectDuckDBAcquisition(requirement,
    schema, table, ...contracts, ...estimates,
    policy.policy === 'priority' ? policy.priority : []));
  const report = JSON.parse(moon.clientProgramDuckDBSelectionDocument(selected));
  const eligible = new Set(report.candidates.map(candidate => candidate.candidate));
  const selection = freezeAcquisitionDiagnostic({...report,
    policy: policy.policy,
    ...(policy.policy === 'priority' ? {priority: policy.priority} : {}),
    evidence: admitted,
    missing: [...report.missing, ...missingEvidence.filter(field =>
      eligible.has(field.split('.')[0]))]});
  return {selection, native: moon.clientProgramDuckDBSelectionNative(selected),
    broad: moon.clientProgramDuckDBSelectionBroad(selected)};
}
