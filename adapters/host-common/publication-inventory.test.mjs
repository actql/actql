import assert from 'node:assert/strict';
import test from 'node:test';
import {canonicalCid} from './run-publication-contracts.mjs';
import {
  prepareCheckedPublicationInventory,
} from './publication-inventory.mjs';

const programDefinitionCid = `sha256:${'1'.repeat(64)}`;

test('checked aliases become distinct immutable Result definitions', () => {
  const checked = [
    {name: 'first', task: 1},
    {name: 'second', task: 1},
  ];
  const prepared = prepareCheckedPublicationInventory(
    programDefinitionCid,
    checked,
  );
  checked[0].name = 'changed';
  checked.push({name: 'third', task: 2});
  assert.deepEqual(prepared.requestInventory, [
    {
      result_name: 'first',
      result_definition_cid: canonicalCid({
        version: 'actql-result-definition/0.1',
        program_definition_cid: programDefinitionCid,
        result_name: 'first',
      }),
    },
    {
      result_name: 'second',
      result_definition_cid: canonicalCid({
        version: 'actql-result-definition/0.1',
        program_definition_cid: programDefinitionCid,
        result_name: 'second',
      }),
    },
  ]);
  assert.deepEqual(prepared.occurrences.map(value => ({
    name: value.name,
    task: value.task,
  })), [
    {name: 'first', task: 1},
    {name: 'second', task: 1},
  ]);
  assert(Object.isFrozen(prepared));
  assert(Object.isFrozen(prepared.occurrences));
  assert(prepared.occurrences.every(Object.isFrozen));
  assert(prepared.occurrences.every(value =>
    Object.isFrozen(value.definition)));
  assert(Object.isFrozen(prepared.requestInventory));
  assert(prepared.requestInventory.every(Object.isFrozen));
});

test('acquisition Result occurrence remains task zero', () => {
  const prepared = prepareCheckedPublicationInventory(
    programDefinitionCid,
    [{name: 'acquired', task: 0}],
  );
  assert.equal(prepared.occurrences[0].task, 0);
  assert.equal(prepared.occurrences[0].definition.result_name, 'acquired');
});

test('unchecked subsets and malformed identities cannot form inventory', () => {
  for (const [program, results] of [
    ['not-a-cid', [{name: 'r', task: 1}]],
    [programDefinitionCid, []],
    [programDefinitionCid, [{name: '', task: 1}]],
    [programDefinitionCid, [{name: 'r', task: -1}]],
    [programDefinitionCid, [{name: 'r', task: 1}, {name: 'r', task: 2}]],
  ]) {
    assert.throws(
      () => prepareCheckedPublicationInventory(program, results),
      {code: 'InvalidCheckedPublicationInventory'},
    );
  }
});
