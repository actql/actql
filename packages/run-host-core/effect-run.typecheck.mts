import {prepareEffect, compileEffect, issueAllowedEffectRun, issueEffectRunDefinition,
  issueEffectRunMaterials, admitEffectRunMaterials, effectExecutionShape, compileValues,
  prepareEffectRequest, effectSourceInputBinding, issueEffectSourceDispatch,
  prepareEffectRetainedTaskInputEdge, issueEffectRetainedTaskDispatch,
  type ValuesSiteSelection, type RetainedTaskInput, type CheckEnvironment, type PreparedEffectProgram, type EffectCompilation,
  type AllowedEffectRun} from '@actql/run-host-core';
declare const environment: CheckEnvironment;
const prepared = prepareEffect('{}', 'json', environment);
const compiled = compileEffect(prepared);
const allowed = issueAllowedEffectRun(prepared, compiled, {
  executionContextCid: 'cid', hostPolicyCid: 'policy', expiresAt: 'time'});
const definition = issueEffectRunDefinition(allowed, 'scope', 'run', 'created', 'valid');
const wire = issueEffectRunMaterials(allowed, definition,
  {format: 'json', document: '{}', environment, environmentWire: '{}'});
const restored = admitEffectRunMaterials(wire, 'definition', {rela: true});
effectExecutionShape(restored.prepared, restored.compilation);
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
effectSourceInputBinding(compiled);
prepareEffectRetainedTaskInputEdge(allowed, definition);
issueEffectSourceDispatch(allowed, definition, caller, selection);
issueEffectRetainedTaskDispatch(allowed, definition, caller, selection, retainedInput);
// @ts-expect-error A preparation is not the original allowed Effect Run.
issueEffectSourceDispatch(prepared, definition, caller, selection);
// @ts-expect-error Raw binding bytes cannot replace the admitted receiver owner.
issueEffectRetainedTaskDispatch(allowed, definition, caller, selection, {wire: '{}', cid: 'cid'});
