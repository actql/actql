import {prepareProgram, compileValues, compileEffect,
  type CheckEnvironment} from '@actql/run-host-core';

declare const environment: CheckEnvironment;
const selected = prepareProgram('{}', 'json', environment);
if (selected.kind === 'effect') {
  compileEffect(selected.prepared);
  // @ts-expect-error Effect preparation cannot enter the Pure compiler.
  compileValues(selected.prepared);
} else {
  compileValues(selected.prepared);
  // @ts-expect-error Pure preparation cannot enter the Effect compiler.
  compileEffect(selected.prepared);
}
