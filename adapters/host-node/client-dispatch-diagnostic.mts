// Inert diagnostics of the existing dispatch Owner and SAME Journal frame.
// No product module is re-executed, error chain followed, input checked,
// execution state changed or cleanup/current authority issued here.
import {originalDispatchFailureSnapshot} from '../host-common/dispatch-failure-observation.mjs';
import {types as nodeTypes} from 'node:util';

type DescribeCause = (cause: string) => string | undefined;
type Diagnostic = Readonly<Record<string, unknown>>;
type Budget = Readonly<{requested: string; remaining: string; policy: string; requestedIsLowerBound: boolean}>;
type WorkOrResource = Readonly<{budget?: Budget; workLimit?: number; controlWorkLimit?: number}> &
  (Readonly<{kind: 'resource'; dimension: 'retained_bytes' | 'execution_bytes'}> |
   Readonly<{kind: 'control_work' | 'value_capture_work'}>);
type LocalDiagnostic = Readonly<{phase: 'local_managed_advance'; task: number}> &
  (WorkOrResource |
   Readonly<{kind: 'logical_work'; step: number; workLimit: string; setting: 'installation.sourceFreeMaxWork' | 'unavailable'}> |
   Readonly<{kind: 'row_failure'; cause: string; step: number}> |
   Readonly<{kind: 'local_issue'; cause: string}>);
type SerializationDiagnostic = Readonly<{phase: 'serialization_input'; kind: 'row_limit'}>;
type RunControl = Readonly<Record<string, unknown>>;
type JournalFailureState = Readonly<{
  status?: unknown;
  terminal_error?: Readonly<{code?: unknown; message?: unknown}> | null;
}>;
type PreviousJournalState = JournalFailureState & Readonly<{
  run_id?: unknown;
  result_available?: unknown;
  next_action?: Readonly<{kind?: unknown}>;
  control: RunControl;
}>;

// Resolve only the engine's own lazy Error stack. The managed cleanup wrapper
// retains its original failure in one inert own slot; prefer that original
// site without walking a cause chain or changing the cleanup owner. An
// observer receives locations, never the exception, message or capabilities.
export function dispatchFailureCodeSite(error: unknown, errorType: ErrorConstructor, formatter: unknown) {
  try {
    if (nodeTypes.isProxy(error) || !nodeTypes.isNativeError(error)) return undefined;
    const primary = Object.getOwnPropertyDescriptor(error as object, 'primaryFailure');
    if (primary !== undefined) {
      if (!Object.hasOwn(primary, 'value') || primary.value === error) return undefined;
      error = primary.value;
      if (nodeTypes.isProxy(error) || !nodeTypes.isNativeError(error)) return undefined;
    }
    if (Object.getPrototypeOf(error) !== errorType.prototype) return undefined;
    const currentFormatter = Object.getOwnPropertyDescriptor(errorType, 'prepareStackTrace');
    if (currentFormatter !== undefined && !Object.hasOwn(currentFormatter, 'value') ||
        currentFormatter?.value !== formatter) return undefined;
    const heading = {} as Record<'name' | 'message', string>;
    const code = Object.getOwnPropertyDescriptor(error as object, 'code');
    if (!code || !Object.hasOwn(code, 'value') || typeof code.value !== 'string' ||
        code.value.length < 1 || code.value.length > 96 ||
        !/^[A-Za-z][A-Za-z0-9_]*$/u.test(code.value)) return undefined;
    for (const key of ['name', 'message'] as const) {
      const own = Object.getOwnPropertyDescriptor(error as object, key);
      const inherited = Object.getOwnPropertyDescriptor(errorType.prototype, key);
      if (key === 'message' && own === undefined) return undefined;
      if (own !== undefined && (!Object.hasOwn(own, 'value') || typeof own.value !== 'string') ||
          inherited === undefined || !Object.hasOwn(inherited, 'value')) return undefined;
      heading[key] = own?.value ?? inherited.value;
    }
    // Only a bounded code used verbatim as its own inert message is a safe
    // heading. Arbitrary exception text is neither resolved nor copied.
    if (heading.name !== 'Error' || heading.message !== code.value) return undefined;
    const field = Object.getOwnPropertyDescriptor(error as object, 'stack');
    if (field === undefined) return undefined;
    let stack: unknown;
    if (Object.hasOwn(field, 'value')) stack = field.value;
    else {
      const native = Object.getOwnPropertyDescriptor(new errorType(), 'stack');
      if (typeof native?.get !== 'function' || field.get !== native.get || field.set !== native.set) return undefined;
      stack = native.get.call(error);
    }
    if (typeof stack !== 'string') return undefined;
    const header = (heading.name as string) === '' ? heading.message : heading.message === ''
      ? heading.name : `${heading.name}: ${heading.message}`;
    if (!stack.startsWith(`${header}\n`)) return undefined;
    const sites: string[] = [];
    for (const line of stack.slice(header.length + 1, header.length + 16385).split('\n').slice(0, 16)) {
      // Drop function names and absolute installation/state prefixes. These
      // are optional source locations, not artifact or provenance evidence.
      const site = /^\s+at [^\n]*\/((?:adapters|packages)\/[A-Za-z0-9_./-]+\.[cm]?js|_build\/js\/release\/build\/[A-Za-z0-9_./-]+\.js):([1-9][0-9]{0,8}):([1-9][0-9]{0,8})\)?$/u.exec(line);
      if (site !== null && !site[1].split('/').includes('..')) {
        sites.push(`${site[1]}:${site[2]}:${site[3]}`);
        if (sites.length === 8) break;
      }
    }
    if (sites.length !== 0) return Object.freeze({phase: 'dispatch', kind: 'code_site',
      message: sites.join('\n').slice(0, 2048)});
  } catch { /* Optional diagnostics cannot replace a failure or its cleanup. */ }
  return undefined;
}


