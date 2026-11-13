import assert from 'node:assert/strict';

// Shared controls appear in more than one independently authored corpus.
// A case name is also its request identity: equivalent controls run once;
// conflicting source or expectations must never be silently overwritten.
export function uniquePublicQueryCases(cases) {
  const unique = new Map();
  for (const item of cases) {
    if (unique.has(item.name)) {
      assert.deepEqual(item, unique.get(item.name),
        `Conflicting public query fixture: ${item.name}`);
    } else unique.set(item.name, item);
  }
  return [...unique.values()];
}

export function publicQueryCohorts(inputs) {
  const cohorts = [];
  let current = {successes: [], executionFailures: [], refusals: []};
  // Count distinct references before any content-address deduplication. The
  // Store owner allows 8R + 11 for publication; each read retains a grant,
  // attempt, two records and receipt, and describe retains one manifest grant.
  // Also reserve one fresh-process read/describe per Result for every case
  // (only the first/last are exercised), plus the existing String restart.
  const maxObjects = 10000;
  const publicationObjects = results => 8 * results + 11;
  // Each fresh delivery performs two complete prior-attempt scans. Keeping
  // N(N-1) <= 4096 bounds those admission scans across a cohort; this is a
  // harness work bound, not a product limit or an allowance for parallel work.
  const maxDeliveryContractVisits = 4096;
  const maxDeliveryAttempts = Math.floor((1 + Math.sqrt(1 +
    4 * maxDeliveryContractVisits)) / 2);
  const deliveryObjects = 5;
  const descriptionObjects = 1;
  let retainedObjectAllowance = 0;
  let deliveryAttemptAllowance = 0;
  for (const kind of ['successes', 'executionFailures', 'refusals']) {
    for (const item of inputs[kind] ?? []) {
      const results = kind === 'successes'
        ? Math.max(1, Object.keys(item.results ?? {answer: null}).length)
        : kind === 'executionFailures' ? Math.max(1, item.resultNames.length) : 0;
      const allowance = kind === 'refusals' ? 0 : publicationObjects(results) +
        results * (3 * deliveryObjects + 2 * descriptionObjects) +
        (item.name === 'sql' ? deliveryObjects : 0) +
        (item.name === 'exact-string-values' ? deliveryObjects + descriptionObjects : 0);
      const deliveries = 3 * results +
        (item.name === 'sql' ? 1 : 0) + (item.name === 'exact-string-values' ? 1 : 0);
      assert.ok(allowance <= maxObjects && deliveries <= maxDeliveryAttempts,
        `Public query case ${item.name} exceeds an indivisible cohort budget: ` +
        `${allowance}/${maxObjects} objects, ${deliveries}/${maxDeliveryAttempts} deliveries`);
      if (retainedObjectAllowance !== 0 &&
          (retainedObjectAllowance + allowance > maxObjects ||
            deliveryAttemptAllowance + deliveries > maxDeliveryAttempts)) {
        cohorts.push(current);
        current = {successes: [], executionFailures: [], refusals: []};
        retainedObjectAllowance = 0;
        deliveryAttemptAllowance = 0;
      }
      // Never split an authored multi-Result case or lower its own limits.
      current[kind].push(item);
      retainedObjectAllowance += allowance;
      deliveryAttemptAllowance += deliveries;
    }
  }
  if (Object.values(current).some(items => items.length > 0) || cohorts.length === 0) cohorts.push(current);
  for (const kind of ['successes', 'executionFailures', 'refusals']) {
    assert.deepEqual(cohorts.flatMap(cohort => cohort[kind]), inputs[kind] ?? [],
      'cohorts preserve every authored case in original order');
  }
  for (const cohort of cohorts) for (const kind of ['successes', 'executionFailures']) {
    assert.equal(new Set(cohort[kind].map(item => item.name)).size, cohort[kind].length,
      'independent accepted cases cannot reuse a submission nonce within one cohort');
  }
  return cohorts;
}

// Partition whole original cohorts, including their original first/last Saved
// samples. Stable least-case-load assignment changes only CI ownership.
export function partitionPublicQueryProfiles(profiles, part, inventoryKeys) {
  assert.ok(part === undefined || [1, 2, 3].includes(part), 'UnknownPackedPortablePart');
  const loads = [0, 0, 0], entries = [];
  for (const profile of profiles) {
    const offsets = {};
    profile.cohorts.forEach((cohort, index) => entries.push({profile, cohort, index,
      inventory: inventoryKeys(profile.name, cohort, offsets)}));
  }
  // The first original cohort owns String restart and the serial ancillary
  // controls in part1. Seed each lane with an original success cohort so its
  // retained Saved control remains nonempty. Place remaining whole cohorts largest-first so the last
  // refusal-heavy cohort cannot overload an otherwise balanced lane.
  for (const [index, entry] of entries.slice(0, 3).entries()) {
    entry.owner = index + 1;
    loads[index] = entry.inventory.length;
  }
  for (const entry of entries.slice(3).toSorted((a, b) => b.inventory.length - a.inventory.length)) {
    const owner = loads.indexOf(Math.min(...loads));
    entry.owner = owner + 1;
    loads[owner] += entry.inventory.length;
  }
  return profiles.map(profile => {
    const selected = entries.filter(entry => entry.profile === profile &&
      (part === undefined || entry.owner === part));
    return {...profile, cohorts: selected.map(entry => entry.cohort),
      cohortIndexes: selected.map(entry => entry.index),
      cohortInventories: selected.map(entry => entry.inventory),
      inputs: Object.fromEntries(['successes', 'executionFailures', 'refusals'].map(kind =>
        [kind, selected.flatMap(entry => entry.cohort[kind] ?? [])]))};
  }).filter(profile => profile.cohorts.length > 0);
}
