import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';

type CopyRuntime = Readonly<{
  clientProgramModelRequestInputFrameGeometry(request: unknown, maxBytes: number): unknown;
  clientProgramEffectModelEvidenceCopyCapacity(bundleBytes: number, bundleNodes: number,
    bundleDepth: number, input: unknown, textUnits: number, count: number): unknown;
}>;
type CopySource = Readonly<{
  evaluationInput(slot: number): Readonly<{callWire: string; request: unknown}> | undefined;
  evaluationRequest(slot: number): unknown;
}>;
type CopyBundle = Readonly<{
  count: number; wire: string; usage?: unknown; calls: readonly Readonly<{callWire: string}>[];
}>;

// Calculate the existing Common quote over the same admitted call inventory.
// The caller's original owner retains the reserve, grow and receipt duties.
export function inferEvidenceCopyConstruction(moon: CopyRuntime, operation: CopySource,
  bundle: CopyBundle, kind: 'typed-input' | undefined) {
  const failure = (code: string) => {
    const error = new Error(code) as Error & {code?: string};
    if (kind === 'typed-input') error.code = code;
    return error;
  };
  const usage = bundle.usage;
  if (usage === undefined || !Number.isSafeInteger(bundle.count) || bundle.count < 1 || bundle.count > 2147483647 ||
      runtimeField(usage, 0) !== Buffer.byteLength(bundle.wire)) {
    throw failure('RequiredEvidenceUnavailable');
  }
  let retained = 0n, execution = 0n;
  for (let slot = 0; slot < bundle.count; slot++) {
    const logical = kind === 'typed-input' ? operation.evaluationInput(slot) : undefined;
    const physical = kind === 'typed-input' ? undefined : operation.evaluationRequest(slot);
    if (kind === 'typed-input' ? logical === undefined || logical.callWire !== bundle.calls[slot].callWire
      : physical === undefined) throw failure('RequiredEvidenceUnavailable');
    const request = kind === 'typed-input' ? logical!.request : runtimeField(physical, 0);
    const shape = checked(moon.clientProgramModelRequestInputFrameGeometry(request, 65536));
    const text = bundle.calls[slot].callWire.length + (kind === 'typed-input' ? 0
      : (runtimeField(physical, 1) as string).length + (runtimeField(physical, 2) as string).length);
    if (!Number.isSafeInteger(text) || text > 2147483647) throw failure('EvaluationBudgetExceeded');
    const capacity = checked(moon.clientProgramEffectModelEvidenceCopyCapacity(
      runtimeField(usage, 0) as number, runtimeField(usage, 1) as number, runtimeField(usage, 2) as number,
      shape, text, bundle.count));
    const r = runtimeField(capacity, 0) as bigint, e = runtimeField(capacity, 1) as bigint;
    retained = r > retained ? r : retained; execution = e > execution ? e : execution;
  }
  return {retained, execution};
}
