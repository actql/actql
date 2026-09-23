import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const corpus = JSON.parse(readFileSync(
  new URL('../portability/corpus/event-window-boundaries.json', import.meta.url),
  'utf8',
));

function decimalRatio(text) {
  const negative = text.startsWith('-');
  const digits = negative ? text.slice(1) : text;
  const [whole, fraction = ''] = digits.split('.');
  const denominator = 10n ** BigInt(fraction.length);
  const numerator = BigInt(whole) * denominator + BigInt(fraction || '0');
  return [negative ? -numerator : numerator, denominator];
}

function floorDiv(numerator, denominator) {
  const quotient = numerator / denominator;
  return numerator % denominator < 0n ? quotient - 1n : quotient;
}

function exactlyBinary64(value) {
  const encoded = Number(value);
  return Number.isFinite(encoded) && BigInt(encoded) === value;
}

test('independent event window vectors separate membership from encoding', () => {
  assert.equal(corpus.version, 'actql-event-window-boundary-vectors/0.1');
  for (const vector of corpus.cases) {
    const [time, denominator] = decimalRatio(vector.time);
    const size = BigInt(vector.size);
    const step = BigInt(vector.step);
    const offset = BigInt(vector.offset);
    let start = offset + step * floorDiv(
      time - offset * denominator, step * denominator,
    );
    const starts = [];
    const ends = [];
    let issue;
    for (let polls = 0; polls < 100; polls++) {
      const end = start + size;
      if (!(start * denominator <= time && time < end * denominator)) break;
      if (!exactlyBinary64(start) || !exactlyBinary64(end)) {
        issue = 'EventWindowArithmetic';
        break;
      }
      starts.unshift(start.toString());
      ends.unshift(end.toString());
      if (vector.kind === 'fixed') break;
      start -= step;
    }
    assert.equal(issue, vector.issue, vector.id);
    if (issue === undefined) {
      assert.deepEqual(starts, vector.starts, vector.id);
      assert.deepEqual(ends, vector.ends, vector.id);
    }
  }
});
