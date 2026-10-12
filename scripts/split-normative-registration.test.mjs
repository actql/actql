import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {normalizedParagraphs} from './actql-requirement-extraction.mjs';

// These authored IDs are checked against extraction without rewriting any
// registry, requirement status, machine pin or historical identity.
test('SPLIT normative obligations each have one distinct explicit owned ID', () => {
  const source = readFileSync('docs/spec/language.md', 'utf8');
  const all = [...source.matchAll(/<!-- requirement-block: ([^\n]+) -->/gu)];
  const marks = all.filter(mark => mark[1].startsWith('scalar-expressions.google-split-'));
  assert.deepEqual(marks.map(mark => mark[1]), [
    'scalar-expressions.google-split-signature',
    'scalar-expressions.google-split-value',
    'scalar-expressions.google-split-type-bounds',
    'scalar-expressions.google-split-eager-children',
    'scalar-expressions.google-split-identity',
    'scalar-expressions.google-split-admission',
  ]);
  const allIds = all.flatMap(mark => mark[1].split(' '));
  for (const mark of marks) {
    const next = all[all.indexOf(mark) + 1]?.index ?? source.length;
    const entries = normalizedParagraphs(source.slice(mark.index + mark[0].length, next));
    assert.equal(entries.length, 1, mark[1]);
    assert.equal(entries[0].keyword, 'MUST');
    assert.equal(allIds.filter(id => id === mark[1]).length, 1);
  }
});

test('common SPLIT spelling admits an ordinary optional String delimiter', () => {
  const source = readFileSync('spec/grammar/actql-expression-0.1.ebnf', 'utf8');
  const grammar = source.replace(/\(\*[\s\S]*?\*\)/gu, '');
  const names = /\bfunction_name\s*=([^;]+);/u.exec(grammar)?.[1];
  assert.equal([...names.matchAll(/"split"/gu)].length, 1);
  assert.match(source, /optional delimiter\s+is an ordinary expression, not restricted to a literal or parameter/u);
  assert.match(source, /one-element array\s+for omission/u);
  const query = readFileSync('docs/spec/query-text.md', 'utf8');
  assert.match(query, /`SPLIT\(value\[, delimiter\]\)` selects the common `split`/u);
  assert.match(query, /does not require a literal-valued argument/u);
});
