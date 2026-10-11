import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {normalizedParagraphs} from './actql-requirement-extraction.mjs';

test('side/padding common EBNF declares function spellings without changing join fields', () => {
  const source = readFileSync('spec/grammar/actql-expression-0.1.ebnf', 'utf8');
  const grammar = source.replace(/\(\*[\s\S]*?\*\)/gu, '');
  const names = /\bfunction_name\s*=([^;]+);/u.exec(grammar)?.[1];
  assert.ok(names, 'common function-name production');
  for (const name of ['left', 'right', 'lpad', 'rpad']) {
    assert.equal([...names.matchAll(new RegExp(`"${name}"`, 'gu'))].length, 1);
  }
  assert.match(grammar, /join_field = \( "left" \| "right" \), "\.", identifier ;/u);
  assert.match(source, /Length[s]? count Unicode scalars/u);
});

test('each side/padding obligation has one distinct authored requirement ID', () => {
  const source = readFileSync('docs/spec/language.md', 'utf8');
  const mark = /<!-- requirement-block: (scalar-expressions\.google-side-slices-padding[^\n]*) -->/u.exec(source);
  assert.ok(mark);
  assert.deepEqual(mark[1].split(' '), [
    'scalar-expressions.google-side-slices-padding',
    'scalar-expressions.google-padding-length',
    'scalar-expressions.google-side-padding-eager-children',
    'scalar-expressions.google-side-padding-scalar-preservation',
    'scalar-expressions.google-side-padding-output-admission',
  ]);
  const rest = source.slice(mark.index + mark[0].length);
  const entries = normalizedParagraphs(rest.split('<!-- requirement-block:')[0]);
  assert.equal(entries.length, 5);
  for (const [index, expected] of [
    /`left\(value, length\)` and `right\(value, length\)` MUST/u,
    /`lpad\(value, length\[, pattern\]\)` and `rpad\(value, length\[, pattern\]\)` MUST/u,
    /Every supplied child MUST evaluate once/u,
    /MUST remain unchanged without normalization/u,
    /workspace MUST be admitted/u,
  ].entries()) assert.match(entries[index].text, expected);
  const allIds = [...source.matchAll(/<!-- requirement-block: ([^\n]+) -->/gu)]
    .flatMap(match => match[1].split(' '));
  for (const id of mark[1].split(' ')) assert.equal(allIds.filter(value => value === id).length, 1);
});
