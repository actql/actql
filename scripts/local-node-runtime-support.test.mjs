import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('Local Node package and development metadata cover the required SQLite APIs', () => {
  // isTransaction exists from 22.16 on the 22.x line and from 24.0 on the
  // later line. Node 23 does not provide this required transaction state.
  const expected = '^22.16.0 || >=24.0.0';
  for (const name of ['node', 'local-node']) {
    const manifest = JSON.parse(read(`packages/${name}/package.json`));
    assert.equal(manifest.engines.node, expected, manifest.name);
    const documentation = read(`packages/${name}/README.md`).replace(/\s+/gu, ' ');
    assert(documentation.includes('Node.js 22.16 or later in the 22.x line, or Node.js 24.0 or later'));
    assert(documentation.includes('isTransaction'));
  }
  assert.equal(JSON.parse(read('package.json')).engines.node, expected);
  assert.equal(JSON.parse(read('package-lock.json')).packages[''].engines.node, expected);
  // The transport-only SDK does not acquire the Local SQLite dependency.
  assert.equal(JSON.parse(read('packages/sdk/package.json')).engines.node, '>=22');
});
