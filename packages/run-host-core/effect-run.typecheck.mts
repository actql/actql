import {prepareEffect, compileEffect, issueAllowedEffectRun, issueEffectRunDefinition,
  issueEffectRunMaterials, admitEffectRunMaterials, effectExecutionShape, compileValues,
  prepareEffectRequest, effectSourceInputBinding, issueEffectSourceDispatch,
  prepareEffectRetainedTaskInputEdge, issueEffectRetainedTaskDispatch,
  effectTaskKeys, effectResultDefinitions, effectResultSchema, effectSourceEvidenceFacts, effectReviewCheckpointMembers,
  inspectEffectTaskProgress, prepareEffectTaskPhysicalStart,
  type PreparedProgram, type TaskCompilation,
  type ValuesSiteSelection, type RetainedTaskInput, type CheckEnvironment, type PreparedEffectProgram, type EffectCompilation,
  type AllowedEffectRun} from '@actql/run-host-core';
declare const environment: CheckEnvironment;
const prepared = prepareEffect('{}', 'json', environment);
const compiled = compileEffect(prepared);
const allowed = issueAllowedEffectRun(prepared, compiled, {
  executionContextCid: 'cid', hostPolicyCid: 'policy', expiresAt: 'time'});
const definition = issueEffectRunDefinition(allowed, 'scope', 'run', 'created', 'valid');
const memberIds: readonly string[] = effectReviewCheckpointMembers(allowed, definition, '');
// @ts-expect-error Member metadata is not approval and cannot be mutated.
memberIds.push('other');
// @ts-expect-error A prepared computation is not an allowed original Run.
effectReviewCheckpointMembers(prepared, definition, '');
const wire = issueEffectRunMaterials(allowed, definition,
  {format: 'json', document: '{}', environment, environmentWire: '{}'});
const restored = admitEffectRunMaterials(wire, 'definition', {rela: true});
effectExecutionShape(restored.prepared, restored.compilation);
effectTaskKeys(prepared, compiled);
effectResultDefinitions(prepared, compiled);
effectResultSchema(prepared, compiled, 'answer');
effectSourceEvidenceFacts(prepared, compiled, 0, 0);
declare const pure: PreparedProgram;
declare const pureCompilation: TaskCompilation;
// @ts-expect-error A Pure Program cannot replace the original Effect Owner.
effectTaskKeys(pure, compiled);
// @ts-expect-error Effect inventory retains its own typed compilation.
effectResultDefinitions(prepared, pureCompilation);
// @ts-expect-error Schema selection is a Result name, not an ordinal.
effectResultSchema(prepared, compiled, 0);
// @ts-expect-error A Result declaration is not an execution or approval permit.
issueEffectSourceDispatch(effectResultDefinitions(prepared, compiled), definition,
  prepareEffectRequest(prepared, compiled, 'authority', 'caller'), {});
// @ts-expect-error Effect computation is not an Effect-free Values Program.
compileValues(prepared);
// @ts-expect-error Opaque preparation cannot be constructed by a caller.
const copiedPreparation: PreparedEffectProgram = {};
// @ts-expect-error Compilation must be issued by the common Owner.
const copiedCompilation: EffectCompilation = {};
// @ts-expect-error A preparation is not an allowed Run or approval.
const copiedAllowed: AllowedEffectRun = prepared;
void [copiedPreparation, copiedCompilation, copiedAllowed];

declare const selection: ValuesSiteSelection;
declare const retainedInput: RetainedTaskInput;
const caller = prepareEffectRequest(prepared, compiled, 'authority', 'caller');
issueEffectRunMaterials(allowed, definition,
  {format: 'json', document: '{}', environment, environmentWire: '{}'}, caller);
if (restored.request) {
  issueEffectRunMaterials(restored.allowed, restored.definition,
    {format: 'json', document: '{}', environment, environmentWire: '{}'}, restored.request);
}
// @ts-expect-error Only the original opaque request Owner can be transported.
issueEffectRunMaterials(allowed, definition, {format: 'json', document: '{}', environment, environmentWire: '{}'}, {callerRequestId: 'caller'});
effectSourceInputBinding(compiled);
prepareEffectRetainedTaskInputEdge(allowed, definition);
issueEffectSourceDispatch(allowed, definition, caller, selection);
issueEffectRetainedTaskDispatch(allowed, definition, caller, selection, retainedInput);
const progress = inspectEffectTaskProgress(allowed, definition, 'authority', []);
prepareEffectTaskPhysicalStart(allowed, definition, 'authority', [], caller, caller,
  {taskKey: 'task', dispatchCid: 'dispatch', definitionCid: 'run', reserved: true,
    unstarted: true, authorized: true, cancelled: false, failed: false});
// @ts-expect-error Computation completion is not public Run completion.
progress.executionComplete;
// @ts-expect-error No effect-free state or publication projection is exposed.
progress.stateWire;
// @ts-expect-error A preparation cannot stand in for the original allowed Run.
inspectEffectTaskProgress(prepared, definition, 'authority', []);
// @ts-expect-error Claim facts have exact boolean fields.
prepareEffectTaskPhysicalStart(allowed, definition, 'authority', [], caller, caller, {reserved: true});
// @ts-expect-error A preparation is not the original allowed Effect Run.
issueEffectSourceDispatch(prepared, definition, caller, selection);
// @ts-expect-error Raw binding bytes cannot replace the admitted receiver owner.
issueEffectRetainedTaskDispatch(allowed, definition, caller, selection, {wire: '{}', cid: 'cid'});


// Live binding accepts only the existing nominal issuer tuple.
import {issuePreparedEffectRunMaterials, bindPreparedEffectRunMaterials,
  type RequestIdentity, type IssuedEffectRunMaterials} from '@actql/run-host-core';
declare const originalRequest: RequestIdentity;
const issuedMaterials: IssuedEffectRunMaterials = issuePreparedEffectRunMaterials(allowed, definition, originalRequest);
const liveMaterials = bindPreparedEffectRunMaterials(allowed, definition, issuedMaterials, originalRequest);
liveMaterials.compilation satisfies typeof compiled;
// @ts-expect-error A visible wire does not carry original material custody.
bindPreparedEffectRunMaterials(allowed, definition, {wire: issuedMaterials.wire}, originalRequest);
// @ts-expect-error A request field object is not its nominal identity.
bindPreparedEffectRunMaterials(allowed, definition, issuedMaterials, {requestId: 'copied'});
