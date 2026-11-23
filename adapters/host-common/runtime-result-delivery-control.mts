import {checked} from './runtime-result.mjs';
import type {PublicationContract} from '../store-local/publication-contract-store.mjs';

type Limits = Readonly<{maxWireBytes: number; maxNodes: number; maxDepth: number}>;
type FrameLimits = Readonly<{maxBytes: number; maxRows: number; maxRowBytes: number;
  maxDepth: number; maxFrameBytes: number}>;
type Grant = Readonly<{principalId: string; purpose: string; dataCeilingCid: string;
  maxBytes: number; maxUses: number; expiresAt: string; authorizationContextCid: string}>;
type ResultGrant = Grant & Readonly<{resultNames: readonly string[]; formats: readonly string[];
  egressAdmissionCid: string}>;
type AttemptRequest = Readonly<{resultName: string; format: string; attemptId: string; requestedAt: string}>;
type OriginalDeliveryAttempt = Readonly<{kind: 'issued-delivery-attempt'}>;
type DeliveryFacts = Readonly<{index: unknown; manifest: unknown; grant: PublicationContract;
  attempt: PublicationContract; request: AttemptRequest; limits: Limits}>;
type IssuedDelivery = Readonly<{original: OriginalDeliveryAttempt; index: unknown;
  manifest: unknown; grant: unknown}>;
type DeliverySummary = Readonly<{byteCount: number; sha256: string}>;
type DeliveryRecord = Readonly<{state: string; confirmedByteCount: number; exposure: string;
  possibleUnconfirmedMaxBytes?: number; deliveredSha256?: string; receipt?: unknown;
  failureCid?: string; observedAt: string; cleanupOwnerCids: readonly string[]}>;

