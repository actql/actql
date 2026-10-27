import assert from 'node:assert/strict';

export function operationInventory(source) {
  const start = source.indexOf('<a id="operation-inventory"></a>');
  const end = source.indexOf('<a id="relation-operations"></a>', start);
  assert.ok(start >= 0 && end > start, 'Missing authoritative operation inventory');
  const names = [];
  for (const line of source.slice(start, end).split('\n')) {
    if (!line.startsWith('|')) continue;
    const operationCell = line.split('|')[2];
    for (const match of operationCell.matchAll(/\[`([a-z_]+)`\]\(#[a-z-]+\)/g)) {
      names.push(match[1]);
    }
  }
  assert.ok(names.length > 0, 'Empty operation inventory');
  assert.equal(new Set(names).size, names.length, 'Duplicate operation inventory entry');
  return names.sort();
}
