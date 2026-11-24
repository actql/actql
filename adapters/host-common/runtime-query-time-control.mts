import {runtimeOptionalField} from './compiler-binding.generated.mjs';
import {checked} from './runtime-result.mjs';

// Keep Common-owned handles and its unboxed Option opaque. The original
// invocation projection supplies its four exact fields in compiler order.
type CommonQueryTimeBindings = Readonly<{
  clientProgramRequiresQueryTime?(prepared: unknown, maxWork: number, maxExpressionsPerTask: number): unknown;
  clientProgramPrepareQueryTime?(prepared: unknown, request: unknown, createdAt: string): unknown;
  clientProgramBindQueryTime?(preparation: unknown, prepared: unknown, compilation: unknown,
    definition: unknown, request: unknown): unknown;
  clientProgramQueryTimeInvocationOriginal?(preparation: unknown, prepared: unknown): unknown;
  clientProgramInstalledManagedRunInvocationOriginal?(run: unknown, prepared: unknown): unknown;
  clientProgramRestoreQueryTimePreparation?(prepared: unknown, compilation: unknown,
    definition: unknown, request: unknown): unknown;
  clientProgramQueryTimeContext(preparation: unknown): unknown;
}>;

type RetainedQueryInvocation = Readonly<{
  preparedProgram: unknown;
  requestIdentity: unknown;
  compiled: unknown;
  runDefinition: unknown;
  queryTimePreparation: unknown;
  queryTime: unknown;
}>;

type Owners = Readonly<{
  compiledRunTokens: WeakMap<object, unknown>;
  token: (contract: unknown) => unknown;
  currentControl: () => Readonly<{checkClientCompiledRunOwner(compiled: unknown, prepared: unknown): unknown}>;
}>;

export function createQueryTimeControls(moon: CommonQueryTimeBindings, {
  compiledRunTokens, token, currentControl,
}: Owners) {
  return {
    clientRequiresQueryTime(prepared: unknown) {
      if (typeof moon.clientProgramRequiresQueryTime !== 'function') return false;
      const value = checked(moon.clientProgramRequiresQueryTime(prepared, 100000, 100000));
      if (typeof value !== 'boolean') throw new TypeError('Invalid Client query-time requirement');
      return value;
    },
    prepareClientQueryTime(prepared: unknown, request: unknown, createdAt: string) {
      if (typeof moon.clientProgramPrepareQueryTime !== 'function') {
        throw new TypeError('Client query-time preparation unavailable');
      }
      return checked(moon.clientProgramPrepareQueryTime(prepared, request, createdAt));
    },
    bindClientQueryTime(original: unknown, prepared: unknown, compiled: unknown, definition: unknown, request: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || typeof moon.clientProgramBindQueryTime !== 'function') {
        throw new TypeError('Foreign Client query-time compilation');
      }
      return checked(moon.clientProgramBindQueryTime(original, prepared, value, token(definition), request));
    },
    clientQueryTimeInvocationOriginal(original: unknown, prepared: unknown) {
      const project = moon.clientProgramQueryTimeInvocationOriginal;
      if (typeof project !== 'function') throw new TypeError('Client query-time original unavailable');
      // Opaque Option from the matching Core; never synthesize a JS tuple.
      return Reflect.apply(project, moon, [original, prepared]);
    },
    checkedClientManagedQueryInvocationOriginal<Original extends RetainedQueryInvocation>(
      run: unknown, prepared: unknown, original: Original) {
      const project = moon.clientProgramInstalledManagedRunInvocationOriginal;
      if (typeof project !== 'function') throw new TypeError('Client query-time original unavailable');
      const retained = Reflect.apply(project, moon, [run, prepared]);
      const compiled = compiledRunTokens.get(original.compiled as object);
      if (compiled === undefined || original.preparedProgram !== prepared ||
          runtimeOptionalField(retained, 0) !== original.queryTimePreparation ||
          runtimeOptionalField(retained, 1) !== original.requestIdentity ||
          runtimeOptionalField(retained, 2) !== compiled ||
          runtimeOptionalField(retained, 3) !== token(original.runDefinition) ||
          moon.clientProgramQueryTimeContext(original.queryTimePreparation) !== original.queryTime) {
        throw new TypeError('Foreign Client original query-time invocation');
      }
      currentControl().checkClientCompiledRunOwner(original.compiled, prepared);
      return original;
    },
    restoreClientQueryTime(prepared: unknown, compiled: unknown, definition: unknown, request: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      if (value === undefined || typeof moon.clientProgramRestoreQueryTimePreparation !== 'function') {
        throw new TypeError('Foreign Client query-time compilation');
      }
      const preparation = checked(moon.clientProgramRestoreQueryTimePreparation(prepared, value, token(definition), request));
      const context = moon.clientProgramQueryTimeContext(preparation);
      if (context === undefined) throw new TypeError('Client query-time context unavailable');
      return Object.freeze({queryTimePreparation:preparation,queryTime:context});
    },
  };
}
