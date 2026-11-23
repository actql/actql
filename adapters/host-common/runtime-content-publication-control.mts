import {runtimeField} from './compiler-binding.generated.mjs';

type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type RunEvidence = Readonly<{name: string; identity: string; wire: string}>;
type PublicationContract = RunEvidence & Readonly<{identityField: string}>;
// The Common inventory producers return exactly these three roles.
type RecoveryBindingName = 'content_input_artifact' | 'content_evidence' | 'content_generation';
type RetainedContentOutput = Readonly<{binding: string; descriptorWire: string; rows: readonly string[]}>;

// Node Common bridges keep compiled handles and Result variants opaque.
// The checked projections below reflect the declared String, Int, Int64 and tuple outputs.
type CommonContentPublicationBindings = Readonly<{
  clientProgramSerializationByteHoldingCid(run: unknown, definition: unknown, storeCid: string): unknown;
  clientCapturedContentGenerationCount(captured: unknown): unknown;
  clientCapturedContentGenerationStorage(captured: unknown, definition: unknown, storeCid: string,
    index: number): unknown;
  clientProgramSerializationRecoveryBindings(generation: unknown, run: unknown, storeCid: string): unknown;
  clientProgramSerializationGenerationOutput(generation: unknown, run: unknown): unknown;
  clientProgramExportContentGenerationOutput(generation: unknown, run: unknown, definition: unknown,
    storeCid: string): unknown;
  clientProgramSerializationGenerationEvidence(generation: unknown, run: unknown): unknown;
  clientProgramPrepareRetainedContentOutput(generation: unknown, run: unknown, definition: unknown,
    storeCid: string, binding: string, descriptorWire: string, rows: readonly string[],
    available: () => boolean): unknown;
  clientProgramCompiledEffectProgram(run: unknown, checkedEffect: unknown): unknown;
  clientProgramSerializationGenerationDerivation(generation: unknown, run: unknown): unknown;
  clientProgramIssueSerializationInvocation(run: unknown, definition: unknown, generation: unknown,
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
}>;

type Owners = Readonly<{
  compiledRunTokens: WeakMap<object, unknown>;
  serializationGenerationTokens: WeakMap<object, unknown>;
  compiledContent: (run: unknown) => unknown;
  compiledRunResult: (result: unknown, code: string) => unknown;
  token: (value: unknown) => unknown;
  inspectEvidence: (evidence: unknown) => RunEvidence;
  inspect: (contract: unknown, limits: Limits) => PublicationContract;
  captureContractLimits: (limits: Limits, label: string) => Limits;
}>;

export function createContentPublicationControls(moon: CommonContentPublicationBindings, {
  compiledRunTokens, serializationGenerationTokens, compiledContent, compiledRunResult, token,
  inspectEvidence, inspect, captureContractLimits,
}: Owners) {
  return {
    checkedClientSerializationByteHoldingCid(compiled: unknown, definition: unknown, storeAuthorityCid: string) {
      const value = compiledContent(compiled);
      return compiledRunResult(moon.clientProgramSerializationByteHoldingCid(
        value, token(definition), storeAuthorityCid), 'Client Content byte binding unavailable') as string;
    },
    capturedContentGenerationCount(captured: unknown) {
      return compiledRunResult(moon.clientCapturedContentGenerationCount(token(captured)),
        'Captured Content inventory unavailable') as number;
    },
    capturedContentGenerationStorage(captured: unknown, definition: unknown, storeAuthorityCid: string, index: number) {
      if (!Number.isSafeInteger(index) || index < 0) {
        throw new TypeError('Invalid Captured Content occurrence');
      }
      const value = compiledRunResult(moon.clientCapturedContentGenerationStorage(
        token(captured), token(definition), storeAuthorityCid, index),
      'Captured Content storage binding unavailable');
      return Object.freeze({holdingCid: runtimeField(value, 0) as string, manifestCid: runtimeField(value, 1) as string,
        contentCid: runtimeField(value, 2) as string, byteCount: runtimeField(value, 3) as bigint,
        bindings: Object.freeze((runtimeField(value, 4) as readonly unknown[]).map(binding => Object.freeze({
          name: runtimeField(binding, 0) as RecoveryBindingName, semanticCid: runtimeField(binding, 1) as string, wire: runtimeField(binding, 2) as string, holdingCid: runtimeField(binding, 3) as string,
        })))});
    },
    checkedClientSerializationRecoveryBindings(compiled: unknown, generation: unknown, storeAuthorityCid: string) {
      const value = compiledRunTokens.get(compiled as object);
      const completion = serializationGenerationTokens.get(generation as object);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const bindings = compiledRunResult(moon.clientProgramSerializationRecoveryBindings(completion,
        value, storeAuthorityCid), 'Client Content recovery binding unavailable') as readonly unknown[];
      return Object.freeze(bindings.map(binding => Object.freeze({
        name: runtimeField(binding, 0) as RecoveryBindingName, semanticCid: runtimeField(binding, 1) as string, wire: runtimeField(binding, 2) as string, holdingCid: runtimeField(binding, 3) as string,
      })));
    },
    checkedClientSerializationGenerationOutput(compiled: unknown, generation: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      const completion = serializationGenerationTokens.get(generation as object);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const output = moon.clientProgramSerializationGenerationOutput(completion, value);
      if (output === undefined) throw new TypeError('Client Content generation unavailable');
      return output;
    },
    exportCheckedClientContentGenerationOutput(compiled: unknown, definition: unknown, generation: unknown, storeAuthorityCid: string) {
      const value = compiledRunTokens.get(compiled as object);
      const completion = serializationGenerationTokens.get(generation as object);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const exported = compiledRunResult(moon.clientProgramExportContentGenerationOutput(
        completion, value, token(definition), storeAuthorityCid),
      'Client Content completion export unavailable');
      return Object.freeze({binding: runtimeField(exported, 0) as string, descriptorWire: runtimeField(exported, 1) as string,
        rows: Object.freeze((runtimeField(exported, 2) as readonly string[]).slice())});
    },
    checkedClientSerializationGenerationEvidence(compiled: unknown, generation: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      const completion = serializationGenerationTokens.get(generation as object);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const evidence = moon.clientProgramSerializationGenerationEvidence(completion, value);
      if (evidence === undefined) throw new TypeError('Client Content generation unavailable');
      return inspectEvidence(evidence);
    },
    prepareCheckedClientRetainedContentOutput(compiled: unknown, definition: unknown, generation: unknown,
      storeAuthorityCid: string, completion: RetainedContentOutput, available: () => boolean) {
      const run = compiledRunTokens.get(compiled as object);
      const original = serializationGenerationTokens.get(generation as object);
      if (run === undefined || original === undefined || typeof available !== 'function') {
        throw new TypeError('Foreign Client retained Content output');
      }
      return compiledRunResult(moon.clientProgramPrepareRetainedContentOutput(
        original, run, token(definition), storeAuthorityCid, completion.binding,
        completion.descriptorWire, completion.rows, available),
      'Client Content completion recovery unavailable');
    },
    checkedClientCompiledEffectProgram(compiled: unknown, checkedEffect: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      const original = value === undefined ? undefined
        : moon.clientProgramCompiledEffectProgram(value, checkedEffect);
      if (original === undefined) throw new TypeError('Foreign Client compiled Effect Run');
      return original;
    },
    checkedClientSerializationGenerationDerivation(compiled: unknown, generation: unknown) {
      const value = compiledRunTokens.get(compiled as object);
      const completion = serializationGenerationTokens.get(generation as object);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      const evidence = moon.clientProgramSerializationGenerationDerivation(completion, value);
      if (evidence === undefined) throw new TypeError('Client Content generation unavailable');
      return inspectEvidence(evidence);
    },
    issueCheckedClientSerializationInvocation(compiled: unknown, definition: unknown, generation: unknown, limits: Limits) {
      const value = compiledRunTokens.get(compiled as object);
      const completion = serializationGenerationTokens.get(generation as object);
      if (value === undefined || completion === undefined) {
        throw new TypeError('Foreign Client Content generation');
      }
      limits = captureContractLimits(limits, 'Content Invocation');
      const issued = compiledRunResult(moon.clientProgramIssueSerializationInvocation(
        value, token(definition), completion,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth), 'RunHostContentInvocationRejected');
      return Object.freeze({observation: inspectEvidence(runtimeField(issued, 0)),
        invocation: inspect(runtimeField(issued, 1), limits), owner: runtimeField(issued, 1)});
    },
  };
}
