import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {graphRemainingOperationInputs} from './fixtures/graph-remaining-operation-inputs.mjs';
import {graphGraftSourceSuccesses, graphGraftSourceRefusals,
  graphGraftSourceExecutionFailures} from './fixtures/graph-graft-source-input.mjs';
import {graphReachSourceSuccesses, graphReachSourceRefusals}
  from './fixtures/graph-reach-source-input.mjs';
import {graphShortestSourceSuccesses, graphShortestSourceRefusals}
  from './fixtures/graph-shortest-source-input.mjs';
import {graphMeanSourceOracles, graphMeanSourceRefusals}
  from './fixtures/graph-mean-source-input.mjs';

test('combined Graph selection retains all original independent oracles exactly once', () => {
  for (const [kind, families, expectedCount] of [
    ['successes', [graphGraftSourceSuccesses, graphReachSourceSuccesses,
      graphShortestSourceSuccesses, graphMeanSourceOracles], 27],
    ['refusals', [graphGraftSourceRefusals, graphReachSourceRefusals,
      graphShortestSourceRefusals, graphMeanSourceRefusals], 16],
    ['executionFailures', [graphGraftSourceExecutionFailures], 1],
  ]) {
    const actual = graphRemainingOperationInputs[kind];
    assert.equal(actual.length, expectedCount);
    assert.equal(new Set(actual.map(item => item.name)).size, expectedCount);
    for (const [index, expected] of families.flat().entries()) {
      assert.equal(actual[index], expected, `${kind} retains the authored oracle`);
    }
  }
});

test('combined Graph selection stays narrow and rereads after both producers exit', async () => {
  const driver = await readFile(new URL('./test-packed-public-query.mjs', import.meta.url), 'utf8');
  const flag = "'--graph-remaining-operations-only'";
  const narrow = driver.slice(driver.indexOf('const narrowPublicQuery ='),
    driver.indexOf('.includes(flag));', driver.indexOf('const narrowPublicQuery =')));
  assert.ok(narrow.includes(flag));
  assert.ok(driver.includes("runtimeEnvironment.ACTQL_TEST_GRAPH_REMAINING_OPERATIONS_ONLY = '1'"));
  assert.ok(driver.includes("['scripts/fixtures/graph-remaining-operation-inputs.mjs', 'graph-remaining-operation-inputs.mjs']"));
  const source = driver.indexOf("['packed-query-transports.mjs']");
  const restart = driver.indexOf('if (process.argv.includes(\'--graph-graft-only\')', source);
  const end = driver.indexOf("if (process.argv.includes('--source-graph-member-only'))", restart);
  assert.ok(source >= 0 && restart > source && end > restart);
  const branch = driver.slice(restart, end);
  assert.ok(branch.includes(flag));
  assert.ok(branch.includes("exerciseRetainedQueryRestart({ACTQL_TEST_RETAINED_COHORT_ONLY: '1'})"));
  assert.ok(branch.includes('return;'));
  const corpus = await readFile(new URL('./fixtures/packed-public-query.mjs', import.meta.url), 'utf8');
  assert.ok(corpus.includes('graphRemainingOperationsOnly ? graphRemainingOperationInputs'));
});
