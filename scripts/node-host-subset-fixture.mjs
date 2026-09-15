// Run only in a copied tree with no installed Connector dependencies.
import assert from 'node:assert/strict';
import {runCapturedStrategy} from '../adapters/host-node/entry.mjs';
import * as fixture from '../_build/js/release/build/node_host_conformance/node_host_conformance.js';
import {checked} from '../adapters/host-common/runtime-result.mjs';

for (const mode of [0,1,2]) {
  const scenario = checked(fixture.prepareSubset(mode));
  const setup = fixture.subsetHost(scenario);
  let result;
  try {
    const unused = new Proxy({}, {get() { assert.fail('unused configuration inspected'); }});
    result = await runCapturedStrategy(setup,{duckdb:unused});
    assert.equal(result.status,'host-tasks-completed');
    assert.equal(result.completed.length,3);
    assert.equal(fixture.outputRows(result.output(3)),1);
    assert.equal(fixture.outputValue(result.output(3)),3);
    assert.equal(result.usage().transferredBytes,0n);
  } finally { result?.close(); fixture.closeSubset(scenario); }
  assert.equal(await result.cleanup(),true);
  assert.equal(result.usage().heldBytes,0n);
  assert.equal(result.usage().reservedExecutionBytes,0n);
}
console.log('Local-only, reference-only and mixed standard entry passed without DuckDB dependencies.');
