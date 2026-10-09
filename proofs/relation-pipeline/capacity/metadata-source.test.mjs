import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { checkCensus } from './census.mjs';

const root = fileURLToPath(new URL('../../../', import.meta.url));

test('immutable name totals remain in the existing structural census', () => {
  const census = checkCensus(root);
  for (const name of ['Fields', 'Schema']) {
    const record = census.sourceFields.find(item => item.struct === name);
    assert(record, `missing ${name} metadata owner`);
    assert.equal(record.fieldTypes.name_bytes, 'Int');
  }
  assert.match(census.selectedCompletionMetadataScope, /not treated as zero-byte/);
});

for (const [name, path] of [
  ['Fields', 'src/value_contract/types.mbt'],
  ['Schema', 'src/relation_schema/schema.mbt'],
]) {
  test(`${name} cached-word removal is rejected by the source census`, () => {
    assert.throws(() => checkCensus(root, requested => {
      const source = readFileSync(join(root, requested), 'utf8');
      return requested === path ? source.replace(/^  name_bytes : Int\n/m, '') : source;
    }), /Unreviewed state\/container field/);
  });
}
