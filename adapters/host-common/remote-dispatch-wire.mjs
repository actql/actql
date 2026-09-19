const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};

const text = value => typeof value === 'string' && value.length > 0;
const exactKeys = (value, keys) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');

export function admitRemoteDispatchJson(
  control,
  bodyText,
  claimedRequestCid,
  maxBytes = 65_536,
) {
  if (control === null || typeof control !== 'object' ||
      typeof control.admit !== 'function' ||
      typeof control.requestJson !== 'function' ||
      !text(bodyText) || !text(claimedRequestCid) ||
      !Number.isSafeInteger(maxBytes) || maxBytes <= 0 ||
      new TextEncoder().encode(bodyText).byteLength > maxBytes) {
    fail('InvalidRemoteDispatchWire');
  }
  let body;
  try { body = JSON.parse(bodyText); }
  catch (error) { fail('InvalidRemoteDispatchWire', error); }
  if (body === null || typeof body !== 'object' || Array.isArray(body) ||
      body.version !== 'actql-remote-dispatch-request/0.1') {
    fail('InvalidRemoteDispatchWire');
  }
  let request;
  try {
    request = control.admit(Object.freeze({
      coordinatorAuthority: body.coordinator_authority,
      runDefinitionCid: body.run_definition_cid,
      taskKey: body.task_key,
      taskAttempt: body.task_attempt,
      dispatchId: body.dispatch_id,
      dispatchRequestCid: claimedRequestCid,
      siteKey: body.site_key,
      siteGeneration: body.site_generation,
      runtimeBundleCid: body.runtime_bundle_cid,
      connectorRegistration: body.connector_registration,
      connectorRevision: body.connector_revision,
      strategyRevision: body.strategy_revision,
      inputBindingCid: body.input_binding_cid,
      obligationsCid: body.obligations_cid,
      budgetCid: body.budget_cid,
      grantCid: body.grant_cid,
    }));
  } catch (error) {
    fail('InvalidRemoteDispatchWire', error);
  }
  if (control.requestJson(request) !== bodyText) {
    fail('NonCanonicalRemoteDispatchWire');
  }
  return request;
}

export function admitRemoteExecutionEvidenceJson(
  control,
  bodyText,
  claimedEvidenceCid,
  dispatch,
  maxBytes = 65_536,
) {
  if (control === null || typeof control !== 'object' ||
      typeof control.admitExecutionEvidence !== 'function' ||
      typeof control.evidenceJson !== 'function' ||
      typeof control.evidenceMatchesDispatch !== 'function' ||
      !text(bodyText) || !text(claimedEvidenceCid) || dispatch === undefined ||
      !Number.isSafeInteger(maxBytes) || maxBytes <= 0 ||
      new TextEncoder().encode(bodyText).byteLength > maxBytes) {
    fail('InvalidRemoteExecutionEvidenceWire');
  }
  let body;
  try { body = JSON.parse(bodyText); }
  catch (error) { fail('InvalidRemoteExecutionEvidenceWire', error); }
  if (body === null || typeof body !== 'object' || Array.isArray(body) ||
      body.version !== 'actql-remote-execution-evidence/0.1') {
    fail('InvalidRemoteExecutionEvidenceWire');
  }
  let evidence;
  try {
    evidence = control.admitExecutionEvidence(Object.freeze({
      connectorRegistration: body.connector_registration,
      connectorRevision: body.connector_revision,
      dispatchRequestCid: body.dispatch_request_cid,
      evidenceKind: body.evidence_kind,
      evidenceSubjectCid: body.evidence_subject_cid,
      holdingEvidenceCid: body.holding_evidence_cid,
      issuerCapabilityCid: body.issuer_capability_cid,
      materialGeneration: body.material_generation,
      obligationsCid: body.obligations_cid,
      runtimeBundleCid: body.runtime_bundle_cid,
      siteGeneration: body.site_generation,
      siteKey: body.site_key,
      strategyRevision: body.strategy_revision,
      evidenceCid: claimedEvidenceCid,
    }));
  } catch (error) {
    fail('InvalidRemoteExecutionEvidenceWire', error);
  }
  if (control.evidenceJson(evidence) !== bodyText ||
      !control.evidenceMatchesDispatch(evidence, dispatch)) {
    fail('NonCanonicalRemoteExecutionEvidenceWire');
  }
  return evidence;
}

export function admitRemoteManagedOutputSubjectJson(
  control,
  bodyText,
  claimedSubjectCid,
  dispatch,
  maxBytes = 65_536,
) {
  if (control === null || typeof control !== 'object' ||
      typeof control.admitManagedOutputSubject !== 'function' ||
      typeof control.managedOutputSubjectJson !== 'function' ||
      typeof control.managedOutputSubjectProjection !== 'function' ||
      typeof control.identity !== 'function' || !text(bodyText) ||
      !text(claimedSubjectCid) || dispatch === undefined ||
      !Number.isSafeInteger(maxBytes) || maxBytes <= 0 ||
      new TextEncoder().encode(bodyText).byteLength > maxBytes) {
    fail('InvalidRemoteManagedOutputSubjectWire');
  }
  let body;
  try { body = JSON.parse(bodyText); }
  catch (error) { fail('InvalidRemoteManagedOutputSubjectWire', error); }
  const keys = [
    'dispatch_request_cid',
    'holding_evidence_cid',
    'logical_view_cid',
    'managed_profile_cid',
    'material_generation',
    'physical_manifest_cid',
    'representation_codec_cid',
    'result_schema_cid',
    'retained_bytes',
    'row_count',
    'version',
  ];
  if (!exactKeys(body, keys) ||
      body.version !== 'actql-remote-managed-output-subject/0.1' ||
      !/^(0|[1-9][0-9]*)$/.test(body.retained_bytes) ||
      !Number.isSafeInteger(body.row_count) || body.row_count < 0) {
    fail('InvalidRemoteManagedOutputSubjectWire');
  }
  let retainedBytes;
  try { retainedBytes = BigInt(body.retained_bytes); }
  catch (error) { fail('InvalidRemoteManagedOutputSubjectWire', error); }
  if (retainedBytes > 9_223_372_036_854_775_807n) {
    fail('InvalidRemoteManagedOutputSubjectWire');
  }
  let subject;
  try {
    subject = control.admitManagedOutputSubject(Object.freeze({
      dispatchRequestCid: body.dispatch_request_cid,
      materialGeneration: body.material_generation,
      holdingEvidenceCid: body.holding_evidence_cid,
      managedProfileCid: body.managed_profile_cid,
      resultSchemaCid: body.result_schema_cid,
      logicalViewCid: body.logical_view_cid,
      representationCodecCid: body.representation_codec_cid,
      physicalManifestCid: body.physical_manifest_cid,
      rowCount: body.row_count,
      retainedBytes,
      subjectCid: claimedSubjectCid,
    }));
  } catch (error) {
    fail('InvalidRemoteManagedOutputSubjectWire', error);
  }
  const projection = control.managedOutputSubjectProjection(subject);
  if (control.managedOutputSubjectJson(subject) !== bodyText ||
      !Array.isArray(projection) || projection.length !== 11 ||
      projection[0] !== control.identity(dispatch) ||
      projection[10] !== claimedSubjectCid) {
    fail('InvalidRemoteManagedOutputSubjectWire');
  }
  return subject;
}
