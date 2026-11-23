// Private DATA of the SAME failed typed dispatch. No error-shape classifier,
// Owner/Run/Scope alias, feasibility retry or late ledger sample is retained.
import {runtimeField, runtimeUnboxedReferenceOption} from './compiler-binding.generated.mjs';

const originals = new WeakMap();
const codePattern = /^[a-z_]+$/u;
const serializationRowLimit = Object.freeze({primaryDiagnostic: Object.freeze({
  code: 'MoonBitHostFailure', phase: 'serialization_input', kind: 'row_limit',
})});

export function rememberOriginalSerializationRowLimit(error) {
  originals.set(error, serializationRowLimit);
}

export function rememberOriginalDispatchFailure(error, original) {
  if (originals.has(error)) return;
  const view = runtimeUnboxedReferenceOption(original);
  if (view === undefined) return;
  const phase = runtimeField(view, 0), kind = runtimeField(view, 1);
  const task = runtimeField(view, 2), assessmentCount = runtimeField(view, 3);
  const complete = runtimeField(view, 4), truncated = runtimeField(view, 5);
  const records = runtimeField(view, 6), unavailable = runtimeField(view, 7);
  if (phase !== 'adaptive_dispatch' || typeof kind !== 'string' ||
      kind.length === 0 || kind.length > 64 || !codePattern.test(kind) ||
      !Number.isInteger(task) || task < 0 || task > 2147483647 ||
      !Number.isInteger(assessmentCount) || assessmentCount < 0 || assessmentCount > 2147483647 ||
      typeof complete !== 'boolean' || typeof truncated !== 'boolean' ||
      !Array.isArray(records) || records.length !== Math.min(assessmentCount, 8) ||
      truncated !== (assessmentCount > records.length) || unavailable !== 'unavailable' ||
      // Only the Common-owned NoStrategy branch has a current search report.
      (kind !== 'no_strategy' && (assessmentCount !== 0 || complete || truncated))) {
    throw new TypeError('InvalidOriginalDispatchFailure');
  }
  // The maximum and closed strings come from the typed Common export. These
  // are representation checks, not a second Ledger/refusal spelling table.
  const assessments = records.map(record => {
    const position = runtimeField(record, 0);
    const rejection = runtimeUnboxedReferenceOption(runtimeField(record, 1));
    if (!Number.isInteger(position) || position < 0 || position > 2147483647 ||
        (rejection !== undefined && (typeof rejection !== 'string' ||
          rejection.length > 64 || !codePattern.test(rejection)))) {
      throw new TypeError('InvalidOriginalDispatchAssessment');
    }
    return Object.freeze({position, rejection: rejection ?? null});
  });
  originals.set(error, Object.freeze({primaryDiagnostic: Object.freeze({
    code: 'MoonBitHostFailure', phase, kind, task, assessmentCount, complete,
    truncated, decision: unavailable, candidateCount: unavailable,
    assessments: Object.freeze(assessments),
  })}));
}

export function originalDispatchFailureSnapshot(error) {
  return originals.get(error);
}
