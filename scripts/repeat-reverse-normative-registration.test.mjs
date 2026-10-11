import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {normalizedParagraphs} from './actql-requirement-extraction.mjs';
test('REPEAT/REVERSE obligations each have one distinct explicit owned ID', () => {
  const source = readFileSync('docs/spec/language.md', 'utf8');
  const all = [...source.matchAll(/<!-- requirement-block: ([^\n]+) -->/gu)];
  const ids = [
    'scalar-expressions.google-repeat-reverse-signatures',
    'scalar-expressions.google-repeat-value',
    'scalar-expressions.google-reverse-value',
    'scalar-expressions.google-repeat-reverse-typing',
    'scalar-expressions.google-repeat-reverse-demand-resources',
    'scalar-expressions.google-repeat-reverse-identity',
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
test('REPEAT/REVERSE EBNF registers exact spellings with binary and unary canonical bodies', () => {
  const source = readFileSync('spec/grammar/actql-expression-0.1.ebnf', 'utf8');
  const grammar = source.replace(/\(\*[\s\S]*?\*\)/gu, '');
  const names = /\bfunction_name\s*=([^;]+);/u.exec(grammar)?.[1];
  for (const name of ['repeat', 'reverse'])
    assert.equal([...names.matchAll(new RegExp(`"${name}"`, 'gu'))].length, 1);
  assert.match(source, /ordered binary canonical array/u);
  assert.match(source, /direct unary canonical body/u);
  const query = readFileSync('docs/spec/query-text.md', 'utf8');
  assert.match(query, /`REPEAT\(value, count\)` selects the ordered binary/u);
  assert.match(query, /`REVERSE\(value\)` selects direct unary/u);
  assert.match(query, /BYTES and distinct INT64 remain coverage/u);
});
