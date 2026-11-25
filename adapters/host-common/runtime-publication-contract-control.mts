import {checked} from './runtime-result.mjs';
import type {PublicationFrontierBounds} from './publication-capacity.mjs';

type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type Original = Readonly<{name: string; identity: string; identityField: string; wire: string}>;
type ResultChain = Readonly<{
  runDefinition: unknown; definition: unknown; invocation: unknown;
  artifact: unknown; ordering: unknown; retention: unknown;
}>;
type ResultPhysical = Readonly<{
  codecContractCid: string; resultFields: readonly string[]; resultSchemaWire: string;
  materialGenerationCid: string; storeAuthorityCid: string | undefined;
  rowCount: number; byteCount: number; physicalSha256: string;
}>;
type PublicationIntent = Readonly<{
  namespaceId: string; authorityScopeCid: string; publicationPolicyCid: string;
  publicationTargetCid: string; requestedAt: string;
}>;
type Attempt = Readonly<{
  attemptId: string; fenceCid: string; externalIdempotencyKey?: string; startedAt: string;
}>;
type EvidenceContext = Readonly<{
  computationContractCid: string; inputRelationCids: readonly string[];
  scopeCid: string; effectiveDataPolicyCid: string; authorityScopeCid: string;
}>;
type ReceiptPlan = Readonly<{
  admission: unknown; invocation: unknown; observation: unknown; normalizationJournal: unknown;
  receiptEvidence: Readonly<{
    bindings: readonly Readonly<{name: string; sha256: string}>[];
    sourceEvidence: readonly unknown[]; modelEvidence: readonly unknown[];
    barrierAttemptReceiptCids: readonly string[];
  }>;
}>;
type IndexChain = Readonly<{
  runDefinition: unknown; invocation: unknown; manifest: unknown; receipt: unknown; capturedRun: unknown;
  durableBindings: readonly unknown[]; request: unknown; attempt: unknown;
}>;
type RecordUpdate = Readonly<{
  state: string; observedAt: string; publicIndexEntry?: unknown; failureCid?: string;
  cleanupOwnerCids: readonly string[]; uncommittedConfirmed: boolean;
}>;

