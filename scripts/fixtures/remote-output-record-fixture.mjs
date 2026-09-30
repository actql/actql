import {createHash} from 'node:crypto';

// One durable Coordinator Output record built only through public owners: a
// Site executes the dispatch in memory and reports its retained output with
// evidence; the Coordinator observes that reply, issues the output plan poll,
// admits the Site's plan and keeps the durable Output record. `coordinator`
// is `@actql/coordinator-core` (repository or packed) and `runtime` is
// `runtimeCore(bridge)`. Test-only: it names a concrete Connector, so it lives
// with the test fixtures, not in the common adapters.
export function durableOutputRecordFixture(coordinator, runtime,
  {dispatchId = 'dispatch-output'} = {}) {
  const cid = digit => `sha256:${digit.repeat(64)}`;
  const physicalCid = value =>
    `sha256:${createHash('sha256').update(value).digest('hex')}`;
  const control = runtime.remoteSiteControl;
  const transferControl = runtime.remoteTransferControl;
  const input = Object.freeze({
    coordinatorAuthority: 'coordinator-a', runDefinitionCid: cid('0'),
    taskKey: 'task-a', taskAttempt: 1, dispatchId, siteKey: 'site-a',
    siteGeneration: 1, runtimeBundleCid: cid('a'),
    connectorRegistration: 'local', connectorRevision: 'local/1',
    strategyRevision: 'strategy/1', inputBindingCid: cid('1'),
    obligationsCid: cid('2'), budgetCid: cid('3'),
    evidenceIssuerCapabilityCid: cid('b'), grantCid: cid('4'),
  });
  const resultDefinitionCid = cid('7');
  const limits = {maxChunks: 4, maxManifestBytes: 4096,
    maxReferencedBytes: 12n};

  // Coordinator: the durable intent.
  const request = coordinator.prepareDispatch(input);
  const journal = coordinator.createJournal('coordinator-a');
  const admission = coordinator.prepareIntent(journal, request);
  const initial = coordinator.admitDurableJson(
    coordinator.admissionDurableJson(admission));
  const record = coordinator.commitIntent(admission);

  // Site: the same dispatch executed in memory, its output retained and its
  // evidence issued.
  const site = runtime.siteControl.create(Object.freeze({
    key: 'site-a', generation: 1, runtimeRevision: cid('a'),
    maxConcurrentOperations: 4, maxConcurrentTransfers: 4,
    maxRetainedBytes: 1_048_576n, maxExecutionBytes: 1_048_576n,
  }));
  const siteRequest = control.prepare(input);
  const siteRecord = control.commitAdmission(
    control.prepareAdmission(control.createJournal(site), siteRequest), true);
  const capability = control.registerExecutionCapability(Object.freeze({
    site, runtimeBundleCid: cid('a'), connectorRegistration: 'local',
    connectorRevision: 'local/1', strategyRevision: 'strategy/1',
    operationCapabilityCid: cid('4'),
  }));
  control.commitTransition(
    control.prepareProvisioning(siteRecord, capability), true);
  control.commitTransition(control.prepareExecution(siteRecord), true);
  control.commitTransition(control.prepareSettled(siteRecord), true);
  const materialGeneration = cid('e');
  const physicalManifest = {
    version: 'actql-managed-physical-manifest/0.1',
    schemaContractCid: cid('1'), viewContractCid: cid('2'),
    codecContractCid: cid('3'), rowCount: 2,
    chunks: [{cid: cid('a'), byteLength: 12n, rowCount: 2}],
  };
  const transferRequest = transferControl.prepare({
    coordinatorAuthority: 'coordinator-a', transferAttemptId: 'transfer-output',
    route: 'direct', sourceSite: 'site-a', sourceSiteGeneration: 1,
    destinationSite: 'site-b', destinationSiteGeneration: 2,
    sourceMaterialGeneration: materialGeneration, physicalManifest, limits,
    capacityBytes: 1024n, expiresAtMilliseconds: 2_000_000_000_000n,
    sourceGrantCid: cid('9'), destinationGrantCid: cid('c'),
    routeCapabilityCid: cid('d'),
  });
  const holdingEvidenceCid = control.outputHoldingEvidenceIdentity(
    siteRequest, materialGeneration, 12n);
  control.commitTransition(control.prepareRetained(
    siteRecord, materialGeneration, holdingEvidenceCid), true);
  const issuer = control.registerEvidenceIssuer(Object.freeze({
    site, runtimeBundleCid: cid('a'), connectorRegistration: 'local',
    connectorRevision: 'local/1', strategyRevision: 'strategy/1',
    evidenceKind: control.managedOutputEvidenceKind,
    issuerCapabilityCid: cid('b'),
  }));
  const measurement = control.prepareManagedOutputMeasurement(Object.freeze({
    rowCount: 2, admissionNodes: 0, admissionTextBytes: 0, admissionWork: 0,
    columnRows: Object.freeze([2]), columnBytes: Object.freeze([12]),
    columnNodes: Object.freeze([2]), columnMaxValueBytes: Object.freeze([6]),
    columnNullRows: Object.freeze([0]),
    columnAdmittedDepths: Object.freeze([10]),
  }));
  const subject = control.prepareManagedOutputSubject(siteRequest,
    Object.freeze({
      materialGeneration, managedProfileCid: cid('4'),
      resultSchemaCid: physicalManifest.schemaContractCid,
      logicalViewCid: physicalManifest.viewContractCid,
      representationCodecCid: physicalManifest.codecContractCid,
      physicalManifestCid: physicalCid(
        transferControl.manifestJson(transferRequest)),
      rowCount: 2, retainedBytes: 12n,
    }), measurement, holdingEvidenceCid);
  const evidence = control.issueManagedOutputEvidence(
    issuer, siteRecord, subject);
  control.commitTransition(control.prepareEvidence(siteRecord, evidence), true);
  const reply = control.statusJson(siteRecord, evidence, subject, measurement);

  // Coordinator: the Site's status with its output is observed durably.
  const response = coordinator.admitResponseJson(reply, request, true);
  const observed = coordinator.prepareResponseObservation(record, response);
  const durable = coordinator.admitDurableJson(
    coordinator.responseDurableJson(initial, observed, response));
  coordinator.commitTransition(observed);

  // Coordinator: the output plan poll; Site: its plan; Coordinator: the
  // durable Output record.
  const pollBody = coordinator.issueOutputPlanPollJson(durable, {
    storeAuthorityCid: cid('5'), publicationAttemptCid: cid('6'),
    resultDefinitionCid, orderingEvidenceCid: cid('8'),
    coordinatorAuthority: 'coordinator-a', transferAttempt: 'transfer-output',
    transferRoute: 'direct', destinationSiteKey: 'site-b',
    destinationSiteGeneration: 2, transferMaxBytes: 1024,
    transferExpiresUnixMs: 2_000_000_000_000,
    sourceGrantCid: cid('9'), destinationGrantCid: cid('c'),
    routeCapabilityCid: cid('d'),
    transferOrigin: 'https://transfer.example.invalid/output',
  });
  const planOutput = control.admitPollOutputPlan(pollBody);
  const payloadRequest = control.preparePublicationPayload({
    storeAuthorityCid: cid('5'), publicationAttemptCid: cid('6'),
    materialGenerationCid: materialGeneration, resultDefinitionCid,
    logicalRelationCid: physicalManifest.viewContractCid,
    resultSchemaCid: physicalManifest.schemaContractCid,
    orderingEvidenceCid: cid('8'),
    durableCodecCid: physicalManifest.codecContractCid,
    maxBytes: 12n, rowCount: 2n,
  });
  const planBody = control.outputPlanJson(control.prepareOutputPlan(
    planOutput, subject, payloadRequest, transferRequest));
  const checkedPlan = coordinator.admitCheckedOutputPlan(
    durable, pollBody, planBody, resultDefinitionCid, limits);
  const outputDurable = coordinator.admitDurableOutputJson(
    coordinator.outputAdmissionDurableJson(checkedPlan), durable,
    resultDefinitionCid, limits);
  // The same intent as the Site's own owner would issue for this dispatch.
  const siteIntent = control.prepareOutputIntent(siteRequest, {
    storeAuthorityCid: cid('5'), publicationAttemptCid: cid('6'),
    resultDefinitionCid, orderingEvidenceCid: cid('8'),
    coordinatorAuthority: 'coordinator-a', transferAttemptId: 'transfer-output',
    transferRoute: 'direct', destinationSite: 'site-b',
    destinationSiteGeneration: 2, transferMaxBytes: 1024n,
    transferExpiresAtMilliseconds: 2_000_000_000_000n,
    sourceGrantCid: cid('9'), destinationGrantCid: cid('c'),
    routeCapabilityCid: cid('d'),
    transferOrigin: 'https://transfer.example.invalid/output',
  });
  return Object.freeze({request, requestCid: coordinator.dispatchCid(request),
    durable, outputDurable, pollBody, planOutput, control, siteRequest,
    siteIntent, reply});
}
