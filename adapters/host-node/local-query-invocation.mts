import {createHash, randomUUID} from 'node:crypto';
import {valuesExecutionContextCid} from './local-values-capacity.mjs';
import {sampleOriginalQueryTime} from './query-evaluation-clock.mjs';

type CompilationKind = 'values' | 'tasks' | 'infer' | 'serialization';
type CompiledRun = Readonly<{kind: CompilationKind}>;
type RunDefinition = Readonly<{wire: string}>;
type RetainedHeader = Readonly<{created_at?: unknown; valid_until?: unknown}>;
type QueryTime = Readonly<{queryTimePreparation: unknown; queryTime: unknown}>;
type QueryInvocation = {request: unknown; createdAt?: string; preparation?: unknown};
type RetainedInvocation = {
  readonly preparedProgram: unknown;
  readonly requestIdentity: unknown;
  compiled: CompiledRun | undefined;
  runDefinition: RunDefinition | undefined;
  createdAt: unknown;
  validUntil: unknown;
  queryTimePreparation: unknown;
  queryTime: unknown;
};
type QueryTimeControl = {
  clientRequiresQueryTime?(prepared: unknown): boolean;
  prepareClientQueryTime(prepared: unknown, request: unknown, createdAt: string): unknown;
  restoreClientQueryTime(prepared: unknown, compiled: CompiledRun, definition: RunDefinition,
    request: unknown): QueryTime;
  bindClientQueryTime(original: unknown, prepared: unknown, compiled: CompiledRun,
    definition: RunDefinition, request: unknown): unknown;
};
type InvocationChecks = {
  checkClientCompiledRunOwner(compiled: CompiledRun, prepared: unknown): unknown;
  checkClientCompiledRunDefinition(compiled: CompiledRun, definition: RunDefinition | undefined): unknown;
};
type TimedControl = QueryTimeControl & {
  prepareCheckedClientCompiledRun(prepared: unknown, kind: 'values' | 'tasks',
    policy: Readonly<{executionContextCid: string; hostPolicyCid: string; expiresAt: unknown}>,
    graph: undefined, original: unknown): CompiledRun;
  defineCheckedClientCompiledRun(compiled: CompiledRun, options: Readonly<{
    namespaceId: string; runId: string; createdAt: unknown; validUntil: unknown;
    retainedDefinitionWire: string | undefined;
  }>): RunDefinition;
  clientQueryTimeInvocationOriginal(original: unknown, prepared: unknown): unknown;
};
type TimedOptions = {
  control: TimedControl;
  preparedProgram: unknown;
  requestIdentity: unknown;
  compilationOriginal: unknown;
  kind: 'values' | 'tasks';
  authorityScopeCid: string;
  namespaceId: string;
  now: () => string;
  retainedDefinitionWire?: string;
  retainedInvocation: RetainedInvocation;
};

export function prepareQueryInvocation(control: QueryTimeControl, prepared: unknown,
  request: unknown, retained: unknown): QueryInvocation | undefined {
  if (control.clientRequiresQueryTime?.(prepared) !== true) return undefined;
  if (request === undefined) throw new TypeError('OriginalClientQueryRequestRequired');
  if (retained !== undefined) return {request};
  const createdAt=sampleOriginalQueryTime();
  return {request,createdAt,preparation:control.prepareClientQueryTime(prepared,request,createdAt)};
}

export function bindQueryInvocation(control: QueryTimeControl, original: QueryInvocation | undefined,
  prepared: unknown, compiled: CompiledRun, definition: RunDefinition): Partial<QueryTime> {
  if (original === undefined) return {};
  if (original.preparation === undefined) {
    return control.restoreClientQueryTime(prepared,compiled,definition,original.request);
  }
  return Object.freeze({queryTimePreparation:original.preparation,
    queryTime:control.bindClientQueryTime(original.preparation,prepared,compiled,definition,original.request)});
}