// Only Core owns the admitted contracts and evidence representations.
type CommonPublicationBindings = Readonly<{
  strategyPublicationRecordTransition(previous: unknown, next: unknown, uncommittedConfirmed: boolean): boolean;
  strategyPublicationRecordAllowsCommit(record: unknown): boolean;
  strategyRunPublicationChainValid(runDefinition: unknown, invocation: unknown,
    definitions: readonly unknown[], artifacts: readonly unknown[], manifest: unknown,
    maxWireBytes: number, maxNodes: number, maxDepth: number): boolean;
  strategyIssueResultManifest(runDefinition: unknown, invocation: unknown, definitions: readonly unknown[],
    artifacts: readonly unknown[], maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  strategyIssueDurableResultBinding(runDefinition: unknown, definition: unknown, invocation: unknown,
    artifact: unknown, ordering: unknown, retention: unknown, codecContractCid: string,
    resultFields: readonly string[], resultSchemaWire: string, materialGenerationCid: string,
    storeAuthorityCid: string, rowCount: number, byteCount: number, physicalSha256: string,
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  strategyResultPublicationContractByteBounds(inputRelationCids: readonly string[], maxSchemaBytes: number,
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  strategyOrdinaryPublicationReceiptByteBound(admission: unknown, request: unknown, invocation: unknown,
    observation: unknown, normalization: unknown, bindingNames: readonly string[], bindingDigests: readonly string[],
    sources: readonly unknown[], models: readonly unknown[], barriers: readonly string[],
    maxWireBytes: number, maxNodes: number, maxDepth: number): number;
  strategyOrdinaryPublicationFrontierByteBounds(request: unknown, resultCount: number,
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  strategyOrdinaryPublicationManifestByteBound(request: unknown,
    maxWireBytes: number, maxNodes: number, maxDepth: number): number;
  strategyIssuePublicationRequest(runDefinition: unknown, definitions: readonly unknown[],
    namespaceId: string, authorityScopeCid: string, publicationPolicyCid: string, publicationTargetCid: string,
    requestedAt: string, maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  strategyIssuePublicationAttempt(request: unknown, runDefinition: unknown, attemptId: string, fenceCid: string,
    externalIdempotencyKey: string | undefined, startedAt: string,
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  strategyPublicationPreflightValid(admission: unknown, runDefinition: unknown, invocation: unknown,
    definitions: readonly unknown[], retentions: readonly unknown[], computationContractCids: readonly string[],
    inputRelationCids: readonly (readonly string[])[], scopeCids: readonly string[],
    effectiveDataPolicyCids: readonly string[], authorityScopeCids: readonly string[],
    request: unknown, attempt: unknown, programDefinitionCid: string): boolean;
  strategyIssuePublicIndexEntry(runDefinition: unknown, invocation: unknown, manifest: unknown, receipt: unknown,
    capturedRun: unknown, durableBindings: readonly unknown[], request: unknown, attempt: unknown, committedAt: string,
    maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
  strategyPublicIndexSameCommittedContent(committed: unknown, candidate: unknown): boolean;
  strategyIssuePublicationRecord(attempt: unknown, previous: unknown, state: string, observedAt: string,
    publicIndexEntry: unknown, failureCid: string | undefined, cleanupOwnerCids: readonly string[],
    uncommittedConfirmed: boolean, maxWireBytes: number, maxNodes: number, maxDepth: number): unknown;
}>;

type PublicationPorts = Readonly<{
  token(value: unknown): unknown;
  admissionToken(value: unknown): unknown;
  evidenceToken(value: unknown): unknown;
  inspect(value: unknown, limits: Limits): Original;
  captureContractLimits(limits: Limits, label: string): Limits;
}>;

// Measurement and issuance share the existing publication owner's original
// contract, admission and evidence custody.
export function createPublicationContractControls(moon: CommonPublicationBindings, {
  token, admissionToken, evidenceToken, inspect, captureContractLimits,
}: PublicationPorts) {
  return {
    transitionControls: {
      recordTransition(previous: unknown, next: unknown, uncommittedConfirmed: boolean) {
        return moon.strategyPublicationRecordTransition(
          previous === undefined ? undefined : token(previous),
          token(next),
          uncommittedConfirmed,
        );
      },
      recordAllowsCommit(record: unknown) {
        return moon.strategyPublicationRecordAllowsCommit(token(record));
      },
    },
    contractControls: {
      runChainValid(runDefinition: unknown, invocation: unknown, definitions: readonly unknown[], artifacts: readonly unknown[],
        manifest: unknown, limits: Limits) {
        return moon.strategyRunPublicationChainValid(
          token(runDefinition),
          token(invocation),
          definitions.map(token),
          artifacts.map(token),
          token(manifest),
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        );
      },
      issueResultManifest(runDefinition: unknown, invocation: unknown, definitions: readonly unknown[], artifacts: readonly unknown[],
        limits: Limits) {
        limits = captureContractLimits(limits, 'Result Manifest');
        return inspect(checked(moon.strategyIssueResultManifest(
          token(runDefinition),
          token(invocation),
          definitions.map(token),
          artifacts.map(token),
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        )), limits);
      },
      issueDurableResultBinding(chain: ResultChain, physical: ResultPhysical, limits: Limits) {
        limits = captureContractLimits(limits, 'durable Result binding');
        if (chain === null || typeof chain !== 'object' ||
            physical === null || typeof physical !== 'object') {
          throw new TypeError('Invalid durable Result binding request');
        }
        return inspect(checked(moon.strategyIssueDurableResultBinding(
          token(chain.runDefinition),
          token(chain.definition),
          token(chain.invocation),
          token(chain.artifact),
          token(chain.ordering),
          token(chain.retention),
          physical.codecContractCid,
          physical.resultFields,
          physical.resultSchemaWire,
          physical.materialGenerationCid,
          physical.storeAuthorityCid as string,
          physical.rowCount,
          physical.byteCount,
          physical.physicalSha256,
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        )), limits);
      },
      resultPublicationContractByteBounds(inputRelationCids: unknown, maxSchemaBytes: number, limits: Limits) {
        limits = captureContractLimits(limits, 'Result publication capacity');
        if (!Array.isArray(inputRelationCids) ||
            !inputRelationCids.every(value => typeof value === 'string' &&
              /^sha256:[0-9a-f]{64}$/u.test(value)) ||
            !Number.isSafeInteger(maxSchemaBytes) || maxSchemaBytes < 0) {
          throw new TypeError('Invalid Result publication capacity');
        }
        const values = moon.strategyResultPublicationContractByteBounds(
          inputRelationCids, maxSchemaBytes, limits.maxWireBytes,
          limits.maxNodes, limits.maxDepth,
        );
        if (!Array.isArray(values) || values.length !== 4 ||
            !values.every(value => Number.isSafeInteger(value) && value >= 0 &&
              value <= limits.maxWireBytes)) {
          throw new TypeError('Invalid Result publication capacity projection');
        }
        return Object.freeze([...values] as number[]);
      },
      ordinaryPublicationReceiptByteBound(plan: ReceiptPlan, request: unknown, limits: Limits) {
        limits = captureContractLimits(limits, 'Publication receipt capacity');
        const provenance = plan.receiptEvidence;
        const value = moon.strategyOrdinaryPublicationReceiptByteBound(
          admissionToken(plan.admission), token(request), token(plan.invocation),
          evidenceToken(plan.observation), evidenceToken(plan.normalizationJournal),
          provenance.bindings.map(binding => binding.name),
          provenance.bindings.map(binding => binding.sha256),
          provenance.sourceEvidence.map(evidenceToken),
          provenance.modelEvidence.map(evidenceToken), provenance.barrierAttemptReceiptCids,
          limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
        );
        if (!Number.isSafeInteger(value) || value < 0 || value > limits.maxWireBytes) {
          throw new TypeError('Invalid publication receipt capacity projection');
        }
        return value;
      },
      ordinaryPublicationFrontierByteBounds(request: unknown, resultCount: number,
        limits: Limits): PublicationFrontierBounds & {readonly manifest: number} {
        limits = captureContractLimits(limits, 'Publication frontier capacity');
        if (!Number.isSafeInteger(resultCount) || resultCount < 0 || resultCount > 2147483647) {
          throw new TypeError('Invalid publication frontier inventory');
        }
        const values = moon.strategyOrdinaryPublicationFrontierByteBounds(
          token(request), resultCount, limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
        );
        if (!Array.isArray(values) || values.length !== 6 ||
            !values.every(value => Number.isSafeInteger(value) && value >= 0 &&
              value <= limits.maxWireBytes)) {
          throw new TypeError('Invalid publication frontier capacity projection');
        }
        const manifest = moon.strategyOrdinaryPublicationManifestByteBound(
          token(request), limits.maxWireBytes, limits.maxNodes, limits.maxDepth,
        );
        if (!Number.isSafeInteger(manifest) || manifest < 0 || manifest > limits.maxWireBytes) {
          throw new TypeError('Invalid publication manifest capacity projection');
        }
        return Object.freeze({
          manifest,
          index: values[0],
          current: Object.freeze({preparing: values[1], committing: values[2],
            publicationUnknown: values[3], terminal: values[4]}),
          possibleForeignWinnerTerminal: values[5],
        });
      },
      issuePublicationRequest(runDefinition: unknown, definitions: readonly unknown[], intent: PublicationIntent, limits: Limits) {
        limits = captureContractLimits(limits, 'Publication Request');
        if (intent === null || typeof intent !== 'object') {
          throw new TypeError('Invalid Publication Request intent');
        }
        return inspect(checked(moon.strategyIssuePublicationRequest(
          token(runDefinition),
          definitions.map(token),
          intent.namespaceId,
          intent.authorityScopeCid,
          intent.publicationPolicyCid,
          intent.publicationTargetCid,
          intent.requestedAt,
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        )), limits);
      },
      issuePublicationAttempt(request: unknown, runDefinition: unknown, attempt: Attempt, limits: Limits) {
        limits = captureContractLimits(limits, 'Publication Attempt');
        if (attempt === null || typeof attempt !== 'object') {
          throw new TypeError('Invalid Publication Attempt');
        }
        return inspect(checked(moon.strategyIssuePublicationAttempt(
          token(request),
          token(runDefinition),
          attempt.attemptId,
          attempt.fenceCid,
          attempt.externalIdempotencyKey,
          attempt.startedAt,
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        )), limits);
      },
      publicationPreflightValid(
        admission: unknown,
        runDefinition: unknown,
        invocation: unknown,
        definitions: readonly unknown[],
        retentions: readonly unknown[],
        evidenceContexts: readonly EvidenceContext[],
        request: unknown,
        attempt: unknown,
        programDefinitionCid: string,
      ) {
        return moon.strategyPublicationPreflightValid(
          admissionToken(admission),
          token(runDefinition),
          token(invocation),
          definitions.map(token),
          retentions.map(token),
          evidenceContexts.map(value => value.computationContractCid),
          evidenceContexts.map(value => value.inputRelationCids),
          evidenceContexts.map(value => value.scopeCid),
          evidenceContexts.map(value => value.effectiveDataPolicyCid),
          evidenceContexts.map(value => value.authorityScopeCid),
          token(request),
          token(attempt),
          programDefinitionCid,
        );
      },
      issuePublicIndexEntry(chain: IndexChain, committedAt: string, limits: Limits) {
        limits = captureContractLimits(limits, 'Public Index Entry');
        if (chain === null || typeof chain !== 'object' ||
            !Array.isArray(chain.durableBindings)) {
          throw new TypeError('Invalid publication chain');
        }
        return inspect(checked(moon.strategyIssuePublicIndexEntry(
          token(chain.runDefinition),
          token(chain.invocation),
          token(chain.manifest),
          token(chain.receipt),
          token(chain.capturedRun),
          chain.durableBindings.map(token),
          token(chain.request),
          token(chain.attempt),
          committedAt,
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        )), limits);
      },
      publicIndexSameCommittedContent(committed: unknown, candidate: unknown) {
        return moon.strategyPublicIndexSameCommittedContent(
          token(committed), token(candidate));
      },
      issuePublicationRecord(attempt: unknown, previous: unknown, update: RecordUpdate, limits: Limits) {
        limits = captureContractLimits(limits, 'Publication Record');
        if (update === null || typeof update !== 'object') {
          throw new TypeError('Invalid Publication Record update');
        }
        return inspect(checked(moon.strategyIssuePublicationRecord(
          token(attempt),
          previous === undefined ? undefined : token(previous),
          update.state,
          update.observedAt,
          update.publicIndexEntry === undefined
            ? undefined : token(update.publicIndexEntry),
          update.failureCid,
          update.cleanupOwnerCids,
          update.uncommittedConfirmed,
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        )), limits);
      },
    },
  };
}
