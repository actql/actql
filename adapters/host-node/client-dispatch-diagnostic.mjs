// Inert diagnostics of the existing dispatch Owner and SAME Journal frame.
// No product module is re-executed, error chain followed, input checked,
// execution state changed or cleanup/current authority issued here.
export function dispatchFailureSnapshot(error) {
  if (error === undefined) return undefined;
  const text = name => {
    try {
      const field = Object.getOwnPropertyDescriptor(error, name);
      return field !== undefined && Object.hasOwn(field, 'value') &&
        typeof field.value === 'string' ? field.value : undefined;
    } catch { return undefined; }
  };
  let primaryDiagnostic;
  try {
    let field = Object.getOwnPropertyDescriptor(error, 'primaryDiagnostic');
    if (field === undefined) {
      const primary = Object.getOwnPropertyDescriptor(error, 'primaryFailure');
      if (primary !== undefined && Object.hasOwn(primary, 'value') && primary.value !== error) {
        field = Object.getOwnPropertyDescriptor(primary.value, 'primaryDiagnostic');
      }
    }
    if (field !== undefined && Object.hasOwn(field, 'value')) {
      const data = {};
      let validOrdinals = true;
      for (const key of ['code', 'phase', 'kind', 'task', 'unit', 'step']) {
        const member = Object.getOwnPropertyDescriptor(field.value, key);
        if (member !== undefined && Object.hasOwn(member, 'value')) data[key] = member.value;
        if ((key === 'task' || key === 'unit' || key === 'step') &&
            (!Number.isSafeInteger(data[key]) || data[key] < 0 || data[key] > 2147483647)) {
          validOrdinals = false;
        }
      }
      const workLimit = Object.getOwnPropertyDescriptor(field.value, 'controlWorkLimit');
      const localWork = data.phase === 'local_managed_advance' && data.kind === 'control_work' &&
        Number.isSafeInteger(data.task) && data.task >= 0 && data.task <= 2147483647 &&
        !Object.hasOwn(field.value, 'unit') && !Object.hasOwn(field.value, 'step') &&
        workLimit !== undefined && Object.hasOwn(workLimit, 'value') &&
        Number.isSafeInteger(workLimit.value) && workLimit.value >= 0 && workLimit.value <= 2147483647;
      const valueLimit = Object.getOwnPropertyDescriptor(field.value, 'workLimit');
      const valueWork = data.phase === 'local_managed_advance' && data.kind === 'value_capture_work' &&
        Number.isSafeInteger(data.task) && data.task >= 0 && data.task <= 2147483647 &&
        Number.isSafeInteger(data.step) && data.step >= 0 && data.step <= 2147483647 &&
        !Object.hasOwn(field.value, 'unit') && !Object.hasOwn(field.value, 'controlWorkLimit') &&
        valueLimit !== undefined && Object.hasOwn(valueLimit, 'value') &&
        Number.isSafeInteger(valueLimit.value) && valueLimit.value >= 0 && valueLimit.value <= 2147483647;
      const setting = Object.getOwnPropertyDescriptor(field.value, 'setting');
      const logicalWork = data.phase === 'local_managed_advance' && data.kind === 'logical_work' &&
        Number.isSafeInteger(data.task) && data.task >= 0 && data.task <= 2147483647 &&
        Number.isSafeInteger(data.step) && data.step >= 0 && data.step <= 2147483647 &&
        !Object.hasOwn(field.value, 'unit') && !Object.hasOwn(field.value, 'controlWorkLimit') &&
        !Object.hasOwn(field.value, 'dimension') && !Object.hasOwn(field.value, 'budget') &&
        valueLimit !== undefined && Object.hasOwn(valueLimit, 'value') &&
        typeof valueLimit.value === 'string' && /^(?:0|[1-9][0-9]{0,18})$/u.test(valueLimit.value) &&
        BigInt(valueLimit.value) <= 9223372036854775807n &&
        setting !== undefined && Object.hasOwn(setting, 'value') &&
        (setting.value === 'installation.sourceFreeMaxWork' || setting.value === 'unavailable');
      const dimension = Object.getOwnPropertyDescriptor(field.value, 'dimension');
      const resource = data.phase === 'local_managed_advance' && data.kind === 'resource' &&
        Number.isSafeInteger(data.task) && data.task >= 0 && data.task <= 2147483647 &&
        !Object.hasOwn(field.value, 'unit') && !Object.hasOwn(field.value, 'step') &&
        !Object.hasOwn(field.value, 'controlWorkLimit') && !Object.hasOwn(field.value, 'workLimit') &&
        dimension !== undefined && Object.hasOwn(dimension, 'value') &&
        (dimension.value === 'retained_bytes' || dimension.value === 'execution_bytes');
      const cause = Object.getOwnPropertyDescriptor(field.value, 'cause');
      const originalCause = data.phase === 'local_managed_advance' &&
        Number.isSafeInteger(data.task) && data.task >= 0 && data.task <= 2147483647 &&
        !Object.hasOwn(field.value, 'unit') && !Object.hasOwn(field.value, 'dimension') &&
        !Object.hasOwn(field.value, 'controlWorkLimit') && !Object.hasOwn(field.value, 'workLimit') &&
        !Object.hasOwn(field.value, 'budget') && cause && Object.hasOwn(cause, 'value') &&
        typeof cause.value === 'string' && cause.value.length <= 96 &&
        /^[a-z_]+(?:\.[a-z_]+)*$/u.test(cause.value);
      const rowFailure = originalCause && data.kind === 'row_failure' &&
        Number.isSafeInteger(data.step) && data.step >= 0 && data.step <= 2147483647;
      const localIssue = originalCause && data.kind === 'local_issue' &&
        !Object.hasOwn(field.value, 'step');
      if (data.code === 'MoonBitHostFailure' &&
          (['original_model_acquired_effect_evidence', 'original_effect_source_unit_result_export', 'original_effect_source_unit_artifact', 'original_infer_component'].includes(data.phase) &&
            validOrdinals || localWork || valueWork || logicalWork || resource || rowFailure || localIssue) &&
          typeof data.kind === 'string' && data.kind.length <= 96 &&
          /^[a-z_]+(?:\.[a-z_]+)*$/u.test(data.kind)) {
        if (localWork) data.controlWorkLimit = workLimit.value;
        if (valueWork) data.workLimit = valueLimit.value;
        if (logicalWork) { data.workLimit = valueLimit.value; data.setting = setting.value; }
        if (resource) data.dimension = dimension.value;
        if (rowFailure || localIssue) data.cause = cause.value;
        // Preserve only closed inert quantities supplied by that original
        // failed reserve/probe. A later ledger sample is not this failure.
        const budgetField = Object.getOwnPropertyDescriptor(field.value, 'budget');
        if ((resource || valueWork) && budgetField && Object.hasOwn(budgetField, 'value')) {
          const original = budgetField.value, selected = {};
          const keys = ['requested', 'remaining', 'policy', 'requestedIsLowerBound'];
          if (original != null && Object.keys(original).length === keys.length) {
            let valid = true;
            for (const key of keys) {
              const member = Object.getOwnPropertyDescriptor(original, key);
              if (!member || !Object.hasOwn(member, 'value')) { valid = false; break; }
              selected[key] = member.value;
            }
            if (valid && keys.slice(0, 3).every(key => typeof selected[key] === 'string' &&
                /^(?:0|[1-9][0-9]{0,18})$/u.test(selected[key]) && BigInt(selected[key]) <= 9223372036854775807n) &&
                BigInt(selected.requested) > BigInt(selected.remaining) &&
                BigInt(selected.remaining) <= BigInt(selected.policy) &&
                selected.requestedIsLowerBound === valueWork &&
                (!valueWork || selected.policy === String(data.workLimit))) {
              data.budget = Object.freeze(selected);
            }
          }
        }
        primaryDiagnostic = Object.freeze(data);
      }
    }
  } catch { /* Optional inert DATA cannot mask execution or cleanup. */ }
  let cleanupDiagnostic;
  try {
    const original = Object.getOwnPropertyDescriptor(error, 'primaryFailure');
    const field = Object.getOwnPropertyDescriptor(error, 'cleanupDiagnostic') ??
      (original !== undefined && Object.hasOwn(original, 'value') && original.value != null
        ? Object.getOwnPropertyDescriptor(original.value, 'cleanupDiagnostic') : undefined);
    if (field !== undefined && Object.hasOwn(field, 'value')) {
      const read = key => Object.getOwnPropertyDescriptor(field.value, key)?.value;
      const owner = read('owner'), phase = read('phase'), continuation = read('continuation');
      if (['local_managed', 'managed_operations'].includes(owner) &&
          ['close_additional', 'close_operations', 'await_stop', 'settle_operations', 'refresh_cleanup'].includes(phase) &&
          ['runnable', 'blocked', 'unavailable'].includes(continuation)) {
        cleanupDiagnostic = Object.freeze({owner, phase, continuation});
      }
    }
  } catch { /* Optional cleanup DATA does not observe or retry an owner. */ }
  return Object.freeze({name: text('name') ?? 'Error', code: text('code'),
    message: typeof error === 'string' ? error : text('message'),
    ...(primaryDiagnostic === undefined ? {} : {primaryDiagnostic}),
    ...(cleanupDiagnostic === undefined ? {} : {cleanupDiagnostic})});
}

