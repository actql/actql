import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {adaptBaselineSmallJoin} from './baseline-small-join.mjs';

test('small join adaptation changes capacities without changing topology or algorithms', () => {
  const read = name => readFileSync(new URL(name, import.meta.url), 'utf8');
  const host = read('./baseline-host-limits.mbt.txt');
  const generation = read('./baseline-generation.mbt.txt');
  const result = adaptBaselineSmallJoin(host, generation);
  const numeric = text => text.replace(/\d+/g, '#');
  assert.equal(numeric(result.host), numeric(host));
  assert.equal(numeric(result.generation), numeric(generation));
  assert.equal(result.generation.slice(0, result.generation.indexOf('fn generate(')),
    generation.slice(0, generation.indexOf('fn generate(')));
  assert(result.host.includes('max_received_rows: 204'));
  assert(result.host.includes('max_rows: 204'));
  assert(result.host.includes('join_validation: { max_rows: 200'));
  assert(result.generation.includes('max_input_rows: 200L'));
  assert.deepEqual(result.compute, {rows: 600, cells: 1000, inputRows: 200});
  assert.throws(() => adaptBaselineSmallJoin(host + ' ', generation), /UnrecognizedBaseline/);
  assert.throws(() => adaptBaselineSmallJoin(host, generation + ' '), /UnrecognizedBaseline/);
});
