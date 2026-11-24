import {installedEffectDependencyOriginal} from './installed-effect-dependency-original.mjs';
import {runtimeField, runtimeIsBoxedSome} from './compiler-binding.generated.mjs';
import {checked} from './runtime-result.mjs';
import {tuplePair} from './runtime-tuple.mjs';

type CaptureLimits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type SnapshotLimits = Readonly<{
  maxLogicalWireBytes: number;
  maxLogicalWireNodes: number;
  maxLogicalWireDepth: number;
}>;
type CaptureSignal = Pick<AbortSignal, 'throwIfAborted'>;
type CaptureContract = Readonly<{name: string; identityField: string; identity: string; wire: string}>;
type ResultSnapshot = Readonly<{kind: 'captured-result-snapshot'}>;
type DependencyOriginal = ReturnType<typeof installedEffectDependencyOriginal>;
type CaptureChain = Readonly<{
  runDefinition: unknown;
  invocation: unknown;
  definitions: readonly unknown[];
  artifacts: readonly unknown[];
  manifest: unknown;
  receipt: unknown;
}>;
type CaptureEvidence = Readonly<{
  snapshots: readonly unknown[];
  authoringContext: unknown;
  pendingSourceStateAdvances: readonly unknown[];
  modelEvidence: readonly unknown[];
  contentGenerations?: readonly unknown[];
}>;
type EffectCaptureEvidence = CaptureEvidence & Readonly<{
  effectSources: readonly unknown[];
  localEffectSources: readonly unknown[];
  dependencyInventoryWire?: string;
  dependencyConstruction?: unknown;
}>;
type CapturePlan = Readonly<{name: string; wire: string}>;

// Generated Common owns the opaque preparation and checked Result representations.
type CommonCaptureBindings = Readonly<{
  clientProgramAdvanceCapture(capture: unknown, quantum: number): unknown;
  clientProgramAdvanceSnapshot(snapshot: unknown, quantum: number): unknown;
  clientProgramBeginSnapshot(publication: unknown, output: unknown): unknown;
  clientProgramCancelCapture(capture: unknown): undefined;
  clientProgramCancelSnapshot(snapshot: unknown): undefined;
  clientProgramCaptureLimits(capture: unknown): unknown;
  clientProgramFinishCapture(capture: unknown): unknown;
  clientProgramFinishInstalledEffectDependencyCapture(owner: unknown, prepared: unknown,
    request: unknown, plan: unknown, issuer: unknown): unknown;
  clientProgramFinishSnapshot(snapshot: unknown): unknown;
  clientProgramInstalledEffectDependencyCaptureAdvance(owner: unknown, prepared: unknown,
    request: unknown, plan: unknown, issuer: unknown, quantum: number): unknown;
  clientProgramInstalledEffectDependencyCaptureBegin(owner: unknown, prepared: unknown, request: unknown,
    expectedPlan: unknown, definition: unknown, invocation: unknown, definitions: unknown,
    artifacts: unknown, manifest: unknown, receipt: unknown, snapshots: unknown, sources: unknown,
    localSources: unknown, advances: unknown, authoring: unknown, models: unknown, preview: unknown,
    planNames: unknown, planWires: unknown, dependencyWire: string, contentGenerations: unknown,
    maxBodyBytes: number, maxBodyNodes: number, maxBodyDepth: number): unknown;
  clientProgramInstalledEffectDependencyCaptureReserve(owner: unknown, prepared: unknown,
    request: unknown, plan: unknown, definition: unknown, invocation: unknown, slots: number): unknown;
  clientProgramPrepareCapture(publication: unknown, definition: unknown, invocation: unknown,
    definitions: unknown, artifacts: unknown, manifest: unknown, receipt: unknown, snapshots: unknown,
    authoring: unknown, models: unknown): unknown;
  clientProgramStartCapture(capture: unknown): unknown;
  strategyBeginEffectfulCapturedRun(runDefinition: unknown, invocation: unknown, definitions: unknown,
    artifacts: unknown, manifest: unknown, receipt: unknown, snapshots: unknown, sources: unknown,
    localSources: unknown, advances: unknown, authoring: unknown, models: unknown, preview: unknown,
    planNames: unknown, planWires: unknown, maxWireBytes: number, maxNodes: number, maxDepth: number,
    dependencyWire: string | undefined, maxWorkspace: number, contentGenerations: unknown): unknown;
  strategyBeginOriginalEffectFreeCapturedRun(runDefinition: unknown, invocation: unknown,
    definitions: unknown, artifacts: unknown, manifest: unknown, receipt: unknown, snapshots: unknown,
    advances: unknown, authoring: unknown, models: unknown, maxWireBytes: number, maxNodes: number,
    maxDepth: number, maxWorkspace: number, contentGenerations: unknown): unknown;
  strategyCapturedRunAdvance(preparation: unknown, quantum: number): unknown;
  strategyCapturedRunCancel(preparation: unknown): undefined;
  strategyCapturedRunFinish(preparation: unknown): unknown;
  strategyCapturedRunFinishRetained(preparation: unknown): unknown;
  strategyCapturedRunPreparationLimits(original: unknown): unknown;
  strategyHostOutputSnapshotAdvance(value: unknown, quantum: number): unknown;
  strategyHostOutputSnapshotBegin(value: unknown, maxWireBytes: number, maxNodes: number,
    maxDepth: number): unknown;
  strategyHostOutputSnapshotCancel(value: unknown): undefined;
  strategyHostOutputSnapshotFinish(value: unknown): unknown;
  strategyPublicationEvidenceWorkspace(maxNodes: number): number;
}>;

