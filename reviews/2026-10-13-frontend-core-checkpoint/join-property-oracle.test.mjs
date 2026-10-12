import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';

const record = JSON.parse(readFileSync(new URL('./join-property-original-controls.json', import.meta.url)));
const hash = text => createHash('sha256').update(text).digest('hex');
const literals = (source, name) => {
  const start = source.indexOf(`fn ${name}(`);
  assert.ok(start >= 0);
  return source.slice(start, source.indexOf('\n}\n', start)).split('\n')
    .map(line => line.trim()).filter(line => line.startsWith('#|')).map(line => line.slice(2));
};
const testStrings = source => [...source.slice(source.indexOf('test "')).split('\n')
  .filter(line => !line.trim().startsWith('#|') && !line.trim().startsWith('//')).join('\n')
  .matchAll(/"(?:\\.|[^"\\])*"/g)].map(match => match[0]);

for (const control of record.controls) {
  test(`${control.file}: keep typed nullable receivers and complete operator bodies`, () => {
    const source = readFileSync(control.file, 'utf8');
    const old = literals(source, control.oldHelper);
    const current = literals(source, control.currentHelper);
    assert.equal(old.length, 1);
    assert.equal(current.length, 1);
    assert.equal(hash(old[0]), control.originalLiteralSha256);
    const strings = testStrings(source);
    assert.equal(strings.length, control.testStringsCount);
    assert.equal(hash(strings.join('\n')), control.testStringsSha256);
    const expected = JSON.parse(old[0]);
    const main = expected.stages.at(-1);
    const mapping = new Map();
    const seeds = expected.stages.slice(0, -1).map((stage, index) => {
      assert.equal(stage.steps.length, 1);
      assert.ok(stage.steps[0].values);
      const name = `aql_script_seed_${2 + index}`;
      for (const [input, port] of Object.entries(main.inputs)) {
        if (port.result.stage === stage.id) mapping.set(input, name);
      }
      return {values: stage.steps[0].values, as: name};
    });
    assert.equal(seeds.length, 2);
    if (control.profile === 'chain') {
      mapping.set('aql_chain_join_2', 'aql_chain_join_4');
      mapping.set('aql_chain_result_3', 'aql_chain_result_5');
    } else {
      const roles = ['prefiltered', 'output', 'raw', 'filtered', 'derived',
        'order_derived', 'unique', 'sorted', 'taken', 'visible', 'result', 'merged'];
      roles.forEach((role, index) => mapping.set(`aql_join_${role}`, `aql_join_${role}_${4 + index}`));
    }
    for (const step of main.steps) {
      for (const key of ['as', 'from']) {
        if (mapping.has(step[key])) step[key] = mapping.get(step[key]);
      }
      if (step.join) {
        assert.ok(mapping.has(step.join.with));
        step.join.with = mapping.get(step.join.with);
      }
    }
    for (const result of Object.values(main.results)) result.from = mapping.get(result.from) ?? result.from;
    main.inputs = {};
    main.steps = [...seeds, ...main.steps];
    expected.stages = [main];
    assert.deepEqual(JSON.parse(current[0]), expected);
  });
}

test('ORDER assertions preserve every original source and semantic check', () => {
  const source = readFileSync('src/query_program/join_order_test.mbt', 'utf8');
  const strings = testStrings(source);
  const updated = strings.filter(value => value === '"\\"aql_join_visible_13\\""');
  assert.equal(updated.length, 2);
  const original = strings.map(value => value === '"\\"aql_join_visible_13\\""'
    ? '"\\"aql_join_visible\\""' : value);
  assert.equal(hash(original.join('\n')), record.originalOrderStringsSha256);
  assert.equal(original.length, record.originalOrderStringsCount);
});
