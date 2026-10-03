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
