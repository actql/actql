import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, existsSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
const rows = 'src/execution_relation/bounded_binding_rows.mbt';
const sort = 'src/execution_relation/bounded_index_sort.mbt';
const reads = 'src/execution_relation/producer_read.mbt';
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
export const replacements = {
  [packagePath]: [['supported_targets = "+js+wasm+native"', `supported_targets = "+js+wasm+native"

options(
  "native-stub": [ "capacity_map_probe_stub.c" ],
  targets: {
    "capacity_map_probe_native.mbt": [ "native" ],
    "capacity_map_probe_portable.mbt": [ "not", "native" ],
  },
)`]],
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
    ['  Ok({ bound, schema, columns, max_entries, max_name_bytes, })', `  let observed : ProducerRead = { bound, schema, columns, max_entries, max_name_bytes, }
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
  Ok(observed)`],
  ],
};
export function instrument(path, original) {
  let changed = original;
  for (let [before, after] of replacements[path] ?? []) {
    const copy = mutations.find(m => m.name === 'handoff-copy-without-accounting');
    if (path === reads && original.includes(copy.after)) {
      before = copy.after;
      after = after.replace('let observed : ProducerRead = { bound,', `let observed : ProducerRead = { bound: ${copy.binding},`);
    }
    assert.equal(changed.split(before).length, 2, `Ambiguous observation site ${path}`);
    changed = changed.replace(before, after);
  }
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
    before: '  Ok({ bound, schema, columns, max_entries, max_name_bytes, })',
    binding: 'if bound.consumer_step is Some(_) { { ..bound, output: copy_completed_output_independent(bound.output, completed_row_count(bound.output), completed_column_count(bound.output)).unwrap(), } } else { bound }',
    after: '  Ok({ bound: if bound.consumer_step is Some(_) { { ..bound, output: copy_completed_output_independent(bound.output, completed_row_count(bound.output), completed_column_count(bound.output)).unwrap(), } } else { bound }, schema, columns, max_entries, max_name_bytes, })',
    fault: 'borrowed backing was replaced', event: 'input-view', resource: 'checked handoff backing ownership', edge: true },
  { name: 'oversized-metadata-map', path: rows,
    before: '  let input_ordinals : Map[String, Int] = Map([])',
    after: '  let input_ordinals : Map[String, Int] = Map([], capacity=16)',
    fault: 'Map buckets exceed the admitted constructor bound', event: 'start', resource: 'input ordinal Map table slots' },
];
export function workspaceOverlay(original, offset) {
  const before = '  let workspace = row_workspace(max_entries)';
  assert.equal(original.split(before).length, 2);
  return original.replace(before, `  let capacity_n = bounded_binding_input_row_count(input)\n  let capacity_peak = if capacity_n == 0 { 5 * output_width } else { Int::max(5 * output_width + 2 * capacity_n, 6 * output_width + capacity_n) }\n  let workspace = row_workspace(if distinct && !dedupe { capacity_peak + (${offset}) } else { max_entries })`);
}
