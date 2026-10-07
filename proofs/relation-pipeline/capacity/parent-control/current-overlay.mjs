import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {checkChainSource} from './chain-source.mjs';
export const currentHelper = 'src/connectors/local/current_chain_capacity_native.mbt';
export const currentStub = 'src/connectors/local/current_chain_capacity_stub.c';
export const currentFixture = 'src/connectors/local/current_chain_capacity_wbtest.mbt';
export const currentPaths = ['src/connectors/local/selected_relation_provider.mbt', 'src/connectors/local/moon.pkg'];
export function currentOverlay(read) {
  const source = read(currentPaths[0]).toString();
  checkChainSource(source);
  const start = source.indexOf('fn bounded_relation_chain_execution_state(');
  const end = source.indexOf('\n///|\nfn selected_relation_provider(', start);
  assert(start >= 0 && end > start);
  let body = source.slice(start,end);
  const open = '  Ok(\n    managed_provider_execution_with_child_work_issue(';
  const tail = '    ),\n  ).map(active => (active, state))\n}\n';
  assert.equal(body.split(open).length,2);assert(body.endsWith(tail));
  body = body.replace(open,'  let observed_parent = managed_provider_execution_with_child_work_issue(')
    .slice(0,-tail.length) + '    )\n  println(current_chain_start_probe(observed_parent, state, used, cancelled, terminal, reclaimed, cleanup_index, sequence, inputs, execution, measurement, numeric, family, count, max_value_bytes, reclaims_scratch))\n  Ok((observed_parent, state))\n}\n';
  let observedSource=source.slice(0,start)+body+source.slice(end);
  const candidates=observedSource.match(/  for\n    provider in (\[[\s\S]*?\n    \]) \{/);
  assert(candidates && observedSource.split(candidates[0]).length===2,'Changed provider candidate construction');
  observedSource=observedSource.replace(candidates[0],`  let construction_candidates = ${candidates[1]}
  println(provider_construction_probe(construction_candidates, execution, measurement))
  for provider in construction_candidates {`);
  return {
    [currentPaths[0]]: observedSource,
    [currentPaths[1]]: read(currentPaths[1]).toString() + '\noptions("native-stub": [ "current_chain_capacity_stub.c" ], targets: { "current_chain_capacity_native.mbt": [ "native" ], "current_chain_capacity_wbtest.mbt": [ "native" ] })\n',
    [currentHelper]: readFileSync(new URL('./current-helper.mbt',import.meta.url),'utf8'),
    [currentStub]: readFileSync(new URL('./current-reader.c',import.meta.url),'utf8') + '\n#define layout current_shape\n#define regular_bytes(p) (8 + current_shape(p)[0]*4)\n#define has_pointer current_contains\n' + readFileSync(new URL('./provider-reader.c',import.meta.url),'utf8'),
    [currentFixture]: readFileSync(new URL('./current-fixture.mbt',import.meta.url),'utf8'),
  };
}