export function publicBudgetFailureMessage(error) {
  const data = dispatchFailureSnapshot(error)?.primaryDiagnostic;
  if (data?.phase !== 'local_managed_advance') return undefined;
  if (data.kind === 'logical_work') {
    return `Budget exceeded: phase=${data.phase}; task=${data.task}; step=${data.step}; dimension=logical_work; requested_delta=unavailable; remaining=unavailable; policy=${data.workLimit}; unit=work_units; setting=${data.setting}. ` +
      'Runtime logical work; requested and remaining quantities were not retained.';
  }
  if (data.kind === 'row_failure') {
    return `Execution failed: phase=${data.phase}; task=${data.task}; step=${data.step}; cause=${data.cause}. ` +
      'Original execution failure; resource quantities were not retained.';
  }
  if (data.kind === 'local_issue') {
    return `Execution failed: phase=${data.phase}; task=${data.task}; cause=${data.cause}. ` +
      'Original execution failure; resource quantities were not retained.';
  }
  const memory = data.kind === 'resource';
  if (!memory && !['value_capture_work', 'control_work'].includes(data.kind)) return undefined;
  const dimension = memory ? data.dimension : data.kind;
  const setting = memory ? `installation.requestMemory.${dimension === 'retained_bytes' ? 'retainedBytes' : 'executionBytes'}`
    : 'installation.sourceFreeMaxWork';
  const unit = memory ? 'logical_bytes' : 'work_units';
  const budget = data.budget;
  const requested = budget === undefined ? 'unavailable'
    : `${budget.requestedIsLowerBound ? '>=' : ''}${budget.requested}`;
  const remaining = budget?.remaining ?? 'unavailable';
  const policy = budget?.policy ?? (memory ? 'unavailable' : String(data.workLimit ?? data.controlWorkLimit));
  return `Budget exceeded: phase=${data.phase}; dimension=${dimension}; requested_delta=${requested}; remaining=${remaining}; policy=${policy}; unit=${unit}; setting=${setting}. ` +
    (memory ? 'Logical quota, not process RSS.'
      : 'Runtime work, not Program parsing/checking. A lower bound does not give the complete UTF8 demand.');
}

