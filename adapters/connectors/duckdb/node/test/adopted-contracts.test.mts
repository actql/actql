import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

// All keys/numbers in these contract bodies are in JSON's ordinary exact domain.
const canonical = (value: unknown): string => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical((value as Record<string, unknown>)[key])}`).join(',')}}`
    : JSON.stringify(value);
const cid = (value: unknown) => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;

test('example ships exact adopted contract bodies, not test-generated execution expectations', async () => {
  const bundle = JSON.parse(await readFile(new URL('../contracts/adopted-relation.json', import.meta.url), 'utf8')) as Record<string, unknown>;
  const root = new URL('../../../../../', import.meta.url);
  const aoa = JSON.parse(await readFile(new URL('spec/contracts/actql-aoa.json', root), 'utf8')) as Readonly<{
    pipeline_registry_file: string;
    execution_contracts: Record<string, unknown>;
  }>;
  const authoritative = {
    registry: JSON.parse(await readFile(new URL(aoa.pipeline_registry_file, root), 'utf8')),
    values: aoa.execution_contracts['REL.values'],
    fragment: aoa.execution_contracts['ACTQL.expression_fragment/0.1'],
    graph: aoa.execution_contracts['BRIDGE.rows.to_graph'],
  };
  const expected = {
    registry: 'sha256:f4f66d1ce9e86d1cf3326f86a4909a27eed1c83f6e0a7603d7bd3b5f819873cc',
    values: 'sha256:96c7925a693801dcb3bce9f3e2da9b4fd9ed39e517af90cbac0e1adbee5ad2ae',
    fragment: 'sha256:0e118d8833c7c8f3d211d273d6f839591f459db0aaa8b0d770e562de2488111b',
    graph: 'sha256:0979999a64bb47f7fcb0d113c0bbcab592ad0a268b548a8776f8fac4fd6f6d84',
  };
  for (const [key, identity] of Object.entries(expected)) {
    assert.equal(cid(authoritative[key as keyof typeof authoritative]), identity);
    assert.deepEqual(bundle[key], authoritative[key as keyof typeof authoritative]);
    assert.equal(bundle[`${key}_cid`], identity);
    assert.equal(cid(bundle[key]), identity);
  }
  assert.deepEqual(Object.keys(bundle).sort(), [
    'registry', 'registry_cid', 'values', 'values_cid',
    'fragment', 'fragment_cid', 'graph', 'graph_cid',
  ].sort());
});
