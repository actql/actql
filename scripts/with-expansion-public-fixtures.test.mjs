import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
const retained = JSON.parse(readFileSync(new URL('../reviews/2026-10-11-with-carrier-cutover/with-expansion-public-original-inventory.json', import.meta.url), 'utf8'));
// This is a narrow independent fixture-body comparison, not a public parser or
// migration API. These retained declarations contain no semicolons in literals.
function expectedWrapper(text) {
  const bindings = [];
  while (text.startsWith('DATA ')) {
    const match = /^DATA ([a-z_]+) = ([^;]+);\s*/.exec(text);
    assert.ok(match, 'unexpected retained declaration: ' + text);
    bindings.push(`${match[1]} AS (${match[2]})`);
    text = text.slice(match[0].length);
  }
  assert.ok(bindings.length);
  return 'WITH ' + bindings.join(', ') + ' ' + text;
}
for (const [name, previous] of Object.entries(retained.snapshots)) {
  test('WITH expansion preserves complete independent ' + name + ' inventory', async () => {
    const current = await import(new URL('./fixtures/' + name + '-source-input.mjs', import.meta.url));
    // JSON encoding only omits optional undefined fixture metadata; no values
    // are normalized and the full JSON Program text stays byte-identical.
    const actual = JSON.parse(JSON.stringify(current));
    assert.deepEqual(Object.keys(actual), Object.keys(previous));
    for (const key of Object.keys(previous)) {
      if (!Array.isArray(previous[key])) {
        assert.deepEqual(actual[key], previous[key]);
        continue;
      }
      assert.deepEqual(actual[key].map(({text, ...item}) => item), previous[key].map(({text, ...item}) => item));
      for (let index = 0; index < previous[key].length; index++) {
        const before = previous[key][index];
        const after = actual[key][index];
        assert.equal(after.text, /^DATA /.test(before.text ?? '') ? expectedWrapper(before.text) : before.text);
        assert.doesNotMatch(after.text ?? '', /\bDATA\b/);
      }
    }
  });
}
