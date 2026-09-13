import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';

const read = p => JSON.parse(readFileSync(p, 'utf8'));
const corpus = read('portability/corpus/window-capacity.json');
// Independent finite interval enumeration; no compiler or lowerer output.
function count(c) {
  const stride = c.kind === 'fixed' ? c.size : c.step;
  let n = 0;
  for (const time of c.times) {
    for (let start = Math.floor((time - c.size) / stride) * stride; start <= time; start += stride) {
      if (start <= time && time < start + c.size) n++;
    }
  }
  return n;
}
test('window output scopes count memberships and keep unknown inputs separate', () => {
  for (const c of corpus.cases) {
    const factor = c.kind === 'fixed' ? 1n : (BigInt(c.size) + BigInt(c.step) - 1n) / BigInt(c.step);
    const program = c.input_bound === null ? null : BigInt(c.input_bound) * factor;
    const host = BigInt(c.carrier === 'relation' ? c.relation_host : c.events_host);
    const max = program === null || host < program ? host : program;
    assert.equal(Number(factor), c.factor, c.name);
    assert.equal(program === null ? null : Number(program), c.program_bound, c.name);
    assert.equal(Number(max), c.maximum, c.name);
    assert.equal(count(c), c.memberships, c.name);
    assert.equal(BigInt(count(c)) <= max, c.accepted, c.name);
  }
});
test('window consumers select existing row-unit Host laws without changing policy wire', () => {
  const c = read('spec/contracts/actql-capacity-host-policy.json');
  assert.deepEqual(c.host_witness_laws.max_relation_output_rows, {unit:'rows',law_id:'actql.host.relation-output'});
  assert.deepEqual(c.host_witness_laws.max_temporal_output_rows, {unit:'rows',law_id:'actql.host.temporal-output'});
  for (const field of ['max_relation_output_rows','max_temporal_output_rows']) assert(c.schema.required.includes(field));
});
