import assert from 'node:assert/strict';
import test from 'node:test';
import {
  prepareCheckedPublicationInventory,
} from './publication-inventory.mjs';

const programDefinitionCid = `sha256:${'1'.repeat(64)}`;
const resultDefinitionCids = Object.freeze({
  first: 'sha256:33cc81bf0c5e877d80d3dacf71d80fb8ef5472d6e224c83efac057853e67d966',
  second: 'sha256:e11eba03bcf3d0704ba0f54930d687a118b5a14875f160a46ccc189e142b2ae2',
  acquired: 'sha256:f4abdaa82822d682597d9b57a9954d89ed05b79940415695f7c52d23b5ec5853',
});
const definition = name => ({
  program_definition_cid: programDefinitionCid,
  result_definition_cid: resultDefinitionCids[name] ?? `sha256:${'a'.repeat(64)}`,
  result_name: name,
  version: 'actql-result-definition/0.1',
});

test('checked aliases become distinct immutable Result definitions', () => {
  const checked = [
    {name: 'first', task: 1, definition: definition('first')},
    {name: 'second', task: 1, definition: definition('second')},
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
      result_definition_cid: resultDefinitionCids.first,
    },
    {
      result_name: 'second',
      result_definition_cid: resultDefinitionCids.second,
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
    [{name: 'acquired', task: 0, definition: definition('acquired')}],
  );
  assert.equal(prepared.occurrences[0].task, 0);
  assert.equal(prepared.occurrences[0].definition.result_name, 'acquired');
});

test('unchecked subsets and malformed identities cannot form inventory', () => {
  for (const [program, results] of [
    ['not-a-cid', [{name: 'r', task: 1, definition: definition('r')}]],
    [programDefinitionCid, []],
    [programDefinitionCid, [{name: '', task: 1, definition: definition('')}]],
    [programDefinitionCid, [{name: 'r', task: -1, definition: definition('r')}]],
    [programDefinitionCid, [
      {name: 'r', task: 1, definition: definition('r')},
      {name: 'r', task: 2, definition: definition('r')},
    ]],
  ]) {
    assert.throws(
      () => prepareCheckedPublicationInventory(program, results),
      {code: 'InvalidCheckedPublicationInventory'},
    );
  }
});
