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
  assert.doesNotMatch(
    source,
    /Err\(InvalidInput\)[^\n]*Err\(InvalidRows\)[\s\S]{0,120}Err\(Limit\)[^\n]*Err\(RowLimit\)[\s\S]{0,120}Err\(Scalar\([^)]*\)\)[^\n]*Err\(Comparison/u,
    `${name} duplicates the common ordering error conversion`,
  );
}

const workspace = sources.get('row_workspace.mbt');
for (const required of [
  'fn row_workspace(',
  'fn reserve_slots(',
  'fn release_slots(',
  'fn[T] with_scoped_slots(',
  'fn charge_row(',
  'fn charge_named(',
  'fn resolve_column(',
  'fn charge_text_append(',
]) {
  assert.ok(workspace.includes(required), `missing accounting primitive: ${required}`);
}
assert.match(workspace, /count > w\.live[\s\S]*w\.live = -1/u);

assert.ok(
  sources.get('stable_order.mbt').includes('fn ordering_row_issue('),
  'ordering resource conversion is not centralized',
);
assert.ok(
  sources.get('rows.mbt').includes('fn evaluation_row_issue('),
  'evaluation resource conversion is not centralized',
);

function declaration(source, name) {
  const start = new RegExp(`\\bfn(?:\\[[^\\]]+\\])?\\s+${name}\\(`, 'u')
    .exec(source)?.index ?? -1;
  assert.ok(start >= 0, `missing production declaration ${name}`);
  const end = source.indexOf('\n///|', start + 1);
  return source.slice(start, end < 0 ? undefined : end);
}

const dispatch = declaration(
  sources.get('sequence_driver.mbt'), 'run_sequence_steps',
);
const branches = [...dispatch.matchAll(
  /@lower\.(\w+Step)\([^)]*\)\s*=>\s*/gu,
)];
const dispatchFamilies = new Set();
for (let index = 0; index < branches.length; index++) {
  const branch = branches[index][1];
  const body = dispatch.slice(
    branches[index].index + branches[index][0].length,
    branches[index + 1]?.index,
  );
  if (branch === 'ValuesStep' || /^(?:return Err\(InputSet\))/u.test(body)) {
    continue;
  }
  const family = branch === 'RowStep' ? 'row'
    : body.match(/evaluate_(\w+) is Some\(evaluate\)/u)?.[1];
  assert.ok(family, `${branch} has no accounted evaluator`);
  assert.ok(!dispatchFamilies.has(family), `${family} has duplicate dispatch`);
  dispatchFamilies.add(family);
}

for (const [driver, entry, rowEvaluator] of [
  ['completed_sequence.mbt', 'evaluate_physical_sequence',
    'evaluate_completed_rows'],
  ['sequence_driver.mbt', 'run_sequence_invocation',
    'evaluate_rows_with_workspace'],
]) {
  const body = declaration(sources.get(driver), entry);
  const callbacks = [...body.matchAll(/evaluate_(\w+)=Some\(/gu)];
  const registered = new Set(['row']);
  assert.match(
    body,
    new RegExp(`with_sequence_workspace[\\s\\S]*?${rowEvaluator}\\(`, 'u'),
    `${driver} does not scope its row evaluator`,
  );
  for (let index = 0; index < callbacks.length; index++) {
    const family = callbacks[index][1];
    assert.ok(!registered.has(family), `${driver} duplicates ${family}`);
    registered.add(family);
    const callback = body.slice(
      callbacks[index].index,
      callbacks[index + 1]?.index,
    );
    assert.match(
      callback,
      /with_sequence_workspace\([^]*?workspace\s*=>\s*\{/u,
      `${driver}.${family} lacks a scoped workspace`,
    );
    assert.match(
      callback,
      new RegExp(`evaluate_${family}_rows\\(`, 'u'),
      `${driver}.${family} lacks its evaluator`,
    );
  }
  assert.deepEqual(
    [...registered].sort(), [...dispatchFamilies].sort(),
    `${driver} registrations differ from production dispatch`,
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

const testFiles = files.filter(name => name.endsWith('_wbtest.mbt'));
const testSources = new Map(await Promise.all(testFiles.map(async name => [
  name,
  await readFile(path.join(executionRoot, name), 'utf8'),
])));
const budgetFixture = testSources.get('kernel_budget_conformance_wbtest.mbt');
for (const required of [
  'fn[T] kernel_budget_attempt(',
  'fn[T] assert_kernel_budget_sweep(',
  'Err(RowLimit) => ()',
  'assert_eq(live, 0)',
]) {
  assert.ok(
    budgetFixture.includes(required),
    `kernel budget conformance omits: ${required}`,
  );
}
const testFamilies = [...testSources.values()].flatMap(source =>
  [...source.matchAll(/assert_kernel_budget_sweep\("([^"]+)"/gu)]
    .map(match => match[1]),
);
assert.equal(new Set(testFamilies).size, testFamilies.length);
assert.deepEqual(
  testFamilies.sort(), [...dispatchFamilies].sort(),
  'budget conformance fixtures differ from production dispatch',
);

const design = await readFile(
  path.join(root, 'docs/design/lowering-relation-implementation.md'),
  'utf8',
);
for (const rule of [
  '`start` may create only small, constant-size metadata',
  '`resume` owns charged work',
  'structural allocation reserves before construction',
  'Resource exhaustion is the canonical `RowLimit` family',
  'sweeps every slot limit',
]) {
  assert.ok(design.includes(rule), `bounded kernel contract omits: ${rule}`);
}

console.log(`Engine accounting gate checked ${productFiles.length} product files`);
