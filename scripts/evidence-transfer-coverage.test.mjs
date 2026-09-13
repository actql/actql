import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {test} from 'node:test';

const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const variants = read('src/relation_typing/types.mbt')
  .match(/enum Operation \{([^}]+)\}/)[1].trim().split(/\s+/);
const consumers = [
  ['keys', 'src/relation_evidence/collection_transfer.mbt', 'match @relation.operation(operation) {'],
  ['literal domains', 'src/relation_evidence/literal_domains.mbt', 'match @relation.operation(op) {'],
  ['completeness scopes', 'src/pipeline_typing/completeness.mbt', 'match @relation.operation(op) {'],
  ['ranking annotations', 'src/relation_evidence/ranking_transfer.mbt', 'match @relation.operation(op) {'],
  ['window roles', 'src/pipeline_typing/window.mbt', 'match @relation.operation(op) {'],
  ['input order', 'src/relation_typing/row_operations.mbt', 'pub fn preserves_input_order'],
];

// This is a coverage guard for these exhaustive unary dispatches, not a MoonBit
// parser or proof of the semantic correctness of an individual transfer rule.
function topLevelMatch(source, marker) {
  source = source.replace(/"(?:\\.|[^"\\])*"|\/\/[^\n]*/g, '');
  const start = source.indexOf(marker);
  assert.ok(start >= 0, 'Missing evidence dispatcher');
  const match = source.indexOf('match ', start);
  const open = source.indexOf('{', match);
  let depth = 1;
  let top = '';
  for (let i = open + 1; i < source.length; i++) {
    const c = source[i];
    if (c === '{') { depth++; continue; }
    if (c === '}') { if (--depth === 0) return top; continue; }
    if (depth === 1) top += c;
  }
  assert.fail('Unclosed evidence dispatcher');
}

function check(source, marker, names = variants) {
  const top = topLevelMatch(source, marker);
  assert.doesNotMatch(top, /\b_\s*=>/, 'Fallback hides unreviewed operations');
  for (const name of names) {
    assert.match(top, new RegExp(`\\b${name}\\b`), `Unclassified operation: ${name}`);
  }
}

for (const [kind, path, marker] of consumers) {
  test(`${kind} explicitly considers every checked unary operation`, () => {
    check(read(path), marker);
  });
  test(`${kind} coverage detects a new operation or a fallback regression`, () => {
    const source = read(path);
    assert.throws(() => check(source, marker, [...variants, 'FutureOperation']));
    const withoutAnalytic = source.replace(/\bAnalytic\b/g, 'Unreviewed');
    assert.throws(() => check(withoutAnalytic, marker));
    const fallback = source.replace(/\bAnalytic\b/g, '_');
    assert.throws(() => check(fallback, marker));
  });
}
