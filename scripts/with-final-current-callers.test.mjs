import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
const previous = JSON.parse(readFileSync(new URL('../reviews/2026-10-11-with-carrier-cutover/with-final-current-callers-original.json', import.meta.url)));
// Frozen authored examples only, not a product compatibility parser.
function wrapper(text) {
  let output = '', first = true;
  while (text.startsWith('DATA ')) {
    const match = /^DATA ([a-z_]+) = ([\s\S]*?);(\s*)/.exec(text);
    assert.ok(match);
    output += (first ? 'WITH ' : ', ') + match[1] + ' AS ('
      + match[2].replace(/^PROPERTY GRAPH\b/, 'GRAPH') + ')' + match[3];
    text = text.slice(match[0].length); first = false;
  }
  return output + text;
}
for (const [name, original] of Object.entries(previous.snapshots)) {
  test('WITH final caller retains complete independent ' + name + ' contract', async () => {
    const expected = structuredClone(original);
    function visit(value) {
      if (!value || typeof value !== 'object') return;
      if (typeof value.text === 'string' && value.format !== 'json') value.text = wrapper(value.text);
      for (const child of Object.values(value)) visit(child);
    }
    visit(expected);
    if (name === 'graph-delta-json-source') expected.graphDeltaJsonSource = wrapper(expected.graphDeltaJsonSource);
    const module = await import('./fixtures/' + name + '.mjs');
    const actual = name === 'nearest-public-input'
      ? await module.nearestPublicInputFixtures('spec/frontend/fixtures/nearest-keep')
      : JSON.parse(JSON.stringify(module));
    assert.deepEqual(actual, expected);
  });
}
for (const file of ['two-source-without-effect.aql', 'two-source-with-effect.aql.template']) {
  test('WITH optional Effect preserves complete original terminal body ' + file, () => {
    const path = 'scripts/fixtures/' + file;
    assert.equal(readFileSync(new URL('./fixtures/' + file, import.meta.url), 'utf8'), wrapper(previous.originals[path].source));
  });
}
test('WITH Python ABI fixture changes only the binding wrapper', () => {
  const path = 'scripts/fixtures/python-local-preparation-abi.py';
  const expected = previous.originals[path].source.replace('DATA seed = SELECT 1 AS n;', 'WITH seed AS (SELECT 1 AS n)');
  assert.equal(readFileSync(new URL('./fixtures/python-local-preparation-abi.py', import.meta.url), 'utf8'), expected);
});
test('WITH Graph snapshot keeps original oracle and consumer assertions', () => {
  const path = 'scripts/graph-source-snapshot.test.mjs';
  const original = previous.originals[path].source;
  const source = /const source = `\n([\s\S]*?)`;/u.exec(original)[1];
  const expected = original.replace(source, wrapper(source));
  assert.equal(readFileSync(new URL('./graph-source-snapshot.test.mjs', import.meta.url), 'utf8'), expected);
});
