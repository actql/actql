import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {normalizedParagraphs} from './actql-requirement-extraction.mjs';
test('direct trigonometric obligations each have one distinct explicit owned ID', () => {
  const source = readFileSync('docs/spec/language.md', 'utf8');
  const all = [...source.matchAll(/<!-- requirement-block: ([^\n]+) -->/gu)];
  const ids = [
    'scalar-expressions.google-direct-trig-signatures',
    'scalar-expressions.google-direct-trig-values',
    'scalar-expressions.google-direct-trig-domains',
    'scalar-expressions.google-direct-trig-atan2',
    'scalar-expressions.google-direct-trig-algorithms',
    'scalar-expressions.google-direct-trig-typing',
    'scalar-expressions.google-direct-trig-demand-resources',
    'scalar-expressions.google-direct-trig-identity',
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
test('direct trigonometric EBNF registers exact spellings and canonical arities', () => {
  const source = readFileSync('spec/grammar/actql-expression-0.1.ebnf', 'utf8');
  const grammar = source.replace(/\(\*[\s\S]*?\*\)/gu, '');
  const tokens = /\bfunction_name\s*=([^;]+);/u.exec(grammar)?.[1];
  for (const name of ['sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'atan2', 'sinh', 'cosh', 'tanh', 'asinh', 'acosh', 'atanh']) {
    assert.equal([...tokens.matchAll(new RegExp(`"${name}"`, 'gu'))].length, 1);
  }
  for (const name of ['cot', 'coth', 'csc', 'csch', 'sec', 'sech']) assert.ok(!tokens.includes(`"${name}"`));
  assert.match(source, /each take one finite NUMBER expression in a direct unary canonical body/u);
  assert.match(source, /atan2 takes exactly two finite NUMBER expressions in authored order/u);
  const query = readFileSync('docs/spec/query-text.md', 'utf8');
  assert.match(query, /`ATAN2\(first, second\)` selects the ordered binary `atan2`/u);
  assert.match(query, /ATANH\nrequires strict \(-1,1\)/u);
  assert.match(query, /No reciprocal functions, implicit conversions/u);
});
