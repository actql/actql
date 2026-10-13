import test from 'node:test';
import assert from 'node:assert/strict';
import {completionRecordLimits, snapshotCompletionDescriptor, snapshotCompletionTask} from './completion-record.mjs';

const cid = `sha256:${'1'.repeat(64)}`;
const limits = () => ({maxCompletions: 2, maxInputs: 2, maxColumns: 10});
const descriptor = () => ({registry_cid: cid, values_contract_cid: cid, rows_cid: cid,
  output_step: 1, input_count: 1, columns: 1, rows: 1, bytes: 10, nodes: 4, depth: 3,
  values: {nodes: 2, text_bytes: 2, work: 4}});
const task = () => ({task: 1, output_step: 1,
  program_definition_cid: cid, program_parameters_cid: cid,
  unit_definition_cid: cid, unit_parameters_cid: cid, unit_contracts_cid: cid,
  inputs: [{input: 0, producer: 0, producer_target_is_input: false, producer_target_index: 1}],
  controls: [0]});

test('completion limit intake refuses frozen accessors without invoking them', () => {
  let calls = 0;
  const input = {...limits(), get maxColumns() { return ++calls === 1 ? 1 : 2_147_483_648; }};
  Object.freeze(input);
  assert.throws(() => completionRecordLimits(input), /InvalidCompletionRecordLimits/);
  assert.equal(calls, 0);
});

test('completion limit intake requires individual own keys, not joined spelling', () => {
  const input = Object.create(limits());
  input['maxColumns,maxCompletions,maxInputs'] = true;
  assert.throws(() => completionRecordLimits(input), /InvalidCompletionRecordLimits/);
});

test('completion descriptor intake refuses nested accessor data before use', () => {
  let calls = 0;
  const input = descriptor();
  Object.defineProperty(input.values, 'nodes', {enumerable: true,
    get() { calls++; return 2; }});
  assert.throws(() => snapshotCompletionDescriptor(input, limits()), /InvalidCompletionDescriptor/);
  assert.equal(calls, 0);
});

test('completion task intake never invokes a task or input accessor', () => {
  for (const atInput of [false, true]) {
    let calls = 0;
    const input = task();
    Object.defineProperty(atInput ? input.inputs[0] : input, atInput ? 'input' : 'task',
      {enumerable: true, get() { calls++; return atInput ? 0 : 1; }});
    assert.throws(() => snapshotCompletionTask(input, limits()), /InvalidCompletionTask/);
    assert.equal(calls, 0);
  }
});

test('completion task intake refuses holes, accessor elements and extra array properties', () => {
  for (const field of ['inputs', 'controls']) {
    for (const kind of ['hole', 'accessor', 'extra']) {
      let calls = 0;
      const input = task();
      if (kind === 'hole') delete input[field][0];
      else if (kind === 'accessor') Object.defineProperty(input[field], '0',
        {enumerable: true, get() { calls++; return field === 'inputs' ? task().inputs[0] : 0; }});
      else input[field].extra = true;
      assert.throws(() => snapshotCompletionTask(input, limits()), /InvalidCompletionTask/);
      assert.equal(calls, 0);
    }
  }
});

test('completion DATA snapshots preserve valid plain and null-prototype metadata', () => {
  const input = Object.assign(Object.create(null), descriptor());
  const kept = snapshotCompletionDescriptor(input, completionRecordLimits(limits()));
  input.values.nodes = 999;
  input.columns = 999;
  assert.equal(kept.values.nodes, 2);
  assert.equal(kept.columns, 1);
  assert(Object.isFrozen(kept) && Object.isFrozen(kept.values));
  const expected = task();
  const preserved = snapshotCompletionTask(expected, limits());
  expected.inputs[0].producer_target_index = 99;
  expected.controls[0] = 99;
  assert.equal(preserved.inputs[0].producer_target_index, 1);
  assert.deepEqual(preserved.controls, [0]);
  assert(Object.isFrozen(preserved.inputs[0]) && Object.isFrozen(preserved.controls));
});

test('completion DATA intake refuses hidden and symbolic own metadata', () => {
  for (const symbol of [false, true]) {
    const input = limits();
    Object.defineProperty(input, symbol ? Symbol('extra') : 'extra', {value: true});
    assert.throws(() => completionRecordLimits(input), /InvalidCompletionRecordLimits/);
  }
});

test('completion DATA uses each inspected descriptor once rather than rereading original properties', () => {
  const reads = new Map();
  const input = new Proxy(limits(), {
    get() { assert.fail('Original property reread'); },
    getOwnPropertyDescriptor(target, key) {
      reads.set(key, (reads.get(key) ?? 0) + 1);
      return Reflect.getOwnPropertyDescriptor(target, key);
    },
  });
  assert.deepEqual(completionRecordLimits(input), limits());
  assert.deepEqual([...reads.values()], [1, 1, 1]);
  // Reflection on this trusted fixture executes traps; it is not a sandbox.
});

test('completion DATA numeric and source-port limits remain enforced', () => {
  assert.throws(() => completionRecordLimits({...limits(), maxColumns: 2_147_483_648}), /InvalidCompletionRecordLimits/);
  assert.throws(() => completionRecordLimits({...limits(), maxCompletions: 0}), /InvalidCompletionRecordLimits/);
  assert.throws(() => snapshotCompletionDescriptor({...descriptor(), columns: 11}, limits()), /InvalidCompletionDescriptor/);
  assert.throws(() => snapshotCompletionTask({...task(), inputs: [task().inputs[0], task().inputs[0]]}, limits()), /InvalidCompletionTask/);
});
