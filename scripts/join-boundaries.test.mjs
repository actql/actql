import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const source = new URL('../src/', import.meta.url);

// Conservative closure: include test imports too. The lower join package must
// never reach evidence or the upper facade through any repository dependency.
function closure(root) {
  const seen = new Set();
  const pending = [root];
  while (pending.length) {
    const name = pending.pop();
    if (seen.has(name)) continue;
    seen.add(name);
    const manifest = readFileSync(new URL(`${name}/moon.pkg`, source), 'utf8');
    for (const match of manifest.matchAll(/"actql\/actql\/([^"\n]+)"/g)) {
      pending.push(match[1]);
    }
  }
  return seen;
}

test('checked join shape remains below key evidence and as-of completion', () => {
  const lower = closure('relation_join_shape');
  assert.ok(lower.has('relation_key_obligation'));
  assert.ok(!lower.has('relation_evidence'));
  assert.ok(!lower.has('relation_join'));
  assert.ok(closure('relation_join').has('relation_evidence'));
  assert.deepEqual([...closure('relation_key_obligation')], ['relation_key_obligation']);
});
