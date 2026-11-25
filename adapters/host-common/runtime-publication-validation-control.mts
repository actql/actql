import {checked} from './runtime-result.mjs';
import {tuplePair} from './runtime-tuple.mjs';

type ValidationLimits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type ValidationSignal = Pick<AbortSignal, 'throwIfAborted'>;
type PreparationView = Readonly<{program?: unknown}>;
type EffectCommitChain = Readonly<{
  runDefinition: unknown;
  invocation: unknown;
  definitions: readonly unknown[];
  artifacts: readonly unknown[];
  derivations: readonly unknown[];
  orderings: readonly unknown[];
  retentions: readonly unknown[];
  durableBindings: readonly unknown[];
  manifest: unknown;
  computationReceipt: unknown;
  capturedRun: unknown;
}>;
type EffectCommitReceipts = Readonly<{
  setWire: string;
  finalWire: string;
  memberWires: readonly string[];
}>;

// Generated Common handles and raw Result variants stay opaque until their existing checks.
type CommonPublicationValidationBindings = Readonly<{
  clientProgramAdvanceValidation(validation: unknown, quantum: number): unknown;
  clientProgramCancelValidation(validation: unknown): undefined;
  clientProgramFinishValidation(validation: unknown): unknown;
  clientProgramPrepareChainValidation(capture: unknown, definition: unknown, invocation: unknown,
    definitions: unknown, artifacts: unknown, manifest: unknown, receipt: unknown, capturedRun: unknown): unknown;
  clientProgramPrepareCommitValidation(capture: unknown, definition: unknown, invocation: unknown,
    definitions: unknown, artifacts: unknown, derivations: unknown, orderings: unknown, retentions: unknown,
    bindings: unknown, manifest: unknown, receipt: unknown, capturedRun: unknown, request: unknown,
    attempt: unknown, index: unknown): unknown;
  clientProgramPreparedEffectfulPublicationCommitValid(runDefinition: unknown, invocation: unknown,
    definitions: unknown, artifacts: unknown, derivations: unknown, orderings: unknown, retentions: unknown,
    durableBindings: unknown, manifest: unknown, computationReceipt: unknown, capturedRun: unknown,
    prepared: unknown, preview: unknown, setReceiptWire: string, memberReceiptWires: unknown,
    finalReceiptWire: string, request: unknown, attempt: unknown, indexEntry: unknown, maxWireBytes: number,
    maxNodes: number, maxDepth: number): boolean;
  clientProgramStartValidation(validation: unknown): unknown;
  clientStoreAdvanceOriginalValidation(value: unknown, quantum: number): unknown;
  clientStoreBeginOriginalCommitValidation(definition: unknown, invocation: unknown, definitions: unknown,
    artifacts: unknown, derivations: unknown, orderings: unknown, retentions: unknown, bindings: unknown,
    manifest: unknown, receipt: unknown, capturedRun: unknown, request: unknown, attempt: unknown,
    index: unknown): unknown;
  clientStoreCancelOriginalValidation(value: unknown): undefined;
  clientStoreFinishOriginalValidation(value: unknown): unknown;
  strategyBeginEffectFreeChainCheck(runDefinition: unknown, invocation: unknown, definitions: unknown,
    artifacts: unknown, manifest: unknown, receipt: unknown, capturedRun: unknown, maxWireBytes: number,
    maxNodes: number, maxDepth: number, maxWorkspace: number): unknown;
  strategyBeginEffectFreeChainCheckRetained(original: unknown, runDefinition: unknown, invocation: unknown,
    definitions: unknown, artifacts: unknown, manifest: unknown, receipt: unknown, capturedRun: unknown,
    maxWireBytes: number, maxNodes: number, maxDepth: number, maxWorkspace: number): unknown;
  strategyBeginEffectFreeCommitCheck(runDefinition: unknown, invocation: unknown, definitions: unknown,
    artifacts: unknown, derivations: unknown, orderings: unknown, retentions: unknown, durableBindings: unknown,
    manifest: unknown, receipt: unknown, capturedRun: unknown, request: unknown, attempt: unknown,
    indexEntry: unknown, maxWireBytes: number, maxNodes: number, maxDepth: number, maxWorkspace: number): unknown;
  strategyBeginEffectFreeCommitCheckRetained(original: unknown, runDefinition: unknown, invocation: unknown,
    definitions: unknown, artifacts: unknown, derivations: unknown, orderings: unknown, retentions: unknown,
    durableBindings: unknown, manifest: unknown, receipt: unknown, capturedRun: unknown, request: unknown,
    attempt: unknown, indexEntry: unknown, maxWireBytes: number, maxNodes: number, maxDepth: number,
    maxWorkspace: number): unknown;
  strategyEffectFreeChainCheckAdvance(preparation: unknown, quantum: number): number;
  strategyEffectFreeChainCheckCancel(preparation: unknown): undefined;
  strategyEffectFreeChainCheckFinish(preparation: unknown): boolean;
  strategyEffectFreeCommitCheckAdvance(preparation: unknown, quantum: number): number;
  strategyEffectFreeCommitCheckCancel(preparation: unknown): undefined;
  strategyEffectFreeCommitCheckFinish(preparation: unknown): boolean;
  strategyEffectfulPublicationCommitValid(runDefinition: unknown, invocation: unknown, definitions: unknown,
    artifacts: unknown, derivations: unknown, orderings: unknown, retentions: unknown, durableBindings: unknown,
    manifest: unknown, computationReceipt: unknown, capturedRun: unknown, preview: unknown,
    setReceiptWire: string, memberReceiptWires: unknown, finalReceiptWire: string, request: unknown,
    attempt: unknown, indexEntry: unknown, maxWireBytes: number, maxNodes: number, maxDepth: number): boolean;
  strategyPublicationEvidenceWorkspace(maxNodes: number): number;
}>;

