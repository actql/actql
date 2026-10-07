import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
export function checkCensus(root, read = path => readFileSync(join(root, path), 'utf8')) {
  const census = JSON.parse(read('proofs/relation-pipeline/capacity/census.json'));
  assert.equal(census.version, 'actql-relation-structural-census/0.1');
  for (const item of census.sourceFields) {
    const source = read(item.path);
    const body = source.match(new RegExp(`(?:priv )?struct ${item.struct} \\{\\n([\\s\\S]*?)\\n\\}`))?.[1];
    assert(body, `Missing actual state ${item.struct}`);
    const fields = [...body.matchAll(/^  (?:mut )?(\w+)\s*:/gm)].map(m => m[1]);
    assert.deepEqual(fields, item.fields, `Unreviewed state/container field ${item.struct}`);
    for (const [name, type] of Object.entries(item.fieldTypes ?? {})) {
      assert(item.fields.includes(name), `Unknown typed census field ${item.struct}.${name}`);
      const actual = body.match(new RegExp(`^  (?:mut )?${name}\\s*:\\s*([^\\n]+)$`, 'm'))?.[1];
      assert.equal(actual?.trim(), type, `Unreviewed retained representation ${item.struct}.${name}`);
    }
  }
  return census;
}
