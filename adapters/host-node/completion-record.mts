// Private local-process metadata, not ActQL wire or an admission constructor.
// Deliberately fixed and bounded: no rows, schemas, paths or arbitrary payloads.
const quantity = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) >= 0 && (value as number) <= 2147483647;
// Inspect DATA once and validate/use that same snapshot. These private records
// contain no capability handles. Reflection can execute Proxy traps: installed
// same-process implementation code remains trusted, not sandboxed by this API.
function snapshotDataRecord(value: unknown, keys: readonly string[], issue: string): DataRecord {
  const fail: () => never = () => { throw new TypeError(issue); };
  if (value == null || typeof value !== 'object' || Array.isArray(value)) fail();
  const names = Reflect.ownKeys(value);
  if (names.length !== keys.length || names.some(name => !keys.includes(name as string))) fail();
  const entries = keys.map(key => {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (descriptor?.enumerable !== true || !Object.hasOwn(descriptor, 'value')) fail();
    return [key, descriptor.value as unknown];
  });
  return Object.freeze(Object.fromEntries(entries));
}

function snapshotDataArray(value: unknown, maximum: number, issue: string): readonly unknown[] {
  const fail: () => never = () => { throw new TypeError(issue); };
  if (!Array.isArray(value)) fail();
  const length: unknown = Object.getOwnPropertyDescriptor(value, 'length')?.value;
  if (!quantity(length) || length > maximum) fail();
  const names = Reflect.ownKeys(value);
  if (names.length !== length + 1 || names.some(name => name !== 'length' &&
      (typeof name !== 'string' || !/^(0|[1-9][0-9]*)$/.test(name) || Number(name) >= length))) fail();
  const snapshot: unknown[] = [];
  for (let index = 0; index < length; index++) {
    const descriptor = Object.getOwnPropertyDescriptor(value, String(index));
    if (descriptor?.enumerable !== true || !Object.hasOwn(descriptor, 'value')) fail();
    snapshot.push(descriptor.value);
  }
  return Object.freeze(snapshot);
}
const descriptorCounts = ['output_step', 'input_count', 'columns', 'rows', 'bytes', 'nodes', 'depth'] as const;
const identities = ['registry_cid', 'values_contract_cid', 'rows_cid'] as const;
const valueCounts = ['nodes', 'text_bytes', 'work'] as const;
const taskIdentities = ['program_definition_cid', 'program_parameters_cid',
  'unit_definition_cid', 'unit_parameters_cid', 'unit_contracts_cid'] as const;

// These are validated private DATA snapshots, not nominal evidence/current
// authority. Key families derive from the existing closed field inventories.
type DataRecord = Readonly<Record<string, unknown>>;
type CompletionLimits = ReturnType<typeof completionRecordLimits>;
type DescriptorSnapshot = Readonly<Record<(typeof descriptorCounts)[number], number> &
  Record<(typeof identities)[number], string> & {values: Readonly<Record<(typeof valueCounts)[number], number>>}>;
export interface InputSnapshot {readonly input: number; readonly producer: number;
  readonly producer_target_is_input: boolean; readonly producer_target_index: number}
type TaskSnapshot = Readonly<Record<(typeof taskIdentities)[number], string> & {
  task: number; output_step: number; inputs: readonly InputSnapshot[]; controls: readonly number[];
}>;

export function completionRecordLimits(value: unknown) {
  const keys = ['maxCompletions', 'maxInputs', 'maxColumns'] as const;
  value = snapshotDataRecord(value, keys, 'InvalidCompletionRecordLimits');
  if (keys.some(key => !quantity((value as DataRecord)[key])) || (value as DataRecord).maxCompletions === 0) {
    throw new TypeError('InvalidCompletionRecordLimits');
  }
  return Object.freeze(Object.fromEntries(keys.map(key => [key, (value as DataRecord)[key]]))) as Readonly<Record<(typeof keys)[number], number>>;
}

export function snapshotCompletionDescriptor(value: unknown, limits: unknown): DescriptorSnapshot {
  limits = completionRecordLimits(limits);
  value = snapshotDataRecord(value, [...descriptorCounts, ...identities, 'values'], 'InvalidCompletionDescriptor');
  const values = snapshotDataRecord((value as DataRecord).values, valueCounts, 'InvalidCompletionDescriptor');
  if (descriptorCounts.some(key => !quantity((value as DataRecord)[key])) ||
      identities.some(key => typeof (value as DataRecord)[key] !== 'string' || !/^sha256:[a-f0-9]{64}$/.test((value as DataRecord)[key] as string)) ||
      valueCounts.some(key => !quantity(values[key])) ||
      (value as DescriptorSnapshot).input_count > (limits as CompletionLimits).maxInputs || (value as DescriptorSnapshot).columns > (limits as CompletionLimits).maxColumns) {
    throw new TypeError('InvalidCompletionDescriptor');
  }
  return Object.freeze({
    ...Object.fromEntries([...descriptorCounts, ...identities].map(key => [key, (value as DataRecord)[key]])),
    values,
  }) as DescriptorSnapshot;
}

export function snapshotCompletionTask(value: unknown, limits: unknown): TaskSnapshot {
  limits = completionRecordLimits(limits);
  value = snapshotDataRecord(value, [...taskIdentities, 'task', 'output_step', 'inputs', 'controls'], 'InvalidCompletionTask');
  const inputData = snapshotDataArray((value as DataRecord).inputs, (limits as CompletionLimits).maxInputs, 'InvalidCompletionTask');
  const controlData = snapshotDataArray((value as DataRecord).controls, (limits as CompletionLimits).maxCompletions, 'InvalidCompletionTask');
  if (taskIdentities.some(key => typeof (value as DataRecord)[key] !== 'string' || !/^sha256:[a-f0-9]{64}$/.test((value as DataRecord)[key] as string)) ||
      !quantity((value as TaskSnapshot).task) || (value as TaskSnapshot).task === 0 || !quantity((value as TaskSnapshot).output_step)) {
    throw new TypeError('InvalidCompletionTask');
  }
  const ports = new Set();
  const inputs = inputData.map(input => {
    const keys = ['input', 'producer', 'producer_target_is_input', 'producer_target_index'];
    input = snapshotDataRecord(input, keys, 'InvalidCompletionTask');
    if (!quantity((input as InputSnapshot).input) || (input as InputSnapshot).input >= inputData.length ||
        ports.has((input as InputSnapshot).input) || !quantity((input as InputSnapshot).producer) || (input as InputSnapshot).producer >= (value as TaskSnapshot).task ||
        typeof (input as InputSnapshot).producer_target_is_input !== 'boolean' || !quantity((input as InputSnapshot).producer_target_index)) {
      throw new TypeError('InvalidCompletionTask');
    }
    ports.add((input as InputSnapshot).input);
    return Object.freeze(Object.fromEntries(keys.map(key => [key, (input as DataRecord)[key]]))) as unknown as InputSnapshot;
  });
  const controls = controlData.map(task => {
    if (!quantity(task) || task >= (value as TaskSnapshot).task) throw new TypeError('InvalidCompletionTask');
    return task;
  });
  return Object.freeze({...Object.fromEntries(taskIdentities.map(key => [key, (value as DataRecord)[key]])),
    task: (value as TaskSnapshot).task, output_step: (value as TaskSnapshot).output_step, inputs: Object.freeze(inputs), controls: Object.freeze(controls)}) as TaskSnapshot;
}