type PublicationValidationPorts = Readonly<{
  capturedComputationPreparations: WeakMap<object, unknown>;
  recoveredEffectCaptures: WeakMap<object, unknown>;
  computationPreviewTokens: WeakMap<object, unknown>;
  token: (reference: unknown) => unknown;
  issuanceLimits: (limits: ValidationLimits, label: string) => ValidationLimits;
  capturedPreparationLimits: (preparation: unknown) => ValidationLimits;
}>;

export function createPublicationValidationControls(moon: CommonPublicationValidationBindings, {
  capturedComputationPreparations, recoveredEffectCaptures, computationPreviewTokens,
  token, issuanceLimits, capturedPreparationLimits,
}: PublicationValidationPorts) {
  const finishProgramValidation = async (validation: unknown, signal?: ValidationSignal,
    requireCurrent?: () => unknown) => {
    try {
      requireCurrent?.();
      checked(moon.clientProgramStartValidation(validation));
      while (true) {
        signal?.throwIfAborted();
        requireCurrent?.();
        const progress = tuplePair(checked(
          moon.clientProgramAdvanceValidation(validation, 256)));
        if (!Array.isArray(progress) || progress.length !== 2 ||
            typeof progress[0] !== 'boolean' ||
            !Number.isSafeInteger(progress[1]) || progress[1] < 0) {
          throw new TypeError('Invalid original publication validation progress');
        }
        if (progress[0]) {
          signal?.throwIfAborted();
          requireCurrent?.();
          checked(moon.clientProgramFinishValidation(validation));
          return true;
        }
        await new Promise(resolve => typeof setImmediate === 'function'
          ? setImmediate(resolve) : setTimeout(resolve, 0));
      }
    } finally {
      moon.clientProgramCancelValidation(validation);
    }
  };
  const finishStoreValidation = async (validation: unknown, requireCurrent: () => unknown) => {
    try {
      while (true) {
        requireCurrent();
        const progress = tuplePair(checked(
          moon.clientStoreAdvanceOriginalValidation(validation, 256)));
        if (!Array.isArray(progress) || progress.length !== 2 ||
            typeof progress[0] !== 'boolean' ||
            !Number.isSafeInteger(progress[1]) || progress[1] < 0) {
          throw new TypeError('Invalid original Store validation progress');
        }
        if (progress[0]) {
          requireCurrent();
          checked(moon.clientStoreFinishOriginalValidation(validation));
          return true;
        }
        await new Promise(resolve => typeof setImmediate === 'function'
          ? setImmediate(resolve) : setTimeout(resolve, 0));
      }
    } finally {
      moon.clientStoreCancelOriginalValidation(validation);
    }
  };
  const finishPublicationValidation = async (
    preparation: unknown, advance: (preparation: unknown, quantum: number) => number,
    finish: (preparation: unknown) => boolean, cancel: (preparation: unknown) => undefined,
    signal?: ValidationSignal,
  ) => {
    try {
      while (true) {
        signal?.throwIfAborted();
        const progress = advance(preparation, 256);
        if (progress === -1) return false;
        if (progress === 1) {
          signal?.throwIfAborted();
          return finish(preparation);
        }
        if (progress !== 0) {
          throw new TypeError('Invalid publication validation progress');
        }
        await new Promise(resolve => typeof setImmediate === 'function'
          ? setImmediate(resolve) : setTimeout(resolve, 0));
      }
    } finally {
      cancel(preparation);
    }
  };
  return {
    async effectFreeChainValid(runDefinition: unknown, invocation: unknown,
      definitions: readonly unknown[], artifacts: readonly unknown[], manifest: unknown,
      receipt: unknown, capturedRun: unknown, limits: ValidationLimits, signal?: ValidationSignal) {
      issuanceLimits(limits, 'Effect-free chain validation');
      signal?.throwIfAborted();
      const original = capturedComputationPreparations.get(capturedRun as object) as PreparationView | undefined;
      if (original?.program !== undefined) {
        const validation = checked(moon.clientProgramPrepareChainValidation(
          original.program, token(runDefinition), token(invocation),
          definitions.map(token), artifacts.map(token), token(manifest),
          token(receipt), token(capturedRun),
        ));
        return finishProgramValidation(validation, signal);
      }
      if (original !== undefined) limits = capturedPreparationLimits(original);
      const args = [
        token(runDefinition),
        token(invocation),
        definitions.map(token),
        artifacts.map(token),
        token(manifest),
        token(receipt),
        token(capturedRun),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
        moon.strategyPublicationEvidenceWorkspace(limits.maxNodes),
      ] as const;
      const preparation = original === undefined
        ? moon.strategyBeginEffectFreeChainCheck(...args)
        : moon.strategyBeginEffectFreeChainCheckRetained(original, ...args);
      return finishPublicationValidation(preparation,
        moon.strategyEffectFreeChainCheckAdvance,
        moon.strategyEffectFreeChainCheckFinish,
        moon.strategyEffectFreeChainCheckCancel, signal);
    },
    // The selected Store read owns this full-original validation operation.
    // No preparation owner is reconstructed after reopen and no metadata
    // ceiling is reused for a larger independently admitted contract.
    async effectFreeStoredCommitValid(runDefinition: unknown, invocation: unknown,
      definitions: readonly unknown[], artifacts: readonly unknown[], derivations: readonly unknown[],
      orderings: readonly unknown[], retentions: readonly unknown[], durableBindings: readonly unknown[],
      manifest: unknown, receipt: unknown, capturedRun: unknown, request: unknown, attempt: unknown,
      indexEntry: unknown, requireCurrent: () => unknown) {
      if (typeof requireCurrent !== 'function') {
        throw new TypeError('Store publication validation owner unavailable');
      }
      requireCurrent();
      const retained = capturedComputationPreparations.get(capturedRun as object) as PreparationView | undefined;
      if (retained?.program !== undefined) {
        const validation = checked(moon.clientProgramPrepareCommitValidation(
          retained.program, token(runDefinition), token(invocation),
          definitions.map(token), artifacts.map(token), derivations.map(token),
          orderings.map(token), retentions.map(token), durableBindings.map(token),
          token(manifest), token(receipt), token(capturedRun), token(request),
          token(attempt), token(indexEntry),
        ));
        return finishProgramValidation(validation, undefined, requireCurrent);
      }
      const validation = checked(moon.clientStoreBeginOriginalCommitValidation(
        token(runDefinition), token(invocation), definitions.map(token),
        artifacts.map(token), derivations.map(token), orderings.map(token),
        retentions.map(token), durableBindings.map(token), token(manifest),
        token(receipt), token(capturedRun), token(request), token(attempt),
        token(indexEntry),
      ));
      return finishStoreValidation(validation, requireCurrent);
    },
    async effectFreeCommitValid(runDefinition: unknown, invocation: unknown,
      definitions: readonly unknown[], artifacts: readonly unknown[], derivations: readonly unknown[],
      orderings: readonly unknown[], retentions: readonly unknown[], durableBindings: readonly unknown[],
      manifest: unknown, receipt: unknown, capturedRun: unknown, request: unknown, attempt: unknown,
      indexEntry: unknown, limits: ValidationLimits) {
      issuanceLimits(limits, 'Effect-free commit validation');
      const original = capturedComputationPreparations.get(capturedRun as object) as PreparationView | undefined;
      if (original?.program !== undefined) {
        const validation = checked(moon.clientProgramPrepareCommitValidation(
          original.program, token(runDefinition), token(invocation),
          definitions.map(token), artifacts.map(token), derivations.map(token),
          orderings.map(token), retentions.map(token), durableBindings.map(token),
          token(manifest), token(receipt), token(capturedRun), token(request),
          token(attempt), token(indexEntry),
        ));
        // Commit reconciliation remains authoritative after cancellation.
        return finishProgramValidation(validation);
      }
      if (original !== undefined) limits = capturedPreparationLimits(original);
      const args = [
        token(runDefinition),
        token(invocation),
        definitions.map(token),
        artifacts.map(token),
        derivations.map(token),
        orderings.map(token),
        retentions.map(token),
        durableBindings.map(token),
        token(manifest),
        token(receipt),
        token(capturedRun),
        token(request),
        token(attempt),
        token(indexEntry),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
        moon.strategyPublicationEvidenceWorkspace(limits.maxNodes),
      ] as const;
      const preparation = original === undefined
        ? moon.strategyBeginEffectFreeCommitCheck(...args)
        : moon.strategyBeginEffectFreeCommitCheckRetained(original, ...args);
      // A committed outcome is authoritative even after request cancellation.
      return finishPublicationValidation(preparation,
        moon.strategyEffectFreeCommitCheckAdvance,
        moon.strategyEffectFreeCommitCheckFinish,
        moon.strategyEffectFreeCommitCheckCancel);
    },
    effectfulCommitValid(chain: EffectCommitChain, preview: unknown, receipts: EffectCommitReceipts,
      request: unknown, attempt: unknown, indexEntry: unknown, limits: ValidationLimits) {
      issuanceLimits(limits, 'Effectful publication commit');
      if (chain === null || typeof chain !== 'object' ||
          !(['definitions', 'artifacts', 'derivations', 'orderings',
            'retentions', 'durableBindings'] as const).every(name =>
            Array.isArray(chain[name])) ||
          receipts === null || typeof receipts !== 'object' ||
          typeof receipts.setWire !== 'string' ||
          typeof receipts.finalWire !== 'string' ||
          !Array.isArray(receipts.memberWires) ||
          receipts.memberWires.some(wire => typeof wire !== 'string')) {
        throw new TypeError('Invalid Effectful publication commit');
      }
      const ownedPreview = computationPreviewTokens.get(preview as object);
      if (ownedPreview === undefined) {
        throw new TypeError('Foreign Effect computation Preview');
      }
      const prepared = recoveredEffectCaptures.get(chain.capturedRun as object);
      return prepared === undefined ? moon.strategyEffectfulPublicationCommitValid(
        token(chain.runDefinition), token(chain.invocation),
        chain.definitions.map(token), chain.artifacts.map(token),
        chain.derivations.map(token), chain.orderings.map(token),
        chain.retentions.map(token), chain.durableBindings.map(token),
        token(chain.manifest), token(chain.computationReceipt),
        token(chain.capturedRun), ownedPreview, receipts.setWire,
        receipts.memberWires, receipts.finalWire, token(request),
        token(attempt), token(indexEntry), limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth,
      ) : moon.clientProgramPreparedEffectfulPublicationCommitValid(
        token(chain.runDefinition), token(chain.invocation),
        chain.definitions.map(token), chain.artifacts.map(token),
        chain.derivations.map(token), chain.orderings.map(token),
        chain.retentions.map(token), chain.durableBindings.map(token),
        token(chain.manifest), token(chain.computationReceipt),
        token(chain.capturedRun), prepared, ownedPreview, receipts.setWire,
        receipts.memberWires, receipts.finalWire, token(request),
        token(attempt), token(indexEntry), limits.maxWireBytes,
        limits.maxNodes, limits.maxDepth,
      );
    },
  };
}
