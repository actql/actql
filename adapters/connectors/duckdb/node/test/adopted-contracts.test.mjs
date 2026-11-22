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
    registry: 'sha256:52e62094b1162213605e27199aa9a0e4832ee7771bcc1be66124f2fefb0a01e7',
    values: 'sha256:acdc65097f478d6b14126eb2d2e1bdd8df5893de923b3f9db7412b73b4a318fe',
    fragment: 'sha256:5041f5fb5d612d2db5a86b9aa4d6a47e5644b524db88cdebbc27923957b77736',
    graph: 'sha256:1c871512fceef5e68415511a2fe40a62df2c287fb31360edca749b3f13921113',
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