export function retainedBudgetFailureMessage(key, state, runId, control) {
  if (typeof key !== 'string' || state.status !== 'failed' ||
      state.terminal_error?.code !== 'ACTQL_E_UNPUBLISHED_RUN' ||
      control.physical_stop !== 'confirmed') return undefined;
  let previous;
  try { previous = JSON.parse(key); } catch { return undefined; }
  if (previous?.run_id !== runId || previous.status !== 'failed' ||
      previous.result_available !== false || previous.next_action?.kind !== 'none' ||
      previous.terminal_error?.code !== 'ACTQL_E_UNPUBLISHED_RUN' ||
      previous.control === null || typeof previous.control !== 'object' ||
      Object.keys(previous.control).sort().join('\0') !== Object.keys(control).sort().join('\0') ||
      Object.keys(control).some(name => previous.control[name] !== control[name])) return undefined;
  const message = previous.terminal_error.message;
  if (typeof message !== 'string') return undefined;
  const cause = message.length <= 512 &&
    /^Execution failed: phase=local_managed_advance; task=(0|[1-9][0-9]{0,9}); (?:step=(0|[1-9][0-9]{0,9}); )?cause=([a-z_]+(?:\.[a-z_]+)*)\. Original execution failure; resource quantities were not retained\.$/u.exec(message);
  if (cause && Number(cause[1]) <= 2147483647 &&
      (cause[2] === undefined || Number(cause[2]) <= 2147483647) && cause[3].length <= 96) return message;
  const logical = /^Budget exceeded: phase=local_managed_advance; task=(0|[1-9][0-9]{0,9}); step=(0|[1-9][0-9]{0,9}); dimension=logical_work; requested_delta=unavailable; remaining=unavailable; policy=(0|[1-9][0-9]{0,18}); unit=work_units; setting=(?:installation\.sourceFreeMaxWork|unavailable)\. Runtime logical work; requested and remaining quantities were not retained\.$/u.exec(message);
  if (message.length <= 512 && logical && Number(logical[1]) <= 2147483647 &&
      Number(logical[2]) <= 2147483647 && BigInt(logical[3]) <= 9223372036854775807n) return message;
  const amount = '(?:0|[1-9][0-9]{0,18}|unavailable)';
  const prefix = 'Budget exceeded: phase=local_managed_advance; dimension=';
  const memory = new RegExp('^' + prefix + '(retained_bytes|execution_bytes); requested_delta=' + amount +
    '; remaining=' + amount + '; policy=' + amount + '; unit=logical_bytes; setting=installation\\.requestMemory\\.' +
    '(retainedBytes|executionBytes)\\. Logical quota, not process RSS\\.$', 'u').exec(message);
  if (memory && memory[2] === (memory[1] === 'retained_bytes' ? 'retainedBytes' : 'executionBytes')) return message;
  const work = new RegExp('^' + prefix + '(?:value_capture_work|control_work); requested_delta=(?:>=[1-9][0-9]{0,18}|unavailable)' +
    '; remaining=' + amount + '; policy=' + amount + '; unit=work_units; setting=installation\\.sourceFreeMaxWork\\. ' +
    'Runtime work, not Program parsing/checking\\. A lower bound does not give the complete UTF8 demand\\.$', 'u');
  return work.test(message) ? message : undefined;
}
