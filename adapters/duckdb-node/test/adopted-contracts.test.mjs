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
    registry: 'sha256:5be4133ab14b50ece1109cb2ce7cacf52005ff1c04ef48b2aa7b88f163eba09f',
    values: 'sha256:c95bc0d474fd6fbe62d3182bdefe6af412070f6ad2c8e102c5279d7a8b3eed17',
    fragment: 'sha256:1282c3d8af052606f64be809cead104630c67a8b676050bcdc7edd4a884b9b60',
  };
  for (const [key, identity] of Object.entries(expected)) {
    assert.equal(bundle[`${key}_cid`], identity);
    assert.equal(cid(bundle[key]), identity);
  }
  assert.equal(bundle.source_revision, 'aa3c7a3e047144b8823ec59ae86dfdaeb76b4d74');
});
