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
    registry: 'sha256:bad5b4562a4e6cbb056ab2dea31cd9a20366190353b14e0be3125454177519b8',
    values: 'sha256:9b716536b27d313e93deadae776d9abf21c3d06dcd653d2eb3b74e0c276a182b',
    fragment: 'sha256:01b5deb12652eaff90dbf16c4595b7806a71266a65859fd12ffe3a5941045459',
    graph: 'sha256:b6c5006e94c3c865672ab2478f4b1897aa567314502e55eb50f784a50a94d210',
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
