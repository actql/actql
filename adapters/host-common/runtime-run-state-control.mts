import {runtimeField} from './compiler-binding.generated.mjs';
import {checked} from './runtime-result.mjs';

type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type Receipts = Readonly<{setWire: string; memberWires: readonly string[]}>;
type EffectRun = Readonly<{runId: string; updatedAt: string; resultNames: readonly string[]}>;
type AvailabilityObservation = Readonly<{name: string; state: string; reason: string; observedAt: string}>;
type SucceededRun = Readonly<{runId: string; updatedAt: string; declaredResults: readonly string[];
  observations: readonly AvailabilityObservation[]}>;
type ModelDocument = Readonly<{kind: 'model-original-resource-document'; wire: string}>;

export type RunCancellationFacts = Readonly<{
  cancellationRequested: boolean;
  modelFenceRequired: boolean;
  modelFenced: boolean;
  unresolvedModelCalls: boolean;
  unresolvedEffects: boolean;
  reconciliationRequired: boolean;
  publicationCommitted: boolean;
  physicalStopConfirmed: boolean;
  cleanupConfirmed: boolean;
  revisionUnchanged: boolean;
}>;

// Opaque handles and Result variants are owned by the compiled Common.
type CommonRunStateBindings = Readonly<{
  strategyEffectSetReceiptRunDisposition(preview: unknown, setWire: string, memberWires: readonly string[],
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  strategyEffectReconciliationRunState(preview: unknown, setWire: string, memberWires: readonly string[],
    runId: string, updatedAt: string, declaredResults: readonly string[],
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  strategyRunDefinitionRunId(definition: unknown): unknown;
  clientLocalCheckpointRunLifetime(definition: unknown, expectedCid: string): unknown;
  clientProgramEncodeModelOriginalResourceDocument(originWire: string, stateWire: string, cutWire: string,
    phase: string, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramReadModelOriginalResourceDocument(wire: string,
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  clientProgramModelOriginalResourceOriginField(document: unknown, field: string): string | undefined;
  clientRunCancellationConfirmed(cancellationRequested: boolean, modelFenceRequired: boolean,
    modelFenced: boolean, unresolvedModelCalls: boolean, unresolvedEffects: boolean, reconciliationRequired: boolean,
    publicationCommitted: boolean, physicalStopConfirmed: boolean, cleanupConfirmed: boolean,
    revisionUnchanged: boolean): boolean;
  strategyPublicationSnapshotState(record: unknown, index: unknown): unknown;
  strategyIssueSucceededRunState(runId: string, updatedAt: string, declaredResults: readonly string[],
    names: readonly string[], states: readonly string[], reasons: readonly string[], observedAt: readonly string[],
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
}>;

type PublicationPorts = Readonly<{
  token(contract: unknown): unknown;
  issuanceLimits(limits: Limits, label: string): Limits;
  computationPreviewTokens: WeakMap<object, unknown>;
  modelOriginalDocumentTokens: WeakMap<ModelDocument, unknown>;
}>;

// The publication owner retains the existing identity maps, and Common
// issues each Run state and decides whether a cancellation is confirmed.
export function createRunStateControls(moon: CommonRunStateBindings, {
  token, issuanceLimits, computationPreviewTokens, modelOriginalDocumentTokens,
}: PublicationPorts) {
  return {
    effectRunStateControls: {
      effectSetReceiptRunDisposition(preview: object, receipts: Receipts, limits: Limits) {
        issuanceLimits(limits, 'Effect Set Run disposition');
        const ownedPreview = computationPreviewTokens.get(preview);
        if (ownedPreview === undefined ||
            typeof receipts?.setWire !== 'string' ||
            !Array.isArray(receipts.memberWires) ||
            receipts.memberWires.some(wire => typeof wire !== 'string')) {
          throw new TypeError('Invalid Effect Set Run disposition');
        }
        return checked(moon.strategyEffectSetReceiptRunDisposition(
          ownedPreview, receipts.setWire, receipts.memberWires,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
        )) as number;
      },
      // The public state of a Run whose complete admitted Effect Set has
      // unknown outcomes: `needs_reconciliation` naming exactly those Effects.
      effectReconciliationRunState(preview: object, receipts: Receipts, {runId, updatedAt,
        resultNames}: EffectRun, limits: Limits) {
        issuanceLimits(limits, 'Effect reconciliation Run state');
        const ownedPreview = computationPreviewTokens.get(preview);
        if (ownedPreview === undefined ||
            typeof receipts?.setWire !== 'string' ||
            !Array.isArray(receipts.memberWires) ||
            receipts.memberWires.some(wire => typeof wire !== 'string') ||
            !Array.isArray(resultNames) ||
            resultNames.some(name => typeof name !== 'string')) {
          throw new TypeError('Invalid Effect reconciliation Run state');
        }
        return checked(moon.strategyEffectReconciliationRunState(
          ownedPreview, receipts.setWire, receipts.memberWires, runId,
          updatedAt, resultNames, limits.maxWireBytes, limits.maxNodes,
          limits.maxDepth,
        )) as string;
      },
    },
    runIdentityControls: {
      runDefinitionRunId(runDefinition: unknown) {
        return checked(moon.strategyRunDefinitionRunId(token(runDefinition))) as string;
      },
      runDefinitionLifetime(runDefinition: unknown, expectedCid: string) {
        const lifetime = checked(moon.clientLocalCheckpointRunLifetime(
          token(runDefinition), expectedCid));
        return Object.freeze({createdAt: runtimeField(lifetime, 0) as string,
          validUntil: runtimeField(lifetime, 1) as string});
      },
      // The Common reader checks the exact canonical document and embedded
      // resource CID. This private handle carries data, never restored custody.
      encodeModelOriginalResourceDocument(originWire: string, stateWire: string, cutWire: string,
        phase: string, limits: Limits) {
        if (![originWire, stateWire, cutWire, phase].every(value => typeof value === 'string')) {
          throw new TypeError('Invalid original Model document inputs');
        }
        issuanceLimits(limits, 'Original Model document');
        const {maxWireBytes, maxNodes, maxDepth} = limits;
        return checked(moon.clientProgramEncodeModelOriginalResourceDocument(
          originWire, stateWire, cutWire, phase, maxWireBytes, maxNodes, maxDepth)) as string;
      },
      readModelOriginalResourceDocument(wire: string, limits: Limits) {
        if (typeof wire !== 'string') throw new TypeError('Invalid original Model document');
        issuanceLimits(limits, 'Original Model document');
        const {maxWireBytes, maxNodes, maxDepth} = limits;
        const document = checked(moon.clientProgramReadModelOriginalResourceDocument(
          wire, maxWireBytes, maxNodes, maxDepth));
        const view = Object.freeze({kind: 'model-original-resource-document', wire});
        modelOriginalDocumentTokens.set(view, document);
        return view;
      },
      modelOriginalResourceOriginField(document: ModelDocument, field: string) {
        const original = modelOriginalDocumentTokens.get(document);
        if (original === undefined) throw new TypeError('Foreign original Model document');
        if (typeof field !== 'string') throw new TypeError('Invalid original Model origin field');
        return moon.clientProgramModelOriginalResourceOriginField(original, field);
      },
      runCancellationConfirmed(facts: RunCancellationFacts) {
        const names = ['cancellationRequested', 'modelFenceRequired', 'modelFenced',
          'unresolvedModelCalls', 'unresolvedEffects', 'reconciliationRequired',
          'publicationCommitted', 'physicalStopConfirmed', 'cleanupConfirmed',
          'revisionUnchanged'] as const;
        if (names.some(name => typeof facts?.[name] !== 'boolean')) {
          throw new TypeError('Invalid Run cancellation observations');
        }
        return moon.clientRunCancellationConfirmed(...names.map(name => facts[name]) as
          Parameters<CommonRunStateBindings['clientRunCancellationConfirmed']>);
      },
    },
    publicationStateControls: {
      projectCommittedPublicationState(record: unknown, index: unknown) {
        return checked(moon.strategyPublicationSnapshotState(
          record === undefined ? undefined : token(record),
          token(index),
        )) as string;
      },
      issueSucceededRunState(request: SucceededRun, limits: Limits) {
        issuanceLimits(limits, 'Succeeded Run state');
        if (request === null || typeof request !== 'object' ||
            typeof request.runId !== 'string' ||
            typeof request.updatedAt !== 'string' ||
            !Array.isArray(request.declaredResults) ||
            !Array.isArray(request.observations)) {
          throw new TypeError('Invalid succeeded Run state');
        }
        const names = [];
        const states = [];
        const reasons = [];
        const observedAt = [];
        for (const observation of request.observations) {
          if (observation === null || typeof observation !== 'object' ||
              typeof observation.name !== 'string' ||
              typeof observation.state !== 'string' ||
              typeof observation.reason !== 'string' ||
              typeof observation.observedAt !== 'string') {
            throw new TypeError('Invalid Result availability observation');
          }
          names.push(observation.name);
          states.push(observation.state);
          reasons.push(observation.reason);
          observedAt.push(observation.observedAt);
        }
        return checked(moon.strategyIssueSucceededRunState(
          request.runId,
          request.updatedAt,
          request.declaredResults,
          names,
          states,
          reasons,
          observedAt,
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        )) as string;
      },
    },
  };
}
