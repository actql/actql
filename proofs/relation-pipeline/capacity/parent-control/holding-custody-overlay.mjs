import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {checkHoldingCustodySource} from './holding-custody-source.mjs';
export const holdingTemporary = ['src/physical_resources/holding_custody_native.mbt', 'src/physical_strategy/holding_custody_native.mbt'];
export const holdingPaths = ['src/physical_resources/moon.pkg', 'src/physical_strategy/moon.pkg'];
const once = (s, from, to) => {
  assert.equal(s.split(from).length, 2, 'Changed holding observation attachment');
  return s.replace(from, to);
};
export function holdingCustodyOverlay(read, overlay) {
  checkHoldingCustodySource(read);
  const path = 'src/query_integration/graph_host_custody_wbtest.mbt';
  let host = overlay[path];
  const observe = phase => `  println(@strategy.native_holding_custody_observation(run, 4, custody_token, filtered, "${phase}"))\n`;
  host = once(host, '  let second_live = Ref(true)\n  let mut closed_parent_bytes',
    '  let custody_token = @strategy.native_holding_custody_token(run, 4, filtered).unwrap()\n' + observe('acquired') + '  let second_live = Ref(true)\n  let mut closed_parent_bytes');
  host = once(host, '    assert_false(\n      @strategy.captured_managed_task_output_matches(',
    observe('parent-port-closed') + '    assert_false(\n      @strategy.captured_managed_task_output_matches(');
  host = once(host, '    let completed = completion.unwrap()\n', '    let completed = completion.unwrap()\n' + observe('consumer-completed'));
  host = once(host, '    assert_eq(attempts.val, 2)\n    (operations, completed)', observe('owner-cleaned') + '    assert_eq(attempts.val, 2)\n    (operations, completed)');
  host = once(host, '    released_parent_bytes=closed_parent_bytes,\n  )\n', '    released_parent_bytes=closed_parent_bytes,\n  )\n' + observe('last-consumer-closed'));
  host = once(host, '  projected_live.val = false\n  @strategy.close_captured_task_output(run, 3)', observe('duplicate-parent-close') + '  projected_live.val = false\n  @strategy.close_captured_task_output(run, 3)');
  overlay[path] = host;
  for (const [i, name] of ['resources', 'strategy'].entries()) {
    overlay[holdingTemporary[i]] = readFileSync(new URL(`./holding-custody-${name}.mbt`, import.meta.url), 'utf8');
    overlay[holdingPaths[i]] = read(holdingPaths[i]).toString() + '\noptions(targets: {"holding_custody_native.mbt": ["native"]})\n';
  }
}
