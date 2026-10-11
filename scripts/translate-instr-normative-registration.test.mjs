import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {normalizedParagraphs} from './actql-requirement-extraction.mjs';
test('TRANSLATE/INSTR obligations each have one distinct explicit owned ID', () => {
  const source = readFileSync('docs/spec/language.md', 'utf8');
  const all = [...source.matchAll(/<!-- requirement-block: ([^\n]+) -->/gu)];
  const ids = [
    'scalar-expressions.google-translate-instr-signatures',
    'scalar-expressions.google-translate-value',
    'scalar-expressions.google-instr-value',
    'scalar-expressions.google-instr-empty',
    'scalar-expressions.google-instr-number-domain',
    'scalar-expressions.google-translate-instr-typing',
    'scalar-expressions.google-translate-instr-demand-resources',
    'scalar-expressions.google-translate-instr-identity',
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
test('TRANSLATE/INSTR EBNF and query profile retain exact arities and omission', () => {
  const source = readFileSync('spec/grammar/actql-expression-0.1.ebnf', 'utf8');
  const grammar = source.replace(/\(\*[\s\S]*?\*\)/gu, '');
  const tokens = /\bfunction_name\s*=([^;]+);/u.exec(grammar)?.[1];
  for (const name of ['translate', 'instr']) {
    assert.equal([...tokens.matchAll(new RegExp(`"${name}"`, 'gu'))].length, 1);
  }
  assert.match(source, /translate takes exactly three STRING expressions/u);
  assert.match(source, /instr takes two to four expressions/u);
  assert.match(source, /remain omitted in canonical identity/u);
  const query = readFileSync('docs/spec/query-text.md', 'utf8');
  assert.match(query, /`TRANSLATE\(value, source, target\)` selects/u);
  assert.match(query, /`INSTR\(value, subvalue\[, position\[, occurrence\]\]\)` selects/u);
  assert.match(query, /without an INT64 or safe-integer cap/u);
  assert.match(query, /BYTES, collation, regex and implicit coercion are not added/u);
});
