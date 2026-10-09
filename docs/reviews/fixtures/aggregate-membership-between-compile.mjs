// Diagnostic for the common task compiler, not public execution acceptance.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import * as moon from '../../../packages/local-node/_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';

const environment = moon.clientProgramCheckEnvironment(
  (await readFile(new URL('../../../packages/sdk/fixtures/values.environment.json', import.meta.url), 'utf8')).trimEnd(),
  'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904',
  false, false, true, false, false, false, false);
assert.ok(environment);
const document = await readFile(new URL('./aggregate-membership-between.program.json', import.meta.url), 'utf8');
const outcome = moon.clientProgramPrepareEffectFreeWithParameters(document, 'json', environment, undefined);
const prepared = moon.clientProgramPreparationReady(outcome);
assert.ok(prepared, 'the independent Program must pass ordinary preparation');
const compiled = moon.clientProgramCompileLocalTasks(prepared);
// Read the Result, not merely whether the function returned a handle.
const expressionKind = value => {
  if (value === null || typeof value !== 'object') return undefined;
  if (value.kind?._0 === 'between') return 'between';
  for (const key of ['_0', '_1']) {
    const found = expressionKind(value[key]);
    if (found !== undefined) return found;
  }
};
console.log(JSON.stringify({prepared: true, compilationResultTag: compiled?.$tag,
  rejectedExpression: compiled?.$tag === 0 ? expressionKind(compiled._0) : undefined}));
if (compiled?.$tag !== 1) process.exitCode = 1;
