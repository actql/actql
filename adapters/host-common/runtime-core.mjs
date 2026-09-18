import {checked} from './runtime-result.mjs';
import {
  validOutputLimits,
  validResultOutputLimits,
} from './result-output-limits.mjs';

const usageKeys = ['planningWork', 'attempts', 'holdings', 'transferredBytes',
  'reservedTransferBytes', 'heldBytes', 'reservedRetentionBytes', 'reservedExecutionBytes'];
const tuplePair = value => Array.isArray(value)
  ? value
  : value !== null && typeof value === 'object'
    ? [value._0, value._1]
    : undefined;
const siteControls = new WeakMap();
const publicationControls = new WeakMap();

function siteControl(moon) {
  let control = siteControls.get(moon);
  if (control !== undefined) return control;
  control = Object.freeze({
    create: configuration => moon.strategySiteCreate(
      configuration.key,
      configuration.generation,
      configuration.runtimeRevision,
      configuration.maxConcurrentOperations,
      configuration.maxConcurrentTransfers,
      configuration.maxRetainedBytes,
      configuration.maxExecutionBytes,
    ),
    available: moon.strategySiteAvailable,
    revoked: moon.strategySiteRevoked,
    capacitySupports: moon.strategySiteCapacitySupports,
    bindingCurrent: moon.strategySiteBindingCurrent,
    startOperation: moon.strategySiteStartOperation,
    operationAvailable: moon.strategySiteOperationAvailable,
    settleOperation: moon.strategySiteSettleOperation,
    retainOperationHolding: moon.strategySiteRetainOperationHolding,
    startTransfer: moon.strategySiteStartTransfer,
    transferAvailable: moon.strategySiteTransferAvailable,
    settleTransferSource: moon.strategySiteSettleTransferSource,
    settleTransferDestination: moon.strategySiteSettleTransferDestination,
    retainTransferHolding: moon.strategySiteRetainTransferHolding,
    retainHolding: moon.strategySiteRetainHolding,
    releaseHolding: moon.strategySiteReleaseHolding,
    retainCleanup: moon.strategySiteRetainCleanup,
    releaseCleanup: moon.strategySiteReleaseCleanup,
    beginTeardown: moon.strategySiteBeginTeardown,
    revoke: moon.strategySiteRevoke,
    status: moon.strategySiteStatus,
  });
  siteControls.set(moon, control);
  return control;
}

