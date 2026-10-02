import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

// All keys/numbers in these contract bodies are in JSON's ordinary exact domain.
const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const cid = value => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;

test('example ships exact adopted contract bodies, not test-generated execution expectations', async () => {
  const bundle = JSON.parse(await readFile(new URL('../contracts/adopted-relation.json', import.meta.url), 'utf8'));
  const expected = {
    registry: 'sha256:21108cfa0ed73e4722f9199e494160fa24b17ad37f2807aa1a954316d15cea9d',
    values: 'sha256:9b716536b27d313e93deadae776d9abf21c3d06dcd653d2eb3b74e0c276a182b',
    fragment: 'sha256:1282c3d8af052606f64be809cead104630c67a8b676050bcdc7edd4a884b9b60',
    property_graph: 'sha256:6f84b787b55f3a84c6b420046e3f9346ac9019627bc852311fcf8d9f577dec03',
  };
  for (const [key, identity] of Object.entries(expected)) {
    assert.equal(bundle[`${key}_cid`], identity);
    assert.equal(cid(bundle[key]), identity);
  }
  assert.equal(
    bundle.source_revision,
    '9edb5a65db8b822b8629cfa4913fb1097fb99945',
  );
});
