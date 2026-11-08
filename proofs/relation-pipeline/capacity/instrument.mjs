import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, existsSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import {tokens, readPackageTargetOptions} from '../../../scripts/portable-core.mjs';
const rows = 'src/execution_relation/bounded_binding_rows.mbt';
const sort = 'src/execution_relation/bounded_index_sort.mbt';
const reads = 'src/execution_relation/producer_read_preparation.mbt';
const providers = 'src/connectors/local/managed_provider.mbt';
const packagePath = 'src/execution_relation/moon.pkg';
export const generatedObservers = {
  'src/execution_relation/capacity_map_probe_stub.c': readFileSync(new URL('./backing/probe/layout_stub.c', import.meta.url), 'utf8'),
  'src/execution_relation/capacity_map_probe_native.mbt': readFileSync(new URL('./backing/observer_native.mbt.txt', import.meta.url), 'utf8'),
  'src/execution_relation/capacity_map_probe_portable.mbt': readFileSync(new URL('./backing/observer_portable.mbt.txt', import.meta.url), 'utf8'),
};
const ownedObservers = new Set();
export function installGeneratedObservers(root) {
  for (const [path, code] of Object.entries(generatedObservers)) {
    const full = join(root, path);
    if (ownedObservers.has(full)) {
      assert.equal(readFileSync(full, 'utf8'), code, 'Owned observer was changed');
    } else {
      assert(!existsSync(full), 'Another task owns the temporary native observer');
      writeFileSync(full, code, { flag: 'wx' }); ownedObservers.add(full);
    }
  }
}
export function restoreGeneratedObservers(root) {
  for (const [path, code] of Object.entries(generatedObservers)) {
    const full = join(root, path);
    if (!ownedObservers.has(full)) continue;
    assert.equal(readFileSync(full, 'utf8'), code, 'Owned observer was changed');
    unlinkSync(full); ownedObservers.delete(full);
  }
}
const observerTargets = [
  ['capacity_map_probe_native.mbt', ['native']],
  ['capacity_map_probe_portable.mbt', ['not', 'native']],
];
const observerStub = 'capacity_map_probe_stub.c';

