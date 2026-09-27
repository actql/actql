// Run only in a copied tree with no installed Connector dependencies.
import assert from 'node:assert/strict';
import {runCapturedInternalStrategy, runCapturedStrategy} from
  '../adapters/host-node/entry.mjs';
import * as fixture from '../_build/js/release/build/node_host_conformance/node_host_conformance.js';
import {checked} from '../adapters/host-common/runtime-result.mjs';
import {runtimeCore} from '../adapters/host-common/runtime-core.mjs';
import * as moon from '../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {tmpdir} from 'node:os';
import {readPublishedResultRows} from './published-result-rows.mjs';

// Managed Local completions are not mirrored into the captured output slot;
// results are read through the Named Result publication export instead.
const resultLimits = Object.freeze({
  maxRows: 100, maxValueNodes: 1000, maxValueTextBytes: 10000,
  maxValueDepth: 20, maxValueWork: 100000, maxWireBytes: 100000,
  maxWireNodes: 1000, maxWireDepth: 20, maxColumns: 20, maxOrderWork: 10000,
  maxLogicalWireBytes: 100000, maxLogicalWireNodes: 1000,
  maxLogicalWireDepth: 20, maxSchemaFields: 20, maxSchemaBytes: 10000,
  maxSchemaNodes: 1000, maxSchemaDepth: 20, maxBatchBytes: 4096,
  maxResultFields: 20, maxResultMappingWork: 1000, maxResultOrderWork: 1000,
  maxResultWorkspaceEntries: 1000,
});
const published = (execution, result) => readPublishedResultRows(
  runtimeCore(moon), execution, result, resultLimits, tmpdir());

for (const mode of [0,1,2]) {
  const scenario = checked(fixture.prepareSubset(mode));
  const setup = fixture.subsetHost(scenario);
  let result;
  try {
    const unused = new Proxy({}, {get() { assert.fail('unused configuration inspected'); }});
    result = await runCapturedStrategy(setup,{duckdb:unused});
    assert.equal(result.status,'host-tasks-completed');
    assert.equal(result.completed.length,3);
    // Task 3 publishes Named Result c.
    assert.deepEqual(await published(result, 1), [{id: 3}]);
    // Managed Local bridges its inputs; the reference module reads in place.
    if (mode === 1) assert.equal(result.usage().transferredBytes, 0n);
    else assert.ok(result.usage().transferredBytes > 0n);
  } finally { result?.close(); fixture.closeSubset(scenario); }
  assert.equal(await result.cleanup(),true);
  assert.equal(result.usage().heldBytes,0n);
  assert.equal(result.usage().reservedExecutionBytes,0n);
}
console.log('Local-only, reference-only and mixed standard entry passed without DuckDB dependencies.');
const sorted = checked(fixture.prepareSortTake());
let sortedResult;
try {
  sortedResult = await runCapturedStrategy(fixture.subsetHost(sorted));
  assert.equal(sortedResult.status, 'host-tasks-completed');
  assert.equal(sortedResult.completed.length, 3);
  // Task 3 consumes the sorted take of task 1 and publishes it unchanged.
  assert.deepEqual(sortedResult.completed.map(item => item.outputRows),
    [2, 4, 2]);
  assert.deepEqual(await published(sortedResult, 1), [{id: 4}, {id: 4}]);
  assert.ok(sortedResult.usage().transferredBytes > 0n);
} finally { sortedResult?.close(); fixture.closeSubset(sorted); }
assert.equal(await sortedResult.cleanup(), true);
assert.equal(sortedResult.usage().heldBytes, 0n);
assert.equal(sortedResult.usage().reservedExecutionBytes, 0n);
console.log('Checked sort/take and downstream consumer passed through the standard Local-only Host.');

const events = checked(fixture.prepareEventsSession());
let eventsResult;
try {
  eventsResult = await runCapturedInternalStrategy(
    fixture.subsetHost(events),
  );
  assert.equal(eventsResult.status, 'host-tasks-completed');
  // The session stays fused with its Relation projection, so no Carrier
  // task boundary remains.
  assert.deepEqual(
    eventsResult.completed.map(item => item.outputRepresentation),
    Array(4).fill('managed-local-memory'),
  );
  assert.deepEqual(
    eventsResult.completed.map(item => item.task),
    [1, 2, 3, 4],
  );
  assert.deepEqual(
    eventsResult.completed.map(item => item.outputRows),
    [3, 3, 3, 3],
  );
} finally {
  eventsResult?.close();
  fixture.closeSubset(events);
}
assert.equal(await eventsResult.cleanup(), true);
assert.equal(eventsResult.usage().heldBytes, 0n);
assert.equal(eventsResult.usage().reservedExecutionBytes, 0n);
console.log('Checked a registered Events provider through the standard Host.');
