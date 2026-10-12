import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {sgaRoleSourceOracle} from './sga-source-role-oracle.mjs';
const old = JSON.parse(readFileSync(new URL('../reviews/2026-10-11-with-carrier-cutover/p2-sga-public-original.json', import.meta.url)));
for (const [family, original] of Object.entries(old.snapshots)) {
  test('SGA source role cutover retains full independent ' + family + ' obligations', async () => {
    const expected = structuredClone(original);
    function visit(value) {
      if (!value || typeof value !== 'object') return;
      if (typeof value.text === 'string' && value.format !== 'json')
        value.text = sgaRoleSourceOracle(value.text);
      for (const child of Object.values(value)) visit(child);
    }
    visit(expected);
    if (family === 'graph-delta-json-source')
      expected.graphDeltaJsonSource = sgaRoleSourceOracle(expected.graphDeltaJsonSource);
    const actual = JSON.parse(JSON.stringify(await import('./fixtures/' + family + '.mjs')));
    assert.deepEqual(actual, expected);
  });
}