// Preserve the compiler's existing options and literal target DATA. This
// overlay adds only its own filenames; it does not reinterpret target rules
// or rewrite unrelated linker/compiler options.
function instrumentPackage(original) {
  const list = tokens(original, false, true);
  const symbol = (token, value) => token?.kind === 'symbol' && token.value === value;
  const matching = start => {
    const pairs = {'(': ')', '[': ']', '{': '}'};
    assert(pairs[list[start]?.value], 'Expected package option container');
    const stack = [];
    for (let index = start; index < list.length; index++) {
      const token = list[index];
      if (token.kind !== 'symbol') continue;
      if (pairs[token.value]) stack.push(pairs[token.value]);
      else if ([')', ']', '}'].includes(token.value)) {
        assert.equal(token.value, stack.pop(), 'Unbalanced package options');
        if (!stack.length) return index;
      }
    }
    assert.fail('Unclosed package options');
  };
  let opening, ending;
  for (let index = 0; index < list.length; index++) {
    const token = list[index];
    if (token.kind === 'word' && token.value === 'options') {
      assert.equal(opening, undefined, 'Duplicate package options');
      assert(symbol(list[index + 1], '('), 'Malformed package options');
      opening = index + 1;ending = matching(opening);index = ending;
    } else if (token.kind === 'symbol' && ['(', '[', '{'].includes(token.value)) index = matching(index);
  }
  const targetEntries = observerTargets.map(([file, targets]) => `    ${JSON.stringify(file)}: ${JSON.stringify(targets)},`).join('\n');
  if (opening === undefined) return original + `\noptions(\n  "native-stub": [${JSON.stringify(observerStub)}],\n  targets: {\n${targetEntries}\n  },\n)\n`;
  const options = new Map();
  for (let index = opening + 1; index < ending;) {
    const key = list[index];
    assert(key?.kind === 'word' || key?.kind === 'string', 'Malformed package option name');
    assert(!options.has(key.value), 'Duplicate package option');
    assert(symbol(list[index + 1], ':'), 'Malformed package option value');
    const start = index + 2;
    let end = start;
    while (end < ending && !symbol(list[end], ',')) {
      if (list[end].kind === 'symbol' && ['(', '[', '{'].includes(list[end].value)) end = matching(end);
      end++;
    }
    assert(end > start, 'Missing package option value');
    options.set(key.value, {key: index, start, end});
    index = end + 1;
  }
  const edits = [], additions = [];
  const targets = options.get('targets');
  if (targets === undefined) additions.push(`targets: {\n${targetEntries}\n  }`);
  else {
    const input = [{kind: 'symbol', value: '('}, ...list.slice(targets.key, targets.end), {kind: 'symbol', value: ')'}];
    let index = 0;
    const entries = readPackageTargetOptions({
      take(kind, value) {
        const next = input[index++];
        assert(next?.kind === kind && (value === undefined || next.value === value), 'Malformed literal package targets');
        return next.value;
      },
      peek: value => input[index]?.value === value,
    });
    assert.equal(index, input.length, 'Trailing package target DATA');
    for (const [file] of observerTargets) assert(!entries.some(([existing]) => existing === file), 'Observer target already present');
    const close = list[targets.end - 1];
    assert(symbol(close, '}'), 'Malformed literal package targets');
    const comma = entries.length && !symbol(list[targets.end - 2], ',') ? ',' : '';
    edits.push({begin: close.begin, end: close.begin, text: `${comma}\n${targetEntries}\n  `});
  }
  const stubs = options.get('native-stub');
  if (stubs === undefined) additions.push(`"native-stub": [${JSON.stringify(observerStub)}]`);
  else {
    const values = list.slice(stubs.start, stubs.end);
    assert(symbol(values[0], '[') && symbol(values.at(-1), ']'), 'Malformed native stub array');
    const existing = [];
    for (let index = 1; index < values.length - 1; index += 2) {
      assert.equal(values[index]?.kind, 'string', 'Nonliteral native stub');existing.push(values[index].value);
      assert(index + 1 === values.length - 1 || symbol(values[index + 1], ','), 'Malformed native stub separator');
    }
    assert(!existing.includes(observerStub), 'Observer native stub already present');
    edits.push({begin: values[0].begin, end: values.at(-1).end, text: JSON.stringify([...existing, observerStub])});
  }
  if (additions.length) edits.push({begin: list[opening].end, end: list[opening].end, text: '\n  ' + additions.join(',\n  ') + (options.size ? ',' : '') + '\n'});
  return edits.sort((a, b) => b.begin - a.begin).reduce((text, edit) => text.slice(0, edit.begin) + edit.text + text.slice(edit.end), original);
}

