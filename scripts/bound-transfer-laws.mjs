import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { machineCid } from './actql-spec-family.mjs';

const root = new URL('../', import.meta.url);
const kinds = new Set(['preserve', 'clamp', 'multiply', 'add', 'reduce',
  'carrier_specific', 'explicitly_unknown_requires_ceiling']);

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

export function validateTransferLaws(body, source) {
  assert.deepEqual(Object.keys(body).sort(), ['operations', 'version']);
  assert.equal(body.version, 'actql-bound-transfer-laws/0.1');
  assert.ok(body.operations && typeof body.operations === 'object' && !Array.isArray(body.operations));
  const names = operationInventory(source);
  assert.deepEqual(Object.keys(body.operations).sort(), names,
    'Bound transfer coverage must exactly match the public operation inventory');
  for (const [op, kind] of Object.entries(body.operations)) {
    assert.ok(kinds.has(kind), `Unknown bound transfer classification for ${op}`);
  }
  return { operations: names.length, cid: machineCid(body) };
}

export function loadTransferLaws() {
  return {
    body: JSON.parse(readFileSync(new URL('spec/contracts/actql-bound-transfer-laws.json', root), 'utf8')),
    source: readFileSync(new URL('docs/spec/language.md', root), 'utf8'),
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { body, source } = loadTransferLaws();
  console.log(JSON.stringify(validateTransferLaws(body, source)));
}
