import assert from 'node:assert/strict';
const variants = ['current_filter', 'current_edge_filter'];
const fields = ['execution', 'retention', 'held', 'transfer'];
const address = value => typeof value === 'string' && /^[1-9][0-9]*$/.test(value);

// Addresses identify borrowed objects only within one fixture invocation.
// Root clearing proves loss of this reference, not GC or reservation generation.
export function inspectDriverRetirement(log) {
  const cases = [];
  let current;
  for (const line of log.split('\n')) {
    if (line.startsWith('ACTQL_DRIVER_CASE:')) {
      assert(!current, 'Overlapping Host observations');
      current = {variant: line.slice(18), roots: new Map(), ledger: []};
      assert.equal(current.variant, variants[cases.length], 'Unexpected Host case');
    } else if (line.startsWith('ACTQL_DRIVER_CASE_DONE:')) {
      assert(current && line.slice(23) === current.variant, 'Missing Host completion');
      cases.push(current); current = undefined;
    } else if (line.startsWith('ACTQL_DRIVER_ROOT:')) {
      assert(current, 'Root outside actual Host case');
      const r = JSON.parse(line.slice(18));
      assert(Number.isInteger(r.task) && r.task >= 0 && address(r.root));
      assert.equal(r.rootRequestedBytes, 16, 'Unreviewed Ref ABI');
      assert(r.provider === null || address(r.provider));
      let group = r.task === 0 ? [...current.roots.values()].find(g => g.root === r.root) : current.roots.get(r.task);
      if (!group) {
        assert(r.task > 0 && r.phase === 0, 'Missing initial root');
        assert.equal(r.provider, null);
        assert(![...current.roots.values()].some(g => g.root === r.root), 'Aliased driver roots');
        group = {root: r.root, started: false, cleared: false, pending: 0, repeated: 0};
        current.roots.set(r.task, group);
      } else {
        assert.equal(r.root, group.root, 'Replaced control Ref');
        switch (r.phase) {
          case 1:
            assert(!group.started && !group.cleared && r.provider !== null, 'Invalid provider installation');
            group.started = true; group.provider = r.provider;
            break;
          case 2:
            assert(group.started && !group.cleared, 'Pending cleanup lost custody');
            assert.equal(r.provider, group.provider, 'Pending provider changed or released');
            group.pending++;
            break;
          case 3:
            assert(group.started && !group.cleared, 'Invalid successful cleanup');
            assert.equal(r.provider, null, 'Successful cleanup retained provider root');
            group.cleared = true;
            break;
          case 4:
            assert(!group.started || group.cleared, 'Repeated cleanup cleared root prematurely');
            assert.equal(r.provider, null);
            if (group.cleared) group.repeated++;
            break;
          default: assert.fail('Unknown or repeated initial phase');
        }
      }
    } else if (line.startsWith('ACTQL_DRIVER_LEDGER:')) {
      assert(current, 'Ledger outside actual Host case');
      const r = JSON.parse(line.slice(20));
      assert.equal(r.phase, ['pending', 'cleaned', 'repeated'][current.ledger.length]);
      for (const f of fields) assert(Number.isSafeInteger(r[f]) && r[f] >= 0, 'Unrepresentable ledger observation');
      current.ledger.push(r);
    }
  }
  assert(!current && cases.length === 2, 'Missing completed Host cases');
  const summaries = cases.map(c => {
    const groups = [...c.roots.values()];
    assert(groups.length > 0 && groups.every(g => !g.started || g.cleared), 'Unfinished provider root');
    const delayed = groups.filter(g => g.pending === 2 && g.cleared && g.repeated > 0);
    assert.equal(delayed.length, 1, 'Missing real false/error/retry provider');
    assert.equal(c.ledger.length, 3, 'Missing reservation boundaries');
    const [pending, cleaned, repeated] = c.ledger;
    assert(pending.execution > cleaned.execution, 'Scratch reservation not returned');
    for (const f of fields.filter(f => f !== 'execution')) assert.equal(cleaned[f], pending[f], 'Changed unrelated custody');
    for (const f of fields) assert.equal(repeated[f], cleaned[f], 'Duplicate reservation return');
    return {variant: c.variant, driverRoots: groups.length, delayedProviders: delayed.length,
      rootRequestedBytes: 16, pendingExecution: pending.execution, cleanedExecution: cleaned.execution};
  });
  return {cases: summaries, scope: 'two existing Native Host MATCH cases; real driver stop/cleanup root and reservation correspondence',
    wholePhysicalLifetimeUpper: false, ledgerGenerationCorrespondence: false, physicalGCDestruction: false};
}
