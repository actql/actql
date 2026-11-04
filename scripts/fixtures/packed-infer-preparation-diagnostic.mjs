import {types as nodeTypes} from 'node:util';

// Preserve one existing Host admission event in the command's existing stderr
// evidence. These labels/tags are DATA, not an acceptance or failure verdict.
// Never serialize errors, opaque compiled values, getters or business inputs.
export function inferPreparationFailureData(detail) {
  const own = (record, key) => {
    if (record === null || typeof record !== 'object' || nodeTypes.isProxy(record)) return undefined;
    const field = Object.getOwnPropertyDescriptor(record, key);
    return field && Object.hasOwn(field, 'value') ? field.value : undefined;
  };
  const boundary = own(detail, 'boundary');
  if (!['original_model_compilation', 'model_execution', 'model_dependencies',
    'model_provider', 'model_dispatch', 'model_admission', 'task_compilation',
    'model_admission.original_startup', 'model_admission.compute_suffix',
    'model_admission.egress', 'model_admission.account', 'model_admission.plan_graph',
    'model_admission.provider_binding'].includes(boundary)) return undefined;
  const data = {boundary};
  for (const key of ['code', 'typedCause']) {
    const value = own(detail, key);
    if (typeof value === 'string' && /^[A-Za-z][A-Za-z0-9_.:-]{0,127}$/u.test(value)) data[key] = value;
  }
  const tag = own(own(detail, 'cause'), '$tag');
  if (Number.isSafeInteger(tag) && tag >= 0 && tag <= 65535) data.issueTag = tag;
  return Object.freeze(data);
}

