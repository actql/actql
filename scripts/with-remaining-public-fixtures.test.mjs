import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
const retained = JSON.parse(readFileSync(new URL('../reviews/2026-10-11-with-carrier-cutover/with-remaining-public-original-inventory.json', import.meta.url), 'utf8'));
// Only these frozen fixtures are compared. This is not a public compatibility
// parser or runtime migrator. Their declaration bodies have no semicolon values.
function expectedWrapper(text) {
  const bindings = [];
  while (text.startsWith('DATA ')) {
    const match = /^DATA (`[^`]+`|[a-z_]+) = ([^;]+);\s*/.exec(text);
    assert.ok(match, 'unexpected retained authored declaration');
    const body = match[2].replace(/^PROPERTY GRAPH\b/, 'GRAPH');
    bindings.push(`${match[1]} AS (${body})`);
    text = text.slice(match[0].length);
  }
  return bindings.length ? 'WITH ' + bindings.join(' , ') + ' ' + text : text;
}
for (const [name, previous] of Object.entries(retained.snapshots)) {
  test('WITH remaining callers retain complete independent ' + name + ' inventory', async () => {
    const current = JSON.parse(JSON.stringify(await import(new URL('./fixtures/' + name + '-source-input.mjs', import.meta.url))));
    const expected = structuredClone(previous);
    function visit(value) {
      if (value === null || typeof value !== 'object') return;
      if (typeof value.text === 'string' && value.format !== 'json') value.text = expectedWrapper(value.text);
      for (const child of Object.values(value)) visit(child);
    }
    visit(expected);
    // Full comparison includes rows, ordered schema, refusal codes, parameter
    // declarations/values, limits, read counts and byte-identical JSON controls.
    assert.deepEqual(current, expected);
  });
}