export function dispatchFailureSnapshot(error: unknown) {
  if (error === undefined) return undefined;
  // Only the fixed runtime's actual Err path can populate this weak entry.
  // Do not accept a copied/adversarial primaryDiagnostic with these fields.
  const original = originalDispatchFailureSnapshot(error);
  let observed = original;
  try {
    const primary = Object.getOwnPropertyDescriptor(error as object, 'primaryFailure');
    if (primary !== undefined && Object.hasOwn(primary, 'value')) {
      const retained = originalDispatchFailureSnapshot(primary.value);
      if (retained !== undefined) observed = retained;
    }
  } catch { /* An optional observation cannot invoke a foreign accessor. */ }
  const text = (name: string) => {
    try {
      const field = Object.getOwnPropertyDescriptor(error as object, name);
      return field !== undefined && Object.hasOwn(field, 'value') &&
        typeof field.value === 'string' ? field.value : undefined;
    } catch { return undefined; }
  };
  let primaryDiagnostic: Diagnostic | undefined = observed?.primaryDiagnostic;
  try {
    if (primaryDiagnostic === undefined) {
      let field = Object.getOwnPropertyDescriptor(error as object, 'primaryDiagnostic');
      if (field === undefined) {
        const primary = Object.getOwnPropertyDescriptor(error as object, 'primaryFailure');
        if (primary !== undefined && Object.hasOwn(primary, 'value') && primary.value !== error) {
          field = Object.getOwnPropertyDescriptor(primary.value, 'primaryDiagnostic');
        }
      }
      if (field !== undefined && Object.hasOwn(field, 'value')) {
        const data: Record<string, unknown> = {};
        let validOrdinals = true;
        for (const key of ['code', 'phase', 'kind', 'task', 'unit', 'step']) {
          const member = Object.getOwnPropertyDescriptor(field.value, key);
          if (member !== undefined && Object.hasOwn(member, 'value')) data[key] = member.value;
          if ((key === 'task' || key === 'unit' || key === 'step') &&
              (!Number.isSafeInteger(data[key]) || (data[key] as number) < 0 || (data[key] as number) > 2147483647)) {
            validOrdinals = false;
          }
        }
        const workLimit = Object.getOwnPropertyDescriptor(field.value, 'controlWorkLimit');
        const localWork = data.phase === 'local_managed_advance' && data.kind === 'control_work' &&
          Number.isSafeInteger(data.task) && (data.task as number) >= 0 && (data.task as number) <= 2147483647 &&
          !Object.hasOwn(field.value, 'unit') && !Object.hasOwn(field.value, 'step') &&
          workLimit !== undefined && Object.hasOwn(workLimit, 'value') &&
          Number.isSafeInteger(workLimit.value) && workLimit.value >= 0 && workLimit.value <= 2147483647;
        const valueLimit = Object.getOwnPropertyDescriptor(field.value, 'workLimit');
        const valueWork = data.phase === 'local_managed_advance' && data.kind === 'value_capture_work' &&
          Number.isSafeInteger(data.task) && (data.task as number) >= 0 && (data.task as number) <= 2147483647 &&
          Number.isSafeInteger(data.step) && (data.step as number) >= 0 && (data.step as number) <= 2147483647 &&
          !Object.hasOwn(field.value, 'unit') && !Object.hasOwn(field.value, 'controlWorkLimit') &&
          valueLimit !== undefined && Object.hasOwn(valueLimit, 'value') &&
          Number.isSafeInteger(valueLimit.value) && valueLimit.value >= 0 && valueLimit.value <= 2147483647;
        const setting = Object.getOwnPropertyDescriptor(field.value, 'setting');
        const logicalWork = data.phase === 'local_managed_advance' && data.kind === 'logical_work' &&
          Number.isSafeInteger(data.task) && (data.task as number) >= 0 && (data.task as number) <= 2147483647 &&
          Number.isSafeInteger(data.step) && (data.step as number) >= 0 && (data.step as number) <= 2147483647 &&
          !Object.hasOwn(field.value, 'unit') && !Object.hasOwn(field.value, 'controlWorkLimit') &&
          !Object.hasOwn(field.value, 'dimension') && !Object.hasOwn(field.value, 'budget') &&
          valueLimit !== undefined && Object.hasOwn(valueLimit, 'value') &&
          typeof valueLimit.value === 'string' && /^(?:0|[1-9][0-9]{0,18})$/u.test(valueLimit.value) &&
          BigInt(valueLimit.value) <= 9223372036854775807n &&
          setting !== undefined && Object.hasOwn(setting, 'value') &&
          (setting.value === 'installation.sourceFreeMaxWork' || setting.value === 'unavailable');
        const dimension = Object.getOwnPropertyDescriptor(field.value, 'dimension');
        const resource = data.phase === 'local_managed_advance' && data.kind === 'resource' &&
          Number.isSafeInteger(data.task) && (data.task as number) >= 0 && (data.task as number) <= 2147483647 &&
          !Object.hasOwn(field.value, 'unit') && !Object.hasOwn(field.value, 'step') &&
          !Object.hasOwn(field.value, 'controlWorkLimit') && !Object.hasOwn(field.value, 'workLimit') &&
          dimension !== undefined && Object.hasOwn(dimension, 'value') &&
          (dimension.value === 'retained_bytes' || dimension.value === 'execution_bytes');
        const cause = Object.getOwnPropertyDescriptor(field.value, 'cause');
        const originalCause = data.phase === 'local_managed_advance' &&
          Number.isSafeInteger(data.task) && (data.task as number) >= 0 && (data.task as number) <= 2147483647 &&
          !Object.hasOwn(field.value, 'unit') && !Object.hasOwn(field.value, 'dimension') &&
          !Object.hasOwn(field.value, 'controlWorkLimit') && !Object.hasOwn(field.value, 'workLimit') &&
          !Object.hasOwn(field.value, 'budget') && cause && Object.hasOwn(cause, 'value') &&
          typeof cause.value === 'string' && cause.value.length <= 96 &&
          /^[a-z_]+(?:\.[a-z_]+)*$/u.test(cause.value);
        const rowFailure = originalCause && data.kind === 'row_failure' &&
          Number.isSafeInteger(data.step) && (data.step as number) >= 0 && (data.step as number) <= 2147483647;
        const localIssue = originalCause && data.kind === 'local_issue' &&
          !Object.hasOwn(field.value, 'step');
        if (data.code === 'MoonBitHostFailure' &&
            (['original_model_acquired_effect_evidence', 'original_effect_source_unit_result_export', 'original_effect_source_unit_artifact', 'original_infer_component'].includes(data.phase as string) &&
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
            const original: unknown = budgetField.value, selected: Record<string, unknown> = {};
            const keys = ['requested', 'remaining', 'policy', 'requestedIsLowerBound'];
            if (original != null && Object.keys(original as object).length === keys.length) {
              let valid = true;
              for (const key of keys) {
                const member = Object.getOwnPropertyDescriptor(original, key);
                if (!member || !Object.hasOwn(member, 'value')) { valid = false; break; }
                selected[key] = member.value;
              }
              if (valid && keys.slice(0, 3).every(key => typeof selected[key] === 'string' &&
                  /^(?:0|[1-9][0-9]{0,18})$/u.test(selected[key] as string) && BigInt(selected[key] as string) <= 9223372036854775807n) &&
                  BigInt(selected.requested as string) > BigInt(selected.remaining as string) &&
                  BigInt(selected.remaining as string) <= BigInt(selected.policy as string) &&
                  selected.requestedIsLowerBound === valueWork &&
                  (!valueWork || selected.policy === String(data.workLimit))) {
                data.budget = Object.freeze(selected);
              }
            }
          }
          primaryDiagnostic = Object.freeze(data);
        }
      }
    }
  } catch { /* Optional inert DATA cannot mask execution or cleanup. */ }
  let cleanupDiagnostic;
  try {
    const original = Object.getOwnPropertyDescriptor(error as object, 'primaryFailure');
    const field = Object.getOwnPropertyDescriptor(error as object, 'cleanupDiagnostic') ??
      (original !== undefined && Object.hasOwn(original, 'value') && original.value != null
        ? Object.getOwnPropertyDescriptor(original.value, 'cleanupDiagnostic') : undefined);
    if (field !== undefined && Object.hasOwn(field, 'value')) {
      const read = (key: string) => Object.getOwnPropertyDescriptor(field.value, key)?.value;
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

// The installed Common catalogue returns only presentation DATA. Never infer
// a cause from exception text, or turn a missing/foreign renderer into a new
// failure. The existing complete terminal-message envelope remains 512 units.
const rowFailureHeaderUnits =
  'Execution failed: phase=local_managed_advance; task=2147483647; step=2147483647; cause='.length +
  96 + '. Original execution failure; resource quantities were not retained.'.length;
const rowFailureExplanationUnits = 512 - rowFailureHeaderUnits - 1;
const serializationRowLimitMessage =
  'SERIALIZE row limit exceeded (serialize.row_limit). Reduce input rows or increase SERIALIZE OPTIONS max_rows.';
function failureCauseExplanation(cause: string, describeCause?: DescribeCause) {
  if (typeof describeCause !== 'function') return undefined;
  try {
    const value = describeCause(cause);
    return typeof value === 'string' && value.length > 0 && value.length <= rowFailureExplanationUnits
      ? value : undefined;
  } catch { return undefined; }
}

export function publicBudgetFailureMessage(error: unknown, describeCause?: DescribeCause) {
  const data = dispatchFailureSnapshot(error)?.primaryDiagnostic as LocalDiagnostic | SerializationDiagnostic | undefined;
  if (data?.phase === 'serialization_input' && data.kind === 'row_limit') return serializationRowLimitMessage;
  if (data?.phase !== 'local_managed_advance') return undefined;
  if (data.kind === 'logical_work') {
    return `Budget exceeded: phase=${data.phase}; task=${data.task}; step=${data.step}; dimension=logical_work; requested_delta=unavailable; remaining=unavailable; policy=${data.workLimit}; unit=work_units; setting=${data.setting}. ` +
      'Runtime logical work; requested and remaining quantities were not retained.';
  }
  if (data.kind === 'row_failure') {
    const explanation = failureCauseExplanation(data.cause, describeCause);
    // One complete bounded string, not a prefix copy followed by a second
    // full message. The optional separator and catalogue text are borrowed.
    return `Execution failed: phase=${data.phase}; task=${data.task}; step=${data.step}; cause=${data.cause}. Original execution failure; resource quantities were not retained.${explanation === undefined ? '' : ' '}${explanation ?? ''}`;
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

export function retainedBudgetFailureMessage(key: unknown, state: JournalFailureState, runId: string, control: RunControl,
  describeCause?: DescribeCause) {
  if (typeof key !== 'string' || state.status !== 'failed' ||
      state.terminal_error?.code !== 'ACTQL_E_UNPUBLISHED_RUN' ||
      control.physical_stop !== 'confirmed') return undefined;
  let previous: PreviousJournalState | null;
  try { previous = JSON.parse(key); } catch { return undefined; }
  if (previous?.run_id !== runId || previous.status !== 'failed' ||
      previous.result_available !== false || previous.next_action?.kind !== 'none' ||
      previous.terminal_error?.code !== 'ACTQL_E_UNPUBLISHED_RUN' ||
      previous.control === null || typeof previous.control !== 'object' ||
      Object.keys(previous.control).sort().join('\0') !== Object.keys(control).sort().join('\0') ||
      Object.keys(control).some(name => previous!.control[name] !== control[name])) return undefined;
  const message = previous.terminal_error!.message;
  if (typeof message !== 'string') return undefined;
  if (message === serializationRowLimitMessage) return message;
  const cause = message.length <= 512 &&
    /^Execution failed: phase=local_managed_advance; task=(0|[1-9][0-9]{0,9}); (?:step=(0|[1-9][0-9]{0,9}); )?cause=([a-z_]+(?:\.[a-z_]+)*)\. Original execution failure; resource quantities were not retained\.(?: (.*))?$/u.exec(message);
  if (cause && Number(cause[1]) <= 2147483647 &&
      (cause[2] === undefined || Number(cause[2]) <= 2147483647) && cause[3].length <= 96) {
    // Keep immutable old bare messages verbatim. A new suffix is accepted only
    // when it exactly matches this installed Common catalogue; arbitrary
    // stored text or another cause cannot become a canonical conversion fact.
    if (cause[4] === undefined || cause[2] !== undefined &&
        cause[4] === failureCauseExplanation(cause[3], describeCause)) return message;
  }
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
