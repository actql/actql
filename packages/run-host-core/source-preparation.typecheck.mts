import {prepareSourceProgram, prepareSourceRequest, admitSourceRequestFields,
  sourceProgramMaterialInput, sourceProgramOriginals, sourceProgramSourceInput,
  restoreSourceProgram, requestFields, compileTasks, compileEffect,
  type CheckEnvironment, type SubmittedIntent} from '@actql/run-host-core';
declare const environment: CheckEnvironment;
declare const original: SubmittedIntent;
const selected = prepareSourceProgram(original, environment, '{}');
const source = sourceProgramSourceInput(selected.prepared);
source.document satisfies string;
source.parameterDeclarationsWire satisfies string | undefined;
const material = sourceProgramMaterialInput(selected.prepared, '{}');
material.format satisfies 'json';
const restored = restoreSourceProgram(sourceProgramOriginals(selected.prepared), environment);
const request = prepareSourceRequest(restored.prepared, restored.originalIntent, 'scope', 'request');
admitSourceRequestFields(restored.prepared, restored.originalIntent, requestFields(request));
if (selected.kind === 'effect') {
  compileEffect(selected.prepared);
  // @ts-expect-error Effect cannot enter the Pure task compiler.
  compileTasks(selected.prepared);
} else {
  compileTasks(selected.prepared);
  // @ts-expect-error Pure preparation cannot enter the Effect compiler.
  compileEffect(selected.prepared);
}