export const replacements = {
  [packagePath]: [['supported_targets = "+js+wasm+native"', 'supported_targets = "+js+wasm+native"']],
  [providers]: [
    ['  (provider.start)(\n    sequence,\n    inputs.map(input => RelationInput(input)),',
      `  let declared = managed_provider_capacity(provider, sequence).unwrap()
  println("ACTQL_PIPELINE_FAULT:{\\"kind\\":\\"capacity declaration\\",\\"steps\\":" + @execution.generated_sequence_step_count(sequence).to_string() + ",\\"retainedBytes\\":" + declared.retained_bytes.to_string() + ",\\"executionBytes\\":" + declared.execution_bytes.to_string() + "}")
  (provider.start)(
    sequence,
    inputs.map(input => RelationInput(input)),`],
  ],
  [rows]: [
    ['  let (session, token) = @bounded.start(\n    engine,', '  capacity_observe(state, "start")\n  let (session, token) = @bounded.start(\n    engine,'],
    ['    match state.phase {\n      PrepareInputNames', '    capacity_observe(state, "checkpoint")\n    match state.phase {\n      PrepareInputNames'],
    ['fn cleanup_bounded_binding_rows_state(state : BoundedBindingRowsState) -> Bool {', 'fn cleanup_bounded_binding_rows_state(state : BoundedBindingRowsState) -> Bool {\n  capacity_observe(state, "before-cleanup")'],
    ['    state.live.val = false\n  }\n  true\n}', '    state.live.val = false\n  }\n  capacity_observe(state, "after-cleanup")\n  true\n}'],
    ['        // The merge owns two index arrays.', '        let capacity_before_indices = state.workspace.live\n        // The merge owns two index arrays.'],
    ['        state.sort_execution = start_bounded_index_sort_stepped(', '        if state.distinct && !state.dedupe {\n          println("ACTQL_PIPELINE_FAULT:{\\"kind\\":\\"capacity observation\\",\\"event\\":\\"index-admission\\",\\"n\\":" + count.to_string() + ",\\"delta\\":" + (state.workspace.live - capacity_before_indices).to_string() + "}")\n        }\n        state.sort_execution = start_bounded_index_sort_stepped('],
    ['          Ok(BoundedIndexSortComplete(indices)) => {', '          Ok(BoundedIndexSortComplete(indices)) => {\n            let capacity_before_transfer = state.workspace.live'],
    ['            state.sorted_indices = Some(indices)', '            if state.distinct && !state.dedupe {\n              println("ACTQL_PIPELINE_FAULT:{\\"kind\\":\\"capacity observation\\",\\"event\\":\\"index-transfer\\",\\"n\\":" + count.to_string() + ",\\"delta\\":" + (state.workspace.live - capacity_before_transfer).to_string() + ",\\"length\\":" + indices.length().to_string() + "}")\n            }\n            state.sorted_indices = Some(indices)'],
    ['        if state.sorted_indices is Some(_) {', '        if state.distinct && !state.dedupe {\n          println("ACTQL_PIPELINE_FAULT:{\\"kind\\":\\"capacity observation\\",\\"event\\":\\"output-transfer\\",\\"sharedOutput\\":" + physical_equal(output.buffer.rows, rows.rows).to_string() + "}")\n        }\n        if state.sorted_indices is Some(_) {'],
    ['          output.buffer.rows.push(state.capture_row)', '          output.buffer.rows.push(state.capture_row)\n          if state.distinct && !state.dedupe {\n            println("ACTQL_PIPELINE_FAULT:{\\"kind\\":\\"capacity observation\\",\\"event\\":\\"commit\\",\\"sharedCapture\\":" + physical_equal(output.buffer.rows[output.buffer.rows.length() - 1], state.capture_row).to_string() + "}")\n          }'],
  ],
  [sort]: [
    ['    match state.phase {\n      Initialize', '    println("ACTQL_PIPELINE_FAULT:{\\"kind\\":\\"capacity observation\\",\\"event\\":\\"index\\",\\"source\\":" + state.source.length().to_string() + ",\\"target\\":" + state.target.length().to_string() + ",\\"count\\":" + state.count.to_string() + ",\\"alias\\":" + (state.source.length() > 0 && physical_equal(state.source, state.target)).to_string() + "}")\n    match state.phase {\n      Initialize'],
  ],
  [reads]: [
    ['        return Ok(\n          Some({\n            bound: cursor.bound,\n            schema: cursor.schema,\n            columns: cursor.columns,\n            max_entries: cursor.max_entries,\n            max_name_bytes: cursor.max_name_bytes,\n          }),\n        )', `        let bound = cursor.bound
        let columns = cursor.columns
        let observed : ProducerRead = {
          bound: cursor.bound,
          schema: cursor.schema,
          columns: cursor.columns,
          max_entries: cursor.max_entries,
          max_name_bytes: cursor.max_name_bytes,
        }
        let shared = match (observed.bound.output.table, bound.output.table) {
          (Some(RowTable(a)), Some(RowTable(b))) => physical_equal(a.rows, b.rows)
          (Some(AdmittedTable(a)), Some(AdmittedTable(b))) => physical_equal(a.rows, b.rows)
          (Some(ColumnTable(a)), Some(ColumnTable(b))) => physical_equal(a.columns, b.columns)
          (Some(NumberTable(a)), Some(NumberTable(b))) => {
            let mut same = physical_equal(a.columns, b.columns)
            for i in 0..<a.columns.length() {
              same = same && physical_equal(a.columns[i].values, b.columns[i].values) &&
                physical_equal(a.columns[i].valid, b.columns[i].valid)
            }
            same
          }
          _ => false
        }
        println("ACTQL_PIPELINE_FAULT:{\\"kind\\":\\"capacity observation\\",\\"event\\":\\"input-view\\",\\"sharedBacking\\":" + shared.to_string() + ",\\"rows\\":" + completed_row_count(observed.bound.output).to_string() + ",\\"columns\\":" + columns.length().to_string() + ",\\"consumer\\":" + bound.consumer_step.unwrap_or(-1).to_string() + "}")
        return Ok(Some(observed))`],
  ],
};
export function instrument(path, original) {
  let changed = original;
  for (let [before, after] of replacements[path] ?? []) {
    const copy = mutations.find(m => m.name === 'handoff-copy-without-accounting');
    if (path === reads && original.includes(copy.after)) {
      before = before.replace(copy.before, copy.after);
      after = after.replace('bound: cursor.bound,', `bound: ${copy.binding},`);
    }
    assert.equal(changed.split(before).length, 2, `Ambiguous observation site ${path}`);
    changed = changed.replace(before, after);
  }
  if (path === packagePath) changed = instrumentPackage(changed);
  if (path === rows) changed += '\n' + readFileSync(new URL('./observer.mbt.txt', import.meta.url), 'utf8');
  return changed;
}
export const mutations = [
  { name: 'missing-index-reservation', path: rows,
    before: '!reserve_slots(state.workspace, count * 2)',
    after: '!reserve_slots(state.workspace, 0)', fault: 'live DISTINCT scratch underreserved', event: 'index-admission', resource: 'index-buffer admission' },
  { name: 'premature-keep-release', path: rows,
    before: '      MarkDistinct => {\n        if state.distinct_cursor == count',
    after: '      MarkDistinct => {\n        if state.distinct_cursor == 0 {\n          let capacity_before = state.workspace.live\n          release_slots(state.workspace, count)\n          println("ACTQL_PIPELINE_FAULT:{\\"kind\\":\\"capacity observation\\",\\"event\\":\\"premature-release\\",\\"n\\":" + count.to_string() + ",\\"delta\\":" + (state.workspace.live - capacity_before).to_string() + ",\\"keep\\":" + state.distinct_keep.length().to_string() + "}")\n        }\n        if state.distinct_cursor == count', fault: 'live DISTINCT scratch underreserved', event: 'premature-release', resource: 'live keep bitmap' },
  { name: 'duplicate-index-release', path: rows,
    before: '            release_slots(state.workspace, count)\n            state.sorted_indices = Some(indices)',
    after: '            release_slots(state.workspace, count)\n            release_slots(state.workspace, count)\n            state.sorted_indices = Some(indices)', fault: 'live DISTINCT scratch underreserved', event: 'index-transfer', resource: 'index-result custody transfer' },
  { name: 'handoff-copy-without-accounting', path: reads,
    before: '            bound: cursor.bound,',
    binding: 'if cursor.bound.consumer_step is Some(_) { { ..cursor.bound, output: copy_completed_output_independent(cursor.bound.output, completed_row_count(cursor.bound.output), completed_column_count(cursor.bound.output)).unwrap(), } } else { cursor.bound }',
    after: '            bound: if cursor.bound.consumer_step is Some(_) { { ..cursor.bound, output: copy_completed_output_independent(cursor.bound.output, completed_row_count(cursor.bound.output), completed_column_count(cursor.bound.output)).unwrap(), } } else { cursor.bound },',
    fault: 'borrowed backing was replaced', event: 'input-view', resource: 'checked handoff backing ownership', edge: true },
  { name: 'oversized-metadata-map', path: rows,
    before: '  let input_ordinals : Map[String, Int] = Map([])',
    after: '  let input_ordinals : Map[String, Int] = Map([], capacity=16)',
    fault: 'Map buckets exceed the admitted constructor bound', event: 'start', resource: 'input ordinal Map table slots' },
];
export function workspaceOverlay(original, offset) {
  assert([-1, 0, 1].includes(offset), 'Unknown workspace boundary offset');
  const before = '  let workspace = working_row_workspace(generated, max_entries)';
  assert.equal(original.split(before).length, 2, 'Ambiguous workspace boundary site');
  // Keep the original growth attachment. Passing the diagnostic limit into
  // working_row_workspace would expand it again for an attached Task, hiding
  // the independent exact/one-short structural workspace boundary.
  return original.replace(before, `${before}\n  let capacity_n = bounded_binding_input_row_count(input)\n  let capacity_peak = if capacity_n == 0 { 5 * output_width } else { Int::max(5 * output_width + 2 * capacity_n, 6 * output_width + capacity_n) }\n  let workspace = if distinct && !dedupe { { ..workspace, limit: capacity_peak + (${offset}), } } else { workspace }`);
}
