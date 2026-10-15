import assert from 'node:assert/strict';

// Authored from the original issue #640 corpus at
// 57c5ce979025c57ac8d2dc65affaa9bedb83b0b7, independently of worker selection.
const expected = [
  ['successes', 0, 'independent-json'],
  ['successes', 1, 'sql-alias-collision'],
  ['successes', 2, 'pipe-limit-offset'],
  ['successes', 3, 'cte-shared-producer'],
  ['successes', 4, 'selected-qualified-input'],
  ['successes', 5, 'selected-expression-reuse'],
  ['successes', 6, 'typed-empty'],
  ['executionFailures', 0, 'demanded-sort-failure'],
  ['refusals', 0, 'dropped-input-0'],
  ['refusals', 1, 'dropped-input-1'],
  ['refusals', 2, 'dropped-input-2'],
].map(([kind, position, name]) =>
  ['standard', kind, position, 'distinct-join-order-' + name]);

export function requireDistinctJoinOrderInventory(inventory) {
  assert.ok(Array.isArray(inventory));
  assert.equal(inventory.length, 11, 'original DISTINCT JOIN corpus has eleven cases per transport');
  const identities = inventory.map(value => {
    assert.equal(typeof value, 'string');
    const identity = JSON.parse(value);
    assert.ok(Array.isArray(identity));
    assert.equal(identity.length, 5);
    assert.match(identity[4], /^[a-f0-9]{64}$/u, 'retain the original case-content digest');
    return identity.slice(0, 4);
  });
  assert.deepEqual(identities, expected,
    'selected DISTINCT JOIN acceptance must retain every original case in order');
}

export function requireDistinctJoinOrderReports(reports) {
  assert.deepEqual(reports.map(report => report.mode), ['local', 'remote']);
  for (const report of reports) {
    assert.equal(report.complete, true);
    requireDistinctJoinOrderInventory(report.expectedInventory);
    requireDistinctJoinOrderInventory(report.completedInventory);
    assert.deepEqual(report.completedInventory, report.expectedInventory);
    assert.equal(report.expectedRetainedCohorts, 1);
    assert.equal(report.needsTail, false, 'selected acceptance cannot start unrelated tail work');
  }
}
