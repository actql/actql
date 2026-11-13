import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import test from 'node:test';
import {parse} from 'yaml';

const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));

test('Linux common Native is mandatory without removing the original Darwin matrix', () => {
  const core = workflow.jobs.core, matrix = core.strategy.matrix;
  assert.deepEqual(matrix.partition, ['1/4', '2/4', '3/4', '4/4', 'http', 'source', 'scoped', 'linux-common']);
  assert.equal(core.strategy['fail-fast'], false);
  assert.equal(core['continue-on-error'], undefined);
  assert(workflow.jobs.check.needs.includes('core'));
  for (const target of ['js', 'wasm']) {
    assert(matrix.exclude.some(row => row.target === target && row.partition === 'linux-common'));
  }
  for (const partition of matrix.partition) {
    const runner = runInNewContext(core['runs-on'].slice(3, -2), {matrix: {target: 'native', partition}});
    assert.equal(runner, partition === 'linux-common' ? 'ubuntu-24.04' : 'macos-15');
  }
});

test('Linux common Native uses its selected compiler profile rather than Darwin preparation', () => {
  const core = workflow.jobs.core;
  const platform = core.steps.find(step => step.name === 'Require the supported Core Native platform');
  assert(platform.run.includes('linux-common'));
  assert(platform.run.includes('Linux'));
  const run = core.steps.find(step => step.name === 'Test common core');
  assert(run.run.includes('MOONBIT_NEW_NATIVE=0 node scripts/test-native-core-linux-common.mjs'));
  assert(run.run.indexOf('test-native-core-linux-common.mjs') < run.run.indexOf('platform_native/trusted_clock'));
  assert.equal(run.env.ACTQL_TEST_NATIVE_CORE_PARTITION,
    "${{ matrix.target == 'native' && matrix.partition != 'linux-common' && matrix.partition || '' }}");
  const cache = core.steps.find(step => step.id === 'native-c-object-cache');
  assert(!cache.if.includes('linux-common'));
  const reader = core.steps.find(step => step.name === 'Test actual Native Reader callbacks and original empty compiler driver');
  assert(reader.if.includes("matrix.partition != 'linux-common'"));
});
