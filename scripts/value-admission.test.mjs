import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { generate } from './check-value-admission.mjs';

const read = () => JSON.parse(readFileSync('portability/corpus/value-admission.json', 'utf8'));

test('value-admission generation is deterministic and preserves explicit null', () => {
  assert.equal(generate(read()), generate(read()));
  assert.match(generate(read()), /owned\(parsed\("null"\)\)/);
});

test('value-admission vectors reject incomplete or ambiguous expectations', () => {
  for (const mutate of [
    c => { c.version = 'wrong'; },
    c => { c.cases = []; },
    c => { c.cases.push(c.cases[0]); },
    c => { delete c.cases[0].value; },
    c => { c.cases[0].expected = 'maybe'; },
    c => { c.cases[0].coefficient = '1'; },
    c => { c.cases.find(v => v.coefficient).coefficient = '-0'; },
  ]) {
    const c = read(); mutate(c);
    assert.throws(() => generate(c));
  }
});
