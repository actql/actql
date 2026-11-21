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
  const root = new URL('../../../../../', import.meta.url);
  const aoa = JSON.parse(await readFile(new URL('spec/contracts/actql-aoa.json', root), 'utf8'));
  const authoritative = {
    registry: JSON.parse(await readFile(new URL(aoa.pipeline_registry_file, root), 'utf8')),
    values: aoa.execution_contracts['REL.values'],
    fragment: aoa.execution_contracts['ACTQL.expression_fragment/0.1'],
    graph: aoa.execution_contracts['BRIDGE.rows.to_graph'],
  };
  const expected = {
    registry: 'sha256:cac01dd33b265af8cef9e5d96afa1c374098164124c70c89fbbb931bfea676fa',
    values: 'sha256:96c7925a693801dcb3bce9f3e2da9b4fd9ed39e517af90cbac0e1adbee5ad2ae',
    fragment: 'sha256:de42ffe6629fe426ddba217ea4b34847f868511674ee0589ed62d22271d6eef0',
    graph: 'sha256:0979999a64bb47f7fcb0d113c0bbcab592ad0a268b548a8776f8fac4fd6f6d84',
  };
  for (const [key, identity] of Object.entries(expected)) {
    assert.equal(cid(authoritative[key]), identity);
    assert.deepEqual(bundle[key], authoritative[key]);
    assert.equal(bundle[`${key}_cid`], identity);
    assert.equal(cid(bundle[key]), identity);
  }
  assert.deepEqual(Object.keys(bundle).sort(), [
    'registry', 'registry_cid', 'values', 'values_cid',
    'fragment', 'fragment_cid', 'graph', 'graph_cid',
  ].sort());
});