type CapturePorts = Readonly<{
  capturedComputationPreparations: WeakMap<object, unknown>;
  computationPreviewTokens: WeakMap<object, unknown>;
  token: (contract: unknown) => unknown;
  evidenceToken: (value: unknown) => unknown;
  snapshotToken: (value: unknown) => unknown;
  sourceAdvanceToken: (value: unknown) => unknown;
  contentCaptures: (values?: readonly unknown[]) => readonly unknown[];
  effectSourceToken: (value: unknown) => unknown;
  localEffectSourceToken: (value: unknown) => unknown;
  inspect: (contract: unknown, limits: CaptureLimits) => CaptureContract;
  inspectSnapshot: (snapshot: unknown) => ResultSnapshot;
  inspectPreparedEffectCapturedRun: (value: unknown) => CaptureContract;
  captureContractLimits: (limits: CaptureLimits, label: string) => CaptureLimits;
}>;

export function createCapturedPublicationControls(moon: CommonCaptureBindings, {
  capturedComputationPreparations, computationPreviewTokens, token, evidenceToken, snapshotToken,
  sourceAdvanceToken, contentCaptures, effectSourceToken, localEffectSourceToken,
  inspect, inspectSnapshot, inspectPreparedEffectCapturedRun, captureContractLimits,
}: CapturePorts) {
  const capturedPreparationLimits = (preparation: unknown) => {
      // The same preparation owns the complete context envelope. Metadata
      // contract bounds cannot price embedded Result rows or their wrapper.
      const originalOption = moon.strategyCapturedRunPreparationLimits(preparation);
      const originalLimits = runtimeIsBoxedSome(originalOption)
        ? runtimeField(originalOption, 0) : undefined;
      if (!Array.isArray(originalLimits) || originalLimits.length !== 3 ||
          !Number.isSafeInteger(originalLimits[0]) ||
          !Number.isSafeInteger(originalLimits[1]) ||
          !Number.isSafeInteger(originalLimits[2]) ||
          originalLimits[0] < 0 || originalLimits[0] > 2147483647 ||
          originalLimits[1] < 0 || originalLimits[1] > 2147483647 ||
          originalLimits[2] < 0 || originalLimits[2] > 2147483647) {
        throw new TypeError('Invalid original Captured Run preparation limits');
      }
      return Object.freeze({maxWireBytes: originalLimits[0],
        maxNodes: originalLimits[1], maxDepth: originalLimits[2]});
  };
  const finishCapturedPreparation = async (preparation: unknown, signal?: CaptureSignal,
    retainComputation = false, dependencyOriginal?: DependencyOriginal) => {
    let finished = false;
    try {
      const limits = capturedPreparationLimits(preparation);
      while (true) {
        signal?.throwIfAborted();
        const done = dependencyOriginal === undefined
          ? checked(moon.strategyCapturedRunAdvance(preparation, 256))
          : checked(moon.clientProgramInstalledEffectDependencyCaptureAdvance(
            dependencyOriginal.parent, dependencyOriginal.prepared, dependencyOriginal.request,
            dependencyOriginal.plan, preparation, 256));
        dependencyOriginal?.current();
        if (done) break;
        await new Promise(resolve => typeof setImmediate === 'function'
          ? setImmediate(resolve) : setTimeout(resolve, 0));
      }
      signal?.throwIfAborted();
      const captured = dependencyOriginal === undefined ? inspect(checked(retainComputation
        ? moon.strategyCapturedRunFinishRetained(preparation)
        : moon.strategyCapturedRunFinish(preparation)), limits)
        : inspectPreparedEffectCapturedRun(checked(moon.clientProgramFinishInstalledEffectDependencyCapture(
          dependencyOriginal.parent, dependencyOriginal.prepared, dependencyOriginal.request,
          dependencyOriginal.plan, preparation)));
      dependencyOriginal?.current();
      if (retainComputation) {
        capturedComputationPreparations.set(captured, preparation);
      }
      finished = true;
      return captured;
    } finally {
      if (!finished) moon.strategyCapturedRunCancel(preparation);
    }
  };
  const finishProgramSnapshot = async (publication: unknown, output: unknown, signal?: CaptureSignal) => {
    signal?.throwIfAborted();
    const snapshot = checked(moon.clientProgramBeginSnapshot(publication, output));
    let finished = false;
    try {
      while (true) {
        signal?.throwIfAborted();
        const progress = tuplePair(checked(
          moon.clientProgramAdvanceSnapshot(snapshot, 256)));
        if (!Array.isArray(progress) || progress.length !== 2 ||
            typeof progress[0] !== 'boolean' ||
            !Number.isSafeInteger(progress[1]) || progress[1] < 0) {
          throw new TypeError('Invalid original snapshot progress');
        }
        if (progress[0]) break;
        await new Promise(resolve => typeof setImmediate === 'function'
          ? setImmediate(resolve) : setTimeout(resolve, 0));
      }
      signal?.throwIfAborted();
      const captured = inspectSnapshot(checked(moon.clientProgramFinishSnapshot(snapshot)));
      finished = true;
      return captured;
    } finally {
      if (!finished) moon.clientProgramCancelSnapshot(snapshot);
    }
  };
  const programCaptureLimits = (capture: unknown) => {
    const extent = checked(moon.clientProgramCaptureLimits(capture));
    // The original extent check below proves all three scalar slots.
    const maxWireBytes = runtimeField(extent, 0) as number;
    const maxNodes = runtimeField(extent, 1) as number;
    const maxDepth = runtimeField(extent, 2) as number;
    if (!Number.isSafeInteger(maxWireBytes) || maxWireBytes < 0 ||
        maxWireBytes > 2147483647 ||
        !Number.isSafeInteger(maxNodes) || maxNodes < 0 || maxNodes > 2147483647 ||
        !Number.isSafeInteger(maxDepth) || maxDepth < 0 || maxDepth > 2147483647 ||
        runtimeField(extent, 3) !== undefined) {
      throw new TypeError('Invalid original capture extent');
    }
    return Object.freeze({maxWireBytes, maxNodes, maxDepth});
  };
  // Typed ordinary capture never exposes its inner issuer. The same Host
  // continuation owns cancellation throughout every await and publication.
  const finishProgramCapture = async (capture: unknown, signal?: CaptureSignal) => {
    let finished = false;
    try {
      checked(moon.clientProgramStartCapture(capture));
      const limits = programCaptureLimits(capture);
      while (true) {
        signal?.throwIfAborted();
        const progress = tuplePair(checked(
          moon.clientProgramAdvanceCapture(capture, 256)));
        if (!Array.isArray(progress) || progress.length !== 2 ||
            typeof progress[0] !== 'boolean' ||
            !Number.isSafeInteger(progress[1]) || progress[1] < 0) {
          throw new TypeError('Invalid original capture progress');
        }
        if (progress[0]) break;
        await new Promise(resolve => typeof setImmediate === 'function'
          ? setImmediate(resolve) : setTimeout(resolve, 0));
      }
      signal?.throwIfAborted();
      const captured = inspect(checked(
        moon.clientProgramFinishCapture(capture)), limits);
      // The existing publication owner keeps this one typed continuation.
      // Its private issuer remains on the same preparation resource owner.
      capturedComputationPreparations.set(captured, {program: capture});
      finished = true;
      return captured;
    } finally {
      if (!finished) moon.clientProgramCancelCapture(capture);
    }
  };
  const snapshotControls = {
    async admitCompletedResultSnapshot(exportHandle: unknown, outputLimits: SnapshotLimits,
      signal?: CaptureSignal, publicationResource?: unknown) {
      if (publicationResource !== undefined) {
        return finishProgramSnapshot(publicationResource, exportHandle, signal);
      }
      // Bare row emission and captured admission share this bound; the latter
      // includes the canonical relation wrapper. Borrow the existing checked
      // output policy without constructing a second quota or projection cache.
      if (outputLimits === null || typeof outputLimits !== 'object' ||
          !Number.isSafeInteger(outputLimits.maxLogicalWireBytes) ||
          !Number.isSafeInteger(outputLimits.maxLogicalWireNodes) ||
          !Number.isSafeInteger(outputLimits.maxLogicalWireDepth) ||
          outputLimits.maxLogicalWireBytes < 0 || outputLimits.maxLogicalWireBytes > 2147483647 ||
          outputLimits.maxLogicalWireNodes < 0 || outputLimits.maxLogicalWireNodes > 2147483647 ||
          outputLimits.maxLogicalWireDepth < 0 || outputLimits.maxLogicalWireDepth > 2147483647) {
        throw new TypeError('Invalid completed Result snapshot output limits');
      }
      signal?.throwIfAborted();
      const preparation = checked(moon.strategyHostOutputSnapshotBegin(
        exportHandle, outputLimits.maxLogicalWireBytes,
        outputLimits.maxLogicalWireNodes, outputLimits.maxLogicalWireDepth));
      let finished = false;
      try {
        while (true) {
          signal?.throwIfAborted();
          if (checked(moon.strategyHostOutputSnapshotAdvance(
            preparation, 256))) break;
          await new Promise(resolve => setTimeout(resolve, 0));
        }
        signal?.throwIfAborted();
        const snapshot = inspectSnapshot(checked(
          moon.strategyHostOutputSnapshotFinish(preparation)));
        finished = true;
        return snapshot;
      } finally {
        if (!finished) moon.strategyHostOutputSnapshotCancel(preparation);
      }
    },
  };
  const effectFreeCaptureControls = {
    async issueEffectFreeCapturedRun(chain: CaptureChain, evidence: CaptureEvidence, limits: CaptureLimits,
      signal?: CaptureSignal, publicationResource?: unknown) {
      limits = captureContractLimits(limits, 'Captured Run');
      if (chain === null || typeof chain !== 'object' ||
          evidence === null || typeof evidence !== 'object' ||
          !Array.isArray(chain.definitions) ||
          !Array.isArray(chain.artifacts) ||
          !Array.isArray(evidence.snapshots) ||
          !Array.isArray(evidence.pendingSourceStateAdvances) ||
          !Array.isArray(evidence.modelEvidence)) {
        throw new TypeError('Invalid Captured Run request');
      }
      signal?.throwIfAborted();
      if (publicationResource !== undefined) {
        if (evidence.pendingSourceStateAdvances.length !== 0 ||
            evidence.modelEvidence.length !== 0 ||
            (evidence.contentGenerations !== undefined &&
              (!Array.isArray(evidence.contentGenerations) ||
                evidence.contentGenerations.length !== 0))) {
          throw new TypeError('Invalid original program capture profile');
        }
        const capture = checked(moon.clientProgramPrepareCapture(
          publicationResource, token(chain.runDefinition), token(chain.invocation),
          chain.definitions.map(token), chain.artifacts.map(token),
          token(chain.manifest), token(chain.receipt),
          evidence.snapshots.map(snapshotToken),
          evidenceToken(evidence.authoringContext),
          evidence.modelEvidence.map(evidenceToken),
        ));
        return finishProgramCapture(capture, signal);
      }
      const preparation = moon.strategyBeginOriginalEffectFreeCapturedRun(
        token(chain.runDefinition),
        token(chain.invocation),
        chain.definitions.map(token),
        chain.artifacts.map(token),
        token(chain.manifest),
        token(chain.receipt),
        evidence.snapshots.map(snapshotToken),
        evidence.pendingSourceStateAdvances.map(sourceAdvanceToken),
        evidenceToken(evidence.authoringContext),
        evidence.modelEvidence.map(evidenceToken),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
        moon.strategyPublicationEvidenceWorkspace(limits.maxNodes),
        contentCaptures(evidence.contentGenerations),
      );
      return finishCapturedPreparation(preparation, signal, true);
    },
    retireCapturedComputation(capturedRun: unknown): undefined {
      token(capturedRun);
      const original = capturedComputationPreparations.get(capturedRun as object) as Readonly<{program?: unknown}> | undefined;
      if (original === undefined) return;
      // The publication operation owns this alias through reconciliation.
      // Cancel releases managed facts, not physical children or an ACK.
      if (original.program !== undefined) moon.clientProgramCancelCapture(original.program);
      else moon.strategyCapturedRunCancel(original);
      capturedComputationPreparations.delete(capturedRun as object);
    },
  };
  const effectfulCaptureControls = {
    async issueEffectfulCapturedRun(chain: CaptureChain, evidence: EffectCaptureEvidence, preview: unknown,
      plans: readonly CapturePlan[], limits: CaptureLimits, signal?: CaptureSignal) {
      limits = captureContractLimits(limits, 'Effectful Captured Run');
      if (chain === null || typeof chain !== 'object' ||
          evidence === null || typeof evidence !== 'object' ||
          !Array.isArray(chain.definitions) ||
          !Array.isArray(chain.artifacts) ||
          !Array.isArray(evidence.snapshots) ||
          !Array.isArray(evidence.effectSources) ||
          !Array.isArray(evidence.localEffectSources) ||
          !Array.isArray(evidence.pendingSourceStateAdvances) ||
          !Array.isArray(evidence.modelEvidence) ||
          (evidence.dependencyInventoryWire !== undefined &&
            typeof evidence.dependencyInventoryWire !== 'string') ||
          !Array.isArray(plans) ||
          plans.some(value => !value || typeof value.name !== 'string' ||
            typeof value.wire !== 'string')) {
        throw new TypeError('Invalid Effectful Captured Run request');
      }
      const ownedPreview = computationPreviewTokens.get(preview as object);
      if (ownedPreview === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      signal?.throwIfAborted();
      const original = evidence.dependencyConstruction === undefined ? undefined
        : installedEffectDependencyOriginal(evidence.dependencyConstruction, moon);
      if (original !== undefined) {
        const slots = chain.definitions.length + chain.artifacts.length + evidence.snapshots.length +
          evidence.effectSources.length + evidence.localEffectSources.length +
          evidence.pendingSourceStateAdvances.length + evidence.modelEvidence.length +
          (evidence.contentGenerations?.length ?? 0) + 2 * plans.length;
        if (!Number.isSafeInteger(slots) || slots > 2147483647) throw new RangeError('EffectCaptureInventoryLimit');
        checked(moon.clientProgramInstalledEffectDependencyCaptureReserve(original.parent, original.prepared,
          original.request, original.plan, token(chain.runDefinition), token(chain.invocation), slots));
        original.current();
      }
      const preparation = original === undefined ? checked(moon.strategyBeginEffectfulCapturedRun(
        token(chain.runDefinition), token(chain.invocation),
        chain.definitions.map(token), chain.artifacts.map(token),
        token(chain.manifest), token(chain.receipt),
        evidence.snapshots.map(snapshotToken),
        evidence.effectSources.map(effectSourceToken),
        evidence.localEffectSources.map(localEffectSourceToken),
        evidence.pendingSourceStateAdvances.map(sourceAdvanceToken),
        evidenceToken(evidence.authoringContext),
        evidence.modelEvidence.map(evidenceToken), ownedPreview,
        plans.map(value => value.name), plans.map(value => value.wire),
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
        evidence.dependencyInventoryWire,
        moon.strategyPublicationEvidenceWorkspace(limits.maxNodes),
        contentCaptures(evidence.contentGenerations),
      )) : checked(moon.clientProgramInstalledEffectDependencyCaptureBegin(
        original.parent, original.prepared, original.request, original.plan,
        token(chain.runDefinition), token(chain.invocation), chain.definitions.map(token),
        chain.artifacts.map(token), token(chain.manifest), token(chain.receipt),
        evidence.snapshots.map(snapshotToken), evidence.effectSources.map(effectSourceToken),
        evidence.localEffectSources.map(localEffectSourceToken),
        evidence.pendingSourceStateAdvances.map(sourceAdvanceToken), evidenceToken(evidence.authoringContext),
        evidence.modelEvidence.map(evidenceToken), ownedPreview,
        // retainCompletedEffectDependencyPayloads admits the wire with this installed owner.
        plans.map(value => value.name), plans.map(value => value.wire), evidence.dependencyInventoryWire as string,
        contentCaptures(evidence.contentGenerations), limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
      ));
      original?.current();
      const value = await finishCapturedPreparation(preparation, signal, false, original);
      original?.current();
      return value;
    },
  };
  return {capturedPreparationLimits, snapshotControls, effectFreeCaptureControls, effectfulCaptureControls};
}
