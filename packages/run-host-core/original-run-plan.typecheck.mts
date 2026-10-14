import {captureOriginalRunPlan, originalRunPlanAdmissionEvidence,
  readStoredRunPlanOriginal, type PreparedProgram, type ValuesCompilation,
  type TaskCompilation, type EffectCompilation, type RunAdmission,
  type RunDefinition, type PublicationLimits, type StoredRunPlanOriginal} from '@actql/run-host-core';

declare const prepared: PreparedProgram, values: ValuesCompilation, tasks: TaskCompilation;
declare const effects: EffectCompilation, admission: RunAdmission, definition: RunDefinition;
declare const limits: PublicationLimits, programCid: string;
declare const evidence: Readonly<{prepared: string; authorization: string}>;
const selected = captureOriginalRunPlan(prepared, values, admission, definition, limits);
captureOriginalRunPlan(prepared, tasks, admission, definition, limits);
const saved: StoredRunPlanOriginal = originalRunPlanAdmissionEvidence(selected, definition, programCid, evidence);
const wire: string = readStoredRunPlanOriginal(saved, definition, programCid, limits);
readStoredRunPlanOriginal(undefined, definition, programCid, limits);
void wire;
// @ts-expect-error Restoring metadata cannot reissue first-capture provenance.
originalRunPlanAdmissionEvidence(saved, definition, programCid, evidence);
// @ts-expect-error No fabricated original capture handle.
originalRunPlanAdmissionEvidence({}, definition, programCid, evidence);
// @ts-expect-error Effect support is not advertised by a Values/Tasks projection.
captureOriginalRunPlan(prepared, effects, admission, definition, limits);
// @ts-expect-error Durable original bytes are immutable.
saved.planViewWire = '{}';
