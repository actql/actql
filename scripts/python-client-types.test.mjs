import assert from 'node:assert/strict';
import {test} from 'node:test';
import {pythonTypes} from './generate-python-client-wire.mjs';

test('nested DTOs cannot redefine a canonical root DTO', () => {
  const runRef = {type:'object',properties:{runDefinitionCid:{type:'string'}},
    required:['runDefinitionCid']};
  const cancelRef = {type:'object',properties:{cancelId:{type:'string'}},
    required:['cancelId']};
  const output = pythonTypes({cancellation:{type:'object',
    properties:{ref:runRef,cancelRef:cancelRef},required:['ref','cancelRef']},
    cancellation_ref:cancelRef});
  assert.equal(output.match(/^CancellationRef = /gm)?.length, 1);
  assert.match(output, /^CancellationRefField = TypedDict\("CancellationRefField", \{"runDefinitionCid":/m);
  assert.match(output, /^CancellationRef = TypedDict\("CancellationRef", \{"cancelId":/m);
  assert.match(output, /"ref": Required\["CancellationRefField"\]/);
});

test('nested DTO names remain distinct from reserved roots and other paths', () => {
  const leaf = {type:'object',properties:{value:{type:'string'}},required:['value']};
  const output = pythonTypes({item:{type:'object',properties:{a:leaf,A:leaf}},
    item_a:leaf,item_a_field:leaf});
  const names = [...output.matchAll(/^(\w+) = /gm)].map(match => match[1]);
  assert.equal(new Set(names).size, names.length);
  assert.match(output, /^ItemAField2 = /m);
  assert.match(output, /^ItemAField3 = /m);
  assert.throws(() => pythonTypes({item_a:leaf,'item-a':leaf}), /ConflictingPythonRootTypes/);
});
