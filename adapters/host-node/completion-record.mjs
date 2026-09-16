// Private local-process metadata, not ActQL wire or an admission constructor.
// Deliberately fixed and bounded: no rows, schemas, paths or arbitrary payloads.
const quantity = value => Number.isSafeInteger(value) && value >= 0 && value <= 2147483647;
const exactKeys = (value, keys) => value != null && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join(',') === [...keys].sort().join(',');
const descriptorCounts = ['output_step', 'input_count', 'columns', 'rows', 'bytes', 'nodes', 'depth'];
const identities = ['registry_cid', 'values_contract_cid', 'rows_cid'];
const valueCounts = ['nodes', 'text_bytes', 'work'];
const taskIdentities = ['program_definition_cid', 'program_parameters_cid',
  'unit_definition_cid', 'unit_parameters_cid', 'unit_contracts_cid'];

export function completionRecordLimits(value) {
  const keys = ['maxCompletions', 'maxInputs', 'maxColumns'];
  if (!exactKeys(value, keys) || keys.some(key => !quantity(value[key])) || value.maxCompletions === 0) {
    throw new TypeError('InvalidCompletionRecordLimits');
  }
  return Object.freeze(Object.fromEntries(keys.map(key => [key, value[key]])));
}

export function snapshotCompletionDescriptor(value, limits) {
  if (!exactKeys(value, [...descriptorCounts, ...identities, 'values']) ||
      descriptorCounts.some(key => !quantity(value[key])) ||
      identities.some(key => typeof value[key] !== 'string' || !/^sha256:[a-f0-9]{64}$/.test(value[key])) ||
      !exactKeys(value.values, valueCounts) || valueCounts.some(key => !quantity(value.values[key])) ||
      value.input_count > limits.maxInputs || value.columns > limits.maxColumns) {
    throw new TypeError('InvalidCompletionDescriptor');
  }
  return Object.freeze({
    ...Object.fromEntries([...descriptorCounts, ...identities].map(key => [key, value[key]])),
    values: Object.freeze(Object.fromEntries(valueCounts.map(key => [key, value.values[key]]))),
  });
}

export function snapshotCompletionTask(value, limits) {
  if (!exactKeys(value, [...taskIdentities, 'task', 'output_step', 'inputs', 'controls']) ||
      taskIdentities.some(key => typeof value[key] !== 'string' || !/^sha256:[a-f0-9]{64}$/.test(value[key])) ||
      !quantity(value.task) || value.task === 0 || !quantity(value.output_step) ||
      !Array.isArray(value.inputs) || value.inputs.length > limits.maxInputs ||
      !Array.isArray(value.controls) || value.controls.length > limits.maxCompletions) {
    throw new TypeError('InvalidCompletionTask');
  }
  const ports = new Set();
  const inputs = value.inputs.map(input => {
    const keys = ['input', 'producer', 'producer_target_is_input', 'producer_target_index'];
    if (!exactKeys(input, keys) || !quantity(input.input) || input.input >= value.inputs.length ||
        ports.has(input.input) || !quantity(input.producer) || input.producer >= value.task ||
        typeof input.producer_target_is_input !== 'boolean' || !quantity(input.producer_target_index)) {
      throw new TypeError('InvalidCompletionTask');
    }
    ports.add(input.input);
    return Object.freeze(Object.fromEntries(keys.map(key => [key, input[key]])));
  });
  const controls = value.controls.map(task => {
    if (!quantity(task) || task >= value.task) throw new TypeError('InvalidCompletionTask');
    return task;
  });
  return Object.freeze({...Object.fromEntries(taskIdentities.map(key => [key, value[key]])),
    task: value.task, output_step: value.output_step, inputs: Object.freeze(inputs), controls: Object.freeze(controls)});
}
