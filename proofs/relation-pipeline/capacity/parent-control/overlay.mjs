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
    [stub]: generatedObservers[stub] + '\n' + readFileSync(new URL('./reader.c', import.meta.url), 'utf8'),
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
  overlay[provider] = source.slice(0, start) + body + source.slice(end);
  return overlay;
}