function publicationControl(moon) {
  let control = publicationControls.get(moon);
  if (control !== undefined) return control;
  const tokens = new WeakMap();
  const evidenceTokens = new WeakMap();
  const admissionTokens = new WeakMap();
  const snapshotTokens = new WeakMap();
  const sourceAdvanceTokens = new WeakMap();
  const inspect = contract => {
    const value = Object.freeze({
      name: moon.strategyPublicationContractName(contract),
      identityField: moon.strategyPublicationContractIdentityField(contract),
      identity: moon.strategyPublicationContractIdentity(contract),
      wire: moon.strategyPublicationContractJson(contract),
    });
    tokens.set(value, contract);
    return value;
  };
  const token = value => {
    const result = tokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign publication contract');
    }
    return result;
  };
  const inspectEvidence = evidence => {
    const value = Object.freeze({
      name: moon.strategyRunEvidenceName(evidence),
      identity: moon.strategyRunEvidenceIdentity(evidence),
      wire: moon.strategyRunEvidenceJson(evidence),
    });
    evidenceTokens.set(value, evidence);
    return value;
  };
  const evidenceToken = value => {
    const result = evidenceTokens.get(value);
    if (result === undefined) throw new TypeError('Foreign Run evidence');
    return result;
  };
  const inspectAdmission = admission => {
    const value = Object.freeze({kind: 'run-publication-admission'});
    admissionTokens.set(value, admission);
    return value;
  };
  const admissionToken = value => {
    const result = admissionTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign Run publication admission');
    }
    return result;
  };
  const inspectSnapshot = snapshot => {
    const value = Object.freeze({kind: 'captured-result-snapshot'});
    snapshotTokens.set(value, snapshot);
    return value;
  };
  const snapshotToken = value => {
    const result = snapshotTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign captured Result snapshot');
    }
    return result;
  };
  const inspectSourceAdvance = advance => {
    const value = Object.freeze({kind: 'pending-source-state-advance'});
    sourceAdvanceTokens.set(value, advance);
    return value;
  };
  const sourceAdvanceToken = value => {
    const result = sourceAdvanceTokens.get(value);
    if (result === undefined) {
      throw new TypeError('Foreign pending source-state advance');
    }
    return result;
  };
  const issuanceLimits = (limits, label) => {
    if (limits === null || typeof limits !== 'object' ||
        !Number.isSafeInteger(limits.maxWireBytes) ||
        !Number.isSafeInteger(limits.maxNodes) ||
        !Number.isSafeInteger(limits.maxDepth) ||
        limits.maxWireBytes < 0 || limits.maxNodes < 0 ||
        limits.maxDepth < 0) {
      throw new TypeError(`Invalid ${label} issuance limits`);
    }
    return limits;
  };
  control = Object.freeze({
    seal(name, bodyWire, limits) {
      return inspect(checked(moon.strategyPublicationSeal(
        name,
        bodyWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    admit(name, completeWire, limits) {
      return inspect(checked(moon.strategyPublicationAdmit(
        name,
        completeWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    sealRunEvidence(name, bodyWire, limits) {
      issuanceLimits(limits, 'Run evidence');
      return inspectEvidence(checked(moon.strategyRunEvidenceSeal(
        name,
        bodyWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    admitRunEvidence(name, completeWire, limits) {
      issuanceLimits(limits, 'Run evidence');
      return inspectEvidence(checked(moon.strategyRunEvidenceAdmit(
        name,
        completeWire,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    issueRunInvocation(template, observation, limits) {
      issuanceLimits(limits, 'Run Invocation');
      return inspect(checked(moon.strategyIssueRunInvocation(
        evidenceToken(template),
        evidenceToken(observation),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    admitRunPublication(template, prepared, authorization, compiledPlan) {
      return inspectAdmission(checked(moon.strategyRunPublicationAdmit(
        evidenceToken(template),
        evidenceToken(prepared),
        evidenceToken(authorization),
        token(compiledPlan),
      )));
    },
    issueRunDefinition(admission, definition, limits) {
      issuanceLimits(limits, 'Run Definition');
      if (definition === null || typeof definition !== 'object') {
        throw new TypeError('Invalid Run Definition request');
      }
      return inspect(checked(moon.strategyIssueRunDefinition(
        admissionToken(admission),
        definition.scopeId,
        definition.runId,
        definition.inputArtifactSetCid,
        definition.createdAt,
        definition.validUntil,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    issueEffectFreeRunReceipt(chain, provenance, limits) {
      issuanceLimits(limits, 'Run Receipt');
      if (chain === null || typeof chain !== 'object' ||
          provenance === null || typeof provenance !== 'object' ||
          !Array.isArray(chain.definitions) ||
          !Array.isArray(chain.artifacts) ||
          !Array.isArray(provenance.bindings) ||
          !Array.isArray(provenance.sourceEvidence) ||
          !Array.isArray(provenance.modelEvidence) ||
          !Array.isArray(provenance.barrierAttemptReceiptCids)) {
        throw new TypeError('Invalid Run Receipt request');
      }
      return inspect(checked(moon.strategyIssueEffectFreeRunReceipt(
        admissionToken(chain.admission),
        token(chain.runDefinition),
        token(chain.invocation),
        evidenceToken(chain.observation),
        chain.definitions.map(token),
        chain.artifacts.map(token),
        token(chain.manifest),
        evidenceToken(provenance.normalizationJournal),
        provenance.bindings.map(binding => binding.name),
        provenance.bindings.map(binding => binding.sha256),
        provenance.sourceEvidence.map(evidenceToken),
        provenance.modelEvidence.map(evidenceToken),
        provenance.barrierAttemptReceiptCids,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    admitCapturedResultSnapshot(definition, artifact, rowsWire, fields,
      limits) {
      issuanceLimits(limits, 'Captured Result snapshot');
      if (typeof rowsWire !== 'string' || !Array.isArray(fields) ||
          fields.some(field => typeof field !== 'string')) {
        throw new TypeError('Invalid Captured Result snapshot');
      }
      return inspectSnapshot(checked(
        moon.strategyAdmitCapturedResultSnapshot(
          token(definition),
          token(artifact),
          rowsWire,
          fields,
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        ),
      ));
    },
    admitCompletedResultSnapshot(exportHandle, limits) {
      issuanceLimits(limits, 'completed Result snapshot');
      return inspectSnapshot(checked(
        moon.strategyHostOutputExportAdmitCapturedResultSnapshot(
          exportHandle,
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        ),
      ));
    },
    admitPendingSourceStateAdvance(completeWire, observation, limits) {
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
    issueEffectFreeCapturedRun(chain, evidence, limits) {
      issuanceLimits(limits, 'Captured Run');
      if (chain === null || typeof chain !== 'object' ||
          evidence === null || typeof evidence !== 'object' ||
          !Array.isArray(chain.definitions) ||
          !Array.isArray(chain.artifacts) ||
          !Array.isArray(evidence.snapshots) ||
          !Array.isArray(evidence.pendingSourceStateAdvances) ||
          !Array.isArray(evidence.modelEvidence)) {
        throw new TypeError('Invalid Captured Run request');
      }
      return inspect(checked(moon.strategyIssueEffectFreeCapturedRun(
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
      )));
    },
    recordTransition(previous, next, uncommittedConfirmed) {
      return moon.strategyPublicationRecordTransition(
        previous === undefined ? undefined : token(previous),
        token(next),
        uncommittedConfirmed,
      );
    },
    recordAllowsCommit(record) {
      return moon.strategyPublicationRecordAllowsCommit(token(record));
    },
    runChainValid(runDefinition, invocation, definitions, artifacts,
      manifest, limits) {
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
    issueResultManifest(runDefinition, invocation, definitions, artifacts,
      limits) {
      issuanceLimits(limits, 'Result Manifest');
      return inspect(checked(moon.strategyIssueResultManifest(
        token(runDefinition),
        token(invocation),
        definitions.map(token),
        artifacts.map(token),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    issueDurableResultBinding(chain, physical, limits) {
      issuanceLimits(limits, 'durable Result binding');
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
        physical.storeAuthorityCid,
        physical.rowCount,
        physical.byteCount,
        physical.physicalSha256,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    issuePublicationRequest(runDefinition, definitions, intent, limits) {
      issuanceLimits(limits, 'Publication Request');
      if (intent === null || typeof intent !== 'object') {
        throw new TypeError('Invalid Publication Request intent');
      }
      return inspect(checked(moon.strategyIssuePublicationRequest(
        token(runDefinition),
        definitions.map(token),
        intent.tenantId,
        intent.authorityScopeCid,
        intent.publicationPolicyCid,
        intent.publicationTargetCid,
        intent.requestedAt,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    issuePublicationAttempt(request, runDefinition, attempt, limits) {
      issuanceLimits(limits, 'Publication Attempt');
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
      )));
    },
    publicationPreflightValid(
      admission,
      runDefinition,
      invocation,
      definitions,
      retentions,
      evidenceContexts,
      request,
      attempt,
      programDefinitionCid,
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
    issuePublicIndexEntry(chain, committedAt, limits) {
      issuanceLimits(limits, 'Public Index Entry');
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
      )));
    },
    issuePublicationRecord(attempt, previous, update, limits) {
      issuanceLimits(limits, 'Publication Record');
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
      )));
    },
    effectFreeChainValid(runDefinition, invocation, definitions, artifacts,
      manifest, receipt, capturedRun, limits) {
      return moon.strategyEffectFreeRunEvidenceChainValid(
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
      );
    },
    effectFreeCommitValid(runDefinition, invocation, definitions, artifacts,
      derivations, orderings, retentions, durableBindings, manifest, receipt,
      capturedRun, request, attempt, indexEntry, limits) {
      return moon.strategyEffectFreePublicationCommitValid(
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
      );
    },
    issueResultArtifact(exportHandle, invocation, retention, limits) {
      issuanceLimits(limits, 'Result Artifact');
      return inspect(checked(
        moon.strategyHostOutputExportIssueResultArtifact(
          exportHandle,
          token(invocation),
          token(retention),
          limits.maxWireBytes,
          limits.maxNodes,
          limits.maxDepth,
        ),
      ));
    },
    deliveryTransition(previous, next) {
      return moon.strategyDeliveryRecordTransition(
        previous === undefined ? undefined : token(previous),
        token(next),
      );
    },
    deliverySuccessValid(attempt, receipt, record) {
      return moon.strategyDeliverySuccessValid(
        token(attempt), token(receipt), token(record),
      );
    },
    resultSerializationContractCid(format, limits) {
      issuanceLimits(limits, 'Result serialization');
      return checked(moon.strategyResultSerializationContractCid(
        format,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      ));
    },
    issueManifestReadGrant(index, manifest, grant, limits) {
      issuanceLimits(limits, 'Manifest read grant');
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
      )));
    },
    issueResultReadGrant(index, manifest, grant, limits) {
      issuanceLimits(limits, 'Result read grant');
      if (grant === null || typeof grant !== 'object' ||
          !Array.isArray(grant.resultNames) ||
          !Array.isArray(grant.formats)) {
        throw new TypeError('Invalid Result read grant');
      }
      return inspect(checked(moon.strategyIssueResultReadGrant(
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
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    issueDeliveryAttempt(index, manifest, grant, attempt, limits) {
      issuanceLimits(limits, 'Delivery Attempt');
      if (attempt === null || typeof attempt !== 'object') {
        throw new TypeError('Invalid Delivery Attempt');
      }
      return inspect(checked(moon.strategyIssueDeliveryAttempt(
        token(index),
        token(manifest),
        token(grant),
        attempt.resultName,
        attempt.format,
        attempt.attemptId,
        attempt.requestedAt,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      )));
    },
    deliveryResultDefinitionCid(manifest, attempt) {
      return checked(moon.strategyDeliveryResultDefinitionCid(
        token(manifest),
        token(attempt),
      ));
    },
    resultReadRetentionPolicyCid(manifest, resultName) {
      if (typeof resultName !== 'string') {
        throw new TypeError('Invalid Result retention request');
      }
      return checked(moon.strategyResultReadRetentionPolicyCid(
        token(manifest), resultName,
      ));
    },
    manifestResultNames(manifest, limits) {
      issuanceLimits(limits, 'Manifest Result inventory');
      const wire = checked(moon.strategyManifestResultNames(
        token(manifest),
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      ));
      let names;
      try { names = JSON.parse(wire); }
      catch (error) {
        throw new TypeError('Invalid Manifest Result inventory', {cause: error});
      }
      if (!Array.isArray(names)) {
        throw new TypeError('Invalid Manifest Result inventory');
      }
      return Object.freeze([...names]);
    },
    resultReadDefinitionCid(manifest, resultName) {
      if (typeof resultName !== 'string') {
        throw new TypeError('Invalid Result definition request');
      }
      return checked(moon.strategyResultReadDefinitionCid(
        token(manifest), resultName,
      ));
    },
    runDefinitionRunId(runDefinition) {
      return checked(moon.strategyRunDefinitionRunId(token(runDefinition)));
    },
    resultReadAvailability(manifest, resultName, retention, observedAt) {
      if (typeof resultName !== 'string' || typeof observedAt !== 'string') {
        throw new TypeError('Invalid Result availability request');
      }
      return checked(moon.strategyResultReadAvailability(
        token(manifest), resultName, token(retention), observedAt,
      ));
    },
    resultMetadataRetentionState(retention, observedAt) {
      if (typeof observedAt !== 'string') {
        throw new TypeError('Invalid Result metadata retention request');
      }
      return checked(moon.strategyResultMetadataRetentionState(
        token(retention), observedAt,
      ));
    },
    issueResultRetentionExtension(
      base, availableUntil, admittedAt, limits,
    ) {
      issuanceLimits(limits, 'Result retention extension');
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
      )));
    },
    resultReadExtendedAvailability(
      manifest, resultName, base, extension, observedAt,
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
      ));
    },
    resultRetentionClockContractCid(retention) {
      return checked(moon.strategyResultRetentionClockContractCid(
        token(retention),
      ));
    },
    trustedClockNotBefore(previous, observedAt) {
      if (previous !== undefined && typeof previous !== 'string' ||
          typeof observedAt !== 'string') {
        return false;
      }
      return moon.strategyTrustedClockNotBefore(previous, observedAt);
    },
    issueSucceededRunState(request, limits) {
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
      ));
    },
    resultReadGrantAllowsBytes(grant, byteCount) {
      if (!Number.isSafeInteger(byteCount) || byteCount < 0) return false;
      return moon.strategyResultReadGrantAllowsBytes(
        token(grant), byteCount,
      );
    },
    manifestReadGrantAllowsBytes(grant, byteCount) {
      if (!Number.isSafeInteger(byteCount) || byteCount < 0) return false;
      return moon.strategyManifestReadGrantAllowsBytes(
        token(grant), byteCount,
      );
    },
    manifestReadGrantValidAt(grant, observedAt) {
      if (typeof observedAt !== 'string') return false;
      return moon.strategyManifestReadGrantValidAt(
        token(grant), observedAt,
      );
    },
    resultReadGrantValidAt(grant, observedAt) {
      if (typeof observedAt !== 'string') return false;
      return moon.strategyResultReadGrantValidAt(
        token(grant), observedAt,
      );
    },
    issueResultDeliveryReceipt(index, manifest, grant, attempt, delivered,
      limits) {
      issuanceLimits(limits, 'Result delivery receipt');
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
      )));
    },
    issueDeliveryRecord(attempt, previous, update, limits) {
      issuanceLimits(limits, 'Delivery Record');
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
      )));
    },
    prepareResultDeliverySerializer(format, schemaWire, fields, limits) {
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
    beginResultDelivery(serializer) {
      return checked(moon.strategyBeginResultDelivery(serializer));
    },
    nextResultDeliveryRow(serializer, rowWire) {
      if (typeof rowWire !== 'string') {
        throw new TypeError('Invalid Result delivery row');
      }
      return checked(moon.strategyNextResultDeliveryRow(serializer, rowWire));
    },
    finishResultDelivery(serializer) {
      return checked(moon.strategyFinishResultDelivery(serializer));
    },
  });
  publicationControls.set(moon, control);
  return control;
}

function outputExportControl(moon, publications) {
  const evidenceFields = [
    'computationContractCid',
    'inputRelationCids',
    'scopeCid',
    'effectiveDataPolicyCid',
    'authorityScopeCid',
  ];
  const cidPattern = /^sha256:[0-9a-f]{64}$/u;
  const evidenceLimitFields = ['maxWireBytes', 'maxNodes', 'maxDepth'];
  const validEvidenceLimits = limits =>
    limits !== null && typeof limits === 'object' &&
    !Array.isArray(limits) &&
    Object.keys(limits).sort().join('\0') ===
      [...evidenceLimitFields].sort().join('\0') &&
    evidenceLimitFields.every(name =>
      Number.isSafeInteger(limits[name]) && limits[name] >= 0);
  const validEvidenceContext = value =>
    value !== null && typeof value === 'object' &&
    Object.keys(value).sort().join('\0') ===
      [...evidenceFields].sort().join('\0') &&
    ['computationContractCid', 'scopeCid', 'effectiveDataPolicyCid',
      'authorityScopeCid'].every(name => cidPattern.test(value[name])) &&
    Array.isArray(value.inputRelationCids) &&
    value.inputRelationCids.every(cid => cidPattern.test(cid));
  return Object.freeze({
    begin(output, limits) {
      if (!validOutputLimits(limits)) {
        throw new TypeError('Invalid output export limits');
      }
      return checked(moon.strategyHostOutputExportBegin(
        output,
        limits.maxRows,
        limits.maxValueNodes,
        limits.maxValueTextBytes,
        limits.maxValueDepth,
        limits.maxValueWork,
        limits.maxWireBytes,
        limits.maxWireNodes,
        limits.maxWireDepth,
        limits.maxColumns,
        limits.maxOrderWork,
        limits.maxLogicalWireBytes,
        limits.maxLogicalWireNodes,
        limits.maxLogicalWireDepth,
        limits.maxSchemaFields,
        limits.maxSchemaBytes,
        limits.maxSchemaNodes,
        limits.maxSchemaDepth,
        limits.maxBatchBytes,
      ));
    },
    beginResult(host, result, limits) {
      if (!Number.isSafeInteger(result) || result < 0 ||
          !validResultOutputLimits(limits)) {
        throw new TypeError('Invalid Result output export request');
      }
      return checked(moon.strategyHostResultOutputExportBegin(
        host,
        result,
        limits.maxResultFields,
        limits.maxResultMappingWork,
        limits.maxResultOrderWork,
        limits.maxResultWorkspaceEntries,
        limits.maxRows,
        limits.maxValueNodes,
        limits.maxValueTextBytes,
        limits.maxValueDepth,
        limits.maxValueWork,
        limits.maxWireBytes,
        limits.maxWireNodes,
        limits.maxWireDepth,
        limits.maxColumns,
        limits.maxOrderWork,
        limits.maxLogicalWireBytes,
        limits.maxLogicalWireNodes,
        limits.maxLogicalWireDepth,
        limits.maxSchemaFields,
        limits.maxSchemaBytes,
        limits.maxSchemaNodes,
        limits.maxSchemaDepth,
        limits.maxBatchBytes,
      ));
    },
    next: value => checked(moon.strategyHostOutputExportNext(value)),
    finish: value => checked(moon.strategyHostOutputExportFinish(value)),
    identity(value) {
      return Object.freeze({
        orderedRowsCid: checked(moon.strategyHostOutputExportCid(value)),
        logicalRelationCid:
          checked(moon.strategyHostOutputExportLogicalRelationCid(value)),
        resultSchemaCid:
          checked(moon.strategyHostOutputExportResultSchemaCid(value)),
        resultSchemaWire:
          checked(moon.strategyHostOutputExportResultSchemaWire(value)),
        resultFields:
          checked(moon.strategyHostOutputExportResultFields(value)),
        codecContractCid:
          checked(moon.strategyHostOutputExportCodecContractCid(value)),
        bytes: checked(moon.strategyHostOutputExportBytes(value)),
        nodes: checked(moon.strategyHostOutputExportNodes(value)),
        rows: checked(moon.strategyHostOutputExportRows(value)),
        schemaBytes: checked(
          moon.strategyHostOutputExportSchemaBytes(value),
        ),
        schemaNodes: checked(
          moon.strategyHostOutputExportSchemaNodes(value),
        ),
        schemaFields: checked(
          moon.strategyHostOutputExportSchemaFields(value),
        ),
      });
    },
    issueResultEvidence(value, context, limits) {
      if (!validEvidenceContext(context) ||
          !validEvidenceLimits(limits)) {
        throw new TypeError('Invalid Result evidence issuance request');
      }
      checked(moon.strategyHostOutputExportIssueResultEvidence(
        value,
        context.computationContractCid,
        context.inputRelationCids,
        context.scopeCid,
        context.effectiveDataPolicyCid,
        context.authorityScopeCid,
        limits.maxWireBytes,
        limits.maxNodes,
        limits.maxDepth,
      ));
      return Object.freeze({
        derivation: publications.admit(
          'derivation_evidence',
          checked(moon.strategyHostOutputExportDerivationEvidenceJson(value)),
          limits,
        ),
        ordering: publications.admit(
          'ordering_evidence',
          checked(moon.strategyHostOutputExportOrderingEvidenceJson(value)),
          limits,
        ),
      });
    },
    cancel: moon.strategyHostOutputExportCancel,
  });
}

// Trusted assembly only. Standard entries bind this to their generated runtime;
// execution requests cannot supply a verifier, SQL or replacement runtime.
export function runtimeCore(moon) {
  const publications = publicationControl(moon);
  return Object.freeze({
    siteControl: siteControl(moon),
    publicationControl: publications,
    outputExportControl: outputExportControl(moon, publications),
    count: moon.strategyHostCount,
    programDefinitionCid: moon.strategyHostProgramDefinitionCid,
    resultInventory(value) {
      const names = moon.strategyHostResultNames(value);
      if (!Array.isArray(names)) throw new TypeError('Invalid Result inventory');
      if (names.length === 0) return Object.freeze([]);
      const inventory = checked(moon.strategyHostPublicationInventory(value));
      const count = moon.strategyHostPublicationInventoryCount(inventory);
      if (count !== names.length) {
        throw new TypeError('Invalid Result inventory projection');
      }
      return Object.freeze(Array.from({length: count}, (_, index) => {
        const definitionContract = publications.admit(
          'result_definition',
          checked(moon.strategyHostPublicationInventoryDefinitionJson(
            inventory, index,
          )),
          {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64},
        );
        const definition = JSON.parse(definitionContract.wire);
        return Object.freeze({
          name: checked(
            moon.strategyHostPublicationInventoryName(inventory, index),
          ),
          task: checked(
            moon.strategyHostPublicationInventoryTask(inventory, index),
          ),
          definition: Object.freeze(definition),
          definitionContract,
        });
      }));
    },
    next: value => checked(moon.strategyHostNext(value)),
    nextTask: moon.strategyHostNextTask,
    managedProducer: moon.strategyHostManagedProducer,
    managedProducers: moon.strategyHostManagedProducers,
    managedMatches: moon.strategyHostManagedOutputMatches,
    managedInputMatches: moon.strategyHostManagedInputMatchesMaterial,
    selectManaged: moon.strategyHostSelectManagedRegistration,
    task: moon.strategyHostTask,
    taskCapacity: (value, task) => tuplePair(checked(
      moon.strategyHostTaskCapacity(value, task),
    )),
    registration: moon.strategyHostRegistration,
    completed: moon.strategyHostTaskCompleted,
    finished: moon.strategyHostFinished,
    stop: moon.strategyHostStop,
    closeOutputs: moon.strategyHostCloseOutputs,
    output: moon.strategyHostOutput,
    transferBegin: (value, source, transfer, retained, execution) => checked(
      moon.strategyHostTransferBegin(
        value, source, transfer, retained, execution,
      ),
    ),
    transferCharge: (value, transfer, bytes) => checked(
      moon.strategyHostTransferCharge(value, transfer, bytes),
    ),
    transferSettle: (value, transfer, confirmed) => checked(
      moon.strategyHostTransferSettle(value, transfer, confirmed),
    ),
    transferComplete: (value, transfer, retained) => checked(
      moon.strategyHostTransferComplete(value, transfer, retained),
    ),
    transferAbort: (value, transfer, confirmed) => checked(
      moon.strategyHostTransferAbort(value, transfer, confirmed),
    ),
    transferRelease: (value, receipt) => checked(
      moon.strategyHostTransferRelease(value, receipt),
    ),
    transferPending: moon.strategyHostTransferPending,
    transferReceipt: moon.strategyHostTransferReceipt,
    explain: (value, bytes, nodes) => JSON.parse(checked(moon.strategyHostExplain(value, bytes, nodes))),
    usage: value => Object.freeze(Object.fromEntries(
      moon.strategyHostUsage(value).map((count, index) => [usageKeys[index], count]),
    )),
  });
}
