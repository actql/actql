import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {graphArgumentLiteralIds, graphArgumentCheckInventory, graphArgumentNoExecution,
  requireGraphArgumentCheckReport} from './fixtures/graph-argument-check.mjs';

const complete = mode => ({version: 'actql-graph-argument-check/0.1', mode,
  expectedInventory: [...graphArgumentCheckInventory], completedInventory: [...graphArgumentCheckInventory],
  cases: graphArgumentCheckInventory.map(id => ({id, noExecution: {...graphArgumentNoExecution}})),
  noExecution: {...graphArgumentNoExecution}, beforeDispatchCalls: mode === 'remote' ? 0 : null,
  complete: true, primaryError: null});

test('Graph CHECK inventory retains fourteen authored literals and all disclosure controls', () => {
  assert.equal(graphArgumentLiteralIds.length, 14);
  assert.equal(graphArgumentCheckInventory.length, 28);
  assert.equal(new Set(graphArgumentCheckInventory).size, 28);
  const fixture = JSON.parse(readFileSync(new URL('./fixtures/graph-argument-origin-literals.json', import.meta.url)));
  assert.deepEqual(fixture.cases.map(item => item.id), graphArgumentLiteralIds);
  for (const item of fixture.cases) assert.equal(
    Buffer.from(item.source).subarray(item.startByte, item.endByte).toString('utf8'), item.token);
  assert.deepEqual(graphArgumentCheckInventory.slice(-6), [
    'components-protected-absent', 'components-protected-denied',
    'subgraph-protected-absent', 'subgraph-protected-denied',
    'subgraph-protected-value-absent', 'subgraph-protected-value-denied',
  ]);
});

for (const mode of ['local', 'remote']) {
  test(`Graph CHECK ${mode} receipt requires exact completion and zero execution`, () => {
    requireGraphArgumentCheckReport(complete(mode), mode);
    for (const mutate of [
      report => report.expectedInventory.pop(),
      report => report.completedInventory.pop(),
      report => report.completedInventory.reverse(),
      report => report.completedInventory.push(report.completedInventory[0]),
      report => report.cases.pop(),
      report => { report.cases[0].noExecution.sourceOpens++; },
      report => { report.cases[0].noExecution.dispatchReservations++; },
      report => { report.cases[0].noExecution.physicalReservations++; },
      report => { report.noExecution.runs++; },
      report => { report.complete = false; },
      report => { report.primaryError = 'unfinished'; },
      report => { report.mode = 'other'; },
      report => { report.beforeDispatchCalls = 1; },
    ]) {
      const report = complete(mode);
      mutate(report);
      assert.throws(() => requireGraphArgumentCheckReport(report, mode));
    }
  });
}