type CommonResultDeliveryBindings = {
  strategyBeginResultDelivery(serializer: unknown): unknown;
  strategyCancelDurableResultRowFrames(frames: unknown): void;
  strategyDeliveryRecordTransition(previous: unknown, next: unknown): boolean;
  strategyDeliveryResultDefinitionCid(manifest: unknown, attempt: unknown): unknown;
  strategyDeliverySuccessValid(attempt: unknown, receipt: unknown, record: unknown): boolean;
  strategyDescribeCommittedResult(
    index: unknown, manifest: unknown, resultName: string, bindings: readonly unknown[],
    definition: unknown, schemaWire: string, format: string, maxWireBytes: number, maxNodes: number,
    maxDepth: number,
  ): unknown;
  strategyDurableResultRowFrameGrowth(frames: unknown, bytes: number): unknown;
  strategyFeedDurableResultRowFrames(frames: unknown, chunk: Uint8Array): unknown;
  strategyFinishDurableResultRowFrames(frames: unknown): unknown;
  strategyFinishResultDelivery(serializer: unknown): unknown;
  strategyGrowDurableResultRowFrameBuffer(frames: unknown, bytes: number): unknown;
  strategyIssueDeliveryAttempt(
    index: unknown, manifest: unknown, grant: unknown, resultName: string, format: string,
    attemptId: string, requestedAt: string, maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyIssueDeliveryRecord(
    attempt: unknown, previous: unknown, state: string, confirmedByteCount: number, exposure: string,
    possibleUnconfirmedMaxBytes: number | undefined, deliveredSha256: string | undefined,
    receipt: unknown, failureCid: string | undefined, observedAt: string,
    cleanupOwnerCids: readonly string[], maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyIssueManifestReadGrant(
    index: unknown, manifest: unknown, principalId: string, purpose: string, dataCeilingCid: string,
    maxBytes: number, maxUses: number, expiresAt: string, authorizationContextCid: string,
    maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyIssueResultDeliveryReceipt(
    index: unknown, manifest: unknown, grant: unknown, attempt: unknown, deliveredByteCount: number,
    deliveredSha256: string, maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyIssueResultReadGrant(
    index: unknown, manifest: unknown, resultNames: readonly string[], formats: readonly string[],
    principalId: string, purpose: string, dataCeilingCid: string, maxBytes: number, maxUses: number,
    expiresAt: string, authorizationContextCid: string, egressAdmissionCid: string,
    maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyIssueResultRetentionExtension(
    base: unknown, availableUntil: string, admittedAt: string, maxWireBytes: number, maxNodes: number,
    maxDepth: number,
  ): unknown;
  strategyManifestReadGrantAllowsBytes(grant: unknown, byteCount: number): boolean;
  strategyManifestReadGrantValidAt(grant: unknown, observedAt: string): boolean;
  strategyManifestResultNames(
    manifest: unknown, maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyNextResultDeliveryRow(serializer: unknown, rowWire: string): unknown;
  strategyPrepareDurableResultRowFrames(
    maxBytes: number, maxRows: number, maxRowBytes: number, maxDepth: number, maxFrameBytes: number,
  ): unknown;
  strategyPrepareGrowingDurableResultRowFrames(
    maxBytes: number, maxRows: number, maxRowBytes: number, maxDepth: number, maxFrameBytes: number,
  ): unknown;
  strategyPrepareResultDeliverySerializer(
    format: string, schemaWire: string, fields: readonly string[], maxWireBytes: number,
    maxNodes: number, maxDepth: number,
  ): unknown;
  strategyResultMetadataRetentionState(retention: unknown, observedAt: string): unknown;
  strategyResultReadAvailability(
    manifest: unknown, resultName: string, retention: unknown, observedAt: string,
  ): unknown;
  strategyResultReadDefinitionCid(manifest: unknown, resultName: string): unknown;
  strategyResultReadExtendedAvailability(
    manifest: unknown, resultName: string, base: unknown, extension: unknown, observedAt: string,
  ): unknown;
  strategyResultReadGrantAllowsBytes(grant: unknown, byteCount: number): boolean;
  strategyResultReadGrantValidAt(grant: unknown, observedAt: string): boolean;
  strategyResultReadRetentionPolicyCid(manifest: unknown, resultName: string): unknown;
  strategyResultRetentionClockContractCid(retention: unknown): unknown;
  strategyResultSerializationContractCid(
    format: string, maxWireBytes: number, maxNodes: number, maxDepth: number,
  ): unknown;
  strategyTrustedClockNotBefore(previous: string | undefined, observedAt: string): boolean;
};

type PublicationPorts = Readonly<{
  token(contract: unknown): unknown;
  inspect(original: unknown, limits: Limits): PublicationContract;
  issuanceLimits(limits: Limits, label: string): Limits;
  captureContractLimits(limits: Limits, label: string): Limits;
  issuedDeliveryGrants: WeakMap<PublicationContract, Limits>;
  issuedDeliveryAttempts: WeakMap<PublicationContract, IssuedDelivery>;
  originalDeliveryAttempts: WeakMap<OriginalDeliveryAttempt, DeliveryFacts>;
}>;

// Keep the existing publication token and delivery identities with the same
// publication control instance. This object only implements its Result ports.
export function createResultDeliveryControls(moon: CommonResultDeliveryBindings, {
  token, inspect, issuanceLimits, captureContractLimits,
  issuedDeliveryGrants, issuedDeliveryAttempts, originalDeliveryAttempts,
}: PublicationPorts) {
  return {
    resultReadControls: {
      deliveryTransition(previous: unknown, next: unknown) {
        return moon.strategyDeliveryRecordTransition(
          previous === undefined ? undefined : token(previous),
          token(next),
        );
      },
      deliverySuccessValid(attempt: unknown, receipt: unknown, record: unknown) {
        return moon.strategyDeliverySuccessValid(
          token(attempt), token(receipt), token(record),
        );
      },
      resultSerializationContractCid(format: string, limits: Limits) {
        issuanceLimits(limits, 'Result serialization');
        return checked(moon.strategyResultSerializationContractCid(
          format,
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        )) as string;
      },
      describeCommittedResult(index: unknown, manifest: unknown, resultName: string, bindings: readonly unknown[],
        definition: unknown, schemaWire: string, format: string, limits: Limits) {
        issuanceLimits(limits, 'Result description');
        return JSON.parse(checked(moon.strategyDescribeCommittedResult(
          token(index), token(manifest), resultName, bindings.map(token),
          token(definition), schemaWire, format, limits.maxWireBytes,
          limits.maxNodes, limits.maxDepth)) as string) as unknown;
      },
      issueManifestReadGrant(index: unknown, manifest: unknown, grant: Grant, limits: Limits) {
        limits = captureContractLimits(limits, 'Manifest read grant');
        if (grant === null || typeof grant !== 'object') {
          throw new TypeError('Invalid Manifest read grant');
        }
        return inspect(checked(moon.strategyIssueManifestReadGrant(
          token(index),
          token(manifest),
          grant.principalId,
          grant.purpose,
          grant.dataCeilingCid,
          grant.maxBytes,
          grant.maxUses,
          grant.expiresAt,
          grant.authorizationContextCid,
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        )), limits);
      },
      issueResultReadGrant(index: unknown, manifest: unknown, grant: ResultGrant, limits: Limits) {
        limits = captureContractLimits(limits, 'Result read grant');
        const bounds = Object.freeze({maxWireBytes: limits.maxWireBytes,
          maxNodes: limits.maxNodes, maxDepth: limits.maxDepth});
        if (grant === null || typeof grant !== 'object' ||
            !Array.isArray(grant.resultNames) ||
            !Array.isArray(grant.formats)) {
          throw new TypeError('Invalid Result read grant');
        }
        const result = inspect(checked(moon.strategyIssueResultReadGrant(
          token(index),
          token(manifest),
          grant.resultNames,
          grant.formats,
          grant.principalId,
          grant.purpose,
          grant.dataCeilingCid,
          grant.maxBytes,
          grant.maxUses,
          grant.expiresAt,
          grant.authorizationContextCid,
          grant.egressAdmissionCid,
          bounds.maxWireBytes,
          bounds.maxNodes,
          bounds.maxDepth,
        )), limits);
        issuedDeliveryGrants.set(result, bounds);
        return result;
      },
      issueDeliveryAttempt(index: unknown, manifest: unknown, grant: PublicationContract, attempt: AttemptRequest, limits: Limits) {
        limits = captureContractLimits(limits, 'Delivery Attempt');
        const bounds = Object.freeze({maxWireBytes: limits.maxWireBytes,
          maxNodes: limits.maxNodes, maxDepth: limits.maxDepth});
        if (attempt === null || typeof attempt !== 'object') {
          throw new TypeError('Invalid Delivery Attempt');
        }
        const result = inspect(checked(moon.strategyIssueDeliveryAttempt(
          token(index),
          token(manifest),
          token(grant),
          attempt.resultName,
          attempt.format,
          attempt.attemptId,
          attempt.requestedAt,
          bounds.maxWireBytes,
          bounds.maxNodes,
          bounds.maxDepth,
        )), limits);
        const original = Object.freeze({kind: 'issued-delivery-attempt'});
        const facts = Object.freeze({index, manifest, grant, attempt: result,
          request: Object.freeze({resultName: attempt.resultName, format: attempt.format,
            attemptId: attempt.attemptId, requestedAt: attempt.requestedAt}),
          limits: bounds});
        issuedDeliveryAttempts.set(result, {original,
          index: token(index), manifest: token(manifest), grant: token(grant)});
        originalDeliveryAttempts.set(original, facts);
        return result;
      },
      captureIssuedDeliveryAttempt(attempt: PublicationContract, index: unknown, manifest: unknown, grant: PublicationContract, limits: Limits) {
        token(attempt);
        const actualIndex = token(index), actualManifest = token(manifest), actualGrant = token(grant);
        const issued = issuedDeliveryAttempts.get(attempt);
        if (issued === undefined) return undefined;
        if (issued.index !== actualIndex || issued.manifest !== actualManifest || issued.grant !== actualGrant) {
          throw new TypeError('PublicationDeliveryOriginalMismatch');
        }
        issuanceLimits(limits, 'Delivery Attempt');
        const grantLimits = issuedDeliveryGrants.get(grant);
        const facts = originalDeliveryAttempts.get(issued.original);
        if (grantLimits === undefined || (['maxWireBytes', 'maxNodes', 'maxDepth'] as const).some(
          key => limits[key] !== grantLimits[key] || limits[key] !== facts!.limits[key])) return undefined;
        return issued.original;
      },
      readIssuedDeliveryAttempt(original: OriginalDeliveryAttempt) {
        const facts = originalDeliveryAttempts.get(original);
        if (facts === undefined) throw new TypeError('ForeignPublicationDeliveryOriginal');
        return facts;
      },
      deliveryResultDefinitionCid(manifest: unknown, attempt: unknown) {
        return checked(moon.strategyDeliveryResultDefinitionCid(
          token(manifest),
          token(attempt),
        )) as string;
      },
      resultReadRetentionPolicyCid(manifest: unknown, resultName: string) {
        if (typeof resultName !== 'string') {
          throw new TypeError('Invalid Result retention request');
        }
        return checked(moon.strategyResultReadRetentionPolicyCid(
          token(manifest), resultName,
        )) as string;
      },
      manifestResultNames(manifest: unknown, limits: Limits) {
        issuanceLimits(limits, 'Manifest Result inventory');
        const wire = checked(moon.strategyManifestResultNames(
          token(manifest),
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        ));
        let names: unknown;
        try { names = JSON.parse(wire as string); }
        catch (error) {
          throw new TypeError('Invalid Manifest Result inventory', {cause: error});
        }
        if (!Array.isArray(names)) {
          throw new TypeError('Invalid Manifest Result inventory');
        }
        return Object.freeze([...names]) as readonly unknown[];
      },
      resultReadDefinitionCid(manifest: unknown, resultName: string) {
        if (typeof resultName !== 'string') {
          throw new TypeError('Invalid Result definition request');
        }
        return checked(moon.strategyResultReadDefinitionCid(
          token(manifest), resultName,
        )) as string;
      },
    },
    resultRetentionControls: {
      resultReadAvailability(manifest: unknown, resultName: string, retention: unknown, observedAt: string) {
        if (typeof resultName !== 'string' || typeof observedAt !== 'string') {
          throw new TypeError('Invalid Result availability request');
        }
        return checked(moon.strategyResultReadAvailability(
          token(manifest), resultName, token(retention), observedAt,
        )) as string;
      },
      resultMetadataRetentionState(retention: unknown, observedAt: string) {
        if (typeof observedAt !== 'string') {
          throw new TypeError('Invalid Result metadata retention request');
        }
        return checked(moon.strategyResultMetadataRetentionState(
          token(retention), observedAt,
        )) as string;
      },
      issueResultRetentionExtension(
        base: unknown, availableUntil: string, admittedAt: string, limits: Limits,
      ) {
        limits = captureContractLimits(limits, 'Result retention extension');
        if (typeof availableUntil !== 'string' ||
            typeof admittedAt !== 'string') {
          throw new TypeError('Invalid Result retention extension');
        }
        return inspect(checked(moon.strategyIssueResultRetentionExtension(
          token(base),
          availableUntil,
          admittedAt,
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        )), limits);
      },
      resultReadExtendedAvailability(
        manifest: unknown, resultName: string, base: unknown, extension: unknown, observedAt: string,
      ) {
        if (typeof resultName !== 'string' || typeof observedAt !== 'string') {
          throw new TypeError('Invalid extended Result availability request');
        }
        return checked(moon.strategyResultReadExtendedAvailability(
          token(manifest),
          resultName,
          token(base),
          token(extension),
          observedAt,
        )) as string;
      },
      resultRetentionClockContractCid(retention: unknown) {
        return checked(moon.strategyResultRetentionClockContractCid(
          token(retention),
        )) as string;
      },
      trustedClockNotBefore(previous: string | undefined, observedAt: string) {
        if (previous !== undefined && typeof previous !== 'string' ||
            typeof observedAt !== 'string') {
          return false;
        }
        return moon.strategyTrustedClockNotBefore(previous, observedAt);
      },
    },
    resultDeliveryControls: {
      resultReadGrantAllowsBytes(grant: unknown, byteCount: number) {
        if (!Number.isSafeInteger(byteCount) || byteCount < 0) return false;
        return moon.strategyResultReadGrantAllowsBytes(
          token(grant), byteCount,
        );
      },
      manifestReadGrantAllowsBytes(grant: unknown, byteCount: number) {
        if (!Number.isSafeInteger(byteCount) || byteCount < 0) return false;
        return moon.strategyManifestReadGrantAllowsBytes(
          token(grant), byteCount,
        );
      },
      manifestReadGrantValidAt(grant: unknown, observedAt: string) {
        if (typeof observedAt !== 'string') return false;
        return moon.strategyManifestReadGrantValidAt(
          token(grant), observedAt,
        );
      },
      resultReadGrantValidAt(grant: unknown, observedAt: string) {
        if (typeof observedAt !== 'string') return false;
        return moon.strategyResultReadGrantValidAt(
          token(grant), observedAt,
        );
      },
      issueResultDeliveryReceipt(index: unknown, manifest: unknown, grant: unknown, attempt: unknown, delivered: DeliverySummary,
        limits: Limits) {
        limits = captureContractLimits(limits, 'Result delivery receipt');
        if (delivered === null || typeof delivered !== 'object') {
          throw new TypeError('Invalid Result delivery receipt');
        }
        return inspect(checked(moon.strategyIssueResultDeliveryReceipt(
          token(index),
          token(manifest),
          token(grant),
          token(attempt),
          delivered.byteCount,
          delivered.sha256,
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        )), limits);
      },
      issueDeliveryRecord(attempt: unknown, previous: unknown, update: DeliveryRecord, limits: Limits) {
        limits = captureContractLimits(limits, 'Delivery Record');
        if (update === null || typeof update !== 'object' ||
            !Array.isArray(update.cleanupOwnerCids)) {
          throw new TypeError('Invalid Delivery Record');
        }
        return inspect(checked(moon.strategyIssueDeliveryRecord(
          token(attempt),
          previous === undefined ? undefined : token(previous),
          update.state,
          update.confirmedByteCount,
          update.exposure,
          update.possibleUnconfirmedMaxBytes,
          update.deliveredSha256,
          update.receipt === undefined ? undefined : token(update.receipt),
          update.failureCid,
          update.observedAt,
          update.cleanupOwnerCids,
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        )), limits);
      },
      prepareResultDeliverySerializer(format: string, schemaWire: string, fields: readonly string[], limits: Limits) {
        issuanceLimits(limits, 'Result delivery serializer');
        if (typeof schemaWire !== 'string' || !Array.isArray(fields)) {
          throw new TypeError('Invalid Result delivery serializer');
        }
        return checked(moon.strategyPrepareResultDeliverySerializer(
          format,
          schemaWire,
          fields,
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        ));
      },
      beginResultDelivery(serializer: unknown) {
        return checked(moon.strategyBeginResultDelivery(serializer)) as string;
      },
      nextResultDeliveryRow(serializer: unknown, rowWire: string) {
        if (typeof rowWire !== 'string') {
          throw new TypeError('Invalid Result delivery row');
        }
        return checked(moon.strategyNextResultDeliveryRow(serializer, rowWire)) as string;
      },
      finishResultDelivery(serializer: unknown) {
        return checked(moon.strategyFinishResultDelivery(serializer)) as string;
      },
      prepareDurableResultRowFrames(limits: FrameLimits) {
        if (limits === null || typeof limits !== 'object' ||
            !Number.isSafeInteger(limits.maxBytes) || limits.maxBytes < 0 ||
            !Number.isSafeInteger(limits.maxRows) || limits.maxRows < 0 ||
            !Number.isSafeInteger(limits.maxRowBytes) ||
            limits.maxRowBytes < 1 ||
            !Number.isSafeInteger(limits.maxDepth) || limits.maxDepth < 1 ||
            !Number.isSafeInteger(limits.maxFrameBytes) ||
            limits.maxFrameBytes < 1) {
          throw new TypeError('Invalid durable Result row-frame limits');
        }
        return checked(moon.strategyPrepareDurableResultRowFrames(
          limits.maxBytes,
          limits.maxRows,
          limits.maxRowBytes,
          limits.maxDepth,
          limits.maxFrameBytes,
        ));
      },
      prepareGrowingDurableResultRowFrames(limits: FrameLimits) {
        for (const name of ['maxBytes', 'maxRows', 'maxRowBytes', 'maxDepth', 'maxFrameBytes'] as const) {
          if (!Number.isSafeInteger(limits?.[name]) || limits[name] < 0 || limits[name] > 2147483647) {
            throw new TypeError('Invalid growing durable Result row-frame limits');
          }
        }
        return checked(moon.strategyPrepareGrowingDurableResultRowFrames(
          limits.maxBytes, limits.maxRows, limits.maxRowBytes, limits.maxDepth, limits.maxFrameBytes));
      },
      durableResultRowFrameGrowth(frames: unknown, bytes: number) {
        if (!Number.isSafeInteger(bytes) || bytes < 0 || bytes > 2147483647) {
          throw new TypeError('Invalid durable Result row-frame chunk');
        }
        return checked(moon.strategyDurableResultRowFrameGrowth(frames, bytes)) as number;
      },
      growDurableResultRowFrameBuffer(frames: unknown, bytes: number) {
        if (!Number.isSafeInteger(bytes) || bytes < 0 || bytes > 2147483647) {
          throw new TypeError('Invalid durable Result row-frame capacity');
        }
        return checked(moon.strategyGrowDurableResultRowFrameBuffer(frames, bytes));
      },
      feedDurableResultRowFrames(frames: unknown, chunk: Uint8Array) {
        if (!(chunk instanceof Uint8Array)) {
          throw new TypeError('Invalid durable Result row-frame chunk');
        }
        return checked(moon.strategyFeedDurableResultRowFrames(frames, chunk));
      },
      finishDurableResultRowFrames(frames: unknown) {
        const summary = checked(
          moon.strategyFinishDurableResultRowFrames(frames),
        );
        if (!Array.isArray(summary) || summary.length !== 2 ||
            summary.some(value => !Number.isSafeInteger(value) || value < 0)) {
          throw new TypeError('Invalid durable Result row-frame summary');
        }
        return Object.freeze({bytes: summary[0] as number, rows: summary[1] as number});
      },
      cancelDurableResultRowFrames(frames: unknown) {
        moon.strategyCancelDurableResultRowFrames(frames);
      },
    },
  };
}
