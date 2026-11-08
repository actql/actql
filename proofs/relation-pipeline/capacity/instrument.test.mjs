import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {instrument, mutations, workspaceOverlay} from './instrument.mjs';
import {applyMutation} from '../sites.mjs';

const path = 'src/execution_relation/producer_read_preparation.mbt';
const original = readFileSync(new URL('../../../' + path, import.meta.url), 'utf8');
const copy = mutations.find(entry => entry.name === 'handoff-copy-without-accounting');
assert.equal(copy.path, path);

test('the handoff copy observer replaces the complete original return without nesting statements in a record', () => {
  const mutated = applyMutation(original, copy);
  const healthy = instrument(path, original);
  const field = 'bound: cursor.bound,';
  assert.equal(healthy.split(field).length, 2);
  const expected = healthy.replace(field, `bound: ${copy.binding},`);
  assert.equal(instrument(path, mutated), expected);
  assert.equal(mutated.replace(copy.after, copy.before), original);
});

test('the handoff observer refuses changed and duplicated complete return anchors', () => {
  const mutated = applyMutation(original, copy);
  assert.throws(() => instrument(path, mutated.replace('schema: cursor.schema,', 'schema: foreign,')),
    /Ambiguous observation site/);
  assert.throws(() => instrument(path, mutated + '\n' + mutated), /Ambiguous observation site/);
});

const rowsPath = 'src/execution_relation/bounded_binding_rows.mbt';
const rows = readFileSync(new URL('../../../' + rowsPath, import.meta.url), 'utf8');
const workspace = '  let workspace = working_row_workspace(generated, max_entries)';
for (const offset of [-1, 0, 1]) {
  test(`workspace boundary ${offset} preserves the original Task growth attachment`, () => {
    const changed = workspaceOverlay(rows, offset);
    const expected = `${workspace}
  let capacity_n = bounded_binding_input_row_count(input)
  let capacity_peak = if capacity_n == 0 { 5 * output_width } else { Int::max(5 * output_width + 2 * capacity_n, 6 * output_width + capacity_n) }
  let workspace = if distinct && !dedupe { { ..workspace, limit: capacity_peak + (${offset}), } } else { workspace }`;
    assert.equal(rows.split(workspace).length, 2);
    assert.equal(changed, rows.replace(workspace, expected));
    assert.equal(changed.replace(expected, workspace), rows);
    assert.equal(changed.split(workspace).length, 2, 'The original growth-aware constructor runs once');
    assert.equal(changed.includes('let workspace = row_workspace('), false,
      'A detached workspace would drop the same Task growth owner');
  });
}
test('workspace boundaries refuse changed, missing and duplicate original constructors', () => {
  for (const changed of [rows.replace(workspace, ''), rows + '\n' + workspace,
    rows.replace(workspace, '  let workspace = working_row_workspace(foreign, max_entries)')]) {
    assert.throws(() => workspaceOverlay(changed, 0), /Ambiguous workspace boundary site/);
  }
});
test('workspace boundaries admit only the exact scientific offsets', () => {
  for (const offset of [-2, 2, 0.5, NaN, undefined, '0', '0) + foreign(']) {
    assert.throws(() => workspaceOverlay(rows, offset), /Unknown workspace boundary offset/);
  }
});
