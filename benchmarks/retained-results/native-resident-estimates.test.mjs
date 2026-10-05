import assert from 'node:assert/strict';
import test from 'node:test';
import {nativeResidentEstimateArguments} from './native-resident-estimates.mjs';
const profile = () => ({preparationMilliseconds: '2', cleanupMilliseconds: '3',
  taskMilliseconds: ['4', '5', '6'], importMilliseconds: ['7', null, '8', null]});

test('bind each measured component; unmeasured producer stays unknown', () => {
  assert.deepEqual(nativeResidentEstimateArguments(profile(), 3), [
    '--resident-prepare-ms', '2', '--resident-cleanup-ms', '3',
    '--resident-task-ms', '4,5,6', '--resident-import-ms', '7,?,8,?',
  ]);
});

for (const [name, change] of [
  ['partial profile', value => {delete value.cleanupMilliseconds;}],
  ['capacity field in duration profile', value => {value.executionBytes = '1';}],
  ['wrong task count', value => {value.taskMilliseconds.pop();}],
  ['missing producer estimate slot', value => {value.importMilliseconds.pop();}],
  ['empty value as unknown', value => {value.importMilliseconds[1] = ''; }],
  ['overflow', value => {value.preparationMilliseconds = '2147483648';}],
  ['negative', value => {value.cleanupMilliseconds = '-1';}],
]) test(`reject ${name}`, () => {
  const value = profile(); change(value);
  assert.throws(() => nativeResidentEstimateArguments(value, 3));
});
