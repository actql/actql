import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { generatedObservers, replacements, instrument } from '../instrument.mjs';
export const helper = 'src/connectors/local/parent_control_probe_native.mbt';
export const stub = 'src/execution_relation/capacity_map_probe_stub.c';
const pkg = 'src/connectors/local/moon.pkg';
const provider = 'src/connectors/local/selected_relation_provider.mbt';
export const paths = [...Object.keys(replacements), pkg, provider];
export function parentOverlay(read) {
  const originals = Object.fromEntries(paths.map(path => [path, read(path).toString()]));
  const overlay = { ...generatedObservers,
    ...Object.fromEntries(Object.entries(originals).map(([path, source]) =>
      [path, replacements[path] ? instrument(path, source) : source])),
    [helper]: readFileSync(new URL('./helper.mbt', import.meta.url), 'utf8'),
    [stub]: generatedObservers[stub] + '\n' + readFileSync(new URL('./reader.c', import.meta.url), 'utf8') +
      '\n' + readFileSync(new URL('./phase-reader.c', import.meta.url), 'utf8') +
      '\n' + readFileSync(new URL('./provider-reader.c', import.meta.url), 'utf8'),
    [pkg]: originals[pkg] + '\noptions(targets: { "parent_control_probe_native.mbt": [ "native" ] })\n',
  };
  const source = originals[provider];
  const start = source.indexOf('fn bounded_relation_chain_execution(');
  const end = source.indexOf('\nfn selected_relation_provider(', start);
  assert(start >= 0 && end > start, 'Missing exact chain constructor');
  let body = source.slice(start, end);
  const before = '  Ok(\n    managed_provider_execution_with_child_work_issue(';
  const tail = '    ),\n  )\n}\n';
  assert.equal(body.split(before).length, 2);
  assert.equal(body.split(tail).length, 2);
  body = body.replace(before, '  let observed_parent =\n    managed_provider_execution_with_child_work_issue(')
    .replace(tail, '    )\n  println(parent_control_probe(observed_parent, children, previous, current, position, pending, used, cancelled, terminal, reclaimed, cleanup_index, sequence, inputs, execution, measurement, numeric, family, count))\n  Ok(observed_parent)\n}\n');
  let selectedSource = source.slice(0, start) + body + source.slice(end);
  const candidates = selectedSource.match(/  for\n    provider in (\[[\s\S]*?\n    \]) \{/);
  assert(candidates && selectedSource.split(candidates[0]).length === 2, 'Changed complete provider candidate construction');
  selectedSource = selectedSource.replace(candidates[0], `  let construction_candidates = ${candidates[1]}
  println(provider_construction_probe(construction_candidates, execution, measurement))
  for provider in construction_candidates {`);
  overlay[provider] = selectedSource;
  const managed = 'src/connectors/local/managed_provider.mbt';
  let manager = overlay[managed];
  const sites = [
    ['  let result = (execution.advance)(quantum)', '  println(parent_core_phase_probe(execution, 1))\n  let result = (execution.advance)(quantum)'],
    ['  result\n}\n\n///|\n/// Sum of this owner', '  println(parent_core_phase_probe(execution, 2))\n  result\n}\n\n///|\n/// Sum of this owner'],
    ['  (execution.cancel)()\n}', '  println(parent_core_phase_probe(execution, 3))\n  let result = (execution.cancel)()\n  println(parent_core_phase_probe(execution, 4))\n  result\n}'],
    ['  (execution.cleanup)()\n}', '  println(parent_core_phase_probe(execution, 5))\n  let result = (execution.cleanup)()\n  println(parent_core_phase_probe(execution, 6))\n  result\n}'],
  ];
  for (const [before, after] of sites) {
    assert.equal(manager.split(before).length, 2, 'Changed parent lifecycle observation site');
    manager = manager.replace(before, after);
  }
  overlay[managed] = manager;
  return overlay;
}
