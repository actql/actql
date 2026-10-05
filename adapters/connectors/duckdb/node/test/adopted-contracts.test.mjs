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
    registry: 'sha256:fee948e7f47074c96f02bf392cba9520473679beb4db16522ea15a22b20f8b84',
    values: 'sha256:9b716536b27d313e93deadae776d9abf21c3d06dcd653d2eb3b74e0c276a182b',
    fragment: 'sha256:95b3ee285ed5b097c01cc2d414603e051810ebf83c65cb94bceb18ee1477d1bf',
    property_graph: 'sha256:b00de8912497c6af1596debd1c59ee8d3477faf0391be40f64ac82ebc6d9ebb7',
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
