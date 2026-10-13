import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const sources = [
  'scripts/templates/strategy-node.mbt',
  'src/connectors_builtin_node/bridge.generated.mbt',
  'src/connectors_builtin_node_rela/bridge.generated.mbt',
  'src/connectors_workers_bridge/bridge.generated.mbt',
  'src/connectors_workers_async_bridge/bridge.generated.mbt',
];

for (const path of sources) {
  const source = readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
  const declaration = name => {
    const block = source.split('///|').find(value =>
      value.includes(`pub fn ${name}(`));
    assert.ok(block, `Missing ${name} in ${path}`);
    return block;
  };

  test(`${path}: completion includes the checked source-free root`, () => {
    const body = declaration('strategy_host_finished');
    assert.match(body, /let first = @strategy\.captured_compute_first_task\(run\)/);
    assert.match(body, /for task in first\.\.<strategy_host_count\(host\)/);
  });

  test(`${path}: cleanup closes all Compute outputs and preserves captures`, () => {
    const body = declaration('strategy_host_close_outputs');
    assert.match(body, /let first = @strategy\.captured_compute_first_task\(run\)/);
    assert.match(body,
      /for task = strategy_host_count\(host\) - 1; task >= first; task = task - 1/);
    assert.match(body, /@strategy\.close_captured_task_output\(run, task\)/);
  });
}
