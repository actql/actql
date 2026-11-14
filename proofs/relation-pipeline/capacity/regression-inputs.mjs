import assert from 'node:assert/strict';
import { capacityObligationsByPart, partRole } from '../proof-parts.mjs';

// One invocation owns these read-only inputs. Never retain a validation result:
// every substituted report still traverses the complete capacity validator.
function freeze(value) {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
}

export function prepareCapacityRegressionInputs(original, current, read) {
  // Parsed originals stay private. Each case receives independent mutable
  // clones, including executions, owners and nested source dictionaries.
  const parts = original.parts.map(({ path }) => ({ path, report: JSON.parse(read(path)) }));
  return Object.freeze({
    current: freeze(structuredClone(current)),
    parts: () => structuredClone(parts),
  });
}
// Keep a substituted full union internally consistent with all immutable-part
// views, without broadening either mutant subset or rewriting any owner/receipt.
export function substituteCapacityRegressionParts(parts, report) {
  for (const { report: part } of parts) {
    for (const key of Object.keys(part)) if (Object.hasOwn(report, key) &&
        !['part', 'kind', 'executions', 'executionOwners', 'timings', 'complete', 'targets'].includes(key)) {
      if (key === 'mutations') {
        const names = capacityObligationsByPart[part.part].mutations;
        part.mutations = structuredClone(report.mutations.filter(m => names.includes(m.name)));
      } else if (key === 'postRestore') {
        assert.equal(partRole(part.part), 'capacity-mutants');
        const selected = report.postRestore.parts.find(r => r.part === part.part);
        assert(selected, 'Missing substituted post-restore fragment');
        const { part: _id, ...original } = selected;
        part.postRestore = structuredClone(original);
      } else part[key] = structuredClone(report[key]);
    }
  }
  return parts;
}