// Called only by the existing timed Request adoption constructor. Its parent
// already retains the compiler artifact; the returned Option is a Core original.
export function prepareTimedClientInvocation({control, preparedProgram, requestIdentity,
  compilationOriginal, kind, authorityScopeCid, namespaceId, now, retainedDefinitionWire, retainedInvocation}: TimedOptions) {
  if (!['values', 'tasks'].includes(kind) || compilationOriginal === undefined || requestIdentity === undefined ||
      retainedInvocation === null || typeof retainedInvocation !== 'object' || Object.isFrozen(retainedInvocation)) {
    throw new TypeError('OriginalClientQueryInvocationRequired');
  }
  const fields = Object.getOwnPropertyDescriptors(retainedInvocation);
  if (fields.preparedProgram?.value !== preparedProgram || fields.requestIdentity?.value !== requestIdentity ||
      ['compiled', 'runDefinition', 'createdAt', 'validUntil', 'queryTimePreparation', 'queryTime']
        .some(name => fields[name]?.writable !== true || !Object.hasOwn(fields[name] ?? {}, 'value') ||
          fields[name].value !== undefined)) throw new TypeError('OriginalClientQueryInvocationRequired');
  // Existing native Definition admission permits at most100000 wire bytes.
  // Fence the earlier JS parse too; this cannot admit a looser native body.
  if (retainedDefinitionWire !== undefined &&
      (typeof retainedDefinitionWire !== 'string' || retainedDefinitionWire.length > 100000)) {
    throw new TypeError('OriginalClientQueryInvocationRequired');
  }
  const at = Date.parse(now());
  if (!Number.isFinite(at)) throw new TypeError('InvalidLocalClock');
  const retained = retainedDefinitionWire === undefined ? undefined :
    JSON.parse(retainedDefinitionWire) as RetainedHeader | null;
  const queryInvocation: QueryInvocation = retained === undefined
    ? {request: requestIdentity, createdAt: sampleOriginalQueryTime(), preparation: undefined}
    : {request: requestIdentity};
  if (retained === undefined) {
    retainedInvocation.createdAt = queryInvocation.createdAt;
    retainedInvocation.queryTimePreparation = queryInvocation.preparation = control.prepareClientQueryTime(
      preparedProgram, requestIdentity, queryInvocation.createdAt!);
  }
  const createdAt = retainedInvocation.createdAt = retained?.created_at ?? queryInvocation.createdAt;
  const validUntil = retainedInvocation.validUntil = retained?.valid_until ?? instant(at + 24 * 60 * 60 * 1000);
  const contextCid = kind === 'values' ? valuesExecutionContextCid(authorityScopeCid)
    : cid({version: 'actql-installed-local-context/0.1', authority_scope_cid: authorityScopeCid});
  const compiled = retainedInvocation.compiled = control.prepareCheckedClientCompiledRun(preparedProgram, kind,
    {executionContextCid: contextCid,
      hostPolicyCid: policyCid(kind === 'values' ? 'source-free-values' : 'checked-tasks'),
      expiresAt: validUntil}, undefined, compilationOriginal);
  const runDefinition = retainedInvocation.runDefinition = control.defineCheckedClientCompiledRun(compiled,
    {namespaceId, runId: randomUUID(), createdAt, validUntil, retainedDefinitionWire});
  const queryTime = bindQueryInvocation(control, queryInvocation, preparedProgram, compiled, runDefinition);
  retainedInvocation.queryTimePreparation = queryTime.queryTimePreparation;
  retainedInvocation.queryTime = queryTime.queryTime;
  const invocationOriginal = control.clientQueryTimeInvocationOriginal(queryTime.queryTimePreparation, preparedProgram);
  Object.freeze(retainedInvocation);
  return Object.freeze({original: invocationOriginal, retained: retainedInvocation});
}

export function checkedOriginalQueryInvocation(original: RetainedInvocation,
  control: InvocationChecks, prepared: unknown, request: unknown, kind: CompilationKind,
  retainedWire: string | undefined) {
  if (original.preparedProgram !== prepared || original.requestIdentity !== request ||
      original.compiled?.kind !== kind || original.queryTimePreparation === undefined ||
      original.queryTime === undefined || retainedWire !== undefined &&
        original.runDefinition?.wire !== retainedWire) {
    throw new TypeError('ForeignClientQueryInvocationOriginal');
  }
  control.checkClientCompiledRunOwner(original.compiled, prepared);
  control.checkClientCompiledRunDefinition(original.compiled, original.runDefinition);
  return original;
}

export const cid = (value: unknown) => `sha256:${createHash('sha256')
  .update(JSON.stringify(value)).digest('hex')}`;
export const policyCid = (name: string) => cid({version: 'actql-installed-local-policy/0.1',
  name});
export const instant = (value: number) => new Date(value).toISOString();
