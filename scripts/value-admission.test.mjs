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

test('checked-only enum extents use the explicit checked contract reader without widening author grammar',()=>{
  const corpus=read();
  const checked=corpus.cases.filter(value=>value.contract_mode==='checked');
  assert.deepEqual(checked.map(value=>value.id),[
    'text-enum-extent-intersection','text-enum-unicode-astral','text-enum-unicode-astral-byte-bound']);
  assert.ok(checked.every(value=>Object.hasOwn(value.contract,'max_codepoints')||Object.hasOwn(value.contract,'max_utf8_bytes')));
  const generated=generate({...corpus,cases:checked});
  assert.equal((generated.match(/@contract\.read_checked/g)??[]).length,checked.length);
  assert.equal(generated.includes('let c = contract('),false);
  for(const mode of [null,undefined,'either']){
    const invalid=structuredClone(corpus);invalid.cases[0].contract_mode=mode;
    assert.throws(()=>generate(invalid),/explicit contract reader mode/);
  }
  const legacy=structuredClone(corpus);legacy.cases=legacy.cases.filter(value=>!value.id.startsWith('text-enum-'));
  assert.equal(generate(legacy).includes('@contract.read_checked'),false,'absence retains original author route');
});

test('exact Timestamp corpus retains fixed wire hashes and compares original admitted peers',()=>{
  const cases=read().cases.filter(value=>value.id.startsWith('timestamp-precision-'));
  assert.ok(cases.length>=18);
  const accepted=cases.filter(value=>value.expected==='accepted');
  assert.ok(accepted.some(value=>value.value.endsWith('.123Z')),'old millisecond bytes');
  assert.ok(accepted.some(value=>value.value.endsWith('.218404Z')),'microseconds');
  assert.ok(accepted.some(value=>value.value.endsWith('.123000001Z')),'nanosecond neighbor');
  const output=generate({...read(),cases});
  assert.match(output,/@value_admission\.emit_checked_wire_value/);
  assert.match(output,/@value_admission\.compare_key_values/);
  assert.match(output,/@identity\.cid_value/);
  for(const mutate of [
    c=>{c.cases.find(value=>value.expected_wire).expected_wire+=' ';},
    c=>{c.cases.find(value=>value.expected_wire_cid).expected_wire_cid='sha256:'+'0'.repeat(64);},
    c=>{c.cases.find(value=>Object.hasOwn(value,'peer')).expected_order=2;},
    c=>{c.cases.find(value=>Object.hasOwn(value,'peer')).peer=1;},
    c=>{c.cases.find(value=>value.expected_wire).expected='InvalidTimestamp';},
  ]){
    const invalid=structuredClone(read());mutate(invalid);
    assert.throws(()=>generate(invalid));
  }
});
