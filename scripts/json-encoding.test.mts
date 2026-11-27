import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { checkGenerated, generateTests, validateVectors, verifyKernel } from './check-json-encoding.mjs';

const read = <Value,>(path: string): Value => JSON.parse(readFileSync(new URL('../' + path, import.meta.url), 'utf8'));
type Corpus = Parameters<typeof validateVectors>[0];
const corpus = () => read<Required<Corpus>>('portability/corpus/json-encoding.json');

test('kernel body resolves the existing contract pin without self-field exclusions', () => {
  const body = read<Parameters<typeof verifyKernel>[0] & {laws: unknown[]}>('spec/dependencies/aoa-kernel-laws.json');
  const contract = read<Parameters<typeof verifyKernel>[1]>('spec/contracts/actql-aoa.json');
  verifyKernel(body, contract);
  body.laws.reverse();
  assert.throws(() => verifyKernel(body, contract), /kernel manifest CID/);
});

test('vector validation rejects missing sets, malformed inputs and duplicate identities', () => {
  const mutations: ((c: Required<Corpus>) => void)[] = [
    c => { c.numbers = []; },
    c => { delete (c as Corpus).strings; },
    c => { c.version = 'wrong'; },
    c => { const [number] = c.numbers; assert.ok(number); number.bits = '0'; },
    c => { const [string] = c.strings; assert.ok(string); string.units = [65536]; },
    c => { const [number] = c.numbers; assert.ok(number); c.numbers.push(number); },
  ];
  for (const mutate of mutations) {
    const c = corpus();
    mutate(c);
    assert.throws(() => validateVectors(c));
  }
});

test('fixed expectations cannot silently follow changed encoder output', () => {
  const mutations: ((c: Required<Corpus>) => void)[] = [
    c => { const vector = c.numbers.find(x => x.json === '1'); assert.ok(vector); vector.json = '1.0'; },
    c => { const vector = c.numbers.find(x => x.error); assert.ok(vector); vector.error = 'InvalidUnicode'; },
    c => { const vector = c.strings.find(x => x.id === 'lone-high'); assert.ok(vector); vector.json = '"\\ud800"'; },
    c => { const vector = c.strings.find(x => x.id === 'lone-low'); assert.ok(vector); delete vector.error; },
  ];
  for (const mutate of mutations) {
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
