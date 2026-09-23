import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const corpus = JSON.parse(readFileSync(
  new URL('../portability/corpus/structural-pairwise-mean.json', import.meta.url),
  'utf8',
));

// Every finite binary64 value is an integer multiple of 2^-1075. The mean
// numerator is therefore exact before comparison with adjacent encodings.
function units(hex) {
  const bits = BigInt(`0x${hex}`);
  const exponent = Number((bits >> 52n) & 0x7ffn);
  const fraction = bits & 0x000fffffffffffffn;
  if (exponent === 0x7ff) return null;
  const magnitude = exponent === 0
    ? fraction << 1n
    : ((1n << 52n) | fraction) << BigInt(exponent);
  return (bits & 0x8000000000000000n) === 0n ? magnitude : -magnitude;
}

function distance(meanNumerator, candidateBits) {
  const candidate = units(candidateBits.toString(16).padStart(16, '0'));
  if (candidate === null) return null;
  const difference = meanNumerator - 2n * candidate;
  return difference < 0n ? -difference : difference;
}

test('independent structural pairwise mean vectors are nearest-even', () => {
  assert.equal(corpus.version, 'actql-structural-pairwise-mean-vectors/0.1');
  for (const vector of corpus.cases) {
    const left = units(vector.left);
    const right = units(vector.right);
    if (left === null || right === null) {
      assert.equal(vector.issue, 'NonFinite', vector.id);
      continue;
    }
    assert.equal(vector.issue, undefined, vector.id);
    const expectedBits = BigInt(`0x${vector.expected}`);
    assert.ok(expectedBits <= 0x7fefffffffffffffn, vector.id);
    const numerator = left + right;
    const selected = distance(numerator, expectedBits);
    const neighbors = expectedBits === 0n
      ? [0x8000000000000001n, 1n]
      : [expectedBits - 1n, expectedBits + 1n];
    for (const neighbor of neighbors) {
      const rival = distance(numerator, neighbor);
      if (rival === null) continue;
      assert.ok(selected <= rival, vector.id);
      if (selected === rival) {
        assert.equal(expectedBits & 1n, 0n, vector.id);
      }
    }
  }
});
