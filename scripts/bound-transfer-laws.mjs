import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { machineCid } from './actql-spec-family.mjs';
import {parseDocument} from 'yaml';
import {operationInventory} from './operation-inventory.mjs';

const root = new URL('../', import.meta.url);
const kinds = new Set(['preserve', 'clamp', 'multiply', 'add', 'reduce',
  'carrier_specific', 'explicitly_unknown_requires_ceiling']);

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
    body: parseTransferLawSource(readFileSync(new URL('spec/contracts/actql-bound-transfer-laws.json', root), 'utf8')),
    source: readFileSync(new URL('docs/spec/language.md', root), 'utf8'),
  };
}

// Validate the original JSON source before JSON.parse can erase duplicate keys.
// Reuse the existing document parser only for its duplicate-key diagnostic;
// JSON syntax and the admitted value still come from JSON.parse.
export function parseTransferLawSource(source) {
  const document = parseDocument(source, {uniqueKeys: true});
  assert.equal(document.errors.length, 0,
    document.errors.map(error => error.message).join('; '));
  return JSON.parse(source);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { body, source } = loadTransferLaws();
  console.log(JSON.stringify(validateTransferLaws(body, source)));
}
