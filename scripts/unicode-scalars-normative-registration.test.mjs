import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {normalizedParagraphs} from './actql-requirement-extraction.mjs';
test('Unicode scalar obligations each have one distinct explicit owned ID', () => {
  const source = readFileSync('docs/spec/language.md', 'utf8');
  const all = [...source.matchAll(/<!-- requirement-block: ([^\n]+) -->/gu)];
  const ids = [
    'scalar-expressions.google-unicode-signatures',
    'scalar-expressions.google-byte-length-value',
    'scalar-expressions.google-unicode-value',
    'scalar-expressions.google-chr-value',
    'scalar-expressions.google-unicode-demand-resources',
    'scalar-expressions.google-unicode-identity',
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
test('Unicode scalar EBNF registers four spellings with direct unary canonical bodies', () => {
  const source = readFileSync('spec/grammar/actql-expression-0.1.ebnf', 'utf8');
  const grammar = source.replace(/\(\*[\s\S]*?\*\)/gu, '');
  const names = /\bfunction_name\s*=([^;]+);/u.exec(grammar)?.[1];
  for (const name of ['byte_length', 'octet_length', 'unicode', 'chr'])
    assert.equal([...names.matchAll(new RegExp(`"${name}"`, 'gu'))].length, 1);
  assert.match(source, /direct unary expression body, never an argument array/u);
  const query = readFileSync('docs/spec/query-text.md', 'utf8');
  assert.match(query, /`BYTE_LENGTH\(value\)` and its `OCTET_LENGTH\(value\)` alias select the same unary/u);
  assert.match(query, /BYTES and distinct\nINT64 overloads remain coverage gaps/u);
});
