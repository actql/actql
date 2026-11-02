import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {instrument, mutations} from './instrument.mjs';
import {applyMutation} from '../sites.mjs';

const path = 'src/execution_relation/producer_read_preparation.mbt';
const original = readFileSync(new URL('../../../' + path, import.meta.url), 'utf8');
const copy = mutations.find(entry => entry.name === 'handoff-copy-without-accounting');
assert.equal(copy.path, path);

test('the handoff copy observer replaces the complete original return without nesting statements in a record', () => {
  const mutated = applyMutation(original, copy);
  const healthy = instrument(path, original);
  const field = 'bound: cursor.bound,';
  assert.equal(healthy.split(field).length, 2);
  const expected = healthy.replace(field, `bound: ${copy.binding},`);
  assert.equal(instrument(path, mutated), expected);
  assert.equal(mutated.replace(copy.after, copy.before), original);
});

test('the handoff observer refuses changed and duplicated complete return anchors', () => {
  const mutated = applyMutation(original, copy);
  assert.throws(() => instrument(path, mutated.replace('schema: cursor.schema,', 'schema: foreign,')),
    /Ambiguous observation site/);
  assert.throws(() => instrument(path, mutated + '\n' + mutated), /Ambiguous observation site/);
});
