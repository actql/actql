import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { checkGenerated, generateTests, validateVectors, verifyKernel } from './check-json-encoding.mjs';

const read = path => JSON.parse(readFileSync(new URL('../' + path, import.meta.url), 'utf8'));
const corpus = () => read('portability/corpus/json-encoding.json');

test('kernel body resolves the existing contract pin without self-field exclusions', () => {
  const body = read('spec/dependencies/aoa-kernel-laws.json');
  const contract = read('spec/contracts/actql-aoa.json');
  verifyKernel(body, contract);
  body.laws.reverse();
  assert.throws(() => verifyKernel(body, contract), /kernel manifest CID/);
});

test('vector validation rejects missing sets, malformed inputs and duplicate identities', () => {
  for (const mutate of [
    c => { c.numbers = []; },
    c => { delete c.strings; },
    c => { c.version = 'wrong'; },
    c => { c.numbers[0].bits = '0'; },
    c => { c.strings[0].units = [65536]; },
    c => { c.numbers.push(c.numbers[0]); },
  ]) {
    const c = corpus();
    mutate(c);
    assert.throws(() => validateVectors(c));
  }
});

test('fixed expectations cannot silently follow changed encoder output', () => {
  for (const mutate of [
    c => { c.numbers.find(x => x.json === '1').json = '1.0'; },
    c => { c.numbers.find(x => x.error).error = 'InvalidUnicode'; },
    c => { c.strings.find(x => x.id === 'lone-high').json = '"\\ud800"'; },
    c => { delete c.strings.find(x => x.id === 'lone-low').error; },
  ]) {
    const c = corpus();
    mutate(c);
    assert.throws(() => generateTests(c));
  }
});

test('generated tests are deterministic and stale or missing content is rejected', () => {
  const expected = generateTests(corpus());
  assert.equal(generateTests(corpus()), expected);
  assert.match(expected, /assert_eq\(finish\(exact\), "1"\)/);
  checkGenerated(expected, expected);
  assert.throws(() => checkGenerated('', expected));
  assert.throws(() => checkGenerated(expected.replace('"1"', '"1.0"'), expected));
});
