import assert from 'node:assert/strict';
import {readFile, readdir} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const executionRoot = path.join(root, 'src/execution_relation');
const files = await readdir(executionRoot);
const productFiles = files.filter(name =>
  name.endsWith('.mbt') &&
  !name.endsWith('_test.mbt') &&
  !name.endsWith('_wbtest.mbt') &&
  !name.includes('.generated.'),
);
const sources = new Map(await Promise.all(productFiles.map(async name => [
  name,
  await readFile(path.join(executionRoot, name), 'utf8'),
])));

for (const [name, source] of sources) {
  if (name !== 'row_workspace.mbt') {
    assert.doesNotMatch(
      source,
      /RowWorkspace\s*::\s*\{|\{[ \t]*limit:[ \t]*[^,\n]+,[ \t]*live:[ \t]*0,[ \t]*peak:[ \t]*0/u,
      `${name} bypasses row_workspace()`,
    );
  }
  if (!name.startsWith('bounded_') && name !== 'row_workspace.mbt') {
    assert.doesNotMatch(
      source,
      /workspace\.live\s*[-+]?=/u,
      `${name} mutates workspace custody directly`,
    );
  }
  for (const mixedFailure of [
    /!spend_control(?:_text)?\([^)]*\)\s*\|\|[^{]*\{\s*return Err\((?:InvalidRows|InputMismatch|WindowTime)/u,
    /\|\|\s*!spend_control(?:_text)?\([^)]*\)\s*\{\s*return Err\((?:InvalidRows|InputMismatch|WindowTime)/u,
    /spend_control_text\([^)]*\)\s*&&[^{}]*else\s*\{\s*return Err\((?:InvalidRows|InputMismatch|WindowTime)/u,
  ]) {
    assert.doesNotMatch(
      source,
      mixedFailure,
      `${name} conflates resource exhaustion with a semantic error`,
    );
  }
}

const workspace = sources.get('row_workspace.mbt');
for (const required of [
  'fn row_workspace(',
  'fn reserve_slots(',
  'fn release_slots(',
  'fn[T] with_scoped_slots(',
  'fn charge_row(',
  'fn charge_named(',
  'fn charge_text_append(',
]) {
  assert.ok(workspace.includes(required), `missing accounting primitive: ${required}`);
}
assert.match(workspace, /count > w\.live[\s\S]*w\.live = -1/u);

for (const driver of ['completed_sequence.mbt', 'sequence_driver.mbt']) {
  const source = sources.get(driver);
  const rowEvaluator = driver === 'completed_sequence.mbt'
    ? 'evaluate_completed_rows'
    : 'evaluate_rows_with_workspace';
  for (const evaluator of [
    rowEvaluator,
    'evaluate_window_rows',
    'evaluate_join_rows',
    'evaluate_interval_join_rows',
    'evaluate_asof_join_rows',
    'evaluate_sequence_match_rows',
    'evaluate_cross_join_rows',
    'evaluate_append_rows',
    'evaluate_set_rows',
    'evaluate_nest_rows',
  ]) {
    assert.ok(source.includes(evaluator), `${driver} omits ${evaluator}`);
  }
  assert.ok(
    source.split('with_sequence_workspace').length >= 12,
    `${driver} does not scope every production kernel`,
  );
}

const sequence = sources.get('bounded_sequence_match.mbt');
const prepareOutput = sequence.slice(
  sequence.indexOf('PrepareOutput =>'),
  sequence.indexOf('EmitOutputCells =>'),
);
assert.ok(prepareOutput.indexOf('charge_row(') >= 0);
assert.ok(
  prepareOutput.indexOf('charge_row(') <
    prepareOutput.indexOf('state.output_row = []'),
);
assert.match(sequence, /state\.predicates = \[\]/u);
assert.match(sequence, /state\.matches = \[\]/u);
assert.match(sequence, /partial\.positions\.clear\(\)/u);
assert.match(sequence, /match_\.positions\.clear\(\)/u);

const design = await readFile(
  path.join(root, 'docs/design/lowering-relation-implementation.md'),
  'utf8',
);
for (const rule of [
  '`start` may create only small, constant-size metadata',
  '`resume` owns charged work',
  'structural allocation reserves before construction',
  'Resource exhaustion is the canonical `RowLimit` family',
]) {
  assert.ok(design.includes(rule), `bounded kernel contract omits: ${rule}`);
}

console.log(`Engine accounting gate checked ${productFiles.length} product files`);
