import {runtimeField, runtimeUnboxedReferenceOption} from './compiler-binding.generated.mjs';
import {checked} from './runtime-result.mjs';

type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type EffectRunDefinition = Readonly<{identity: string}>;
type EffectAuthoring = Readonly<{identity: string}>;
type SubmittedStop = Readonly<{intent: unknown; referenceWire: string}>;
type ReviewPolicy = Readonly<{authorityScopeCid: string; approvalClaims: unknown; redactionPolicyCid: string}>;
type Evidence = Readonly<{name: string; identity: string; wire: string}>;

// The compiler treats these checked results and owner tokens as opaque.
type CommonEffectPreviewBindings = Readonly<{
  clientProgramEffectReviewOriginalConstructionCapacity(original: unknown, previewWire: string,
    previewBytes: number, previewNodes: number, previewDepth: number, reviewBytes: number,
    reviewNodes: number, reviewDepth: number): import('./runtime-result.mjs').SynchronousRuntimeData;
  clientProgramInstalledEffectRecoveredInputInventoryRetain(owner: unknown, prepared: unknown,
    request: unknown, plan: unknown, allowed: unknown, definition: unknown, invocation: unknown,
    preview: unknown): unknown;
  clientProgramInstalledEffectRecoveredPreviewKeys(owner: unknown, prepared: unknown,
    request: unknown, plan: unknown, allowed: unknown, definition: unknown, invocation: unknown,
    preview: unknown, scope: unknown, maxMembers: number, maxRows: number, maxWork: number,
    maxKeyBytes: number, maxKeyNodes: number, maxKeyDepth: number): unknown;
  clientProgramProjectEffectReview(original: unknown, previewWire: string, authorityScopeCid: string,
    approvalClaims: unknown, redactionPolicyCid: string, maxBytes: number, maxNodes: number,
    maxDepth: number, previewMaxBytes: number | undefined, previewMaxNodes: number | undefined,
    previewMaxDepth: number | undefined): unknown;
  clientProgramRequestedEffectStopCheckpoint(original: unknown, bodyWire: string,
    continuationWire: string, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramRequestedEffectStopIntentCid(original: unknown): string;
  clientProgramRequestedEffectStopLifetime(original: unknown): unknown;
  clientProgramRestoreRequestedEffectStop(intent: unknown, referenceWire: string, request: unknown,
    materials: unknown, invocation: unknown, preview: unknown, limits: unknown): unknown;
  strategyAdmitEffectComputationPreview(previewWire: string, runIdentityCid: string,
    authoringContextCid: string, maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  strategyAdmitPendingSourceStateAdvance(completeWire: string, observation: unknown,
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  strategyEffectComputationCaptureHoldingCid(runDefinition: unknown, storeAuthorityCid: string): unknown;
  strategyEffectComputationRecordHoldingCid(runDefinition: unknown, storeAuthorityCid: string): unknown;
  strategyEffectPreviewPrivateHoldingCid(preview: unknown, storeAuthorityCid: string): unknown;
  strategyEffectPreviewSemanticCid(preview: unknown): string;
}>;

type RecoverKeys = CommonEffectPreviewBindings['clientProgramInstalledEffectRecoveredPreviewKeys'];
type PreviewConstruction = (receiver: CommonEffectPreviewBindings, method: RecoverKeys,
  args: Parameters<RecoverKeys>) => unknown;
type EffectPreviewPorts = Readonly<{
  computationPreviewTokens: WeakMap<object, unknown>;
  computationPreviewWires: WeakMap<object, string>;
  issuanceLimits: (limits: Limits, label: string) => Limits;
  token: (value: unknown) => unknown;
  evidenceToken: (value: unknown) => unknown;
  inspectEvidence: (value: unknown) => Evidence;
  inspectSourceAdvance: (value: unknown) => Readonly<{kind: 'pending-source-state-advance'}>;
}>;

export function createEffectPreviewControls(moon: CommonEffectPreviewBindings, {
  computationPreviewTokens, computationPreviewWires, issuanceLimits, token,
  evidenceToken, inspectEvidence, inspectSourceAdvance,
}: EffectPreviewPorts) {
  const pendingSourceAdvanceControls = {
    admitPendingSourceStateAdvance(completeWire: unknown, observation: unknown, limits: Limits) {
      issuanceLimits(limits, 'pending source-state advance');
      if (typeof completeWire !== 'string') {
        throw new TypeError('Invalid pending source-state advance');
      }
      return inspectSourceAdvance(checked(
        moon.strategyAdmitPendingSourceStateAdvance(
          completeWire,
          evidenceToken(observation),
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        ),
      ));
    },
  };
  const effectPreviewControls = {
    admitEffectComputationPreview(wire: unknown, runDefinition: EffectRunDefinition,
      authoring: EffectAuthoring | undefined, limits: Limits) {
      issuanceLimits(limits, 'Effect computation Preview');
      if (typeof wire !== 'string' ||
          typeof authoring?.identity !== 'string') {
        throw new TypeError('Invalid Effect computation Preview');
      }
      token(runDefinition);
      evidenceToken(authoring);
      const preview = checked(moon.strategyAdmitEffectComputationPreview(
        wire, runDefinition.identity,
        authoring.identity,
        limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
      ));
      const owned = Object.freeze({kind: 'effect-computation-preview'});
      computationPreviewTokens.set(owned, preview);
      computationPreviewWires.set(owned, wire);
      return owned;
    },
    effectComputationPreviewLedgerIdentity(preview: unknown) {
      const admitted = computationPreviewTokens.get(preview as object);
      if (admitted === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return admitted;
    },
    retainInstalledEffectRecoveredInputInventory(run: unknown, prepared: unknown, request: unknown,
      plan: unknown, allowed: unknown, definition: unknown, invocation: unknown, preview: unknown) {
      const admitted = computationPreviewTokens.get(preview as object);
      if (admitted === undefined) throw new TypeError('Foreign Effect computation Preview');
      return checked(moon.clientProgramInstalledEffectRecoveredInputInventoryRetain(
        run, prepared, request, plan, allowed, definition, token(invocation), admitted));
    },
    recoverInstalledEffectPreviewKeys(run: unknown, prepared: unknown, request: unknown, plan: unknown,
      allowed: unknown, definition: unknown, invocation: unknown, preview: unknown, scope: unknown,
      maxMembers: number, maxRows: number, maxWork: number, maxKeyBytes: number, maxKeyNodes: number,
      maxKeyDepth: number, construction: PreviewConstruction) {
      const admitted = computationPreviewTokens.get(preview as object);
      if (admitted === undefined) throw new TypeError('Foreign Effect computation Preview');
      if (typeof construction !== 'function') throw new TypeError('Missing original Effect construction');
      return checked(construction(moon, moon.clientProgramInstalledEffectRecoveredPreviewKeys, [
        run, prepared, request, plan, allowed, definition, token(invocation), admitted, scope,
        maxMembers, maxRows, maxWork, maxKeyBytes, maxKeyNodes, maxKeyDepth])) as readonly (readonly unknown[])[];
    },
    effectComputationPreviewSemanticCid(preview: unknown) {
      const admitted = computationPreviewTokens.get(preview as object);
      if (admitted === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return moon.strategyEffectPreviewSemanticCid(admitted);
    },
    effectComputationPreviewWire(preview: unknown) {
      const wire = computationPreviewWires.get(preview as object);
      if (wire === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return wire;
    },
    effectComputationReviewConstructionCapacity(preview: unknown, limits: Limits,
      previewLimits: Limits = limits) {
      issuanceLimits(limits, 'Effect review projection');
      issuanceLimits(previewLimits, 'Effect review Preview');
      // SAME private admission key: the identity and immutable wire cannot be
      // supplied independently or replaced by a copied/equal-CID Preview.
      const original = computationPreviewTokens.get(preview as object);
      const wire = computationPreviewWires.get(preview as object);
      if (original === undefined || wire === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return moon.clientProgramEffectReviewOriginalConstructionCapacity(original,
        wire, previewLimits.maxWireBytes, previewLimits.maxNodes,
        previewLimits.maxDepth, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth);
    },
    projectEffectComputationReview(preview: unknown, policy: ReviewPolicy, limits: Limits,
      previewLimits: Limits = limits) {
      issuanceLimits(limits, 'Effect review projection');
      issuanceLimits(previewLimits, 'Effect review Preview');
      const original = computationPreviewTokens.get(preview as object);
      const wire = computationPreviewWires.get(preview as object);
      if (original === undefined || wire === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return inspectEvidence(checked(moon.clientProgramProjectEffectReview(
        original, wire, policy.authorityScopeCid, policy.approvalClaims,
        policy.redactionPolicyCid, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth, previewLimits.maxWireBytes, previewLimits.maxNodes,
        previewLimits.maxDepth)));
    },
    // Private original Client/Checkpoint binding. These operations accept the
    // Common-issued opaque view, never a wire/CID reconstructed substitute.
    requestedEffectStopLifetime(original: unknown) {
      const lifetime = checked(moon.clientProgramRequestedEffectStopLifetime(original));
      return Object.freeze({createdAt: runtimeField(lifetime, 0) as string,
        validUntil: runtimeField(lifetime, 1) as string});
    },
    requestedEffectStopIntentCid(original: unknown) {
      return moon.clientProgramRequestedEffectStopIntentCid(original);
    },
    restoreRequestedEffectStop(original: SubmittedStop, identity: unknown, materials: unknown,
      invocation: unknown, preview: unknown, limits: unknown) {
      const admitted = computationPreviewTokens.get(preview as object);
      if (admitted === undefined) throw new TypeError('Foreign Effect computation Preview');
      return runtimeUnboxedReferenceOption(checked(moon.clientProgramRestoreRequestedEffectStop(
        original.intent, original.referenceWire, identity, materials,
        token(invocation), admitted, limits)));
    },
    sealRequestedEffectStop(original: unknown, bodyWire: string, continuationWire: string, limits: Limits) {
      issuanceLimits(limits, 'Requested Effect stop');
      return checked(moon.clientProgramRequestedEffectStopCheckpoint(original,
        bodyWire, continuationWire, limits.maxWireBytes, limits.maxNodes,
        limits.maxDepth)) as string;
    },
    effectPrivateEvidenceBinding(preview: unknown, storeAuthorityCid: string) {
      const ownedPreview = computationPreviewTokens.get(preview as object);
      if (ownedPreview === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      return Object.freeze({
        name: 'effect_preview',
        semanticCid: moon.strategyEffectPreviewSemanticCid(ownedPreview),
        holdingCid: checked(moon.strategyEffectPreviewPrivateHoldingCid(
          ownedPreview, storeAuthorityCid,
        )) as string,
        // Preview admission records the token and wire under the same original key.
        wire: computationPreviewWires.get(preview as object)!,
      });
    },
    effectComputationCaptureHoldingCid(runDefinition: unknown, storeAuthorityCid: string) {
      if (typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid Effect computation capture holding');
      }
      return checked(moon.strategyEffectComputationCaptureHoldingCid(
        token(runDefinition), storeAuthorityCid,
      )) as string;
    },
    effectComputationRecordHoldingCid(runDefinition: unknown, storeAuthorityCid: string) {
      if (typeof storeAuthorityCid !== 'string') {
        throw new TypeError('Invalid Effect computation record holding');
      }
      return checked(moon.strategyEffectComputationRecordHoldingCid(
        token(runDefinition), storeAuthorityCid,
      )) as string;
    },
  };
  return {pendingSourceAdvanceControls, effectPreviewControls};
}
