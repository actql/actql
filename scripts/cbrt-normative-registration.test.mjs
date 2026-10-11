import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {normalizedParagraphs} from './actql-requirement-extraction.mjs';
test('CBRT obligations each have one distinct explicit owned ID', () => {
  const source = readFileSync('docs/spec/language.md', 'utf8');
  const all = [...source.matchAll(/<!-- requirement-block: ([^\n]+) -->/gu)];
  const ids = [
    'scalar-expressions.google-cbrt-signature',
    'scalar-expressions.google-cbrt-value',
    'scalar-expressions.google-cbrt-algorithm',
    'scalar-expressions.google-cbrt-typing',
    'scalar-expressions.google-cbrt-demand-resources',
    'scalar-expressions.google-cbrt-identity',
  ];
  const marks = all.filter(mark => ids.includes(mark[1]));
  assert.deepEqual(marks.map(mark => mark[1]), ids);
  const allIds = all.flatMap(mark => mark[1].split(' '));
  for (const mark of marks) {
    const next = all[all.indexOf(mark) + 1]?.index ?? source.length;
    const entries = normalizedParagraphs(source.slice(mark.index + mark[0].length, next));
    assert.equal(entries.length, 1, mark[1]);
    assert.equal(entries[0].keyword, 'MUST');
    assert.equal(allIds.filter(id => id === mark[1]).length, 1);
  }
});
test('CBRT EBNF registers its exact spelling and direct unary canonical body', () => {
  const source = readFileSync('spec/grammar/actql-expression-0.1.ebnf', 'utf8');
  const grammar = source.replace(/\(\*[\s\S]*?\*\)/gu, '');
  const names = /\bfunction_name\s*=([^;]+);/u.exec(grammar)?.[1];
  assert.equal([...names.matchAll(/"cbrt"/gu)].length, 1);
  assert.match(source, /cbrt takes exactly one finite NUMBER expression in a direct unary canonical/u);
  const query = readFileSync('docs/spec/query-text.md', 'utf8');
  assert.match(query, /`CBRT\(value\)` selects the direct unary `cbrt`/u);
  assert.match(query, /No implicit conversion/u);
  assert.match(query, /non-finite overload or SAFE prefix/u);
});
