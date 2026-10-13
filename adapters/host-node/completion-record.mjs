// Private local-process metadata, not ActQL wire or an admission constructor.
// Deliberately fixed and bounded: no rows, schemas, paths or arbitrary payloads.
const quantity = value => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647;
// Inspect DATA once and validate/use that same snapshot. These private records
// contain no capability handles. Reflection can execute Proxy traps: installed
// same-process implementation code remains trusted, not sandboxed by this API.
function snapshotDataRecord(value, keys, issue) {
  const fail = () => { throw new TypeError(issue); };
  if (value == null || typeof value !== 'object' || Array.isArray(value)) fail();
  const names = Reflect.ownKeys(value);
  if (names.length !== keys.length || names.some(name => !keys.includes(name))) fail();
  const entries = keys.map(key => {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (descriptor?.enumerable !== true || !Object.hasOwn(descriptor, 'value')) fail();
    return [key, descriptor.value];
  });
  return Object.freeze(Object.fromEntries(entries));
}

function snapshotDataArray(value, maximum, issue) {
  const fail = () => { throw new TypeError(issue); };
  if (!Array.isArray(value)) fail();
  const length = Object.getOwnPropertyDescriptor(value, 'length')?.value;
  if (!quantity(length) || length > maximum) fail();
  const names = Reflect.ownKeys(value);
  if (names.length !== length + 1 || names.some(name => name !== 'length' &&
      (typeof name !== 'string' || !/^(0|[1-9][0-9]*)$/.test(name) || Number(name) >= length))) fail();
  const snapshot = [];
  for (let index = 0; index < length; index++) {
    const descriptor = Object.getOwnPropertyDescriptor(value, String(index));
    if (descriptor?.enumerable !== true || !Object.hasOwn(descriptor, 'value')) fail();
    snapshot.push(descriptor.value);
  }
  return Object.freeze(snapshot);
}
const descriptorCounts = ['output_step', 'input_count', 'columns', 'rows', 'bytes', 'nodes', 'depth'];
const identities = ['registry_cid', 'values_contract_cid', 'rows_cid'];
const valueCounts = ['nodes', 'text_bytes', 'work'];
const taskIdentities = ['program_definition_cid', 'program_parameters_cid',
  'unit_definition_cid', 'unit_parameters_cid', 'unit_contracts_cid'];

export function completionRecordLimits(value) {
  const keys = ['maxCompletions', 'maxInputs', 'maxColumns'];
  value = snapshotDataRecord(value, keys, 'InvalidCompletionRecordLimits');
  if (keys.some(key => !quantity(value[key])) || value.maxCompletions === 0) {
    throw new TypeError('InvalidCompletionRecordLimits');
  }
  return Object.freeze(Object.fromEntries(keys.map(key => [key, value[key]])));
}

export function snapshotCompletionDescriptor(value, limits) {
  limits = completionRecordLimits(limits);
  value = snapshotDataRecord(value, [...descriptorCounts, ...identities, 'values'], 'InvalidCompletionDescriptor');
  const values = snapshotDataRecord(value.values, valueCounts, 'InvalidCompletionDescriptor');
  if (descriptorCounts.some(key => !quantity(value[key])) ||
      identities.some(key => typeof value[key] !== 'string' || !/^sha256:[a-f0-9]{64}$/.test(value[key])) ||
      valueCounts.some(key => !quantity(values[key])) ||
      value.input_count > limits.maxInputs || value.columns > limits.maxColumns) {
    throw new TypeError('InvalidCompletionDescriptor');
  }
  return Object.freeze({
    ...Object.fromEntries([...descriptorCounts, ...identities].map(key => [key, value[key]])),
    values,
  });
}

export function snapshotCompletionTask(value, limits) {
  limits = completionRecordLimits(limits);
  value = snapshotDataRecord(value, [...taskIdentities, 'task', 'output_step', 'inputs', 'controls'], 'InvalidCompletionTask');
  const inputData = snapshotDataArray(value.inputs, limits.maxInputs, 'InvalidCompletionTask');
  const controlData = snapshotDataArray(value.controls, limits.maxCompletions, 'InvalidCompletionTask');
  if (taskIdentities.some(key => typeof value[key] !== 'string' || !/^sha256:[a-f0-9]{64}$/.test(value[key])) ||
      !quantity(value.task) || value.task === 0 || !quantity(value.output_step)) {
    throw new TypeError('InvalidCompletionTask');
  }
  const ports = new Set();
  const inputs = inputData.map(input => {
    const keys = ['input', 'producer', 'producer_target_is_input', 'producer_target_index'];
    input = snapshotDataRecord(input, keys, 'InvalidCompletionTask');
    if (!quantity(input.input) || input.input >= inputData.length ||
        ports.has(input.input) || !quantity(input.producer) || input.producer >= value.task ||
        typeof input.producer_target_is_input !== 'boolean' || !quantity(input.producer_target_index)) {
      throw new TypeError('InvalidCompletionTask');
    }
    ports.add(input.input);
    return Object.freeze(Object.fromEntries(keys.map(key => [key, input[key]])));
  });
  const controls = controlData.map(task => {
    if (!quantity(task) || task >= value.task) throw new TypeError('InvalidCompletionTask');
    return task;
  });
  return Object.freeze({...Object.fromEntries(taskIdentities.map(key => [key, value[key]])),
    task: value.task, output_step: value.output_step, inputs: Object.freeze(inputs), controls: Object.freeze(controls)});
}
