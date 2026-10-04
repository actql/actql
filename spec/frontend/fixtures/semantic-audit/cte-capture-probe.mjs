// Diagnostic reproducer, not a registered passing acceptance test.
// Expectations below come from the authored query and shared-source semantics.
import assert from 'node:assert/strict';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import test from 'node:test';

const root = new URL('../../../../', import.meta.url);
const {compileCapturedQueryJson} = await import(new URL(
  '_build/js/debug/build/query_program_test_bridge/query_program_test_bridge.js', root));
const {cases} = JSON.parse(await readFile(new URL('cases.json', import.meta.url), 'utf8'));
const fixture = cases.find(item => item.name === 'cte-join-shared-source');
const input = {carrier: 'relation', schema: {
  id: {type: 'number', nullable: false},
  amount: {type: 'number', nullable: true}}, primary_key: ['id']};
const wire = compileCapturedQueryJson(fixture.text, 'records', 'records',
  JSON.stringify(input), JSON.stringify(['id', 'amount']), 'fixture.cte_predicate_audit');
assert.notEqual(wire, '', 'the authored query must lower successfully');
const actual = JSON.parse(wire);
const evidence = new URL('_build/semantic-audit/', root);
await mkdir(evidence, {recursive: true});
await writeFile(new URL('cte-capture-observed-program.json', evidence),
  JSON.stringify(actual, null, 2) + '\n');

test('CTE WHERE stays on chosen while JOIN right input reads the shared whole Source', () => {
  const capture = actual.stages.find(stage => stage.id === 'capture');
  assert.ok(capture, 'one shared capture stage');
  // records on the right of CROSS JOIN still needs id=2. Hoisting id=1 to
  // the shared acquisition changes that consumer, even if acquisition is once.
  assert.deepEqual(capture.steps[0].filter, {literal: true});
  const chosen = actual.stages.find(stage => stage.id === 'aql_cte_0');
  assert.ok(chosen, 'chosen CTE stage');
  assert.ok(chosen.steps.some(step => JSON.stringify(step.filter)
    === JSON.stringify({eq: [{field: 'id'}, {literal: 1}]})),
  'chosen retains its independently authored equality predicate');
});
